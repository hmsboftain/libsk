const {setGlobalOptions} = require("firebase-functions");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
} = require("firebase-functions/v2/firestore");

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
  ORDER_CURRENCY,
  getDeliveryCost,
  isSupportedDeliveryMethod,
  isSupportedOrderCurrency,
  normalizeOrderCurrency,
  toStripeAmount,
} = require("./order_utils");

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

// ================= PAYMENTS =================

exports.createPaymentIntent = onCall(async (request) => {
  const stripe = require("stripe")(stripeSecret.value());
  try {
    const data = request.data || {};

    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be logged in.");
    }

    logger.info("Callable data received", {data});

    const items = data.items;
    const deliveryMethod = data.deliveryMethod;
    const currency = normalizeOrderCurrency(data.currency);

    if (!items || !Array.isArray(items) || items.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "Items must be a non-empty array.",
      );
    }

    if (!isSupportedDeliveryMethod(deliveryMethod)) {
      throw new HttpsError("invalid-argument", "Invalid delivery method.");
    }

    if (!isSupportedOrderCurrency(currency)) {
      throw new HttpsError("invalid-argument", "Unsupported currency.");
    }

    let subtotal = 0;

    for (const item of items) {
      const boutiqueId = String(item.boutiqueId || "");
      const productId  = String(item.productId  || "");
      const quantity   = Math.max(1, Math.floor(Number(item.quantity) || 1));

      if (!boutiqueId || !productId) {
        throw new HttpsError("invalid-argument", "Each item must have boutiqueId and productId.");
      }

      if (quantity > 100) {
        throw new HttpsError("invalid-argument", "Quantity cannot exceed 100 per item.");
      }

      const productDoc = await db
        .collection("boutiques").doc(boutiqueId)
        .collection("products").doc(productId)
        .get();

      if (!productDoc.exists) {
        throw new HttpsError("not-found", `Product ${productId} not found.`);
      }

      const serverPrice = Number(productDoc.data().price) || 0;
      subtotal += serverPrice * quantity;
    }

    const delivery = getDeliveryCost(deliveryMethod);
    const total = subtotal + delivery;
    const amount = toStripeAmount(total, currency);

    if (!amount || amount <= 0) {
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
      currency,
      metadata: {
        customerUid: request.auth.uid,
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
  const stripe = require("stripe")(stripeSecret.value());

  if (!request.auth) {
    throw new HttpsError("unauthenticated", "You must be logged in.");
  }

  const uid             = request.auth.uid;
  const data            = request.data || {};
  const items           = data.items;
  const deliveryMethod  = data.deliveryMethod  || "";
  const paymentMethod   = data.paymentMethod   || "";
  const paymentIntentId = data.paymentIntentId || "";

  if (!items || !Array.isArray(items) || items.length === 0) {
    throw new HttpsError("invalid-argument", "Items must be a non-empty array.");
  }

  if (items.length > 50) {
    throw new HttpsError("invalid-argument", "Order cannot contain more than 50 items.");
  }

  const allowedPaymentMethods  = ["Card"];

  if (!isSupportedDeliveryMethod(deliveryMethod)) {
    throw new HttpsError("invalid-argument", "Invalid delivery method.");
  }

  if (!allowedPaymentMethods.includes(paymentMethod)) {
    throw new HttpsError("invalid-argument", "Invalid payment method.");
  }

  if (
    typeof paymentIntentId !== "string" ||
    paymentIntentId.length === 0 ||
    paymentIntentId.length > 200
  ) {
    throw new HttpsError("invalid-argument", "Invalid paymentIntentId.");
  }

  let paymentIntent;
  try {
    paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
  } catch (error) {
    logger.warn("PaymentIntent verification failed", {
      paymentIntentId,
      uid,
      error,
    });
    throw new HttpsError(
      "failed-precondition",
      "Payment could not be verified.",
    );
  }

  const paymentCurrency = normalizeOrderCurrency(paymentIntent.currency);
  const paymentMetadata = paymentIntent.metadata || {};

  if (paymentIntent.status !== "succeeded") {
    throw new HttpsError(
      "failed-precondition",
      "Payment has not completed.",
    );
  }

  if (!isSupportedOrderCurrency(paymentCurrency)) {
    throw new HttpsError(
      "failed-precondition",
      "Payment currency does not match this store.",
    );
  }

  if (paymentMetadata.customerUid !== uid) {
    throw new HttpsError(
      "permission-denied",
      "Payment does not belong to this user.",
    );
  }

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

  const userOrderRef = db.collection("users").doc(uid).collection("orders").doc();
  const globalOrderRef = db.collection("global_orders").doc(userOrderRef.id);
  const counterRef = db.collection("metadata").doc("order_counter");
  const consumedPaymentRef = db
    .collection("payment_intents")
    .doc(paymentIntentId);

  const orderNumber = await db.runTransaction(async (tx) => {
    const consumedPaymentSnap = await tx.get(consumedPaymentRef);
    if (consumedPaymentSnap.exists) {
      throw new HttpsError(
        "already-exists",
        "Payment has already been used for an order.",
      );
    }

    const verifiedItems = [];
    const productChecks = new Map();
    const boutiqueIds = new Set();
    let verifiedSubtotal = 0;

    for (const item of items) {
      const boutiqueId = String(item.boutiqueId || "");
      const productId  = String(item.productId  || "");
      const quantity   = Math.max(1, Math.floor(Number(item.quantity) || 1));

      if (!boutiqueId || !productId) {
        throw new HttpsError("invalid-argument", "Invalid product information.");
      }

      if (quantity > 100) {
        throw new HttpsError("invalid-argument", "Quantity cannot exceed 100 per item.");
      }

      const productKey = `${boutiqueId}/${productId}`;
      let productCheck = productChecks.get(productKey);

      if (!productCheck) {
        const productRef = db.collection("boutiques").doc(boutiqueId)
                             .collection("products").doc(productId);
        const productSnap = await tx.get(productRef);

        if (!productSnap.exists) {
          throw new HttpsError("not-found",
            `${item.title || "Product"} is no longer available.`);
        }

        const productData = productSnap.data();
        const stock = Number(productData.stock) || 0;

        productCheck = {
          productRef,
          productData,
          stock,
          requestedQuantity: 0,
        };
        productChecks.set(productKey, productCheck);
      }

      productCheck.requestedQuantity += quantity;

      if (productCheck.stock < productCheck.requestedQuantity) {
        throw new HttpsError("failed-precondition",
          `${productCheck.productData.title || "Product"} does not have enough stock.`);
      }

      const serverPrice = Number(productCheck.productData.price) || 0;
      verifiedSubtotal += serverPrice * quantity;
      boutiqueIds.add(boutiqueId);

      const verifiedItem = {
        productId,
        boutiqueId,
        title:        productCheck.productData.title        || item.title       || "",
        imageUrl:     item.imageUrl            || "",
        description:  productCheck.productData.description  || item.description || "",
        size:         item.size                || "",
        price:        serverPrice,
        quantity,
        boutiqueName: productCheck.productData.boutiqueName || "",
      };
      const color = String(item.color || "").trim();
      if (color) {
        verifiedItem.color = color;
      }
      verifiedItems.push(verifiedItem);
    }

    const deliveryCost = getDeliveryCost(deliveryMethod);
    const total = verifiedSubtotal + deliveryCost;
    const expectedAmount = toStripeAmount(total, ORDER_CURRENCY);
    const amountReceived = typeof paymentIntent.amount_received === "number" ?
      paymentIntent.amount_received :
      paymentIntent.amount;

    if (
      paymentCurrency !== ORDER_CURRENCY ||
      paymentIntent.amount !== expectedAmount ||
      amountReceived < expectedAmount
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Payment amount does not match the order total.",
      );
    }

    const counterSnap = await tx.get(counterRef);
    let last = 100000;
    if (
      counterSnap.exists &&
      typeof counterSnap.data().lastOrderNumber === "number"
    ) {
      last = counterSnap.data().lastOrderNumber;
    }
    const nextOrderNumber = String(last + 1);

    const orderBase = {
      orderNumber: nextOrderNumber,
      date: dateString,
      itemCount: verifiedItems.reduce((s, i) => s + i.quantity, 0),
      total,
      status: "Placed",
      customerUid: uid,
      customerName,
      customerEmail,
      deliveryMethod,
      paymentMethod,
      paymentIntentId,
      address: addressData,
      items: verifiedItems,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    tx.set(userOrderRef, orderBase);
    tx.set(globalOrderRef, { ...orderBase, sourceUserOrderId: userOrderRef.id });
    tx.create(consumedPaymentRef, {
      uid,
      orderId: userOrderRef.id,
      paymentIntentId,
      amount: paymentIntent.amount,
      currency: paymentCurrency,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.set(counterRef, { lastOrderNumber: last + 1 }, { merge: true });

    for (const boutiqueId of boutiqueIds) {
      const bItems = verifiedItems.filter(i => i.boutiqueId === boutiqueId);
      const bTotal = bItems.reduce((s, i) => s + i.price * i.quantity, 0);
      const bCount = bItems.reduce((s, i) => s + i.quantity, 0);

      const boutiqueOrderRef = db.collection("boutiques").doc(boutiqueId)
                                 .collection("orders").doc();

      tx.set(boutiqueOrderRef, {
        orderNumber: nextOrderNumber,
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

    for (const productCheck of productChecks.values()) {
      tx.update(productCheck.productRef, {
        stock: admin.firestore.FieldValue.increment(
          -productCheck.requestedQuantity,
        ),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return nextOrderNumber;
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