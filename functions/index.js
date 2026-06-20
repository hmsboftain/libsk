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
const resendApiKey = defineString("RESEND_API_KEY");
const myFatoorahApiKey = defineString("MYFATOORAH_API_KEY");

admin.initializeApp();

const db = admin.firestore();

setGlobalOptions({maxInstances: 10});

const {algoliasearch} = require("algoliasearch");

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
    notification: { title, body },
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
    converted[key] = (value === null || value === undefined) ? "" : String(value);
  }
  return converted;
}

async function sendNotificationToBoutiqueOwners(boutiqueId, title, body, type, extraData = {}) {
  const ownersSnapshot = await db
    .collection("boutique_owners")
    .where("boutiqueId", "==", boutiqueId)
    .where("isApproved", "==", true)
    .get();

  await Promise.all(ownersSnapshot.docs.map((ownerDoc) =>
    sendNotificationToUser(ownerDoc.id, title, body, type, extraData),
  ));
}

function getBoutiqueIdsFromItems(items) {
  const boutiqueIds = new Set();
  if (!Array.isArray(items)) return [];
  for (const item of items) {
    if (item.boutiqueId) boutiqueIds.add(String(item.boutiqueId));
  }
  return Array.from(boutiqueIds);
}

// ================= RATE LIMITING =================

async function checkRateLimit(key, maxRequests, windowSeconds) {
  const now = Date.now();
  const windowStart = now - (windowSeconds * 1000);
  const ref = db.collection("rate_limits").doc(key);

  return await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    const data = doc.exists ? doc.data() : { requests: [] };
    const recent = (data.requests || []).filter((ts) => ts > windowStart);

    if (recent.length >= maxRequests) return false;

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

    const withinLimit = await checkRateLimit(`payment_${request.auth.uid}`, 10, 3600);
    if (!withinLimit) {
      throw new HttpsError("resource-exhausted", "Too many requests. Please try again later.");
    }

    const items = data.items;
    const deliveryCost = data.deliveryCost;
    const currency = data.currency;

    if (!items || !Array.isArray(items) || items.length === 0) {
      throw new HttpsError("invalid-argument", "Items must be a non-empty array.");
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

      subtotal += (Number(productDoc.data().price) || 0) * quantity;
    }

    const delivery = Number(deliveryCost) || 0;
    const total = subtotal + delivery;
    const multiplier = currency.toLowerCase() === "kwd" ? 1000 : 100;
    const amount = Math.round(total * multiplier);

    if (amount <= 0) {
      throw new HttpsError("invalid-argument", "Order total must be greater than zero.");
    }

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
    throw new HttpsError("internal", error.message || "Failed to create payment intent.");
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
      throw new HttpsError("permission-denied", "Only approved admins can process refunds.");
    }

    const {paymentIntentId} = request.data || {};
    if (!paymentIntentId) {
      throw new HttpsError("invalid-argument", "paymentIntentId is required.");
    }
    if (typeof paymentIntentId !== "string" || paymentIntentId.length > 200) {
      throw new HttpsError("invalid-argument", "Invalid paymentIntentId.");
    }

    const refund = await stripe.refunds.create({ payment_intent: paymentIntentId });

    return { refundId: refund.id, status: refund.status };
  } catch (error) {
    logger.error("Refund error", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", error.message || "Failed to process refund.");
  }
});

// ================= CREATE ORDER =================

exports.createOrder = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "You must be logged in.");
  }

  const orderRateOk = await checkRateLimit(`order_${request.auth.uid}`, 5, 3600);
  if (!orderRateOk) {
    throw new HttpsError("resource-exhausted", "Too many requests. Please try again later.");
  }

  const uid             = request.auth.uid;
  const data            = request.data || {};
  const items           = data.items;
  const deliveryMethod  = data.deliveryMethod  || "";
  const paymentMethod   = data.paymentMethod   || "";
  const paymentIntentId = data.paymentIntentId || "";
  const discountCodeId  = data.discountCodeId  || null;
  const estimatedDays   = Number(data.estimatedDays) || null;

  if (!items || !Array.isArray(items) || items.length === 0) {
    throw new HttpsError("invalid-argument", "Items must be a non-empty array.");
  }
  if (items.length > 50) {
    throw new HttpsError("invalid-argument", "Order cannot contain more than 50 items.");
  }

  const allowedDeliveryMethods = ["Regular Delivery", "Same Day Delivery", "Made to Order"];
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

  const [addressSnap, userDoc] = await Promise.all([
    db.collection("users").doc(uid)
      .collection("saved_addresses")
      .orderBy("createdAt", "desc")
      .limit(1)
      .get(),
    db.collection("users").doc(uid).get(),
  ]);
  const addressData = addressSnap.empty ? null : addressSnap.docs[0].data();
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
    // Aggregate quantities per unique product first, so duplicate line items
    // (e.g. 4 + 4 of the same product against stock 5) can't each pass an
    // individual stock check and oversell.
    const productKeyOf = (b, p) => `${b}__${p}`;
    const productAgg = {};
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

      const key = productKeyOf(boutiqueId, productId);
      if (!productAgg[key]) productAgg[key] = { boutiqueId, productId, qty: 0 };
      productAgg[key].qty += quantity;
    }

    // Read each unique product once and verify stock against the AGGREGATED
    // quantity, capturing the server price for line-item construction below.
    const productInfo = {};
    for (const key of Object.keys(productAgg)) {
      const { boutiqueId, productId, qty } = productAgg[key];
      const productRef  = db.collection("boutiques").doc(boutiqueId)
                            .collection("products").doc(productId);
      const productSnap = await tx.get(productRef);

      if (!productSnap.exists) {
        throw new HttpsError("not-found", "A product in your cart is no longer available.");
      }

      const productData = productSnap.data();
      const stock       = Number(productData.stock) || 0;

      if (stock < qty) {
        throw new HttpsError("failed-precondition",
          `${productData.title || "Product"} does not have enough stock.`);
      }

      productInfo[key] = {
        ref: productRef,
        data: productData,
        price: Number(productData.price) || 0,
      };
    }

    // Build verified line items (kept per line for the order record) using the
    // server-verified price; never trust the client-supplied price.
    for (const item of items) {
      const boutiqueId = String(item.boutiqueId || "");
      const productId  = String(item.productId  || "");
      const quantity   = Math.max(1, Math.floor(Number(item.quantity) || 1));
      const info        = productInfo[productKeyOf(boutiqueId, productId)];
      const productData = info.data;
      const serverPrice = info.price;

      verifiedSubtotal += serverPrice * quantity;

      const verifiedItem = {
        productId,
        boutiqueId,
        title:        productData.title        || item.title       || "",
        imageUrl:     item.imageUrl            || "",
        description:  productData.description  || item.description || "",
        size:         item.size                || "",
        price:        serverPrice,
        quantity,
        boutiqueName: productData.boutiqueName || "",
      };
      const color = String(item.color || "").trim();
      if (color) verifiedItem.color = color;
      verifiedItems.push(verifiedItem);
    }

    if (verifiedSubtotal > 5000) {
      throw new HttpsError("invalid-argument", "Order total cannot exceed KD 5,000.");
    }

    // Validate discount code server-side — full validation inside the
    // transaction (snapshot isolation), mirroring validateDiscountCode so an
    // expired / exhausted / already-used code can't be replayed via createOrder.
    let discountAmount = 0;
    let discountCodeRef = null;
    if (discountCodeId) {
      discountCodeRef = db.collection("discount_codes").doc(discountCodeId);
      const codeSnap = await tx.get(discountCodeRef);
      if (!codeSnap.exists) {
        throw new HttpsError("not-found", "This discount code is no longer valid.");
      }
      const codeData = codeSnap.data();
      if (codeData.isActive !== true) {
        throw new HttpsError("failed-precondition", "This discount code is no longer active.");
      }
      if (codeData.expiresAt && codeData.expiresAt.toDate &&
          codeData.expiresAt.toDate() < new Date()) {
        throw new HttpsError("failed-precondition", "This discount code has expired.");
      }
      const usageLimit = codeData.usageLimit || null;
      const usageCount = codeData.usageCount || 0;
      if (usageLimit !== null && usageCount >= usageLimit) {
        throw new HttpsError("failed-precondition", "This discount code has reached its usage limit.");
      }
      if (codeData.singleUse === true) {
        const usedSnap = await tx.get(discountCodeRef.collection("used_by").doc(uid));
        if (usedSnap.exists) {
          throw new HttpsError("failed-precondition", "You have already used this discount code.");
        }
      }
      const codeValue = Number(codeData.value) || 0;
      if (codeData.type === "percentage") {
        discountAmount = parseFloat(((verifiedSubtotal * codeValue) / 100).toFixed(3));
      } else {
        discountAmount = Math.min(codeValue, verifiedSubtotal);
      }
    }
    // Clamp incoming discountAmount to server-verified value
    discountAmount = Math.max(0, Math.min(discountAmount, verifiedSubtotal));

    const deliveryCost = deliveryMethod === "Same Day Delivery" ? 5
      : deliveryMethod === "Made to Order" ? 0
      : 3;
    const total = verifiedSubtotal + deliveryCost - discountAmount;

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
      ...(discountCodeId && discountAmount > 0 ? { discountCodeId, discountAmount } : {}),
      ...(deliveryMethod === "Made to Order" && estimatedDays ? { estimatedDays } : {}),
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

    // Decrement stock + bump counters once per unique product, by the
    // aggregated quantity (matches the aggregated stock check above).
    for (const key of Object.keys(productAgg)) {
      tx.update(productInfo[key].ref, {
        stock: admin.firestore.FieldValue.increment(-productAgg[key].qty),
        weeklyOrders: admin.firestore.FieldValue.increment(productAgg[key].qty),
        salesCount: admin.firestore.FieldValue.increment(productAgg[key].qty),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    // Record discount usage atomically with the order. Previously this was a
    // separate post-commit transaction (D1) — if it failed, the order kept the
    // discount but usageCount / used_by never updated, enabling replay.
    if (discountCodeRef && discountAmount > 0) {
      tx.update(discountCodeRef, {
        usageCount: admin.firestore.FieldValue.increment(1),
      });
      tx.set(
        discountCodeRef.collection("used_by").doc(uid),
        { usedAt: admin.firestore.FieldValue.serverTimestamp() },
      );
    }
  });

  return { orderNumber };
});

// ================= DISCOUNT CODES =================

exports.validateDiscountCode = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "You must be logged in.");
  }

  const { code, subtotal } = request.data || {};

  if (!code || typeof code !== "string" || code.length > 50) {
    throw new HttpsError("invalid-argument", "Invalid code.");
  }

  const snap = await db.collection("discount_codes")
    .where("code", "==", code.toUpperCase().trim())
    .where("isActive", "==", true)
    .limit(1)
    .get();

  if (snap.empty) {
    throw new HttpsError("not-found", "Invalid or expired discount code.");
  }

  const docData = snap.docs[0].data();
  const docId = snap.docs[0].id;
  const now = new Date();

  if (docData.expiresAt && docData.expiresAt.toDate() < now) {
    throw new HttpsError("failed-precondition", "This code has expired.");
  }

  const usageLimit = docData.usageLimit || null;
  const usageCount = docData.usageCount || 0;
  if (usageLimit !== null && usageCount >= usageLimit) {
    throw new HttpsError("failed-precondition", "This code has reached its usage limit.");
  }

  const uid = request.auth.uid;
  if (docData.singleUse) {
    const usedSnap = await db.collection("discount_codes").doc(docId)
      .collection("used_by").doc(uid).get();
    if (usedSnap.exists) {
      throw new HttpsError("failed-precondition", "You have already used this code.");
    }
  }

  const type = docData.type;
  const value = Number(docData.value) || 0;
  const sub = Number(subtotal) || 0;

  let discountAmount = 0;
  if (type === "percentage") {
    discountAmount = parseFloat(((sub * value) / 100).toFixed(3));
  } else {
    discountAmount = Math.min(value, sub);
  }

  return {
    codeId: docId,
    code: docData.code,
    type,
    value,
    discountAmount,
    description: docData.description || "",
    boutiqueId: docData.boutiqueId || null,
    boutiqueName: docData.boutiqueName || "",
  };
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
        { type: "order_status", orderId, orderNumber, status: "Placed" },
      );
    }

    await Promise.all(getBoutiqueIdsFromItems(items).map((boutiqueId) =>
      sendNotificationToBoutiqueOwners(
        boutiqueId,
        "New order received",
        `A new order #${orderNumber} has been placed for your boutique.`,
        "new_boutique_order",
        { type: "order_status", orderId, orderNumber, boutiqueId, status: "Placed" },
      ),
    ));
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
        { type: "order_status", orderId, orderNumber, oldStatus, newStatus },
      );
    }

    await Promise.all(getBoutiqueIdsFromItems(items).map((boutiqueId) =>
      sendNotificationToBoutiqueOwners(
        boutiqueId,
        "Order status updated",
        `Order #${orderNumber} is now ${newStatus}.`,
        "boutique_order_status_updated",
        { type: "order_status", orderId, orderNumber, boutiqueId, oldStatus, newStatus },
      ),
    ));
  },
);

// ================= EMAIL NOTIFICATIONS (RESEND) =================

const { Resend } = require("resend");

function getResend() {
  return new Resend(resendApiKey.value());
}

async function sendOrderEmail(to, subject, html) {
  try {
    const resend = getResend();
    await resend.emails.send({
      from: "LIBSK <orders@libsk.com>",
      to,
      subject,
      html,
    });
    logger.info("Order email sent", { to, subject });
  } catch (err) {
    logger.error("Failed to send order email", { to, err });
  }
}

function orderEmailHtml({ title, orderNumber, date, customerName, items, subtotal, deliveryCost, total, deliveryMethod }) {
  const rows = items.map(item => `
    <tr>
      <td style="padding:10px 0;border-bottom:1px solid #E8E4DF;font-family:Georgia,serif;font-size:14px;color:#2C2925;">${item.title}</td>
      <td style="padding:10px 0;border-bottom:1px solid #E8E4DF;font-family:Georgia,serif;font-size:14px;color:#2C2925;text-align:center;">${item.size || "—"}</td>
      <td style="padding:10px 0;border-bottom:1px solid #E8E4DF;font-family:Georgia,serif;font-size:14px;color:#2C2925;text-align:center;">${item.quantity}</td>
      <td style="padding:10px 0;border-bottom:1px solid #E8E4DF;font-family:Georgia,serif;font-size:14px;color:#2C2925;text-align:right;">${item.price.toFixed(0)} KWD</td>
    </tr>
  `).join("");

  return `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#FFFDF8;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#FFFDF8;padding:40px 0;">
    <tr><td align="center">
      <table width="560" cellpadding="0" cellspacing="0" style="background:#FFFDF8;border:1px solid #DDD8D1;max-width:560px;width:100%;">
        <tr><td style="padding:32px 40px 24px;border-bottom:1px solid #DDD8D1;">
          <p style="margin:0;font-family:Georgia,serif;font-size:26px;letter-spacing:4px;color:#2C2925;text-transform:uppercase;">LIBSK</p>
        </td></tr>
        <tr><td style="padding:36px 40px;">
          <p style="margin:0 0 6px;font-family:Georgia,serif;font-size:20px;color:#2C2925;">${title}</p>
          <p style="margin:0 0 28px;font-family:Arial,sans-serif;font-size:13px;color:#8E877D;">Hello ${customerName},</p>
          <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:28px;">
            <tr>
              <td style="font-family:Arial,sans-serif;font-size:12px;color:#8E877D;text-transform:uppercase;letter-spacing:1px;">Order</td>
              <td style="font-family:Arial,sans-serif;font-size:12px;color:#8E877D;text-transform:uppercase;letter-spacing:1px;text-align:right;">Date</td>
            </tr>
            <tr>
              <td style="font-family:Georgia,serif;font-size:15px;color:#2C2925;padding-top:4px;">#${orderNumber}</td>
              <td style="font-family:Georgia,serif;font-size:15px;color:#2C2925;padding-top:4px;text-align:right;">${date}</td>
            </tr>
          </table>
          <table width="100%" cellpadding="0" cellspacing="0">
            <tr style="border-bottom:1px solid #2C2925;">
              <td style="font-family:Arial,sans-serif;font-size:11px;color:#8E877D;text-transform:uppercase;letter-spacing:1px;padding-bottom:8px;">Item</td>
              <td style="font-family:Arial,sans-serif;font-size:11px;color:#8E877D;text-transform:uppercase;letter-spacing:1px;padding-bottom:8px;text-align:center;">Size</td>
              <td style="font-family:Arial,sans-serif;font-size:11px;color:#8E877D;text-transform:uppercase;letter-spacing:1px;padding-bottom:8px;text-align:center;">Qty</td>
              <td style="font-family:Arial,sans-serif;font-size:11px;color:#8E877D;text-transform:uppercase;letter-spacing:1px;padding-bottom:8px;text-align:right;">Price</td>
            </tr>
            ${rows}
          </table>
          <table width="100%" cellpadding="0" cellspacing="0" style="margin-top:20px;">
            <tr>
              <td style="font-family:Arial,sans-serif;font-size:13px;color:#8E877D;padding:4px 0;">Subtotal</td>
              <td style="font-family:Arial,sans-serif;font-size:13px;color:#8E877D;padding:4px 0;text-align:right;">${subtotal.toFixed(0)} KWD</td>
            </tr>
            <tr>
              <td style="font-family:Arial,sans-serif;font-size:13px;color:#8E877D;padding:4px 0;">${deliveryMethod}</td>
              <td style="font-family:Arial,sans-serif;font-size:13px;color:#8E877D;padding:4px 0;text-align:right;">${deliveryCost.toFixed(0)} KWD</td>
            </tr>
            <tr><td colspan="2" style="border-top:1px solid #DDD8D1;padding-top:10px;"></td></tr>
            <tr>
              <td style="font-family:Georgia,serif;font-size:15px;color:#2C2925;font-weight:bold;padding:4px 0;">Total</td>
              <td style="font-family:Georgia,serif;font-size:15px;color:#2C2925;font-weight:bold;padding:4px 0;text-align:right;">${total.toFixed(0)} KWD</td>
            </tr>
          </table>
        </td></tr>
        <tr><td style="padding:20px 40px;border-top:1px solid #DDD8D1;">
          <p style="margin:0;font-family:Arial,sans-serif;font-size:12px;color:#8E877D;">Questions? Contact us at support@libsk.com</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

exports.sendOrderConfirmationEmail = onDocumentCreated(
  "global_orders/{orderId}",
  async (event) => {
    const order = event.data.data();
    if (!order || !order.customerEmail) return;

    const items = order.items || [];
    const deliveryCost = order.deliveryMethod === "Same Day Delivery" ? 5
      : order.deliveryMethod === "Made to Order" ? 0 : 3;
    const subtotal = items.reduce((s, i) => s + (i.price * i.quantity), 0);

    await sendOrderEmail(
      order.customerEmail,
      `Your LIBSK order #${order.orderNumber} is confirmed`,
      orderEmailHtml({
        title: "Order Confirmed",
        orderNumber: order.orderNumber,
        date: order.date,
        customerName: order.customerName || "Customer",
        items,
        subtotal,
        deliveryCost,
        total: order.total,
        deliveryMethod: order.deliveryMethod,
      }),
    );
  },
);

exports.sendOrderStatusEmail = onDocumentUpdated(
  "global_orders/{orderId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after) return;
    if (before.status === after.status) return;
    if (!after.customerEmail) return;

    const statusTitles = {
      "Picked Up": "Your order has been picked up",
      "Out for Delivery": "Your order is out for delivery",
      "Delivered": "Your order has been delivered",
      "Cancelled": "Your order has been cancelled",
    };

    const title = statusTitles[after.status];
    if (!title) return;

    const items = after.items || [];
    const deliveryCost = after.deliveryMethod === "Same Day Delivery" ? 5
      : after.deliveryMethod === "Made to Order" ? 0 : 3;
    const subtotal = items.reduce((s, i) => s + (i.price * i.quantity), 0);

    await sendOrderEmail(
      after.customerEmail,
      `Order #${after.orderNumber} — ${after.status}`,
      orderEmailHtml({
        title,
        orderNumber: after.orderNumber,
        date: after.date,
        customerName: after.customerName || "Customer",
        items,
        subtotal,
        deliveryCost,
        total: after.total,
        deliveryMethod: after.deliveryMethod,
      }),
    );
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
        { type: "dispute_status", disputeId, orderNumber, category },
      );
    }

    const adminsSnapshot = await db
      .collection("admin_users")
      .where("isApproved", "==", true)
      .get();

    await Promise.all(adminsSnapshot.docs.map((adminDoc) =>
      sendNotificationToUser(
        adminDoc.id,
        "New dispute received",
        `A new dispute was submitted for order #${orderNumber}.`,
        "admin_new_dispute",
        { type: "dispute_status", disputeId, orderNumber, category },
      ),
    ));
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

    if (oldStatus === newStatus && oldRefundIssued === newRefundIssued) return;

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
    } else if (newStatus === "Resolved" && newRefundIssued) {
      title = "Dispute resolved";
      body = `Your dispute for order #${orderNumber} was resolved and a refund was issued.`;
      type = "dispute_resolved_refund";
    } else if (newStatus === "Resolved") {
      title = "Dispute resolved";
      body = `Your dispute for order #${orderNumber} was resolved.`;
      type = "dispute_resolved";
    } else if (newStatus === "Rejected") {
      title = "Dispute rejected";
      body = `Your dispute for order #${orderNumber} was rejected.`;
      type = "dispute_rejected";
    }

    await sendNotificationToUser(
      customerUid, title, body, type,
      { type: "dispute_status", disputeId, orderNumber, oldStatus, newStatus, refundIssued: newRefundIssued },
    );
  },
);

exports.submitDispute = onCall(async (request) => {
  try {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be logged in.");
    }

    const disputeRateOk = await checkRateLimit(`dispute_${request.auth.uid}`, 3, 86400);
    if (!disputeRateOk) {
      throw new HttpsError("resource-exhausted", "Too many requests. Please try again later.");
    }

    const uid = request.auth.uid;
    const data = request.data || {};
    const orderId     = data.orderId;
    const category    = data.category;
    const description = data.description || "";

    if (!orderId || !category) {
      throw new HttpsError("invalid-argument", "orderId and category are required.");
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

    const userOrderRef = db.collection("users").doc(uid).collection("orders").doc(orderId);
    const orderDoc = await userOrderRef.get();

    if (!orderDoc.exists) throw new HttpsError("not-found", "Order not found.");

    const orderData = orderDoc.data();

    if (orderData.customerUid !== uid) {
      throw new HttpsError("permission-denied", "You can only dispute your own orders.");
    }
    if (String(orderData.status).toLowerCase() !== "delivered") {
      throw new HttpsError("failed-precondition", "Only delivered orders can be disputed.");
    }

    const createdAt = orderData.createdAt;
    if (!createdAt || !createdAt.toDate) {
      throw new HttpsError("failed-precondition", "Order date is missing.");
    }

    const diffDays = (new Date() - createdAt.toDate()) / (1000 * 60 * 60 * 24);
    if (diffDays > 7) {
      throw new HttpsError("failed-precondition", "The 7-day dispute window has passed.");
    }

    const existingDisputes = await db.collection("disputes")
      .where("orderId", "==", orderId)
      .where("customerUid", "==", uid)
      .limit(1)
      .get();

    if (!existingDisputes.empty) {
      throw new HttpsError("already-exists", "A dispute has already been submitted for this order.");
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

    return { success: true, disputeId: disputeRef.id };
  } catch (error) {
    logger.error("Submit dispute error", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", error.message || "Failed to submit dispute.");
  }
});

// ================= LOW STOCK NOTIFICATIONS =================

exports.notifyLowStock = onDocumentUpdated(
  "boutiques/{boutiqueId}/products/{productId}",
  async (event) => {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    const { boutiqueId, productId } = event.params;

    if (!beforeData || !afterData) return;

    const oldStock = Number(beforeData.stock) || 0;
    const newStock = Number(afterData.stock) || 0;

    if (oldStock <= 5 || newStock > 5) return;

    const productTitle = afterData.title || "Product";
    await sendNotificationToBoutiqueOwners(
      boutiqueId,
      "Low stock alert",
      `${productTitle} is running low. Only ${newStock} left in stock.`,
      "low_stock_alert",
      { type: "low_stock", boutiqueId, productId, productTitle, stock: newStock },
    );
  },
);

// ================= MANUAL ADMIN NOTIFICATIONS =================

exports.sendManualNotification = onCall(async (request) => {
  try {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be logged in.");
    }

    const notifRateOk = await checkRateLimit(`notification_${request.auth.uid}`, 50, 3600);
    if (!notifRateOk) {
      throw new HttpsError("resource-exhausted", "Too many requests. Please try again later.");
    }

    const uid = request.auth.uid;
    const isAdmin = await isAdminUser(uid);
    const isSuperAdmin = await isSuperAdminUser(uid);

    if (!isAdmin && !isSuperAdmin) {
      throw new HttpsError("permission-denied", "Only admins can send notifications.");
    }

    const data = request.data || {};
    const title = data.title;
    const body  = data.body;
    const targetType = data.targetType;

    if (!title || !body || !targetType) {
      throw new HttpsError("invalid-argument", "title, body and targetType are required.");
    }
    if (typeof title !== "string" || title.length > 100) {
      throw new HttpsError("invalid-argument", "Title must be under 100 characters.");
    }
    if (typeof body !== "string" || body.length > 500) {
      throw new HttpsError("invalid-argument", "Body must be under 500 characters.");
    }

    const allowedTargets = ["all_users", "boutique_owners", "admins"];
    if (!allowedTargets.includes(targetType)) {
      throw new HttpsError("invalid-argument", "Invalid targetType.");
    }

    const manualNotificationRef = await db.collection("manual_notifications").add({
      title, body, targetType,
      createdByUid: uid,
      createdByEmail: request.auth.token.email || "",
      status: "sending",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const extraData = {
      type: "manual",
      manualNotificationId: manualNotificationRef.id,
      targetType,
    };

    let sentCount = null;
    let broadcast = false;

    if (targetType === "all_users") {
      // Broadcast to every device through the "all_users" FCM topic — a single
      // send() instead of reading every user doc and messaging them one by one.
      // Devices subscribe to this topic on startup (NotificationService.initialize).
      await admin.messaging().send({
        topic: "all_users",
        notification: { title, body },
        data: convertDataToStrings(extraData),
      });
      broadcast = true;
    } else {
      // Targeted groups are small, bounded sets — fan out in parallel.
      const collectionName = targetType === "boutique_owners"
        ? "boutique_owners"
        : "admin_users";
      const targetUids = (await db.collection(collectionName)
        .where("isApproved", "==", true).get()).docs.map((d) => d.id);

      await Promise.all(targetUids.map((uid) =>
        sendNotificationToUser(uid, title, body, "manual_notification", extraData),
      ));
      sentCount = targetUids.length;
    }

    await manualNotificationRef.update({
      status: "sent",
      ...(broadcast ? { broadcast: true } : { sentCount }),
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, sentCount, broadcast };
  } catch (error) {
    logger.error("Manual notification error", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", error.message || "Failed to send manual notification.");
  }
});

// ================= ALGOLIA SEARCH SYNC =================

exports.algoliaProductCreated = onDocumentCreated(
  "boutiques/{boutiqueId}/products/{productId}",
  async (event) => {
    const data = event.data.data();
    const { boutiqueId, productId } = event.params;
    if (!data) return;
    await saveAlgoliaObject(PRODUCTS_INDEX, {
      objectID: productId, productId, boutiqueId,
      title: data.title || "", description: data.description || "",
      boutiqueName: data.boutiqueName || "", category: data.category || [],
      colors: data.colors || [], price: data.price || 0,
      imageUrl: data.imageUrl || "", imageUrls: data.imageUrls || [],
      stock: data.stock || 0, madeToOrder: data.madeToOrder || false,
    });
  }
);

exports.algoliaProductUpdated = onDocumentUpdated(
  "boutiques/{boutiqueId}/products/{productId}",
  async (event) => {
    const data = event.data.after.data();
    const { boutiqueId, productId } = event.params;
    if (!data) return;
    await saveAlgoliaObject(PRODUCTS_INDEX, {
      objectID: productId, productId, boutiqueId,
      title: data.title || "", description: data.description || "",
      boutiqueName: data.boutiqueName || "", category: data.category || [],
      colors: data.colors || [], price: data.price || 0,
      imageUrl: data.imageUrl || "", imageUrls: data.imageUrls || [],
      stock: data.stock || 0, madeToOrder: data.madeToOrder || false,
    });
  }
);

exports.algoliaProductDeleted = onDocumentDeleted(
  "boutiques/{boutiqueId}/products/{productId}",
  async (event) => {
    await deleteAlgoliaObject(PRODUCTS_INDEX, event.params.productId);
  }
);

exports.algoliaBoutiqueCreated = onDocumentCreated(
  "boutiques/{boutiqueId}",
  async (event) => {
    const data = event.data.data();
    const { boutiqueId } = event.params;
    if (!data) return;
    await saveAlgoliaObject(BOUTIQUES_INDEX, {
      objectID: boutiqueId, boutiqueId,
      name: data.name || "", description: data.description || "",
      logoPath: data.logoPath || "", bannerPath: data.bannerPath || "",
      isActive: data.isActive || false,
    });
  }
);

exports.algoliaBoutiqueUpdated = onDocumentUpdated(
  "boutiques/{boutiqueId}",
  async (event) => {
    const data = event.data.after.data();
    const { boutiqueId } = event.params;
    if (!data) return;
    await saveAlgoliaObject(BOUTIQUES_INDEX, {
      objectID: boutiqueId, boutiqueId,
      name: data.name || "", description: data.description || "",
      logoPath: data.logoPath || "", bannerPath: data.bannerPath || "",
      isActive: data.isActive || false,
    });
  }
);

exports.algoliaBoutiqueDeleted = onDocumentDeleted(
  "boutiques/{boutiqueId}",
  async (event) => {
    await deleteAlgoliaObject(BOUTIQUES_INDEX, event.params.boutiqueId);
  }
);

exports.algoliaReindex = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be logged in.");

  const reindexRateOk = await checkRateLimit(`reindex_${request.auth.uid}`, 1, 600);
  if (!reindexRateOk) throw new HttpsError("resource-exhausted", "Too many requests. Please try again later.");

  if (!await isSuperAdminUser(request.auth.uid)) {
    throw new HttpsError("permission-denied", "Super admins only.");
  }

  const boutiquesSnap = await db.collection("boutiques").get();
  const boutiqueRecords = boutiquesSnap.docs.map(doc => ({
    objectID: doc.id, boutiqueId: doc.id,
    name: doc.data().name || "", description: doc.data().description || "",
    logoPath: doc.data().logoPath || "",
    isActive: doc.data().isActive || false,
  }));
  if (boutiqueRecords.length > 0) await saveAlgoliaObjects(BOUTIQUES_INDEX, boutiqueRecords);

  const productsSnap = await db.collectionGroup("products").get();
  const productRecords = productsSnap.docs.map(doc => {
    const data = doc.data();
    const boutiqueId = doc.ref.parent.parent?.id || "";
    return {
      objectID: doc.id, productId: doc.id, boutiqueId,
      title: data.title || "", description: data.description || "",
      boutiqueName: data.boutiqueName || "", category: data.category || [],
      colors: data.colors || [], price: data.price || 0,
      imageUrl: data.imageUrl || "", imageUrls: data.imageUrls || [],
      stock: data.stock || 0, madeToOrder: data.madeToOrder || false,
    };
  });
  if (productRecords.length > 0) await saveAlgoliaObjects(PRODUCTS_INDEX, productRecords);

  return { success: true, boutiquesIndexed: boutiqueRecords.length, productsIndexed: productRecords.length };
});

// ================= SCHEDULED CLEANUPS =================

exports.cleanupRateLimits = onSchedule("every 24 hours", async () => {
  const cutoff = Date.now() - (86400 * 1000);
  const snap = await db.collection("rate_limits").where("updatedAt", "<", cutoff).limit(500).get();
  const batch = db.batch();
  snap.docs.forEach(doc => batch.delete(doc.ref));
  await batch.commit();
});

exports.cleanupGuestCarts = onSchedule("every 24 hours", async () => {
  const cutoff = admin.firestore.Timestamp.fromDate(new Date(Date.now() - 30 * 24 * 60 * 60 * 1000));
  const guestUsersSnap = await db.collection("users")
    .where("__name__", ">=", "guest_")
    .where("__name__", "<", "guest_~")
    .limit(100)
    .get();

  for (const userDoc of guestUsersSnap.docs) {
    const cartSnap = await userDoc.ref.collection("cart_items").where("createdAt", "<", cutoff).get();
    const batch = db.batch();
    cartSnap.docs.forEach(doc => batch.delete(doc.ref));
    if (cartSnap.docs.length > 0) await batch.commit();
  }
});

exports.resetWeeklyTrending = onSchedule(
  { schedule: "0 0 * * 1", timeZone: "Asia/Kuwait" },
  async () => {
    const trendingSnap = await db.collectionGroup("products").where("weeklyOrders", ">", 0).get();
    let batch = db.batch();
    let ops = 0;
    for (const doc of trendingSnap.docs) {
      batch.update(doc.ref, {weeklyOrders: 0});
      ops++;
      if (ops === 450) { await batch.commit(); batch = db.batch(); ops = 0; }
    }
    if (ops > 0) await batch.commit();
  },
);

exports.expireFeedSponsored = onSchedule("every 1 hours", async () => {
  const now = admin.firestore.Timestamp.now();
  const snap = await db.collectionGroup("products")
    .where("isFeedSponsored", "==", true)
    .where("feedSponsoredUntil", "<", now)
    .limit(500)
    .get();
  const batch = db.batch();
  snap.docs.forEach(doc => batch.update(doc.ref, { isFeedSponsored: false }));
  if (snap.docs.length > 0) await batch.commit();
});

// ================= PROMO SLOTS =================

exports.initiatePromoSlotPayment = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "You must be logged in.");

  const { promoSlotId } = request.data || {};
  if (!promoSlotId || typeof promoSlotId !== "string") {
    throw new HttpsError("invalid-argument", "promoSlotId is required.");
  }

  const slotDoc = await db.collection("promo_slots").doc(promoSlotId).get();
  if (!slotDoc.exists) throw new HttpsError("not-found", "Promo slot not found.");

  const slotData = slotDoc.data();
  const ownerDoc = await db.collection("boutique_owners").doc(request.auth.uid).get();
  if (!ownerDoc.exists || ownerDoc.data().boutiqueId !== slotData.boutiqueId) {
    throw new HttpsError("permission-denied", "Not your promo slot.");
  }
  if (slotData.paymentStatus === "paid") {
    throw new HttpsError("failed-precondition", "Slot is already paid.");
  }

  // Uncomment when MyFatoorah API key is ready:
  // const axios = require("axios");
  // const response = await axios.post(`https://api.myfatoorah.com/v2/InitiatePayment`, {
  //   InvoiceAmount: slotData.priceKwd, CurrencyIso: "KWD",
  // }, { headers: { Authorization: `Bearer ${myFatoorahApiKey.value()}`, "Content-Type": "application/json" } });
  // await db.collection("promo_slots").doc(promoSlotId).update({
  //   myFatoorahInvoiceId: response.data.Data.InvoiceId,
  //   paymentInitiatedAt: admin.firestore.FieldValue.serverTimestamp(),
  // });
  // return { paymentUrl: response.data.Data.PaymentURL };

  throw new HttpsError("unimplemented", "MyFatoorah API key not configured yet.");
});

exports.promoSlotPaymentWebhook = require("firebase-functions/v2/https").onRequest(async (req, res) => {
  try {
    const invoiceId = req.body?.InvoiceId || req.body?.invoiceId;
    if (!invoiceId) { res.status(400).send("Missing InvoiceId"); return; }

    const snap = await db.collection("promo_slots")
      .where("myFatoorahInvoiceId", "==", String(invoiceId))
      .limit(1).get();

    if (snap.empty) { res.status(200).send("OK"); return; }

    const slotDoc = snap.docs[0];
    if (slotDoc.data().paymentStatus === "paid") { res.status(200).send("OK"); return; }

    const durationDays = slotDoc.data().durationDays || 7;
    const expiresAt = new Date(Date.now() + durationDays * 86400000);

    await slotDoc.ref.update({
      status: "active", paymentStatus: "paid",
      activatedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    });

    res.status(200).send("OK");
  } catch (err) {
    logger.error("Webhook error", err);
    res.status(200).send("OK");
  }
});

exports.expirePromoSlots = onSchedule("every 1 hours", async () => {
  const now = admin.firestore.Timestamp.now();
  const snap = await db.collection("promo_slots")
    .where("status", "==", "active").where("expiresAt", "<", now).limit(200).get();
  const batch = db.batch();
  snap.docs.forEach(doc => batch.update(doc.ref, { status: "expired" }));
  if (snap.docs.length > 0) await batch.commit();
});

exports.adminActivatePromoSlot = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be logged in.");
  if (!await isSuperAdminUser(request.auth.uid)) {
    throw new HttpsError("permission-denied", "Super admins only.");
  }

  const { promoSlotId } = request.data || {};
  if (!promoSlotId) throw new HttpsError("invalid-argument", "promoSlotId required.");

  const slotDoc = await db.collection("promo_slots").doc(promoSlotId).get();
  if (!slotDoc.exists) throw new HttpsError("not-found", "Slot not found.");

  const durationDays = slotDoc.data().durationDays || 7;
  const expiresAt = new Date(Date.now() + durationDays * 86400000);

  await slotDoc.ref.update({
    status: "active", paymentStatus: "paid",
    activatedAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
  });

  return { success: true };
});

// ================= FOLLOW COUNTS =================

exports.onFollowCreated = onDocumentCreated(
  "users/{userId}/following/{boutiqueId}",
  async (event) => {
    const boutiqueId = event.params.boutiqueId;
    await db.collection("boutiques").doc(boutiqueId).update({
      followerCount: admin.firestore.FieldValue.increment(1),
    });
  },
);

exports.onFollowDeleted = onDocumentDeleted(
  "users/{userId}/following/{boutiqueId}",
  async (event) => {
    const boutiqueId = event.params.boutiqueId;
    const boutiqueRef = db.collection("boutiques").doc(boutiqueId);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(boutiqueRef);
      const current = snap.data()?.followerCount ?? 0;
      tx.update(boutiqueRef, {
        followerCount: Math.max(0, current - 1),
      });
    });
  },
);

// ================= PUBLIC FORM HELPERS =================

// Escape user input before putting it in an HTML email body. & must be first.
function escapeHtml(value) {
  return String(value === null || value === undefined ? "" : value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// Derive a Firestore-safe rate-limit key from the caller IP (Cloud Run puts the
// real client IP first in x-forwarded-for).
function clientIpKey(req) {
  const fwd = req.headers["x-forwarded-for"];
  const raw = (Array.isArray(fwd) ? fwd[0] : String(fwd || "")).split(",")[0].trim() ||
    req.ip || "unknown";
  return raw.replace(/[^a-zA-Z0-9]/g, "_").slice(0, 80);
}

function isValidEmail(value) {
  return typeof value === "string" && value.length <= 200 &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

// Optional string field: absent/null OR a string within maxLen.
function optStr(value, maxLen) {
  return value === undefined || value === null ||
    (typeof value === "string" && value.length <= maxLen);
}

// True only if every key on obj is in the allowed list.
function onlyAllowedKeys(obj, allowed) {
  return Object.keys(obj).every((k) => allowed.includes(k));
}

// ================= BOUTIQUE APPLICATION =================

exports.submitBoutiqueApplication = require("firebase-functions/v2/https").onRequest(
  { cors: ["https://libsk.com", "https://www.libsk.com", "https://libsk-b68f5.web.app"] },
  async (req, res) => {
    if (req.method !== "POST") { res.status(405).send("Method not allowed"); return; }

    try {
      const data = req.body || {};

      // (1) Rate limit — 5 submissions per IP per hour
      const withinLimit = await checkRateLimit(`boutique_app_${clientIpKey(req)}`, 5, 3600);
      if (!withinLimit) {
        res.status(429).json({ error: "Too many submissions. Please try again later." });
        return;
      }

      // (2) Reject unexpected fields entirely
      const allowed = [
        "firstName", "lastName", "boutiqueName", "instagram", "email", "phone",
        "category", "description", "productCount", "priceRange", "currentSells",
        "referral", "message",
      ];
      if (typeof data !== "object" || Array.isArray(data) || !onlyAllowedKeys(data, allowed)) {
        res.status(400).json({ error: "Invalid request." });
        return;
      }

      // (2) Required fields
      if (!isValidEmail(data.email) ||
          typeof data.firstName !== "string" || data.firstName.length === 0 || data.firstName.length > 100 ||
          typeof data.boutiqueName !== "string" || data.boutiqueName.length === 0 || data.boutiqueName.length > 100) {
        res.status(400).json({ error: "Missing or invalid required fields." });
        return;
      }

      // (2) Optional fields — length-capped
      if (!optStr(data.lastName, 100) || !optStr(data.instagram, 100) ||
          !optStr(data.phone, 20) || !optStr(data.category, 100) ||
          !optStr(data.description, 2000) || !optStr(data.productCount, 50) ||
          !optStr(data.priceRange, 50) || !optStr(data.referral, 200) ||
          !optStr(data.message, 2000)) {
        res.status(400).json({ error: "One or more fields are invalid." });
        return;
      }

      // (2) currentSells — optional array of <=20 short strings
      let currentSells = [];
      if (data.currentSells !== undefined) {
        if (!Array.isArray(data.currentSells) || data.currentSells.length > 20 ||
            !data.currentSells.every((s) => typeof s === "string" && s.length <= 50)) {
          res.status(400).json({ error: "Invalid currentSells." });
          return;
        }
        currentSells = data.currentSells;
      }

      // (4) Whitelisted Firestore write — explicit fields, no ...data spread
      await db.collection("boutique_applications").add({
        firstName: data.firstName,
        lastName: data.lastName || "",
        boutiqueName: data.boutiqueName,
        instagram: data.instagram || "",
        email: data.email,
        phone: data.phone || "",
        category: data.category || "",
        description: data.description || "",
        productCount: data.productCount || "",
        priceRange: data.priceRange || "",
        currentSells,
        referral: data.referral || "",
        message: data.message || "",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        status: "pending",
      });

      // (3) Email — every user value HTML-escaped
      const resend = getResend();
      await resend.emails.send({
        from: "LIBSK <orders@libsk.com>",
        to: "hello@libsk.com",
        subject: `New boutique application — ${data.boutiqueName}`,
        html: `
          <p><strong>Name:</strong> ${escapeHtml(data.firstName)} ${escapeHtml(data.lastName || "")}</p>
          <p><strong>Boutique:</strong> ${escapeHtml(data.boutiqueName)}</p>
          <p><strong>Instagram:</strong> ${escapeHtml(data.instagram || "")}</p>
          <p><strong>Email:</strong> ${escapeHtml(data.email)}</p>
          <p><strong>Phone:</strong> ${escapeHtml(data.phone || "")}</p>
          <p><strong>Category:</strong> ${escapeHtml(data.category || "")}</p>
          <p><strong>Description:</strong> ${escapeHtml(data.description || "")}</p>
          <p><strong>Products:</strong> ${escapeHtml(data.productCount || "")} — ${escapeHtml(data.priceRange || "")}</p>
          <p><strong>Currently sells on:</strong> ${escapeHtml(currentSells.join(", "))}</p>
          <p><strong>Referral:</strong> ${escapeHtml(data.referral || "")}</p>
          <p><strong>Message:</strong> ${escapeHtml(data.message || "—")}</p>
        `,
      });

      res.status(200).json({ success: true });
    } catch (err) {
      logger.error("Boutique application error", err);
      res.status(500).json({ error: "Failed to submit application" });
    }
  }
);

// ================= CONTACT FORM =================

exports.submitContactForm = require("firebase-functions/v2/https").onRequest(
  { cors: ["https://libsk.com", "https://www.libsk.com", "https://libsk-b68f5.web.app"] },
  async (req, res) => {
    if (req.method !== "POST") { res.status(405).send("Method not allowed"); return; }
    try {
      const data = req.body || {};

      // (1) Rate limit — 5 submissions per IP per hour
      const withinLimit = await checkRateLimit(`contact_form_${clientIpKey(req)}`, 5, 3600);
      if (!withinLimit) {
        res.status(429).json({ error: "Too many submissions. Please try again later." });
        return;
      }

      // (2) Reject unexpected fields
      const allowed = ["firstName", "lastName", "email", "phone", "topic", "orderNumber", "message"];
      if (typeof data !== "object" || Array.isArray(data) || !onlyAllowedKeys(data, allowed)) {
        res.status(400).json({ error: "Invalid request." });
        return;
      }

      // (2) Required fields
      if (!isValidEmail(data.email) ||
          typeof data.message !== "string" || data.message.length === 0 || data.message.length > 2000) {
        res.status(400).json({ error: "Missing or invalid required fields." });
        return;
      }

      // (2) Optional fields — length-capped
      if (!optStr(data.firstName, 100) || !optStr(data.lastName, 100) ||
          !optStr(data.phone, 20) || !optStr(data.topic, 50) ||
          !optStr(data.orderNumber, 50)) {
        res.status(400).json({ error: "One or more fields are invalid." });
        return;
      }

      // Route to correct email based on topic
      const toBoutiques = data.topic === "boutique";
      const toEmail = toBoutiques ? "boutiques@libsk.com" : "hello@libsk.com";

      // (3) Email — escape every value; escape THEN convert newlines to <br>
      const resend = getResend();
      await resend.emails.send({
        from: "LIBSK Contact <orders@libsk.com>",
        to: toEmail,
        reply_to: data.email,
        subject: `[${data.topic || "Contact"}] Message from ${data.firstName || ""} ${data.lastName || ""}`,
        html: `
          <p><strong>Name:</strong> ${escapeHtml(data.firstName || "")} ${escapeHtml(data.lastName || "")}</p>
          <p><strong>Email:</strong> ${escapeHtml(data.email)}</p>
          <p><strong>Phone:</strong> ${escapeHtml(data.phone || "—")}</p>
          <p><strong>Topic:</strong> ${escapeHtml(data.topic || "")}</p>
          <p><strong>Order Number:</strong> ${escapeHtml(data.orderNumber || "—")}</p>
          <hr/>
          <p>${escapeHtml(data.message).replace(/\n/g, "<br>")}</p>
        `,
      });

      // (4) Whitelisted Firestore write — explicit fields, no ...data spread
      await db.collection("contact_submissions").add({
        firstName: data.firstName || "",
        lastName: data.lastName || "",
        email: data.email,
        phone: data.phone || "",
        topic: data.topic || "",
        orderNumber: data.orderNumber || "",
        message: data.message,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      res.status(200).json({ success: true });
    } catch (err) {
      logger.error("Contact form error", err);
      res.status(500).json({ error: "Failed to send message" });
    }
  }
);