const {setGlobalOptions} = require("firebase-functions");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
} = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const { defineString } = require("firebase-functions/params");
const stripeSecret = defineString("STRIPE_SECRET_KEY");
const algoliaAppId = defineString("ALGOLIA_APP_ID");
const algoliaAdminKey = defineString("ALGOLIA_ADMIN_KEY");

admin.initializeApp();

const db = admin.firestore();

setGlobalOptions({maxInstances: 10});

const {algoliasearch} = require("algoliasearch");
const {
  CHECKOUT_CURRENCY,
  getDeliveryCost,
  normalizeOrderItems,
  productKey,
  stripeAmountFromKwd,
  assertPaymentIntentMatchesOrder,
} = require("./checkout_helpers");

const PRODUCTS_INDEX = "products";
const BOUTIQUES_INDEX = "boutiques";

let algoliaClient;

function getAlgoliaClient() {
  if (!algoliaClient) {
    const appId = algoliaAppId.value();
    const adminKey = algoliaAdminKey.value();
    if (!appId || !adminKey) {
      throw new Error(
        "Algolia is not configured. Set ALGOLIA_APP_ID and ALGOLIA_ADMIN_KEY.",
      );
    }
    algoliaClient = algoliasearch(appId, adminKey);
  }
  return algoliaClient;
}

async function saveAlgoliaObject(indexName, body) {
  await getAlgoliaClient().saveObject({indexName, body});
}

async function deleteAlgoliaObject(indexName, objectID) {
  await getAlgoliaClient().deleteObject({indexName, objectID});
}

async function saveAlgoliaObjects(indexName, objects) {
  await getAlgoliaClient().saveObjects({indexName, objects});
}

// ================= HELPERS =================

async function isAdminUser(uid) {
  const adminDoc = await db.collection("admin_users").doc(uid).get();

  if (!adminDoc.exists) return false;

  const adminData = adminDoc.data();

  return adminData.isApproved === true;
}

async function isSuperAdminUser(uid) {
  const adminDoc = await db.collection("admin_users").doc(uid).get();

  if (!adminDoc.exists) return false;

  const adminData = adminDoc.data();

  return adminData.isApproved === true && adminData.role === "super_admin";
}

async function saveNotificationToUser(uid, title, body, type, extraData = {}) {
  await db
    .collection("users")
    .doc(uid)
    .collection("notifications")
    .add({
      title,
      body,
      type,
      data: extraData,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

async function sendNotificationToUser(uid, title, body, type, extraData = {}) {
  const userDoc = await db.collection("users").doc(uid).get();

  if (!userDoc.exists) {
    logger.info("User document not found", {uid});
    return;
  }

  const userData = userDoc.data();
  const token = userData.fcmToken;

  await saveNotificationToUser(uid, title, body, type, extraData);

  if (!token) {
    logger.info("No FCM token for user", {uid});
    return;
  }

  const message = {
    token,
    notification: {
      title,
      body,
    },
    data: {
      type: String(type),
      ...convertDataToStrings(extraData),
    },
  };

  try {
    await admin.messaging().send(message);
    logger.info("Notification sent", {uid, type});
  } catch (error) {
    logger.error("Failed to send notification", {uid, error});
  }
}

function convertDataToStrings(data) {
  const converted = {};

  for (const key of Object.keys(data)) {
    const value = data[key];

    if (value === null || value === undefined) {
      converted[key] = "";
    } else {
      converted[key] = String(value);
    }
  }

  return converted;
}

async function buildVerifiedOrderDetails(items, deliveryMethod, getProductSnap) {
  const {normalizedItems, productRequests} = normalizeOrderItems(items);
  const productRecords = new Map();

  for (const request of productRequests) {
    const productRef = db
      .collection("boutiques").doc(request.boutiqueId)
      .collection("products").doc(request.productId);
    const productSnap = await getProductSnap(productRef);

    if (!productSnap.exists) {
      throw new HttpsError("not-found", "Product is no longer available.");
    }

    const productData = productSnap.data();
    productRecords.set(productKey(request.boutiqueId, request.productId), {
      ref: productRef,
      data: productData,
      requestedQuantity: request.quantity,
    });
  }

  for (const record of productRecords.values()) {
    const stock = Number(record.data.stock) || 0;
    if (stock < record.requestedQuantity) {
      throw new HttpsError(
        "failed-precondition",
        `${record.data.title || "Product"} does not have enough stock.`,
      );
    }
  }

  const verifiedItems = [];
  let verifiedSubtotal = 0;

  for (const item of normalizedItems) {
    const record = productRecords.get(productKey(item.boutiqueId, item.productId));
    const productData = record.data;
    const serverPrice = Number(productData.price) || 0;
    verifiedSubtotal += serverPrice * item.quantity;

    const verifiedItem = {
      productId: item.productId,
      boutiqueId: item.boutiqueId,
      title: productData.title || item.title || "",
      imageUrl: item.imageUrl || "",
      description: productData.description || item.description || "",
      size: item.size || "",
      price: serverPrice,
      quantity: item.quantity,
      boutiqueName: productData.boutiqueName || "",
    };

    if (item.color) {
      verifiedItem.color = item.color;
    }

    verifiedItems.push(verifiedItem);
  }

  if (verifiedSubtotal > 5000) {
    throw new HttpsError(
      "invalid-argument",
      "Order total cannot exceed KD 5,000.",
    );
  }

  const deliveryCost = getDeliveryCost(deliveryMethod);
  const total = verifiedSubtotal + deliveryCost;
  const amount = stripeAmountFromKwd(total);

  if (amount <= 0) {
    throw new HttpsError("invalid-argument", "Order total must be greater than zero.");
  }

  return {
    verifiedItems,
    verifiedSubtotal,
    deliveryCost,
    total,
    amount,
    productRecords,
  };
}

async function sendNotificationToBoutiqueOwners(
  boutiqueId,
  title,
  body,
  type,
  extraData = {},
) {
  const ownersSnapshot = await db
    .collection("boutique_owners")
    .where("boutiqueId", "==", boutiqueId)
    .where("isApproved", "==", true)
    .get();

  for (const ownerDoc of ownersSnapshot.docs) {
    await sendNotificationToUser(
      ownerDoc.id,
      title,
      body,
      type,
      extraData,
    );
  }
}

function getBoutiqueIdsFromItems(items) {
  const boutiqueIds = new Set();

  if (!Array.isArray(items)) {
    return [];
  }

  for (const item of items) {
    if (item.boutiqueId) {
      boutiqueIds.add(String(item.boutiqueId));
    }
  }

  return Array.from(boutiqueIds);
}

// ================= RATE LIMITING =================
//
// Generic sliding-window rate limiter backed by Firestore. Each caller is
// keyed by `<action>_<uid>`; recent timestamps are persisted on the
// `rate_limits/<key>` document and pruned to the requested window on every
// check. Returns false when the limit is exceeded so the caller can throw a
// `resource-exhausted` HttpsError to the client.
async function checkRateLimit(key, maxRequests, windowSeconds) {
  const now = Date.now();
  const windowStart = now - (windowSeconds * 1000);
  const ref = db.collection("rate_limits").doc(key);

  return await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    const data = doc.exists ? doc.data() : { requests: [] };

    // Filter to requests within the current window
    const recent = (data.requests || []).filter((ts) => ts > windowStart);

    if (recent.length >= maxRequests) {
      return false; // Rate limit exceeded
    }

    recent.push(now);
    tx.set(ref, { requests: recent, updatedAt: now }, { merge: true });
    return true;
  });
}

// ================= PAYMENTS =================

exports.createPaymentIntent = onCall(async (request) => {
  const stripe = require("stripe")(stripeSecret.value());
  try {
    const data = request.data || {};

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be logged in.");
    }

    const withinLimit = await checkRateLimit(
      `payment_${request.auth.uid}`,
      10,
      3600,
    );
    if (!withinLimit) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many requests. Please try again later.",
      );
    }

    logger.info("Callable data received", {data});

    const items = data.items;
    const deliveryMethod = String(data.deliveryMethod || "");
    const currency = data.currency;
    const {normalizedItems} = normalizeOrderItems(items);

    if (!currency || typeof currency !== "string") {
      throw new HttpsError("invalid-argument", "Currency is required.");
    }

    if (currency.toLowerCase() !== CHECKOUT_CURRENCY) {
      throw new HttpsError("invalid-argument", "Unsupported currency.");
    }

    let subtotal = 0;

    for (const item of normalizedItems) {
      const productDoc = await db
        .collection("boutiques").doc(item.boutiqueId)
        .collection("products").doc(item.productId)
        .get();

      if (!productDoc.exists) {
        throw new HttpsError("not-found", `Product ${item.productId} not found.`);
      }

      const serverPrice = Number(productDoc.data().price) || 0;
      subtotal += serverPrice * item.quantity;
    }

    // New clients send the delivery method so the server derives the fee.
    // The legacy deliveryCost path remains safe because createOrder verifies
    // the final server-side amount before any order or stock write is made.
    const delivery = deliveryMethod ?
      getDeliveryCost(deliveryMethod) :
      Number(data.deliveryCost) || 0;
    const total = subtotal + delivery;
    const amount = stripeAmountFromKwd(total);

    if (amount <= 0) {
      throw new HttpsError("invalid-argument", "Order total must be greater than zero.");
    }

    logger.info("Creating payment intent", {
      subtotal,
      delivery,
      total,
      amount,
      currency,
    });

    const paymentIntent = await stripe.paymentIntents.create({
      amount,
      currency: CHECKOUT_CURRENCY,
      metadata: {
        firebaseUid: request.auth.uid,
        expectedAmount: String(amount),
        currency: CHECKOUT_CURRENCY,
        deliveryMethod,
      },
    });

    return {
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
    };
  } catch (error) {
    logger.error("Stripe error", error);

    if (error instanceof HttpsError) throw error;

    throw new HttpsError(
      "internal",
      error.message || "Failed to create payment intent.",
    );
  }
});

exports.processRefund = onCall(async (request) => {
  const stripe = require("stripe")(stripeSecret.value());
  try {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be logged in.");
    }

    const uid = request.auth.uid;
    const allowed = await isAdminUser(uid);

    if (!allowed) {
      throw new HttpsError(
        "permission-denied",
        "Only approved admins can process refunds.",
      );
    }

    const {paymentIntentId} = request.data || {};

    if (!paymentIntentId) {
      throw new HttpsError(
        "invalid-argument",
        "paymentIntentId is required.",
      );
    }

    if (typeof paymentIntentId !== "string" || paymentIntentId.length > 200) {
      throw new HttpsError("invalid-argument", "Invalid paymentIntentId.");
    }

    logger.info("Processing refund for", {paymentIntentId});

    const refund = await stripe.refunds.create({
      payment_intent: paymentIntentId,
    });

    logger.info("Refund created", {
      refundId: refund.id,
      status: refund.status,
    });

    return {
      refundId: refund.id,
      status: refund.status,
    };
  } catch (error) {
    logger.error("Refund error", error);

    if (error instanceof HttpsError) throw error;

    throw new HttpsError(
      "internal",
      error.message || "Failed to process refund.",
    );
  }
});

// ================= CREATE ORDER =================

exports.createOrder = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "You must be logged in.");
  }

  const orderRateOk = await checkRateLimit(
    `order_${request.auth.uid}`,
    5,
    3600,
  );
  if (!orderRateOk) {
    throw new HttpsError(
      "resource-exhausted",
      "Too many requests. Please try again later.",
    );
  }

  const uid             = request.auth.uid;
  const data            = request.data || {};
  const items           = data.items;
  const deliveryMethod  = data.deliveryMethod  || "";
  const paymentMethod   = data.paymentMethod   || "";
  const rawPaymentIntentId = data.paymentIntentId;
  const allowedPaymentMethods  = ["Card"];

  if (!allowedPaymentMethods.includes(paymentMethod)) {
    throw new HttpsError("invalid-argument", "Invalid payment method.");
  }

  if (
    typeof rawPaymentIntentId !== "string" ||
    rawPaymentIntentId.trim() === "" ||
    rawPaymentIntentId.length > 200
  ) {
    throw new HttpsError("invalid-argument", "Invalid paymentIntentId.");
  }

  const paymentIntentId = rawPaymentIntentId.trim();
  const stripe = require("stripe")(stripeSecret.value());
  const orderPreview = await buildVerifiedOrderDetails(
    items,
    deliveryMethod,
    (productRef) => productRef.get(),
  );
  let paymentIntent;

  try {
    paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
  } catch (error) {
    logger.error("Payment verification failed", {
      uid,
      paymentIntentId,
      error,
    });
    throw new HttpsError(
      "failed-precondition",
      "Payment could not be verified.",
    );
  }

  assertPaymentIntentMatchesOrder(paymentIntent, {
    uid,
    expectedAmount: orderPreview.amount,
    currency: CHECKOUT_CURRENCY,
  });

  const counterRef = db.collection("metadata").doc("order_counter");
  const orderNumber = await db.runTransaction(async (tx) => {
    const snap = await tx.get(counterRef);
    let last = 100000;
    if (snap.exists && typeof snap.data().lastOrderNumber === "number") {
      last = snap.data().lastOrderNumber;
    }
    const next = last + 1;
    tx.set(counterRef, { lastOrderNumber: next }, { merge: true });
    return String(next);
  });

  const addressSnap = await db
    .collection("users").doc(uid)
    .collection("saved_addresses")
    .orderBy("createdAt", "desc")
    .limit(1)
    .get();
  const addressData = addressSnap.empty ? null : addressSnap.docs[0].data();

  const userDoc = await db.collection("users").doc(uid).get();
  const userData = userDoc.exists ? userDoc.data() : {};
  const customerName  = userData.fullName  || request.auth.token.name  || "User";
  const customerEmail = userData.email     || request.auth.token.email || "";

  const now        = new Date();
  const dateString = `${now.getDate()}/${now.getMonth() + 1}/${now.getFullYear()}`;

  const userOrderRef   = db.collection("users").doc(uid).collection("orders").doc();
  const globalOrderRef = db.collection("global_orders").doc(userOrderRef.id);

  await db.runTransaction(async (tx) => {
    const orderDetails = await buildVerifiedOrderDetails(
      items,
      deliveryMethod,
      (productRef) => tx.get(productRef),
    );
    const paymentIntentRef = db
      .collection("payment_intents")
      .doc(paymentIntentId);
    const paymentIntentLock = await tx.get(paymentIntentRef);

    if (paymentIntentLock.exists) {
      throw new HttpsError(
        "already-exists",
        "This payment has already been used for an order.",
      );
    }

    if (orderDetails.amount !== Number(paymentIntent.amount)) {
      throw new HttpsError(
        "failed-precondition",
        "Order total changed after payment.",
      );
    }

    const orderBase = {
      orderNumber,
      date: dateString,
      itemCount: orderDetails.verifiedItems.reduce((s, i) => s + i.quantity, 0),
      total: orderDetails.total,
      status: "Placed",
      customerUid: uid,
      customerName,
      customerEmail,
      deliveryMethod,
      paymentMethod,
      paymentIntentId,
      address: addressData,
      items: orderDetails.verifiedItems,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    tx.set(paymentIntentRef, {
      uid,
      paymentIntentId,
      orderId: userOrderRef.id,
      orderNumber,
      amount: orderDetails.amount,
      currency: CHECKOUT_CURRENCY,
      stripeStatus: paymentIntent.status,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.set(userOrderRef, orderBase);
    tx.set(globalOrderRef, { ...orderBase, sourceUserOrderId: userOrderRef.id });

    const boutiqueIds = new Set(orderDetails.verifiedItems.map(i => i.boutiqueId));
    for (const boutiqueId of boutiqueIds) {
      const bItems = orderDetails.verifiedItems.filter(i => i.boutiqueId === boutiqueId);
      const bTotal = bItems.reduce((s, i) => s + i.price * i.quantity, 0);
      const bCount = bItems.reduce((s, i) => s + i.quantity, 0);

      const boutiqueOrderRef = db.collection("boutiques").doc(boutiqueId)
                                 .collection("orders").doc();

      tx.set(boutiqueOrderRef, {
        orderNumber,
        sourceUserOrderId: userOrderRef.id,
        date: dateString,
        itemCount: bCount,
        total: bTotal,
        status: "Placed",
        customerUid: uid,
        customerName,
        customerEmail,
        deliveryMethod,
        paymentMethod,
        address: addressData,
        items: bItems,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    for (const record of orderDetails.productRecords.values()) {
      tx.update(record.ref, {
        stock: admin.firestore.FieldValue.increment(-record.requestedQuantity),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });

  return { orderNumber };
});

// ================= ORDER NOTIFICATIONS =================

exports.notifyOrderPlaced = onDocumentCreated(
  "global_orders/{orderId}",
  async (event) => {
    const orderData = event.data.data();
    const orderId = event.params.orderId;

    if (!orderData) return;

    const customerUid = orderData.customerUid;
    const orderNumber = orderData.orderNumber || orderId;
    const items = orderData.items || [];

    if (customerUid) {
      await sendNotificationToUser(
        customerUid,
        "Order placed",
        `Your LIBSK order #${orderNumber} has been placed successfully.`,
        "order_placed",
        {
          type: "order_status",
          orderId,
          orderNumber,
          status: "Placed",
        },
      );
    }

    const boutiqueIds = getBoutiqueIdsFromItems(items);

    for (const boutiqueId of boutiqueIds) {
      await sendNotificationToBoutiqueOwners(
        boutiqueId,
        "New order received",
        `A new order #${orderNumber} has been placed for your boutique.`,
        "new_boutique_order",
        {
          type: "order_status",
          orderId,
          orderNumber,
          boutiqueId,
          status: "Placed",
        },
      );
    }
  },
);

exports.notifyOrderStatusChanged = onDocumentUpdated(
  "global_orders/{orderId}",
  async (event) => {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    const orderId = event.params.orderId;

    if (!beforeData || !afterData) return;

    const oldStatus = beforeData.status;
    const newStatus = afterData.status;

    if (oldStatus === newStatus) return;

    const customerUid = afterData.customerUid;
    const orderNumber = afterData.orderNumber || orderId;
    const items = afterData.items || [];

    if (customerUid) {
      await sendNotificationToUser(
        customerUid,
        "Order status updated",
        `Your order #${orderNumber} is now ${newStatus}.`,
        "order_status_updated",
        {
          type: "order_status",
          orderId,
          orderNumber,
          oldStatus,
          newStatus,
        },
      );
    }

    const boutiqueIds = getBoutiqueIdsFromItems(items);

    for (const boutiqueId of boutiqueIds) {
      await sendNotificationToBoutiqueOwners(
        boutiqueId,
        "Order status updated",
        `Order #${orderNumber} is now ${newStatus}.`,
        "boutique_order_status_updated",
        {
          type: "order_status",
          orderId,
          orderNumber,
          boutiqueId,
          oldStatus,
          newStatus,
        },
      );
    }
  },
);

// ================= DISPUTE NOTIFICATIONS =================

exports.notifyDisputeCreated = onDocumentCreated(
  "disputes/{disputeId}",
  async (event) => {
    const disputeData = event.data.data();
    const disputeId = event.params.disputeId;

    if (!disputeData) return;

    const customerUid = disputeData.customerUid;
    const orderNumber = disputeData.orderNumber || "";
    const category = disputeData.category || "Dispute";

    if (customerUid) {
      await sendNotificationToUser(
        customerUid,
        "Dispute submitted",
        `Your dispute for order #${orderNumber} has been submitted.`,
        "dispute_created",
        {
          type: "dispute_status",
          disputeId,
          orderNumber,
          category,
        },
      );
    }

    const adminsSnapshot = await db
      .collection("admin_users")
      .where("isApproved", "==", true)
      .get();

    for (const adminDoc of adminsSnapshot.docs) {
      await sendNotificationToUser(
        adminDoc.id,
        "New dispute received",
        `A new dispute was submitted for order #${orderNumber}.`,
        "admin_new_dispute",
        {
          type: "dispute_status",
          disputeId,
          orderNumber,
          category,
        },
      );
    }
  },
);

exports.notifyDisputeStatusChanged = onDocumentUpdated(
  "disputes/{disputeId}",
  async (event) => {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    const disputeId = event.params.disputeId;

    if (!beforeData || !afterData) return;

    const oldStatus = beforeData.status;
    const newStatus = afterData.status;

    const oldRefundIssued = beforeData.refundIssued === true;
    const newRefundIssued = afterData.refundIssued === true;

    if (oldStatus === newStatus && oldRefundIssued === newRefundIssued) {
      return;
    }

    const customerUid = afterData.customerUid;
    const orderNumber = afterData.orderNumber || "";

    if (!customerUid) return;

    let title = "Dispute updated";
    let body = `Your dispute for order #${orderNumber} is now ${newStatus}.`;
    let type = "dispute_status_updated";

    if (newStatus === "Under Review") {
      title = "Dispute under review";
      body = `Your dispute for order #${orderNumber} is now under review.`;
      type = "dispute_under_review";
    }

    if (newStatus === "Resolved" && newRefundIssued === true) {
      title = "Dispute resolved";
      body = `Your dispute for order #${orderNumber} was resolved and a refund was issued.`;
      type = "dispute_resolved_refund";
    }

    if (newStatus === "Resolved" && newRefundIssued !== true) {
      title = "Dispute resolved";
      body = `Your dispute for order #${orderNumber} was resolved.`;
      type = "dispute_resolved";
    }

    if (newStatus === "Rejected") {
      title = "Dispute rejected";
      body = `Your dispute for order #${orderNumber} was rejected.`;
      type = "dispute_rejected";
    }

    await sendNotificationToUser(
      customerUid,
      title,
      body,
      type,
      {
        type: "dispute_status",
        disputeId,
        orderNumber,
        oldStatus,
        newStatus,
        refundIssued: newRefundIssued,
      },
    );
  },
);

exports.submitDispute = onCall(async (request) => {
  try {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be logged in.");
    }

    const disputeRateOk = await checkRateLimit(
      `dispute_${request.auth.uid}`,
      3,
      86400,
    );
    if (!disputeRateOk) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many requests. Please try again later.",
      );
    }

    const uid = request.auth.uid;
    const data = request.data || {};

    const orderId     = data.orderId;
    const category    = data.category;
    const description = data.description || "";

    if (!orderId || !category) {
      throw new HttpsError(
        "invalid-argument",
        "orderId and category are required.",
      );
    }

    if (typeof orderId !== "string" || orderId.length > 200) {
      throw new HttpsError("invalid-argument", "Invalid orderId.");
    }

    const allowedCategories = ["Wrong Item", "Damaged Item", "Not Delivered", "Other"];
    if (!allowedCategories.includes(category)) {
      throw new HttpsError("invalid-argument", "Invalid category.");
    }

    if (typeof description !== "string" || description.length > 1000) {
      throw new HttpsError("invalid-argument", "Description must be under 1000 characters.");
    }

    const userOrderRef = db
      .collection("users")
      .doc(uid)
      .collection("orders")
      .doc(orderId);

    const orderDoc = await userOrderRef.get();

    if (!orderDoc.exists) {
      throw new HttpsError("not-found", "Order not found.");
    }

    const orderData = orderDoc.data();

    if (orderData.customerUid !== uid) {
      throw new HttpsError(
        "permission-denied",
        "You can only dispute your own orders.",
      );
    }

    if (String(orderData.status).toLowerCase() !== "delivered") {
      throw new HttpsError(
        "failed-precondition",
        "Only delivered orders can be disputed.",
      );
    }

    const createdAt = orderData.createdAt;

    if (!createdAt || !createdAt.toDate) {
      throw new HttpsError(
        "failed-precondition",
        "Order date is missing.",
      );
    }

    const orderDate = createdAt.toDate();
    const now = new Date();

    const diffMs = now.getTime() - orderDate.getTime();
    const diffDays = diffMs / (1000 * 60 * 60 * 24);

    if (diffDays > 7) {
      throw new HttpsError(
        "failed-precondition",
        "The 7-day dispute window has passed.",
      );
    }

    const existingDisputes = await db
      .collection("disputes")
      .where("orderId", "==", orderId)
      .where("customerUid", "==", uid)
      .limit(1)
      .get();

    if (!existingDisputes.empty) {
      throw new HttpsError(
        "already-exists",
        "A dispute has already been submitted for this order.",
      );
    }

    const disputeRef = await db.collection("disputes").add({
      orderId,
      orderNumber: orderData.orderNumber || "",
      customerUid: uid,
      customerName: orderData.customerName || "User",
      customerEmail: orderData.customerEmail || "",
      category,
      description,
      status: "Open",
      orderTotal: orderData.total || 0,
      paymentIntentId: orderData.paymentIntentId || "",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      disputeId: disputeRef.id,
    };
  } catch (error) {
    logger.error("Submit dispute error", error);

    if (error instanceof HttpsError) throw error;

    throw new HttpsError(
      "internal",
      error.message || "Failed to submit dispute.",
    );
  }
});

// ================= LOW STOCK NOTIFICATIONS =================

exports.notifyLowStock = onDocumentUpdated(
  "boutiques/{boutiqueId}/products/{productId}",
  async (event) => {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();

    const boutiqueId = event.params.boutiqueId;
    const productId = event.params.productId;

    if (!beforeData || !afterData) return;

    const oldStock = Number(beforeData.stock) || 0;
    const newStock = Number(afterData.stock) || 0;

    if (oldStock <= 5 || newStock > 5) {
      return;
    }

    const productTitle = afterData.title || "Product";

    await sendNotificationToBoutiqueOwners(
      boutiqueId,
      "Low stock alert",
      `${productTitle} is running low. Only ${newStock} left in stock.`,
      "low_stock_alert",
      {
        type: "low_stock",
        boutiqueId,
        productId,
        productTitle,
        stock: newStock,
      },
    );
  },
);

// ================= MANUAL ADMIN NOTIFICATIONS =================

exports.sendManualNotification = onCall(async (request) => {
  try {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be logged in.");
    }

    const notifRateOk = await checkRateLimit(
      `notification_${request.auth.uid}`,
      50,
      3600,
    );
    if (!notifRateOk) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many requests. Please try again later.",
      );
    }

    const uid = request.auth.uid;
    const isAdmin = await isAdminUser(uid);
    const isSuperAdmin = await isSuperAdminUser(uid);

    if (!isAdmin && !isSuperAdmin) {
      throw new HttpsError(
        "permission-denied",
        "Only admins can send notifications.",
      );
    }

    const data = request.data || {};
    const title = data.title;
    const body  = data.body;
    const targetType = data.targetType;

    if (!title || !body || !targetType) {
      throw new HttpsError(
        "invalid-argument",
        "title, body and targetType are required.",
      );
    }

    if (typeof title !== "string" || title.length > 100) {
      throw new HttpsError("invalid-argument", "Title must be under 100 characters.");
    }

    if (typeof body !== "string" || body.length > 500) {
      throw new HttpsError("invalid-argument", "Body must be under 500 characters.");
    }

    const allowedTargets = [
      "all_users",
      "boutique_owners",
      "admins",
    ];

    if (!allowedTargets.includes(targetType)) {
      throw new HttpsError("invalid-argument", "Invalid targetType.");
    }

    const manualNotificationRef = await db
      .collection("manual_notifications")
      .add({
        title,
        body,
        targetType,
        createdByUid: uid,
        createdByEmail: request.auth.token.email || "",
        status: "sending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    let targetUids = [];

    if (targetType === "all_users") {
      const usersSnapshot = await db.collection("users").get();

      targetUids = usersSnapshot.docs.map((doc) => doc.id);
    }

    if (targetType === "boutique_owners") {
      const ownersSnapshot = await db
        .collection("boutique_owners")
        .where("isApproved", "==", true)
        .get();

      targetUids = ownersSnapshot.docs.map((doc) => doc.id);
    }

    if (targetType === "admins") {
      const adminsSnapshot = await db
        .collection("admin_users")
        .where("isApproved", "==", true)
        .get();

      targetUids = adminsSnapshot.docs.map((doc) => doc.id);
    }

    let sentCount = 0;

    for (const targetUid of targetUids) {
      await sendNotificationToUser(
        targetUid,
        title,
        body,
        "manual_notification",
        {
          type: "manual",
          manualNotificationId: manualNotificationRef.id,
          targetType,
        },
      );

      sentCount++;
    }

    await manualNotificationRef.update({
      status: "sent",
      sentCount,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      sentCount,
    };
  } catch (error) {
    logger.error("Manual notification error", error);

    if (error instanceof HttpsError) throw error;

    throw new HttpsError(
      "internal",
      error.message || "Failed to send manual notification.",
    );
  }
});

// ================= BOUTIQUE OWNER INVITE =================

exports.inviteBoutiqueOwner = onCall(async (request) => {
  try {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be logged in.");
    }

    const inviteRateOk = await checkRateLimit(
      `invite_${request.auth.uid}`,
      20,
      3600,
    );
    if (!inviteRateOk) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many requests. Please try again later.",
      );
    }

    const callerUid = request.auth.uid;
    const isSuperAdmin = await isSuperAdminUser(callerUid);

    if (!isSuperAdmin) {
      throw new HttpsError(
        "permission-denied",
        "Only super admins can onboard boutique owners."
      );
    }

    const data = request.data || {};
    const fullName = String(data.fullName || "").trim();
    const email = String(data.email || "").trim().toLowerCase();
    const phone = String(data.phone || "").trim();
    const boutiqueName = String(data.boutiqueName || "").trim();
    const boutiqueDescription = String(data.boutiqueDescription || "").trim();
    const tier = String(data.tier || "basic").trim().toLowerCase();

    if (!fullName || !email || !phone || !boutiqueName) {
      throw new HttpsError(
        "invalid-argument",
        "fullName, email, phone, and boutiqueName are required."
      );
    }

    const allowedTiers = ["basic", "pro", "elite"];
    if (!allowedTiers.includes(tier)) {
      throw new HttpsError("invalid-argument", "Invalid tier.");
    }

    // Step 1 — Create Firebase Auth account with a random temp password
    const tempPassword = Math.random().toString(36).slice(-10) +
      Math.random().toString(36).toUpperCase().slice(-4) + "!1";

    let userRecord;
    try {
      userRecord = await admin.auth().createUser({
        email,
        password: tempPassword,
        displayName: fullName,
      });
    } catch (authError) {
      if (authError.code === "auth/email-already-exists") {
        throw new HttpsError(
          "already-exists",
          "An account with this email already exists."
        );
      }
      throw authError;
    }

    const uid = userRecord.uid;

    // Step 2 — Create boutique document
    const boutiqueRef = await db.collection("boutiques").add({
      name: boutiqueName,
      description: boutiqueDescription,
      tier,
      isActive: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const boutiqueId = boutiqueRef.id;

    // Step 3 — Create boutique_owners document using Auth UID as doc ID
    await db.collection("boutique_owners").doc(uid).set({
      uid,
      fullName,
      email,
      phone,
      boutiqueId,
      boutiqueName,
      tier,
      role: "boutique_owner",
      isApproved: true,
      mustChangePassword: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Step 4 — Update boutique with ownerUid
    await boutiqueRef.update({ ownerUid: uid });

    // Step 5 — Generate password reset link (owner uses this to set their password)
    const resetLink = await admin.auth().generatePasswordResetLink(email);

    // Step 6 — Send invite email via Firebase Auth
    // The reset link acts as the invite — owner clicks it to set their password
    // Uses Firebase's built-in email (customize in Firebase Console → Authentication → Templates)
    // For custom email content you can use SendGrid/Mailgun here instead

    // Send a notification to the owner's user record if they have a profile
    // (they won't yet, but save to a pending_invites collection for tracking)
    await db.collection("pending_invites").doc(uid).set({
      uid,
      email,
      fullName,
      boutiqueName,
      boutiqueId,
      tier,
      resetLink,
      status: "sent",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info("Boutique owner invited", { uid, email, boutiqueId });

    return {
      success: true,
      uid,
      boutiqueId,
      email,
    };
  } catch (error) {
    logger.error("Invite boutique owner error", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError(
      "internal",
      error.message || "Failed to invite boutique owner."
    );
  }
});
// ================= ALGOLIA SEARCH SYNC =================

// ── Sync product to Algolia on create ──────────────────────────────────────
exports.algoliaProductCreated = onDocumentCreated(
  "boutiques/{boutiqueId}/products/{productId}",
  async (event) => {
    const data = event.data.data();
    const { boutiqueId, productId } = event.params;
    if (!data) return;

    const record = {
      objectID: productId,
      productId,
      boutiqueId,
      title: data.title || "",
      description: data.description || "",
      boutiqueName: data.boutiqueName || "",
      category: data.category || [],
      colors: data.colors || [],
      price: data.price || 0,
      imageUrl: data.imageUrl || "",
      imageUrls: data.imageUrls || [],
      stock: data.stock || 0,
      madeToOrder: data.madeToOrder || false,
    };

    await saveAlgoliaObject(PRODUCTS_INDEX, record);
    logger.info("Algolia product created", { productId });
  }
);

// ── Sync product to Algolia on update ──────────────────────────────────────
exports.algoliaProductUpdated = onDocumentUpdated(
  "boutiques/{boutiqueId}/products/{productId}",
  async (event) => {
    const data = event.data.after.data();
    const { boutiqueId, productId } = event.params;
    if (!data) return;

    const record = {
      objectID: productId,
      productId,
      boutiqueId,
      title: data.title || "",
      description: data.description || "",
      boutiqueName: data.boutiqueName || "",
      category: data.category || [],
      colors: data.colors || [],
      price: data.price || 0,
      imageUrl: data.imageUrl || "",
      imageUrls: data.imageUrls || [],
      stock: data.stock || 0,
      madeToOrder: data.madeToOrder || false,
    };

    await saveAlgoliaObject(PRODUCTS_INDEX, record);
    logger.info("Algolia product updated", { productId });
  }
);

// ── Remove product from Algolia on delete ─────────────────────────────────
exports.algoliaProductDeleted = onDocumentDeleted(
  "boutiques/{boutiqueId}/products/{productId}",
  async (event) => {
    const { productId } = event.params;
    await deleteAlgoliaObject(PRODUCTS_INDEX, productId);
    logger.info("Algolia product deleted", { productId });
  }
);

// ── Sync boutique to Algolia on create ────────────────────────────────────
exports.algoliaBoutiqueCreated = onDocumentCreated(
  "boutiques/{boutiqueId}",
  async (event) => {
    const data = event.data.data();
    const { boutiqueId } = event.params;
    if (!data) return;

    const record = {
      objectID: boutiqueId,
      boutiqueId,
      name: data.name || "",
      description: data.description || "",
      logoPath: data.logoPath || "",
      bannerPath: data.bannerPath || "",
      tier: data.tier || "basic",
      isActive: data.isActive || false,
    };

    await saveAlgoliaObject(BOUTIQUES_INDEX, record);
    logger.info("Algolia boutique created", { boutiqueId });
  }
);

// ── Sync boutique to Algolia on update ────────────────────────────────────
exports.algoliaBoutiqueUpdated = onDocumentUpdated(
  "boutiques/{boutiqueId}",
  async (event) => {
    const data = event.data.after.data();
    const { boutiqueId } = event.params;
    if (!data) return;

    const record = {
      objectID: boutiqueId,
      boutiqueId,
      name: data.name || "",
      description: data.description || "",
      logoPath: data.logoPath || "",
      bannerPath: data.bannerPath || "",
      tier: data.tier || "basic",
      isActive: data.isActive || false,
    };

    await saveAlgoliaObject(BOUTIQUES_INDEX, record);
    logger.info("Algolia boutique updated", { boutiqueId });
  }
);

// ── Remove boutique from Algolia on delete ────────────────────────────────
exports.algoliaBoutiqueDeleted = onDocumentDeleted(
  "boutiques/{boutiqueId}",
  async (event) => {
    const { boutiqueId } = event.params;
    await deleteAlgoliaObject(BOUTIQUES_INDEX, boutiqueId);
    logger.info("Algolia boutique deleted", { boutiqueId });
  }
);

// ── One-time bulk index of all existing Firestore data ────────────────────
// Call this once from super admin to seed Algolia with existing products/boutiques
exports.algoliaReindex = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in.");
  }

  const reindexRateOk = await checkRateLimit(
    `reindex_${request.auth.uid}`,
    1,
    600,
  );
  if (!reindexRateOk) {
    throw new HttpsError(
      "resource-exhausted",
      "Too many requests. Please try again later.",
    );
  }

  const uid = request.auth.uid;
  const superAdmin = await isSuperAdminUser(uid);
  if (!superAdmin) {
    throw new HttpsError("permission-denied", "Super admins only.");
  }

  // Index all boutiques
  const boutiquesSnap = await db.collection("boutiques").get();
  const boutiqueRecords = boutiquesSnap.docs.map((doc) => ({
    objectID: doc.id,
    boutiqueId: doc.id,
    name: doc.data().name || "",
    description: doc.data().description || "",
    logoPath: doc.data().logoPath || "",
    tier: doc.data().tier || "basic",
    isActive: doc.data().isActive || false,
  }));

  if (boutiqueRecords.length > 0) {
    await saveAlgoliaObjects(BOUTIQUES_INDEX, boutiqueRecords);
  }

  // Index all products (collection group)
  const productsSnap = await db.collectionGroup("products").get();
  const productRecords = productsSnap.docs.map((doc) => {
    const data = doc.data();
    const boutiqueId = doc.ref.parent.parent?.id || "";
    return {
      objectID: doc.id,
      productId: doc.id,
      boutiqueId,
      title: data.title || "",
      description: data.description || "",
      boutiqueName: data.boutiqueName || "",
      category: data.category || [],
      colors: data.colors || [],
      price: data.price || 0,
      imageUrl: data.imageUrl || "",
      imageUrls: data.imageUrls || [],
      stock: data.stock || 0,
      madeToOrder: data.madeToOrder || false,
    };
  });

  if (productRecords.length > 0) {
    await saveAlgoliaObjects(PRODUCTS_INDEX, productRecords);
  }

  logger.info("Algolia reindex complete", {
    boutiques: boutiqueRecords.length,
    products: productRecords.length,
  });

  return {
    success: true,
    boutiquesIndexed: boutiqueRecords.length,
    productsIndexed: productRecords.length,
  };
});

// ================= SCHEDULED CLEANUPS =================

// Daily sweep of stale rate-limit documents — anything not touched in the
// past 24 hours is no longer needed for any rolling window we currently use.
exports.cleanupRateLimits = onSchedule("every 24 hours", async () => {
  const cutoff = Date.now() - (86400 * 1000);
  const snap = await db.collection("rate_limits")
    .where("updatedAt", "<", cutoff)
    .limit(500)
    .get();
  const batch = db.batch();
  snap.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
});

// Daily sweep of guest cart items older than 30 days. Guest carts live under
// `users/guest_<id>/cart_items/<itemId>`; we page through the guest user docs
// 100 at a time and batch-delete any items past the TTL.
exports.cleanupGuestCarts = onSchedule("every 24 hours", async () => {
  const cutoff = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - 30 * 24 * 60 * 60 * 1000),
  );

  const guestUsersSnap = await db.collection("users")
    .where("__name__", ">=", "guest_")
    .where("__name__", "<", "guest_~")
    .limit(100)
    .get();

  for (const userDoc of guestUsersSnap.docs) {
    const cartSnap = await userDoc.ref.collection("cart_items")
      .where("createdAt", "<", cutoff)
      .get();
    const batch = db.batch();
    cartSnap.docs.forEach((doc) => batch.delete(doc.ref));
    if (cartSnap.docs.length > 0) await batch.commit();
  }
});