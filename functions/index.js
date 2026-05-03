const {setGlobalOptions} = require("firebase-functions");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");

const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const { defineString } = require("firebase-functions/params");
const stripeSecret = defineString("STRIPE_SECRET_KEY");

admin.initializeApp();

const db = admin.firestore();

setGlobalOptions({maxInstances: 10});

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
    const deliveryCost = data.deliveryCost;
    const currency = data.currency;

    if (!items || !Array.isArray(items) || items.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "Items must be a non-empty array.",
      );
    }

    if (!currency || typeof currency !== "string") {
      throw new HttpsError("invalid-argument", "Currency is required.");
    }

    const allowedCurrencies = ["kwd", "usd", "gbp", "eur"];
    if (!allowedCurrencies.includes(currency.toLowerCase())) {
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

    const delivery = Number(deliveryCost) || 0;
    const total = subtotal + delivery;
    const multiplier = currency.toLowerCase() === "kwd" ? 1000 : 100;
    const amount = Math.round(total * multiplier);

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
      currency: currency.toLowerCase(),
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

  const allowedDeliveryMethods = ["Regular Delivery", "Same Day Delivery"];
  const allowedPaymentMethods  = ["Card"];

  if (!allowedDeliveryMethods.includes(deliveryMethod)) {
    throw new HttpsError("invalid-argument", "Invalid delivery method.");
  }

  if (!allowedPaymentMethods.includes(paymentMethod)) {
    throw new HttpsError("invalid-argument", "Invalid payment method.");
  }

  if (typeof paymentIntentId !== "string" || paymentIntentId.length > 200) {
    throw new HttpsError("invalid-argument", "Invalid paymentIntentId.");
  }

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

  const boutiqueMap = {};
  for (const item of items) {
    const bid = String(item.boutiqueId || "");
    if (!bid) continue;
    if (!boutiqueMap[bid]) boutiqueMap[bid] = [];
    boutiqueMap[bid].push(item);
  }

  const verifiedItems = [];
  let verifiedSubtotal = 0;

  await db.runTransaction(async (tx) => {
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

      const productRef  = db.collection("boutiques").doc(boutiqueId)
                            .collection("products").doc(productId);
      const productSnap = await tx.get(productRef);

      if (!productSnap.exists) {
        throw new HttpsError("not-found",
          `${item.title || "Product"} is no longer available.`);
      }

      const productData = productSnap.data();
      const stock       = Number(productData.stock) || 0;

      if (stock < quantity) {
        throw new HttpsError("failed-precondition",
          `${productData.title || "Product"} does not have enough stock.`);
      }

      const serverPrice = Number(productData.price) || 0;
      verifiedSubtotal += serverPrice * quantity;

      verifiedItems.push({
        productId,
        boutiqueId,
        title:        productData.title        || item.title       || "",
        imageUrl:     item.imageUrl            || "",
        description:  productData.description  || item.description || "",
        size:         item.size                || "",
        price:        serverPrice,
        quantity,
        boutiqueName: productData.boutiqueName || "",
      });
    }

    const deliveryCost = deliveryMethod === "Regular Delivery" ? 3 : 5;
    const total = verifiedSubtotal + deliveryCost;

    const orderBase = {
      orderNumber,
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

    for (const [boutiqueId] of Object.entries(boutiqueMap)) {
      const bItems = verifiedItems.filter(i => i.boutiqueId === boutiqueId);
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

    for (const item of verifiedItems) {
      const productRef = db.collection("boutiques").doc(item.boutiqueId)
                           .collection("products").doc(item.productId);
      tx.update(productRef, {
        stock: admin.firestore.FieldValue.increment(-item.quantity),
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