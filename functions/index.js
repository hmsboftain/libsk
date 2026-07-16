const {setGlobalOptions} = require("firebase-functions");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
} = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const crypto = require("crypto");
// Pure founding-partner credit math (fils conversion + FIFO allocation), unit-
// tested in test/promo_credit.test.js. All credit calculations delegate here.
const {
  FOUNDING_WEEK1_KWD,
  FOUNDING_WEEK2_KWD,
  CREDIT_EXPIRY_DAYS,
  kwdToFils,
  filsToKwd,
  applyFilsDelta,
  spendableBalanceFils,
  allocateCreditFifo,
  splitCreditCharge,
} = require("./promo_credit");
const { defineString, defineSecret } = require("firebase-functions/params");
const algoliaAppId = defineString("ALGOLIA_APP_ID");
const algoliaAdminKey = defineString("ALGOLIA_ADMIN_KEY");
const resendApiKey = defineString("RESEND_API_KEY");
const myFatoorahApiKey = defineString("MYFATOORAH_API_KEY");
// Server-side gate for the Payzah direct (redirect-based) checkout scaffolding.
// Stays "false" until the real Payzah API integration lands, so no client can
// create unpaid Pending Payment orders in the meantime.
const payzahDirectEnabled = defineString("PAYZAH_DIRECT_ENABLED", {default: "false"});
// Payzah Direct Integration credentials. The private key is a Firebase secret
// (firebase functions:secrets:set PAYZAH_PRIVATE_KEY) — never a plain param.
// PAYZAH_ENV picks the gateway host: "test" (sandbox) | "production".
const payzahPrivateKey = defineSecret("PAYZAH_PRIVATE_KEY");
const payzahEnv = defineString("PAYZAH_ENV", {default: "test"});

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
  // "stripe" is the live path; "payzah" is scaffolding for the direct
  // (redirect-based) integration and stays gated behind PAYZAH_DIRECT_ENABLED.
  const paymentProvider = data.paymentProvider || "stripe";

  if (!items || !Array.isArray(items) || items.length === 0) {
    throw new HttpsError("invalid-argument", "Items must be a non-empty array.");
  }
  if (items.length > 50) {
    throw new HttpsError("invalid-argument", "Order cannot contain more than 50 items.");
  }

  const allowedDeliveryMethods = ["Regular Delivery", "Same Day Delivery", "Made to Order"];
  const allowedPaymentMethods  = ["Card", "KNET", "Apple Pay"];

  if (!allowedDeliveryMethods.includes(deliveryMethod)) {
    throw new HttpsError("invalid-argument", "Invalid delivery method.");
  }
  if (!allowedPaymentMethods.includes(paymentMethod)) {
    throw new HttpsError("invalid-argument", "Invalid payment method.");
  }
  if (typeof paymentIntentId !== "string" || paymentIntentId.length > 200) {
    throw new HttpsError("invalid-argument", "Invalid paymentIntentId.");
  }
  if (!["stripe", "payzah"].includes(paymentProvider)) {
    throw new HttpsError("invalid-argument", "Invalid payment provider.");
  }
  if (paymentProvider === "payzah" && payzahDirectEnabled.value() !== "true") {
    throw new HttpsError("failed-precondition", "Payzah direct checkout is not enabled.");
  }
  if (["KNET", "Apple Pay"].includes(paymentMethod) && paymentProvider !== "payzah") {
    throw new HttpsError("invalid-argument", `${paymentMethod} is only available via Payzah.`);
  }

  // Payzah orders are created BEFORE the customer pays (redirect flow), so
  // they start as Pending Payment and reconcilePayzahPayments flips them to
  // Placed or Cancelled. Stripe orders are only created after the payment
  // sheet has already succeeded, so they start as Placed, unchanged.
  const initialOrderStatus = paymentProvider === "payzah" ? "Pending Payment" : "Placed";

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
  const paymentAttemptRef = db.collection("payment_attempts").doc();

  // Payzah trackid: our own unique reference for this checkout attempt,
  // echoed back on the redirect and used for status checks. Docs constraint:
  // alphanumeric, max 255 chars — orderNumber + random suffix satisfies both
  // and stays unique even if the same order ever retries with a new attempt.
  const payzahTrackid = paymentProvider === "payzah"
    ? `LIBSK${orderNumber}${crypto.randomBytes(6).toString("hex")}`
    : null;

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

      // Reject items the boutique flagged out of stock, even if a stale client
      // still has stock > 0 — mirrors the isSoldOut guard in the app UI.
      if (productData.isOutOfStock === true) {
        throw new HttpsError("failed-precondition",
          `${productData.title || "Product"} is out of stock.`);
      }
      if (stock < qty) {
        throw new HttpsError("failed-precondition",
          `${productData.title || "Product"} does not have enough stock.`);
      }

      // Server-side price: prefer a valid sale price below the regular price.
      // Never trust the client-supplied price.
      const basePrice = Number(productData.price) || 0;
      const sale = Number(productData.salePrice);
      const effectivePrice =
        Number.isFinite(sale) && sale > 0 && sale < basePrice
          ? sale
          : basePrice;

      productInfo[key] = {
        ref: productRef,
        data: productData,
        price: effectivePrice,
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
      // Optional customer note for this line (e.g. a small modification). Free
      // text, but capped server-side to keep the order doc bounded regardless
      // of what the client sends.
      const specialRequest = String(item.specialRequest || "").trim().slice(0, 1000);
      if (specialRequest) verifiedItem.specialRequest = specialRequest;
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
      // Boutique-owned codes apply only to that boutique's items (others stay
      // full price); platform-wide codes (no boutiqueId, created by super
      // admins) apply to the whole cart.
      const codeBoutiqueId = String(codeData.boutiqueId || "");
      const discountableSubtotal = codeBoutiqueId
        ? verifiedItems
            .filter((i) => i.boutiqueId === codeBoutiqueId)
            .reduce((sum, i) => sum + i.price * i.quantity, 0)
        : verifiedSubtotal;
      if (discountableSubtotal <= 0) {
        throw new HttpsError("failed-precondition",
          "This discount code is not valid for the items in your cart");
      }
      const codeValue = Number(codeData.value) || 0;
      if (codeData.type === "percentage") {
        discountAmount = parseFloat(((discountableSubtotal * codeValue) / 100).toFixed(3));
      } else {
        discountAmount = Math.min(codeValue, discountableSubtotal);
      }
      // The discount can never exceed the in-boutique (discountable) subtotal.
      discountAmount = Math.min(discountAmount, discountableSubtotal);
    }
    // Clamp incoming discountAmount to server-verified value
    discountAmount = Math.max(0, Math.min(discountAmount, verifiedSubtotal));

    const deliveryCost = deliveryMethod === "Same Day Delivery" ? 5
      : deliveryMethod === "Made to Order" ? 0
      : 3;
    const total = verifiedSubtotal + deliveryCost - discountAmount;

    // Flat 15% LIBSK commission on GMV — computed from the order subtotal,
    // before any discount or delivery fee. Stored on the order so revenue
    // reporting can sum it directly instead of recomputing at read time.
    const commissionAmount = parseFloat((verifiedSubtotal * 0.15).toFixed(3));

    const orderBase = {
      orderNumber,
      date: dateString,
      itemCount: verifiedItems.reduce((s, i) => s + i.quantity, 0),
      total,
      commissionAmount,
      status: initialOrderStatus,
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
      // Flat 15% commission on this boutique's share of the order subtotal.
      const bCommission = parseFloat((bTotal * 0.15).toFixed(3));

      const boutiqueOrderRef = db.collection("boutiques").doc(boutiqueId)
                                 .collection("orders").doc();

      tx.set(boutiqueOrderRef, {
        orderNumber,
        sourceUserOrderId: userOrderRef.id,
        date: dateString,
        itemCount: bCount,
        total: bTotal,
        commissionAmount: bCommission,
        status: initialOrderStatus,
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

    // Payment attempt record — one per checkout, created atomically with the
    // order. Stripe attempts are recorded already-paid (the payment sheet
    // resolved before createOrder is called); Payzah attempts start pending
    // and are resolved by reconcilePayzahPayments.
    tx.set(paymentAttemptRef, {
      orderId: userOrderRef.id,
      orderNumber,
      customerUid: uid,
      boutiqueIds: Object.keys(boutiqueMap),
      provider: paymentProvider,
      trackid: payzahTrackid,
      payzahPaymentId: null,
      // Payzah payment_type: "1" = K-Net, "2" = Credit Card (both Direct
      // Integration), "3" = Transit hosted page (used for Apple Pay).
      payzahPaymentType: paymentProvider === "payzah"
        ? (paymentMethod === "KNET" ? "1" : paymentMethod === "Apple Pay" ? "3" : "2")
        : null,
      // Raw gateway paymentStatus from the most recent status check — lets
      // reconciliation distinguish "never heard anything" (expire + cancel)
      // from HOST TIMEOUT / NOT CAPTURED (outcome uncertain → under review).
      lastGatewayStatus: null,
      status: paymentProvider === "payzah" ? "pending" : "paid",
      amount: total,
      currency: "KWD",
      checkAttempts: 0,
      lastCheckedAt: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(paymentIntentId ? { stripePaymentIntentId: paymentIntentId } : {}),
    });
  });

  return {
    orderNumber,
    orderId: userOrderRef.id,
    paymentAttemptId: paymentAttemptRef.id,
  };
});

// ================= ORDER STATUS (boutique owner) =================

// Boutique owners can't write the customer's users/{uid}/orders doc or the
// global_orders doc (rules restrict both to admins), so their confirm/cancel
// action runs here. We derive the caller's boutique from their APPROVED owner
// record (never trust a client-sent boutiqueId), confirm the order lives under
// that boutique, then update the boutique order + the customer's order + the
// matching global_orders doc atomically with the Admin SDK. The status-change
// triggers (notify/email) fire off the global_orders update as usual.
const ORDER_STATUSES = ["Placed", "Confirmed", "On the Way", "Delivered", "Cancelled"];

exports.updateOrderStatus = onCall(async (request) => {
  try {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be logged in.");
    }
    const uid = request.auth.uid;

    const rateOk = await checkRateLimit(`order_status_${uid}`, 300, 3600);
    if (!rateOk) {
      throw new HttpsError("resource-exhausted", "Too many requests. Please try again later.");
    }

    const data = request.data || {};
    const boutiqueOrderId = data.boutiqueOrderId;
    const newStatus = data.status;

    if (typeof boutiqueOrderId !== "string" || !boutiqueOrderId || boutiqueOrderId.length > 200) {
      throw new HttpsError("invalid-argument", "A valid boutiqueOrderId is required.");
    }
    if (!ORDER_STATUSES.includes(newStatus)) {
      throw new HttpsError("invalid-argument", "Invalid order status.");
    }

    // Authoritative ownership — the boutique is taken from the caller's approved
    // owner doc, so an owner can only ever touch their own boutique's orders.
    const ownerDoc = await db.collection("boutique_owners").doc(uid).get();
    if (!ownerDoc.exists || ownerDoc.data().isApproved !== true) {
      throw new HttpsError("permission-denied", "You are not an approved boutique owner.");
    }
    const boutiqueId = ownerDoc.data().boutiqueId;
    if (!boutiqueId) {
      throw new HttpsError("failed-precondition", "No boutique is assigned to this account.");
    }

    const boutiqueOrderRef = db
      .collection("boutiques").doc(boutiqueId)
      .collection("orders").doc(boutiqueOrderId);
    const boutiqueOrderSnap = await boutiqueOrderRef.get();
    if (!boutiqueOrderSnap.exists) {
      // Missing, or belongs to a different boutique — either way, not theirs.
      throw new HttpsError("not-found", "Order not found for this boutique.");
    }

    const orderData = boutiqueOrderSnap.data();
    const sourceUserOrderId = orderData.sourceUserOrderId || "";
    const customerUid = orderData.customerUid || "";

    const batch = db.batch();
    batch.update(boutiqueOrderRef, { status: newStatus });

    if (customerUid && sourceUserOrderId) {
      batch.update(
        db.collection("users").doc(customerUid)
          .collection("orders").doc(sourceUserOrderId),
        { status: newStatus },
      );
    }

    if (sourceUserOrderId) {
      const globalSnap = await db.collection("global_orders")
        .where("sourceUserOrderId", "==", sourceUserOrderId)
        .get();
      for (const doc of globalSnap.docs) {
        batch.update(doc.ref, { status: newStatus });
      }
    }

    await batch.commit();
    return { success: true, status: newStatus };
  } catch (error) {
    logger.error("Update order status error", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", error.message || "Failed to update order status.");
  }
});

// ================= PAYZAH DIRECT INTEGRATION =================
//
// Direct (redirect-based) checkout. createOrder writes a payment_attempts doc
// per checkout, initializePayzahPayment returns the hosted payment URL, the
// customer pays on KNET / card, and Payzah redirects the browser back to
// payzahRedirect. Per the docs, a redirect alone NEVER confirms payment —
// only a CAPTURED paymentStatus from get-payment-details does — so both the
// redirect handler and the scheduled reconciliation job re-verify through
// that endpoint before touching any order.

const PAYZAH_BASE_URLS = {
  test: "https://development.payzah.net",
  production: "https://payzah.net/production770",
};
const PAYZAH_PATHS = {
  init: "/ws/paymentgateway/index",
  status: "/ws/paymentgateway/get-payment-details",
};
// ISO 4217 numeric code for KWD, per the request sample in the docs.
const PAYZAH_CURRENCY_KWD = "414";

// Gateway paymentStatus values that mean "outcome uncertain" — per the docs
// these are NOT clean failures (funds may still have moved), so at the retry
// cap they resolve to Payment Under Review instead of a cancellation.
const PAYZAH_UNCLEAR_STATUSES = ["HOST TIMEOUT", "NOT CAPTURED"];

// Documented error codes (10000–10015). For logs/support only — never
// surfaced raw to customers. CAUTION (observed live): codes are reused with
// different `message` texts — 10002 fires for ANY missing required field and
// 10012 also fires for a wrong HTTP method — so always read the logged
// `message` alongside `knownMeaning`.
const PAYZAH_ERROR_CODES = {
  10000: "General error. Retry; if it persists, contact Payzah support.",
  10001: "trackid contains invalid/non-alphanumeric characters.",
  10002: "A required field is missing (see message for which).",
  10003: "amount is improperly formatted (plain decimal, no symbols/commas).",
  10004: "amount field is missing from the request body.",
  10005: "success_url field is missing from the request body.",
  10006: "error_url field is missing from the request body.",
  10007: "udf1 contains invalid/special characters.",
  10008: "udf2 contains invalid/special characters.",
  10009: "udf3 contains invalid/special characters.",
  10010: "udf4 contains invalid/special characters.",
  10011: "udf5 contains invalid/special characters.",
  10012: "No payment record for the trackid + payment_id combination (also fires for a wrong HTTP method).",
  10013: "Request body is empty or not valid JSON.",
  10014: "Authorization header is not valid Base64 of the private key.",
  10015: "Account lacks permission for this payment_type.",
};

function logPayzahFailure(context, responseBody) {
  // The docs recommend logging raw code + message from every failed response.
  logger.error(`Payzah failure [${context}]`, {
    code: responseBody?.code,
    message: responseBody?.message,
    knownMeaning: PAYZAH_ERROR_CODES[responseBody?.code] || "unknown code",
  });
}

// Payzah auth: the Authorization header is the Base64 of the raw private key.
async function callPayzah(path, body) {
  const base = PAYZAH_BASE_URLS[payzahEnv.value()] || PAYZAH_BASE_URLS.test;
  const res = await fetch(`${base}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: Buffer.from(payzahPrivateKey.value(), "utf-8").toString("base64"),
    },
    body: JSON.stringify(body),
  });
  return res.json();
}

// Map a gateway paymentStatus onto the payment_attempts lifecycle.
function mapPayzahStatus(gatewayStatus) {
  if (gatewayStatus === "CAPTURED") return "paid";
  if (["CANCELED", "VOIDED", "DENIED BY RISK"].includes(gatewayStatus)) return "failed";
  if (PAYZAH_UNCLEAR_STATUSES.includes(gatewayStatus)) return "unclear";
  return "pending";
}

// Ask Payzah for the authoritative status of an attempt.
// Returns { result: "paid"|"failed"|"unclear"|"pending", gatewayStatus }.
//
// Request/response shape confirmed against a live CAPTURED sandbox payment
// (2026-07-11): the body is { trackid, payment_id } — snake_case, and BOTH
// are required — where payment_id must be the PaymentID from the INIT
// response (stored as payzahPaymentId), NOT the paymentId the redirect
// POSTs back (that one equals knetPaymentId and matches no record). The
// response nests the result under data: { status: true, data: { ...,
// paymentStatus } }.
async function fetchPayzahStatus(attempt) {
  // Local/emulator testing hook: set `mockStatus` ("paid" | "failed" |
  // "pending" | "unclear") on a payment_attempts doc and the next check
  // behaves as if Payzah returned that status.
  if (attempt && ["paid", "failed", "pending", "unclear"].includes(attempt.mockStatus)) {
    return {
      result: attempt.mockStatus,
      gatewayStatus: attempt.mockStatus === "unclear" ? "HOST TIMEOUT" : null,
    };
  }
  if (!attempt || !attempt.trackid) {
    throw new Error("Payment attempt has no trackid.");
  }

  const response = await callPayzah(PAYZAH_PATHS.status, {
    trackid: String(attempt.trackid),
    ...(attempt.payzahPaymentId ? { payment_id: attempt.payzahPaymentId } : {}),
  });

  if (response?.status !== true) {
    // 10012 = no payment record for this trackid yet — the customer may never
    // have reached the gateway. Keep polling; the retry cap handles abandonment.
    if (Number(response?.code) === 10012) {
      return { result: "pending", gatewayStatus: null };
    }
    logPayzahFailure("fetchPayzahStatus", response);
    throw new Error(`Payzah status check failed (code ${response?.code}).`);
  }

  const gatewayStatus = response?.data?.paymentStatus;
  return { result: mapPayzahStatus(gatewayStatus), gatewayStatus: gatewayStatus || null };
}

// ================= PAYZAH PAYMENT RECONCILIATION =================
//
// Backstop for redirects that never arrive (customer closed the browser, OS
// killed the app, deep link dropped): polls pending payment_attempts and
// resolves each to paid / failed / expired / under_review.

const PAYMENT_ATTEMPT_GRACE_MS = 30 * 1000; // don't race the initial request
const PAYMENT_ATTEMPT_MAX_CHECKS = 10;      // beyond this, expire / park for review

// Set the order status on the customer, global and boutique copies of an
// order — the same fan-out as updateOrderStatus, driven by the attempt record.
async function setOrderStatusFromAttempt(attempt, newStatus) {
  const { orderId, customerUid, boutiqueIds } = attempt;
  if (!orderId) return;

  const batch = db.batch();

  if (customerUid) {
    batch.update(
      db.collection("users").doc(customerUid).collection("orders").doc(orderId),
      { status: newStatus },
    );
  }
  // global_orders docs share the user-order doc id (see createOrder).
  batch.update(db.collection("global_orders").doc(orderId), { status: newStatus });

  for (const boutiqueId of boutiqueIds || []) {
    const snap = await db.collection("boutiques").doc(boutiqueId)
      .collection("orders")
      .where("sourceUserOrderId", "==", orderId)
      .get();
    for (const doc of snap.docs) batch.update(doc.ref, { status: newStatus });
  }

  await batch.commit();
}

// Put back the stock (and sales counters) createOrder reserved, for orders
// whose payment failed or expired before it was ever collected.
async function releaseOrderStock(orderId) {
  const orderSnap = await db.collection("global_orders").doc(orderId).get();
  if (!orderSnap.exists) return;
  const items = orderSnap.data().items || [];

  const perProduct = {};
  for (const item of items) {
    if (!item.boutiqueId || !item.productId) continue;
    const key = `${item.boutiqueId}__${item.productId}`;
    if (!perProduct[key]) {
      perProduct[key] = { boutiqueId: item.boutiqueId, productId: item.productId, qty: 0 };
    }
    perProduct[key].qty += Number(item.quantity) || 0;
  }

  const batch = db.batch();
  for (const key of Object.keys(perProduct)) {
    const { boutiqueId, productId, qty } = perProduct[key];
    if (qty <= 0) continue;
    batch.update(
      db.collection("boutiques").doc(boutiqueId).collection("products").doc(productId),
      {
        stock: admin.firestore.FieldValue.increment(qty),
        weeklyOrders: admin.firestore.FieldValue.increment(-qty),
        salesCount: admin.firestore.FieldValue.increment(-qty),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    );
  }
  await batch.commit();
}

async function resolvePaymentAttempt(attemptRef, attempt, outcome) {
  await attemptRef.update({
    status: outcome,
    lastCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Promo-booking attempts resolve onto their booking, not an order — and must
  // NOT run releaseOrderStock (there is no order). Step 4 will additionally
  // apply the placement's rendering flags on 'paid'; here we only transition
  // the booking's own status so payments settle cleanly and a held slot is
  // released on failure.
  if (attempt.kind === "promo_booking") {
    await resolvePromoBookingOutcome(attempt, outcome);
    logger.info("Payment attempt resolved", {
      attemptId: attemptRef.id, outcome, kind: "promo_booking",
    });
    return;
  }

  if (outcome === "paid") {
    // Same destination as the old Stripe success path: the order becomes
    // Placed, which fires the existing status-change notification triggers.
    // TODO: once live, also send the order confirmation email here — it is
    // suppressed at creation time for Pending Payment orders.
    await setOrderStatusFromAttempt(attempt, "Placed");
  } else if (outcome === "under_review") {
    // HOST TIMEOUT / NOT CAPTURED at the retry cap: the gateway could not say
    // whether funds moved, so this is NOT a clean failure. Keep the stock
    // reserved and park the order for manual (admin) resolution — cancelling
    // here could cancel an order the customer actually paid for.
    await setOrderStatusFromAttempt(attempt, "Payment Under Review");
  } else {
    // failed | expired — cancel the order and free the reserved stock.
    await setOrderStatusFromAttempt(attempt, "Cancelled");
    await releaseOrderStock(attempt.orderId);
  }
  logger.info("Payment attempt resolved", { attemptId: attemptRef.id, outcome });
}

// Transition a promo booking to match its payment outcome. Idempotent — only a
// still-pending booking moves, so duplicate redirect/reconcile callbacks are
// safe. Only Case B (partial credit / full charge) bookings ever reach here —
// a fully-credit-funded booking has no payment_attempt.
async function resolvePromoBookingOutcome(attempt, outcome) {
  const bookingId = attempt.promoBookingId;
  if (!bookingId) return;
  const ref = db.collection("promo_bookings").doc(bookingId);

  if (outcome === "paid") {
    // Transactional: spend any DEFERRED promo credit, then activate the booking.
    await settlePaidPromoBooking(ref, bookingId);
    return;
  }

  // under_review / failed / expired — the credit portion was deferred and NEVER
  // taken, so there is nothing to refund; just transition a still-pending
  // booking. (Releasing the hold on cancel is implicit — a cancelled booking no
  // longer counts as occupying.)
  const snap = await ref.get();
  if (!snap.exists) return;
  if (snap.data().status !== "pending_payment") return;
  const now = admin.firestore.FieldValue.serverTimestamp();
  if (outcome === "under_review") {
    await ref.update({ status: "payment_under_review", updatedAt: now });
  } else {
    await ref.update({ status: "cancelled", updatedAt: now });
  }
}

// Settle a paid Case-B booking in one transaction: spend the deferred promo
// credit (if any), then flip the booking to its post-payment status. Atomic +
// idempotent — a duplicate 'paid' callback re-reads a no-longer-pending booking
// and no-ops before touching credit. The spend is capped at BOTH the booking's
// intended credit (amountFromCreditFils, locked at booking time) AND the live
// balance; if the balance was spent elsewhere in between, the shortfall is
// logged for manual reconciliation rather than silently under-charging. Rendering
// is NOT applied here — the scheduled activator turns flags on at window open.
async function settlePaidPromoBooking(ref, bookingId) {
  await db.runTransaction(async (tx) => {
    const bSnap = await tx.get(ref);
    if (!bSnap.exists) return;
    const booking = bSnap.data();
    if (booking.status !== "pending_payment") return; // idempotent

    const wantFils = Math.floor(Number(booking.amountFromCreditFils) || 0);
    const boutiqueRef = wantFils > 0
      ? db.collection("boutiques").doc(booking.boutiqueId) : null;

    // Reads first (transaction rule): booking above, then boutique + its grants.
    let boutiqueSnap = null;
    let grants = [];
    if (boutiqueRef) {
      boutiqueSnap = await tx.get(boutiqueRef);
      const grantsSnap = await tx.get(
        boutiqueRef.collection("promoCredits").where("remainingFils", ">", 0));
      grants = grantsSnap.docs.map(grantToAllocInput);
    }

    const nowTs = admin.firestore.FieldValue.serverTimestamp();
    let creditSpentFils = 0;
    if (boutiqueRef && boutiqueSnap.exists) {
      const alloc = allocateCreditFifo(grants, wantFils, Date.now());
      creditSpentFils = alloc.allocatedFils;
      if (creditSpentFils > 0) {
        const remainById = {};
        for (const g of grants) remainById[g.id] = g.remainingFils;
        for (const a of alloc.allocations) {
          tx.update(boutiqueRef.collection("promoCredits").doc(a.creditId), {
            remainingFils: remainById[a.creditId] - a.fils, updatedAt: nowTs,
          });
        }
        txAddSpendEntry(tx, boutiqueRef, {
          amountFils: -creditSpentFils, type: "spend",
          reason: `promo_booking:${bookingId}`, grantedBy: null,
          allocations: alloc.allocations,
        });
        tx.update(boutiqueRef, {
          promoCreditBalance: applyFilsDelta(
            boutiqueSnap.data().promoCreditBalance, -creditSpentFils),
          updatedAt: nowTs,
        });
      }
      if (creditSpentFils < wantFils) {
        logger.warn("Promo credit settlement shortfall", {
          bookingId, wantFils, creditSpentFils,
        });
      }
    }

    const placement = PROMO_PLACEMENTS[booking.placementType] || {};
    const status = placement.reviewBeforeActive ? "paid_pending_review" : "active";
    tx.update(ref, {
      status,
      paidAt: nowTs,
      expiresAt: booking.dayEnd || booking.weekEnd || null,
      renderingApplied: false,
      creditSpentFils,
      ...(status === "active" ? { activatedAt: nowTs } : {}),
      updatedAt: nowTs,
    });
  });
}

exports.reconcilePayzahPayments = onSchedule(
  { schedule: "every 3 minutes", secrets: [payzahPrivateKey], maxInstances: 1 },
  async () => {
  const graceCutoff = admin.firestore.Timestamp.fromMillis(
    Date.now() - PAYMENT_ATTEMPT_GRACE_MS,
  );

  const snap = await db.collection("payment_attempts")
    .where("status", "==", "pending")
    .where("createdAt", "<", graceCutoff)
    .limit(100)
    .get();

  for (const doc of snap.docs) {
    const attempt = doc.data();
    // Stripe attempts are written already-paid and should never appear here;
    // skip anything that isn't a Payzah attempt just in case.
    if (attempt.provider !== "payzah") continue;

    try {
      if ((attempt.checkAttempts || 0) >= PAYMENT_ATTEMPT_MAX_CHECKS) {
        // If the gateway ever reported an "outcome uncertain" status, this is
        // not a clean abandonment — park it for manual review instead of
        // cancelling (see resolvePaymentAttempt).
        const capOutcome = PAYZAH_UNCLEAR_STATUSES.includes(attempt.lastGatewayStatus)
          ? "under_review"
          : "expired";
        await resolvePaymentAttempt(doc.ref, attempt, capOutcome);
        continue;
      }

      let check;
      try {
        check = await fetchPayzahStatus(attempt);
      } catch (err) {
        // Payzah unreachable / unexpected response — still count the attempt
        // so the retry cap applies and no doc is polled forever.
        logger.warn("Payzah status check unavailable", {
          attemptId: doc.id, error: String(err),
        });
        await doc.ref.update({
          checkAttempts: admin.firestore.FieldValue.increment(1),
          lastCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        continue;
      }

      if (check.result === "paid" || check.result === "failed") {
        await resolvePaymentAttempt(doc.ref, attempt, check.result);
      } else {
        // pending | unclear — keep polling, remembering the last raw gateway
        // status so the cap can distinguish under-review from expiry.
        await doc.ref.update({
          checkAttempts: admin.firestore.FieldValue.increment(1),
          lastGatewayStatus: check.gatewayStatus || attempt.lastGatewayStatus || null,
          lastCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    } catch (err) {
      logger.error("Failed to reconcile payment attempt", {
        attemptId: doc.id, error: String(err),
      });
    }
  }
});

// ================= PAYZAH: INITIALIZE PAYMENT =================
//
// Called by the Flutter client right after createOrder (payzah path). The
// amount, trackid and payment type all come from the payment_attempts doc
// createOrder wrote inside its price-verification transaction — the client
// supplies only the attempt id, never a price.

exports.initializePayzahPayment = onCall(
  { secrets: [payzahPrivateKey] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be logged in.");
    }
    const uid = request.auth.uid;

    if (payzahDirectEnabled.value() !== "true") {
      throw new HttpsError("failed-precondition", "Payzah direct checkout is not enabled.");
    }
    const rateOk = await checkRateLimit(`payzah_init_${uid}`, 20, 3600);
    if (!rateOk) {
      throw new HttpsError("resource-exhausted", "Too many requests. Please try again later.");
    }

    const { attemptId, language } = request.data || {};
    if (!attemptId || typeof attemptId !== "string" || attemptId.length > 100) {
      throw new HttpsError("invalid-argument", "attemptId is required.");
    }

    const attemptRef = db.collection("payment_attempts").doc(attemptId);
    const attemptSnap = await attemptRef.get();
    if (!attemptSnap.exists) {
      throw new HttpsError("not-found", "Payment attempt not found.");
    }
    const attempt = attemptSnap.data();
    if (attempt.customerUid !== uid) {
      throw new HttpsError("permission-denied", "Not your payment attempt.");
    }
    if (attempt.provider !== "payzah") {
      throw new HttpsError("failed-precondition", "Not a Payzah payment attempt.");
    }
    // Re-callable while pending (customer backed out of the browser and
    // retried) but never after resolution.
    if (attempt.status !== "pending") {
      throw new HttpsError("failed-precondition", `Payment attempt is already ${attempt.status}.`);
    }

    const userSnap = await db.collection("users").doc(uid).get();
    const userData = userSnap.exists ? userSnap.data() : {};

    // Payzah rejects the whole init when customer_phone isn't a bare local
    // mobile number — confirmed live 2026-07-11: "+965 50000000" fails with
    // "Improper mobile number passed", "" and "50000000" pass. Strip to
    // digits, drop the Kuwait country code, and send empty rather than ever
    // blocking a checkout over a display-only field.
    let customerPhone = String(userData.phone || userData.phoneNumber || "")
      .replace(/\D/g, "");
    if (customerPhone.startsWith("965") && customerPhone.length > 8) {
      customerPhone = customerPhone.slice(3);
    }
    if (customerPhone.length !== 8) customerPhone = "";

    const projectId = process.env.GCLOUD_PROJECT;
    const redirectUrl = `https://us-central1-${projectId}.cloudfunctions.net/payzahRedirect`;

    const paymentType = attempt.payzahPaymentType || "2";
    const payload = {
      trackid: String(attempt.trackid),
      // Plain decimal string, 3 dp, e.g. "11.250" — no symbols or commas.
      amount: Number(attempt.amount).toFixed(3),
      currency: PAYZAH_CURRENCY_KWD,
      payment_type: paymentType, // "1" K-Net | "2" card | "3" Transit (Apple Pay)
      language: language === "ARA" ? "ARA" : "ENG",
      // Both URLs point at the same handler — it re-verifies via
      // get-payment-details either way and never trusts which one was hit.
      success_url: redirectUrl,
      error_url: redirectUrl,
      customer_name: String(userData.fullName || request.auth.token.name || ""),
      customer_email: String(userData.email || request.auth.token.email || ""),
      customer_phone: customerPhone,
      // kfast_id (Numeric, max 8) appears in the docs' request field table but
      // is never explained anywhere — deliberately omitted until Payzah
      // support confirms its purpose.
    };

    let response;
    try {
      response = await callPayzah(PAYZAH_PATHS.init, payload);
    } catch (err) {
      logger.error("Payzah init network error", { attemptId, error: String(err) });
      throw new HttpsError("unavailable", "Could not reach the payment gateway. Please try again.");
    }

    // Response shape (confirmed live):
    // { status: true, data: { PaymentUrl, PaymentID, transit_url, direct_url } }
    // Direct types ("1"/"2") use direct_url; the Transit hosted page ("3",
    // Apple Pay) lives at transit_url, which is only populated for type 3.
    // Transit's redirect callback and get-payment-details behave identically
    // to Direct's — verified with a live Transit KNET payment on 2026-07-11.
    const paymentUrl = paymentType === "3"
      ? response?.data?.transit_url
      : response?.data?.direct_url;
    const paymentId = response?.data?.PaymentID;
    if (response?.status !== true || !paymentUrl) {
      logPayzahFailure("initializePayzahPayment", response);
      throw new HttpsError("failed-precondition", "Payment initialization failed. Please try again.");
    }

    await attemptRef.update({
      payzahPaymentId: paymentId ? String(paymentId) : null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // directUrl kept as a legacy alias for app builds that predate paymentUrl.
    return { paymentUrl, directUrl: paymentUrl, trackid: attempt.trackid };
  },
);

// ================= PAYZAH: REDIRECT CALLBACK =================
//
// Payzah redirects the customer's browser here after payment; success_url and
// error_url both point at this function. Documented redirect params:
// payzahReferenceCode, trackId, knetPaymentId, transactionNumber,
// trackingNumber, paymentDate, paymentStatus, udf1–udf5. The query-string
// paymentStatus is logged for comparison but NEVER trusted — the docs are
// explicit that only get-payment-details confirms an outcome.

exports.payzahRedirect = onRequest(
  { secrets: [payzahPrivateKey] },
  async (req, res) => {
    // Payzah delivers the result as a form POST (application/x-www-form-
    // urlencoded) to success_url / error_url — confirmed from a live sandbox
    // payment on 2026-07-11 — so the fields live in req.body, not the query
    // string. Observed body fields: trackId, paymentId, paymentStatus,
    // payzahRefrenceCode (sic), knetPaymentId, transactionNumber,
    // trackingNumber, paymentDate, paymentMethod, UDF1–UDF5. The query
    // string is kept as a fallback in case any environment GET-redirects.
    const params = { ...(req.query || {}), ...(req.body || {}) };
    const trackid = params.trackId || params.trackingNumber;

    const deepLink = (status, extra = "") =>
      res.redirect(`libsk://payment-result?status=${status}${extra}`);

    if (!trackid) {
      logger.warn("payzahRedirect hit without trackId/trackingNumber", {
        method: req.method,
        query: req.query || {},
        bodyKeys: Object.keys(req.body || {}),
      });
      return deepLink("unknown");
    }
    const trackParam = `&trackid=${encodeURIComponent(String(trackid))}`;

    try {
      const snap = await db.collection("payment_attempts")
        .where("trackid", "==", String(trackid))
        .limit(1)
        .get();
      if (snap.empty) {
        // Also record the delivery shape — debug/throwaway sessions land here,
        // and comparing receivedFields against the Direct callback is how a
        // new rail (e.g. Transit) gets its callback shape verified.
        logger.warn("payzahRedirect: no payment attempt for trackid", {
          trackid,
          method: req.method,
          receivedFields: Object.keys(params),
          paymentStatus: params.paymentStatus || null,
        });
        return deepLink("unknown", trackParam);
      }
      const attemptRef = snap.docs[0].ref;
      const attempt = snap.docs[0].data();

      logger.info("payzahRedirect received", {
        trackid,
        attemptId: attemptRef.id,
        payzahReferenceCode: params.payzahRefrenceCode || null,
        redirectPaymentStatus: params.paymentStatus || null, // untrusted, log-only
      });

      // Keep the gateway's reference fields for support/reconciliation.
      // NOTE: the redirect's paymentId equals knetPaymentId and is NOT the
      // init PaymentID the status check needs — never write it over
      // payzahPaymentId (confirmed live 2026-07-11: the knet id matches no
      // record on get-payment-details).
      await attemptRef.update({
        // Payzah spells this field "payzahRefrenceCode" on the wire (sic);
        // stored under the corrected name.
        payzahReferenceCode: params.payzahRefrenceCode || null,
        knetPaymentId: params.knetPaymentId || null,
        transactionNumber: params.transactionNumber || null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Redirects can arrive twice (browser refresh / back button) — if the
      // attempt is already resolved, report that outcome without re-resolving.
      if (attempt.status !== "pending") {
        const settled = attempt.status === "paid" ? "success"
          : attempt.status === "under_review" ? "pending"
          : "failed";
        return deepLink(settled, trackParam);
      }

      const check = await fetchPayzahStatus(attempt);
      if (check.result === "paid" || check.result === "failed") {
        await resolvePaymentAttempt(attemptRef, attempt, check.result);
        return deepLink(check.result === "paid" ? "success" : "failed", trackParam);
      }

      // pending / unclear — leave the attempt pending; reconcilePayzahPayments
      // keeps polling and applies the under-review policy at the retry cap.
      await attemptRef.update({
        lastGatewayStatus: check.gatewayStatus || attempt.lastGatewayStatus || null,
        lastCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return deepLink("pending", trackParam);
    } catch (err) {
      logger.error("payzahRedirect error", { trackid, error: String(err) });
      // Status unknown — never claim failure to the app when we could not
      // verify; the app keeps its verifying state and reconciliation settles it.
      return deepLink("pending", trackParam);
    }
  },
);

// ================= PAYZAH: MANUAL STATUS CHECK =================
//
// Backup path for when the deep-link redirect never arrives (OS killed the
// app, customer dismissed the browser). The app calls this on resume / from a
// "check payment status" button; a terminal gateway answer resolves the
// attempt exactly like the redirect or reconciliation would.

exports.checkPayzahPaymentStatus = onCall(
  { secrets: [payzahPrivateKey] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be logged in.");
    }
    const uid = request.auth.uid;

    const rateOk = await checkRateLimit(`payzah_status_${uid}`, 60, 3600);
    if (!rateOk) {
      throw new HttpsError("resource-exhausted", "Too many requests. Please try again later.");
    }

    const { attemptId } = request.data || {};
    if (!attemptId || typeof attemptId !== "string" || attemptId.length > 100) {
      throw new HttpsError("invalid-argument", "attemptId is required.");
    }

    const attemptRef = db.collection("payment_attempts").doc(attemptId);
    const attemptSnap = await attemptRef.get();
    if (!attemptSnap.exists) {
      throw new HttpsError("not-found", "Payment attempt not found.");
    }
    const attempt = attemptSnap.data();
    if (attempt.customerUid !== uid) {
      throw new HttpsError("permission-denied", "Not your payment attempt.");
    }
    if (attempt.provider !== "payzah") {
      throw new HttpsError("failed-precondition", "Not a Payzah payment attempt.");
    }

    // Already resolved — just report it.
    if (attempt.status !== "pending") {
      return { status: attempt.status, gatewayStatus: attempt.lastGatewayStatus || null };
    }

    let check;
    try {
      check = await fetchPayzahStatus(attempt);
    } catch (err) {
      logger.warn("Manual Payzah status check unavailable", {
        attemptId, error: String(err),
      });
      throw new HttpsError("unavailable", "Could not verify the payment right now. Please try again.");
    }

    if (check.result === "paid" || check.result === "failed") {
      await resolvePaymentAttempt(attemptRef, attempt, check.result);
      return { status: check.result, gatewayStatus: check.gatewayStatus };
    }

    await attemptRef.update({
      lastGatewayStatus: check.gatewayStatus || attempt.lastGatewayStatus || null,
      lastCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { status: "pending", gatewayStatus: check.gatewayStatus };
  },
);

// ================= DISCOUNT CODES =================

exports.validateDiscountCode = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "You must be logged in.");
  }

  const { code, subtotal, boutiqueIds } = request.data || {};

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

  // Boutique-owned codes only apply if that boutique has items in the current
  // cart. Platform-wide codes (no boutiqueId) skip the membership check.
  const cartBoutiqueIds = Array.isArray(boutiqueIds)
    ? boutiqueIds.map((b) => String(b))
    : [];
  const codeBoutiqueId = String(docData.boutiqueId || "");
  if (codeBoutiqueId && !cartBoutiqueIds.includes(codeBoutiqueId)) {
    throw new HttpsError("failed-precondition",
      "This discount code is not valid for the items in your cart");
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

    // Payzah redirect orders start as Pending Payment — hold notifications
    // until reconciliation confirms the payment and flips the status.
    if (orderData.status === "Pending Payment") return;

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

    // Payzah redirect orders start as Pending Payment — don't send the
    // confirmation email until the payment is actually confirmed.
    if (order.status === "Pending Payment") return;

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

exports.sendManualNotification = onCall({ maxInstances: 2 }, async (request) => {
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
      salePrice: data.salePrice ?? null, isOutOfStock: data.isOutOfStock || false,
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
      salePrice: data.salePrice ?? null, isOutOfStock: data.isOutOfStock || false,
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

exports.algoliaReindex = onCall({ maxInstances: 2 }, async (request) => {
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
      salePrice: data.salePrice ?? null, isOutOfStock: data.isOutOfStock || false,
      imageUrl: data.imageUrl || "", imageUrls: data.imageUrls || [],
      stock: data.stock || 0, madeToOrder: data.madeToOrder || false,
    };
  });
  if (productRecords.length > 0) await saveAlgoliaObjects(PRODUCTS_INDEX, productRecords);

  return { success: true, boutiquesIndexed: boutiqueRecords.length, productsIndexed: productRecords.length };
});

// ================= SCHEDULED CLEANUPS =================

exports.cleanupRateLimits = onSchedule(
  { schedule: "every 24 hours", maxInstances: 1 },
  async () => {
  const cutoff = Date.now() - (86400 * 1000);
  const snap = await db.collection("rate_limits").where("updatedAt", "<", cutoff).limit(500).get();
  const batch = db.batch();
  snap.docs.forEach(doc => batch.delete(doc.ref));
  await batch.commit();
});

exports.cleanupGuestCarts = onSchedule(
  { schedule: "every 24 hours", maxInstances: 1 },
  async () => {
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
  { schedule: "0 0 * * 1", timeZone: "Asia/Kuwait", maxInstances: 1 },
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

exports.expireFeedSponsored = onSchedule(
  { schedule: "every 1 hours", maxInstances: 1 },
  async () => {
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

// ================= PROMO BOOKINGS: CONFIG =================
//
// Weekly promo placements sold to boutiques, paid through the SAME Payzah
// engine as customer checkout (payment_attempts + initializePayzahPayment).
// Every price, capacity and limit lives here server-side — the client picks a
// placement + quantity + targets and NEVER supplies a price or slot count.
//
// Two independent accounting axes (do not conflate them):
//   • Global cap  — on ANY GIVEN DAY a boutique may hold at most
//     PROMO_MAX_GLOBAL_SLOTS day-placements (each booking = 1 slot).
//     feed_sponsored is week-only and EXEMPT (0). Counted per-day, so a boutique
//     can spread different placements across different day-ranges.
//   • Placement inventory — each placement has a per-DAY capacity and per-DAY
//     per-boutique limit (top_of_category counts items PER CATEGORY per day).
//
// Day-based: the 4 non-feed placements are booked for a CONTIGUOUS run of days
// within the upcoming week (1–7). Price = daily × days, except 7 days = the flat
// weekly rate — so 6 days can cost more than 7 (intentional; surfaced in the UI).
// Every booking is ONE unit (1 banner / product / boutique / category); a
// boutique wanting two books twice (capped by the per-day per-boutique limit).
// feed_sponsored stays week-only and priced per post (1 or 2), unchanged.
const PROMO_PLACEMENTS = {
  home_banner: {
    dayBased: true, daily: 12, weekly: 63,
    capacity: 4, perBoutique: 1,          // per day
    globalSlots: 1,
    targets: "none",
    requiresBannerImage: true,
    reviewBeforeActive: true,             // paid → paid_pending_review → admin approves
  },
  featured_product: {
    dayBased: true, daily: 4, weekly: 21,
    capacity: 6, perBoutique: 2,          // per day (one product per booking)
    globalSlots: 1,
    targets: "product",
  },
  featured_boutique: {
    dayBased: true, daily: 6, weekly: 32,
    capacity: 5, perBoutique: 1,          // per day
    globalSlots: 1,
    targets: "none",
  },
  top_of_category: {
    dayBased: true, daily: 3, weekly: 17,
    perCategory: { capacity: 6, perBoutique: 2 }, // per day, in items (products)
    globalSlots: 1,
    targets: "category",                  // one category + 1–2 of its products
    maxProductsPerCategory: 2,
  },
  feed_sponsored: {
    dayBased: false,                      // week-only
    tiers: { 1: 15, 2: 25 },              // per post, unchanged
    capacity: null, perBoutique: null,    // unlimited
    globalSlots: 0,                       // EXEMPT from the cap
    targets: "products",                  // 1–2 posts
  },
};

// Max day-placement slots one boutique may hold on any single day (feed exempt).
const PROMO_MAX_GLOBAL_SLOTS = 3;

// A pending_payment booking holds its slot(s) for this long before the
// reservation lapses and stops counting against capacity — the promo analogue
// of stock reservation in createOrder. reconcilePayzahPayments polls every
// ~3 min, so 5 min covers a promptly-completed payment while keeping abandoned
// slots from staying locked for long (kept short deliberately for testing —
// raise it if real payments ever run long enough to risk a released slot).
const PROMO_HOLD_MINUTES = 5;

// Kuwait is UTC+3 year-round (no DST).
const KUWAIT_OFFSET_MS = 3 * 60 * 60 * 1000;
const ONE_DAY_MS = 24 * 60 * 60 * 1000;

// ⚠️ ═══════════════════════════════════════════════════════════════════════
// TEMPORARY TEST-ONLY OVERRIDE — MUST BE false IN PRODUCTION / BEFORE LAUNCH.
// ---------------------------------------------------------------------------
// Normally the bookable week is the NEXT full Sun–Sat. When this is true,
// promoNextWeek() instead returns the CURRENT week, so the current week's
// remaining days can be booked for end-to-end testing without waiting for the
// next week. (Past days of the current week are still pickable but only
// today-onward actually renders.)
//   • ENABLE for testing:  set to true,  then deploy getPromoAvailability +
//                          createPromoBooking.
//   • REVERT after testing: set back to false, then redeploy those two.
// DO NOT SHIP OR LAUNCH WITH THIS true.
// ⚠️ ═══════════════════════════════════════════════════════════════════════
const PROMO_TEST_BOOK_CURRENT_WEEK = false;

if (PROMO_TEST_BOOK_CURRENT_WEEK) {
  logger.warn(
    "⚠️ PROMO_TEST_BOOK_CURRENT_WEEK is ON — the CURRENT week is bookable for " +
    "testing. This MUST be false before launch.");
}

// The single bookable week: the NEXT full Sun–Sat in Asia/Kuwait (Kuwait's week
// runs Sunday–Saturday, weekend Fri–Sat). The current in-progress week is never
// sold, so there is exactly one week key at a time and no proration. Returns
// { startMs, endMs } as UTC epoch millis. Under PROMO_TEST_BOOK_CURRENT_WEEK it
// returns the CURRENT Sun–Sat week instead (test-only — see above).
function promoNextWeek(nowMs) {
  const k = new Date(nowMs + KUWAIT_OFFSET_MS);           // Kuwait wall clock
  const daysSinceSunday = k.getUTCDay();                  // Sun=0 … Sat=6
  const currentWeekSundayK = Date.UTC(
    k.getUTCFullYear(), k.getUTCMonth(), k.getUTCDate(),
  ) - daysSinceSunday * ONE_DAY_MS;                        // this week's Sunday 00:00 Kuwait
  const weeksAhead = PROMO_TEST_BOOK_CURRENT_WEEK ? 0 : 1; // test override → current week
  const startK = currentWeekSundayK + weeksAhead * 7 * ONE_DAY_MS; // that week's Sunday 00:00 Kuwait
  const startMs = startK - KUWAIT_OFFSET_MS;               // back to real UTC epoch
  return { startMs, endMs: startMs + 7 * ONE_DAY_MS };
}

// Day index 0 = Sunday … 6 = Saturday (Kuwait's Sun–Sat week).
const DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const promoDayName = (d) => DAY_NAMES[d] || `day ${d}`;

// Server-side price. Day placements: daily × numDays, but a full 7 days is the
// flat weekly rate (so 6 days may cost more than 7 — intentional). feed: priced
// by post count (1 or 2), week-only. Returns null for anything not offered.
function promoPrice(placementType, numDays, quantity) {
  const p = PROMO_PLACEMENTS[placementType];
  if (!p) return null;
  if (!p.dayBased) {
    const price = p.tiers[quantity];
    return typeof price === "number" ? price : null;
  }
  const n = Math.floor(Number(numDays));
  if (!(n >= 1 && n <= 7)) return null;
  return n === 7 ? p.weekly : p.daily * n;
}

// Slots this booking consumes against the per-day global cap (feed = 0). Every
// day-placement booking is one unit → 1 slot on each day it covers.
function promoGlobalSlots(placementType) {
  const p = PROMO_PLACEMENTS[placementType];
  return p ? p.globalSlots : 0;
}

// Does a booking cover a given day index (Sun=0 … Sat=6)? Feed and any legacy
// full-week booking span all 7 days (startDay 0, numDays 7).
function promoCoversDay(booking, day) {
  const start = booking.startDay || 0;
  const n = booking.numDays || 7;
  return day >= start && day < start + n;
}

// Rendering-window state at nowMs — dayStart inclusive, dayEnd exclusive. Drives
// the scheduled activator (render on "during") and expiry (revoke on "ended").
function promoWindowState(booking, nowMs) {
  const startMs = toMillisOr0(booking.dayStart);
  const endMs = toMillisOr0(booking.dayEnd);
  if (nowMs < startMs) return "before";
  if (nowMs < endMs) return "during";
  return "ended";
}

// Whether a booking currently occupies its slot(s). active / awaiting-review
// always do; a pending_payment booking only until its hold lapses, so an
// abandoned checkout stops blocking the slot. `holdExpiresAt` may be a Firestore
// Timestamp (live data) or epoch ms (tests).
function isPromoOccupying(booking, nowMs) {
  if (booking.status === "active" || booking.status === "paid_pending_review") {
    return true;
  }
  if (booking.status === "pending_payment") {
    const h = booking.holdExpiresAt;
    const holdMs = h && typeof h.toMillis === "function" ? h.toMillis() : Number(h) || 0;
    return holdMs > nowMs;
  }
  return false; // cancelled / expired / payment_under_review free the slot
}

// Items a top_of_category booking pins in a given category (0 if none).
function promoItemsInCategory(booking, category) {
  const pin = (booking.categoryPins || []).find((p) => p.category === category);
  return pin ? (pin.productIds || []).length : 0;
}

// Pure availability decision for one requested booking against the week's
// already-occupying bookings, checked PER DAY: the booking fits iff EVERY day in
// its range fits (global cap + placement capacity + per-boutique limit on that
// day). No I/O — unit-tested directly against the real constants.
//   req = { boutiqueId, placementType, startDay, numDays, category?, categoryItems? }
function checkPromoAvailability(occupying, req) {
  const placement = PROMO_PLACEMENTS[req.placementType];
  if (!placement) {
    return { ok: false, code: "invalid-argument", reason: "Unknown placement." };
  }
  // feed_sponsored is week-only, unlimited and cap-exempt — never constrained.
  if (!placement.dayBased) return { ok: true };

  // Only day-placements occupy day-capacity (feed never does).
  const dayOccupying = occupying.filter(
    (b) => PROMO_PLACEMENTS[b.placementType] && PROMO_PLACEMENTS[b.placementType].dayBased);

  for (let day = req.startDay; day < req.startDay + req.numDays; day++) {
    const onDay = dayOccupying.filter((b) => promoCoversDay(b, day));

    // 1) Global cap for this boutique on this day (each day-placement = 1 slot).
    const usedSlots = onDay
      .filter((b) => b.boutiqueId === req.boutiqueId)
      .reduce((s, b) => s + promoGlobalSlots(b.placementType), 0);
    if (usedSlots + promoGlobalSlots(req.placementType) > PROMO_MAX_GLOBAL_SLOTS) {
      return { ok: false, code: "failed-precondition",
        reason: `This would exceed your limit of ${PROMO_MAX_GLOBAL_SLOTS} promo slots on ${promoDayName(day)}.` };
    }

    const sameType = onDay.filter((b) => b.placementType === req.placementType);
    const sameTypeMine = sameType.filter((b) => b.boutiqueId === req.boutiqueId);

    if (placement.perCategory) {
      // top_of_category: capacity & per-boutique limit are counted in ITEMS,
      // per category, per day.
      const cat = req.category;
      const addItems = req.categoryItems || 0;
      const mineItems = sameTypeMine.reduce((s, b) => s + promoItemsInCategory(b, cat), 0);
      if (mineItems + addItems > placement.perCategory.perBoutique) {
        return { ok: false, code: "failed-precondition",
          reason: `You already hold the maximum ${placement.perCategory.perBoutique} promoted items in "${cat}" on ${promoDayName(day)}.` };
      }
      const totalItems = sameType.reduce((s, b) => s + promoItemsInCategory(b, cat), 0);
      if (totalItems + addItems > placement.perCategory.capacity) {
        return { ok: false, code: "failed-precondition",
          reason: `"Top of category" for "${cat}" is fully booked on ${promoDayName(day)}.` };
      }
    } else {
      // One booking = one unit. Capacity/limit count bookings covering the day.
      if (placement.perBoutique !== null && sameTypeMine.length + 1 > placement.perBoutique) {
        return { ok: false, code: "failed-precondition",
          reason: `You already hold the maximum for this placement on ${promoDayName(day)}.` };
      }
      if (placement.capacity !== null && sameType.length + 1 > placement.capacity) {
        return { ok: false, code: "failed-precondition",
          reason: `This placement is fully booked on ${promoDayName(day)}.` };
      }
    }
  }

  return { ok: true };
}

// Book a weekly promo placement for the caller's boutique. Approved-owner gated;
// the boutique, price, week and slot availability are ALL resolved server-side —
// the client supplies only the placement, its targets and a payment method,
// never a price or slot count. Writes a pending_payment booking + a linked
// Payzah payment_attempts doc atomically; the client then runs the SAME Payzah
// flow as checkout over the returned paymentAttemptId.
exports.createPromoBooking = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "You must be logged in.");
  }
  const uid = request.auth.uid;

  const rateOk = await checkRateLimit(`promo_book_${uid}`, 20, 3600);
  if (!rateOk) {
    throw new HttpsError("resource-exhausted", "Too many requests. Please try again later.");
  }

  // Promo payment rides the Payzah engine — but a booking FULLY covered by promo
  // credit skips the gateway entirely, so this gate is enforced later, only when
  // the split leaves a remainder to actually charge (see the transaction below).
  const payzahEnabled = payzahDirectEnabled.value() === "true";

  const data = request.data || {};
  // Opt-in: spend available promo credit on this booking. Deliberately explicit
  // (an owner may prefer to bank credit for a pricier slot), so a false/absent
  // value charges the full price via Payzah and leaves the balance untouched.
  const useCredit = data.useCredit === true;
  const placementType = String(data.placementType || "");
  const placement = PROMO_PLACEMENTS[placementType];
  if (!placement) throw new HttpsError("invalid-argument", "Unknown placement type.");

  const paymentMethod = String(data.paymentMethod || "");
  if (!["KNET", "Card", "Apple Pay"].includes(paymentMethod)) {
    throw new HttpsError("invalid-argument", "Invalid payment method.");
  }

  // Approved-owner gate — derive the boutique server-side, never trust client.
  const ownerSnap = await db.collection("boutique_owners").doc(uid).get();
  if (!ownerSnap.exists || ownerSnap.data().isApproved !== true) {
    throw new HttpsError("permission-denied", "Only approved boutique owners can book promotions.");
  }
  const boutiqueId = String(ownerSnap.data().boutiqueId || "");
  if (!boutiqueId) throw new HttpsError("failed-precondition", "No boutique linked to your account.");

  // ---- Day selection (contiguous run within the upcoming week) ----
  // Day-placements pick startDay (0=Sun … 6=Sat) + numDays (1–7); feed is
  // week-only (full week). startDay + numDays must stay within the 7-day week.
  let startDay = 0;
  let numDays = 7;
  if (placement.dayBased) {
    startDay = Math.floor(Number(data.startDay));
    numDays = Math.floor(Number(data.numDays));
    if (!(startDay >= 0 && startDay <= 6) || !(numDays >= 1 && numDays <= 7)
        || startDay + numDays > 7) {
      throw new HttpsError("invalid-argument",
        "Invalid day range — pick a contiguous block of days within the week.");
    }
  }

  // ---- Targets (one unit per booking; feed takes 1–2 posts) ----
  let targetProductIds = [];
  let categoryPins = []; // top_of_category: exactly one { category, productIds }
  let bannerImageUrl = null;
  let feedPosts = 1;

  if (placement.targets === "product") {
    const pid = String(data.productId || "");
    if (!pid) throw new HttpsError("invalid-argument", "Select a product to promote.");
    targetProductIds = [pid];
  } else if (placement.targets === "products") { // feed: 1–2 posts
    targetProductIds = Array.isArray(data.targetProductIds)
      ? data.targetProductIds.map(String) : [];
    const uniq = new Set(targetProductIds);
    if (targetProductIds.length < 1 || targetProductIds.length > 2
        || uniq.size !== targetProductIds.length) {
      throw new HttpsError("invalid-argument", "Select 1 or 2 posts to sponsor (no duplicates).");
    }
    feedPosts = targetProductIds.length;
  } else if (placement.targets === "category") {
    const category = String(data.category || "");
    const productIds = Array.isArray(data.productIds) ? data.productIds.map(String) : [];
    const uniq = new Set(productIds);
    if (!category) throw new HttpsError("invalid-argument", "Select a category.");
    if (productIds.length < 1 || productIds.length > placement.maxProductsPerCategory
        || uniq.size !== productIds.length) {
      throw new HttpsError("invalid-argument",
        `Pick 1–${placement.maxProductsPerCategory} products for "${category}".`);
    }
    categoryPins = [{ category, productIds }];
  } else { // "none"
    if (placement.requiresBannerImage) {
      bannerImageUrl = String(data.bannerImageUrl || "");
      if (!/^https:\/\/.+/i.test(bannerImageUrl) || bannerImageUrl.length > 2000) {
        throw new HttpsError("invalid-argument", "A valid banner image is required.");
      }
    }
  }

  // Server price: day-placements by numDays, feed by post count. Never trust a
  // client-supplied price.
  const priceKwd = placement.dayBased
    ? promoPrice(placementType, numDays)
    : promoPrice(placementType, null, feedPosts);
  if (priceKwd === null) {
    throw new HttpsError("invalid-argument", "That combination isn't available to book.");
  }
  const priceFils = kwdToFils(priceKwd);

  // Every referenced product must exist under THIS boutique (path-scoped, so
  // ownership is implicit) and — for a category pin — actually be in that
  // category. Existence isn't concurrency-sensitive, so verify before the txn.
  const productsRoot = db.collection("boutiques").doc(boutiqueId).collection("products");
  const verifyProduct = async (pid, requireCategory) => {
    const snap = await productsRoot.doc(pid).get();
    if (!snap.exists) throw new HttpsError("not-found", "A selected product no longer exists.");
    if (requireCategory) {
      const cats = snap.data().category;
      const arr = Array.isArray(cats) ? cats.map(String) : [];
      if (!arr.includes(requireCategory)) {
        throw new HttpsError("failed-precondition",
          `A selected product isn't in the "${requireCategory}" category.`);
      }
    }
  };
  if (targetProductIds.length) {
    await Promise.all(targetProductIds.map((pid) => verifyProduct(pid, null)));
  } else if (categoryPins.length) {
    await Promise.all(categoryPins[0].productIds.map(
      (pid) => verifyProduct(pid, categoryPins[0].category)));
  }

  // ---- Week + days + hold ----
  const nowMs = Date.now();
  const { startMs, endMs } = promoNextWeek(nowMs);
  const weekStart = admin.firestore.Timestamp.fromMillis(startMs);
  const weekEnd = admin.firestore.Timestamp.fromMillis(endMs);
  const dayStartMs = startMs + startDay * ONE_DAY_MS;
  const dayEndMs = dayStartMs + numDays * ONE_DAY_MS;
  const dayStart = admin.firestore.Timestamp.fromMillis(dayStartMs);
  const dayEnd = admin.firestore.Timestamp.fromMillis(dayEndMs);
  const holdExpiresAt = admin.firestore.Timestamp.fromMillis(
    nowMs + PROMO_HOLD_MINUTES * 60 * 1000);

  const boutiqueRef = db.collection("boutiques").doc(boutiqueId);
  const bookingRef = db.collection("promo_bookings").doc();
  const attemptRef = db.collection("payment_attempts").doc();
  const trackid = `LIBSKP${crypto.randomBytes(8).toString("hex")}`;
  const payzahPaymentType = paymentMethod === "KNET" ? "1"
    : paymentMethod === "Apple Pay" ? "3" : "2";

  // ---- Availability + credit split + atomic write ----
  // The week query inside the transaction gives serializable isolation (a
  // concurrent booking that would fill the same day forces a retry), and reading
  // the boutique's live credit in the SAME transaction means the balance can't be
  // double-spent by two concurrent bookings. The credit/charge split is decided
  // here, on the live balance, so the branch (skip Payzah vs. charge a remainder)
  // is chosen atomically with the write.
  let creditOnly = false;
  let creditFils = 0;   // credit applied to THIS booking
  let chargeFils = priceFils; // remainder charged via Payzah
  await db.runTransaction(async (tx) => {
    const weekSnap = await tx.get(
      db.collection("promo_bookings").where("weekStart", "==", weekStart));
    const boutiqueSnap = await tx.get(boutiqueRef);
    // Live spendable grants (only read when the owner opted to use credit).
    let grants = [];
    if (useCredit) {
      const grantsSnap = await tx.get(
        boutiqueRef.collection("promoCredits").where("remainingFils", ">", 0));
      grants = grantsSnap.docs.map(grantToAllocInput);
    }

    const occupying = weekSnap.docs.map((d) => d.data())
      .filter((b) => isPromoOccupying(b, nowMs));
    const availability = checkPromoAvailability(occupying, {
      boutiqueId, placementType, startDay, numDays,
      category: categoryPins[0] ? categoryPins[0].category : undefined,
      categoryItems: categoryPins[0] ? categoryPins[0].productIds.length : 0,
    });
    if (!availability.ok) {
      throw new HttpsError(availability.code, availability.reason);
    }

    // Split against the AUTHORITATIVE live balance (expired-but-unswept grants
    // excluded). useCredit === false → balance 0 → full charge, credit untouched.
    const balanceFils = useCredit ? spendableBalanceFils(grants, nowMs) : 0;
    const split = splitCreditCharge(balanceFils, priceFils, useCredit);
    creditFils = split.creditFils;
    chargeFils = split.chargeFils;
    creditOnly = split.creditOnly;

    // A remainder means the gateway must actually run — enforce the enable-gate
    // now (a fully-credit-funded booking legitimately bypasses it).
    if (!creditOnly && !payzahEnabled) {
      throw new HttpsError("failed-precondition", "Promo checkout is not available right now.");
    }

    const boutiqueName = boutiqueSnap.exists ? String(boutiqueSnap.data().name || "") : "";
    const nowTs = admin.firestore.FieldValue.serverTimestamp();
    const bookingData = {
      boutiqueId, boutiqueName, placementType,
      weekStart, weekEnd,
      startDay, numDays, dayStart, dayEnd,
      priceKwd,
      renderingApplied: false,
      amountFromCredit: filsToKwd(creditFils),
      amountFromCreditFils: creditFils,
      amountToCharge: filsToKwd(chargeFils),
      ...(targetProductIds.length ? { targetProductIds } : {}),
      ...(categoryPins.length
        ? { categoryPins, targetCategories: [categoryPins[0].category] } : {}),
      ...(bannerImageUrl ? { bannerImageUrl } : {}),
      ...(placement.dayBased ? {} : { quantity: feedPosts }),
      createdAt: nowTs,
      updatedAt: nowTs,
    };

    if (creditOnly) {
      // Fully covered by credit: no gateway, no payment_attempt. Spend the credit
      // NOW (FIFO, atomic) and write the booking as if already paid — active, or
      // held for banner review. creditFils <= balanceFils by construction, so the
      // allocation never falls short here.
      const alloc = allocateCreditFifo(grants, creditFils, nowMs);
      const remainById = {};
      for (const g of grants) remainById[g.id] = g.remainingFils;
      for (const a of alloc.allocations) {
        tx.update(boutiqueRef.collection("promoCredits").doc(a.creditId), {
          remainingFils: remainById[a.creditId] - a.fils, updatedAt: nowTs,
        });
      }
      if (alloc.allocatedFils > 0) {
        txAddSpendEntry(tx, boutiqueRef, {
          amountFils: -alloc.allocatedFils, type: "spend",
          reason: `promo_booking:${bookingRef.id}`, grantedBy: null,
          allocations: alloc.allocations,
        });
        tx.update(boutiqueRef, {
          promoCreditBalance: applyFilsDelta(
            boutiqueSnap.exists ? boutiqueSnap.data().promoCreditBalance : 0,
            -alloc.allocatedFils),
          updatedAt: nowTs,
        });
      }
      const status = placement.reviewBeforeActive ? "paid_pending_review" : "active";
      tx.set(bookingRef, {
        ...bookingData,
        status,
        creditOnly: true,
        paymentMethod: "credit",
        creditSpentFils: alloc.allocatedFils,
        paidAt: nowTs,
        expiresAt: dayEnd || weekEnd || null,
        ...(status === "active" ? { activatedAt: nowTs } : {}),
      });
      return;
    }

    // A remainder is charged through Payzah exactly as before; any credit portion
    // is DEFERRED and only spent when this attempt settles 'paid' (see
    // settlePaidPromoBooking), so an abandoned checkout costs no credit.
    tx.set(bookingRef, {
      ...bookingData,
      status: "pending_payment",
      paymentMethod,
      paymentAttemptId: attemptRef.id,
      holdExpiresAt,
    });
    // Payment attempt — same shape the Payzah engine already understands, tagged
    // kind:"promo_booking" so resolvePaymentAttempt routes it to the booking. The
    // amount is the REMAINDER after credit, never the full price.
    tx.set(attemptRef, {
      kind: "promo_booking",
      promoBookingId: bookingRef.id,
      boutiqueId,
      placementType,
      customerUid: uid,
      provider: "payzah",
      trackid,
      payzahPaymentId: null,
      payzahPaymentType,
      lastGatewayStatus: null,
      status: "pending",
      amount: filsToKwd(chargeFils),
      currency: "KWD",
      checkAttempts: 0,
      lastCheckedAt: null,
      createdAt: nowTs,
      updatedAt: nowTs,
    });
  });

  return {
    bookingId: bookingRef.id,
    // No gateway step when credit covers the whole price — the client uses this
    // to skip straight past the payment page.
    paymentAttemptId: creditOnly ? null : attemptRef.id,
    priceKwd,
    amountFromCredit: filsToKwd(creditFils),
    amountToCharge: filsToKwd(chargeFils),
    creditOnly,
    weekStart: startMs,
    weekEnd: endMs,
  };
});

// ================= PROMO BOOKINGS: RENDERING FLAGS =================
//
// Promo placements render through fields the app already queries
// (isFeaturedOnHome/featuredExpiresAt, isVisibleOnHome/homeExpiresAt,
// isFeedSponsored/feedSponsoredUntil, promotedCategories/categoryPromoUntil, and
// the hero_banners collection). Applying a booking sets those fields on its
// target docs; expiry clears them. Writes are NON-DESTRUCTIVE to editorial
// curation (the admin homepage tool sets the same fields for free): an expiry is
// only ever EXTENDED, an *Order is only set when absent, and a flag is cleared
// only once its expiry has actually lapsed — so an admin-featured item that
// outlives the promo week is left intact.

const toMillisOr0 = (v) => (v && typeof v.toMillis === "function" ? v.toMillis() : 0);

// Set a boolean flag + extend its expiry to at least `until` (never shorten a
// later, e.g. admin-set, expiry) + ensure an order field exists.
async function promoSetFlag(ref, { flagField, expiryField, orderField, until }) {
  const snap = await ref.get();
  if (!snap.exists) return;
  const data = snap.data();
  const keepExisting = toMillisOr0(data[expiryField]) > until.toMillis();
  const update = {
    [flagField]: true,
    [expiryField]: keepExisting ? data[expiryField] : until,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  // The home queries orderBy the *Order field, so a doc missing it would be
  // excluded — every promoted doc must have one. Never overwrite an existing
  // (admin-chosen) order; editorial picks use small ints and sort first.
  if (orderField && data[orderField] === undefined) update[orderField] = Date.now();
  await ref.update(update);
}

// Clear a flag ONLY if its expiry has lapsed, so a longer admin feature stays.
async function promoClearFlag(ref, { flagField, expiryField, orderField }) {
  const snap = await ref.get();
  if (!snap.exists) return;
  const data = snap.data();
  if (toMillisOr0(data[expiryField]) > Date.now()) return; // still featured
  const update = {
    [flagField]: false,
    [expiryField]: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (orderField) update[orderField] = admin.firestore.FieldValue.delete();
  await ref.update(update);
}

// Apply a booking's rendering flags to its targets — called by the scheduled
// activator when the booking's day-window opens. Idempotent. Expiry is the
// window end (dayEnd; weekEnd for feed). Returns booking-field updates to merge
// (only home_banner needs one: the id of the hero_banners doc it publishes).
async function applyPromoRendering(booking) {
  const bid = booking.boutiqueId;
  const until = booking.dayEnd || booking.weekEnd; // render-window end
  const product = (pid) =>
    db.collection("boutiques").doc(bid).collection("products").doc(pid);

  switch (booking.placementType) {
    case "featured_product":
      for (const pid of booking.targetProductIds || []) {
        await promoSetFlag(product(pid), {
          flagField: "isFeaturedOnHome", expiryField: "featuredExpiresAt",
          orderField: "featuredOrder", until,
        });
      }
      return {};
    case "featured_boutique":
      await promoSetFlag(db.collection("boutiques").doc(bid), {
        flagField: "isVisibleOnHome", expiryField: "homeExpiresAt",
        orderField: "homeOrder", until,
      });
      return {};
    case "feed_sponsored":
      for (const pid of booking.targetProductIds || []) {
        await promoSetFlag(product(pid), {
          flagField: "isFeedSponsored", expiryField: "feedSponsoredUntil", until,
        });
      }
      return {};
    case "top_of_category":
      for (const pin of booking.categoryPins || []) {
        for (const pid of pin.productIds || []) {
          const ref = product(pid);
          const snap = await ref.get();
          if (!snap.exists) continue;
          const keep = toMillisOr0(snap.data().categoryPromoUntil) > until.toMillis();
          await ref.update({
            promotedCategories: admin.firestore.FieldValue.arrayUnion(pin.category),
            categoryPromoUntil: keep ? snap.data().categoryPromoUntil : until,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }
      return {};
    case "home_banner": {
      // Publish the hero_banners doc RotatingHeroBanner renders (once).
      if (booking.heroBannerId) return {};
      const bannerRef = db.collection("hero_banners").doc();
      await bannerRef.set({
        imageUrl: booking.bannerImageUrl || "",
        isActive: true,
        order: Date.now(), // published after editorial banners (small ints)
        boutiqueId: bid,
        boutiqueName: booking.boutiqueName || "",
        promoBookingId: booking.id || null,
        expiresAt: until,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { heroBannerId: bannerRef.id };
    }
    default:
      return {};
  }
}

// Revoke a booking's rendering flags (called on expiry). Non-destructive: only
// clears what has actually lapsed.
async function revokePromoRendering(booking) {
  const bid = booking.boutiqueId;
  const product = (pid) =>
    db.collection("boutiques").doc(bid).collection("products").doc(pid);

  switch (booking.placementType) {
    case "featured_product":
      for (const pid of booking.targetProductIds || []) {
        await promoClearFlag(product(pid), {
          flagField: "isFeaturedOnHome", expiryField: "featuredExpiresAt",
          orderField: "featuredOrder",
        });
      }
      break;
    case "featured_boutique":
      await promoClearFlag(db.collection("boutiques").doc(bid), {
        flagField: "isVisibleOnHome", expiryField: "homeExpiresAt",
        orderField: "homeOrder",
      });
      break;
    case "feed_sponsored":
      for (const pid of booking.targetProductIds || []) {
        await promoClearFlag(product(pid), {
          flagField: "isFeedSponsored", expiryField: "feedSponsoredUntil",
        });
      }
      break;
    case "top_of_category":
      for (const pin of booking.categoryPins || []) {
        for (const pid of pin.productIds || []) {
          const ref = product(pid);
          const snap = await ref.get();
          if (!snap.exists) continue;
          const update = {
            promotedCategories: admin.firestore.FieldValue.arrayRemove(pin.category),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          };
          if (toMillisOr0(snap.data().categoryPromoUntil) <= Date.now()) {
            update.categoryPromoUntil = admin.firestore.FieldValue.delete();
          }
          await ref.update(update);
        }
      }
      break;
    case "home_banner":
      if (booking.heroBannerId) {
        await db.collection("hero_banners").doc(booking.heroBannerId)
          .update({ isActive: false });
      }
      break;
  }
}

// Hourly: turn a paid booking's rendering ON when its day-window opens, so it
// renders only during its booked days (never early). Banners publish their
// hero_banners doc here too. Idempotent via the renderingApplied flag.
exports.activatePromoBookings = onSchedule(
  { schedule: "every 1 hours", maxInstances: 1 },
  async () => {
  const now = admin.firestore.Timestamp.now();
  const nowMs = Date.now();
  const snap = await db.collection("promo_bookings")
    .where("status", "==", "active")
    .where("dayStart", "<=", now)
    .limit(200)
    .get();
  for (const doc of snap.docs) {
    const booking = doc.data();
    if (booking.renderingApplied === true) continue;              // already live
    if (promoWindowState(booking, nowMs) !== "during") continue;  // not open, or already ended
    try {
      const updates = await applyPromoRendering({ id: doc.id, ...booking });
      await doc.ref.update({
        renderingApplied: true,
        ...(updates || {}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      logger.error("Failed to activate promo booking", { id: doc.id, error: String(err) });
    }
  }
});

// Hourly: expire bookings whose day-window has ended, revoking any rendering
// that was applied. Covers active bookings and banners still awaiting approval
// when the window lapsed (those never rendered, so there's nothing to revoke).
exports.expirePromoBookings = onSchedule(
  { schedule: "every 1 hours", maxInstances: 1 },
  async () => {
  const now = admin.firestore.Timestamp.now();
  for (const status of ["active", "paid_pending_review"]) {
    const snap = await db.collection("promo_bookings")
      .where("status", "==", status)
      .where("dayEnd", "<", now)
      .limit(200)
      .get();
    for (const doc of snap.docs) {
      try {
        const booking = doc.data();
        if (booking.renderingApplied) await revokePromoRendering(booking);
        await doc.ref.update({
          status: "expired",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (err) {
        logger.error("Failed to expire promo booking", { id: doc.id, error: String(err) });
      }
    }
  }
});

// ================= PROMO BOOKINGS: AVAILABILITY =================
//
// Pure availability summary for the upcoming week — per-placement remaining
// capacity + what this boutique already holds + the global cap. Returns COUNTS
// only (never who booked), so it's safe to expose to any owner.
function computePromoAvailability(occupying, boutiqueId) {
  const days = [0, 1, 2, 3, 4, 5, 6];

  // Per-day global slots this boutique holds (day-placements only; feed = 0).
  const globalUsedPerDay = days.map((d) => occupying
    .filter((b) => b.boutiqueId === boutiqueId
      && promoGlobalSlots(b.placementType) > 0 && promoCoversDay(b, d))
    .reduce((s, b) => s + promoGlobalSlots(b.placementType), 0));

  const placements = {};
  for (const [type, p] of Object.entries(PROMO_PLACEMENTS)) {
    const sameType = occupying.filter((b) => b.placementType === type);

    if (!p.dayBased) {
      // feed_sponsored: week-only, unlimited. priceByPosts is the AUTHORITATIVE
      // price table, computed by the same promoPrice() the booking uses — the
      // client only ever looks up a value, never recomputes it (no drift).
      const priceByPosts = {};
      for (const posts of Object.keys(p.tiers)) {
        priceByPosts[posts] = promoPrice(type, null, Number(posts));
      }
      placements[type] = {
        weekly: true, unlimited: true, tiers: p.tiers, priceByPosts,
        mineHeld: sameType
          .filter((b) => b.boutiqueId === boutiqueId)
          .reduce((s, b) => s + (b.quantity || 1), 0),
      };
      continue;
    }

    // Day placements: the exact price for every bookable length (1–7 days),
    // computed server-side via promoPrice() and returned so the UI can display
    // it by lookup only. priceByDays[n] is the price for n days; [0] is unused.
    // The full-week nudge is then just priceByDays[6] > priceByDays[7], never a
    // formula duplicated in Flutter.
    const priceByDays = [null];
    for (let n = 1; n <= 7; n++) priceByDays.push(promoPrice(type, n));

    if (p.perCategory) {
      // Per-category item usage, per day (only categories with bookings appear;
      // any category not listed is fully open on every day).
      const categories = {};
      for (const b of sameType) {
        for (const pin of b.categoryPins || []) {
          const rec = categories[pin.category]
            || { usedPerDay: [0, 0, 0, 0, 0, 0, 0], minePerDay: [0, 0, 0, 0, 0, 0, 0] };
          const items = (pin.productIds || []).length;
          for (const d of days) {
            if (!promoCoversDay(b, d)) continue;
            rec.usedPerDay[d] += items;
            if (b.boutiqueId === boutiqueId) rec.minePerDay[d] += items;
          }
          categories[pin.category] = rec;
        }
      }
      placements[type] = {
        daily: p.daily, weekly: p.weekly, priceByDays,
        perCategoryCapacity: p.perCategory.capacity,
        perCategoryPerBoutique: p.perCategory.perBoutique,
        categories,
      };
    } else {
      const usedPerDay = [0, 0, 0, 0, 0, 0, 0];
      const minePerDay = [0, 0, 0, 0, 0, 0, 0];
      for (const b of sameType) {
        for (const d of days) {
          if (!promoCoversDay(b, d)) continue;
          usedPerDay[d] += 1;
          if (b.boutiqueId === boutiqueId) minePerDay[d] += 1;
        }
      }
      placements[type] = {
        daily: p.daily, weekly: p.weekly, priceByDays,
        capacity: p.capacity, perBoutique: p.perBoutique,
        usedPerDay,
        remainingPerDay: usedPerDay.map((u) => Math.max(0, p.capacity - u)),
        minePerDay,
      };
    }
  }

  return {
    globalCap: PROMO_MAX_GLOBAL_SLOTS,
    globalUsedPerDay,
    globalRemainingPerDay: globalUsedPerDay.map((u) => Math.max(0, PROMO_MAX_GLOBAL_SLOTS - u)),
    placements,
  };
}

exports.getPromoAvailability = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "You must be logged in.");
  }
  const ownerSnap = await db.collection("boutique_owners").doc(request.auth.uid).get();
  if (!ownerSnap.exists || ownerSnap.data().isApproved !== true) {
    throw new HttpsError("permission-denied", "Only approved boutique owners can view availability.");
  }
  const boutiqueId = String(ownerSnap.data().boutiqueId || "");

  const nowMs = Date.now();
  const { startMs, endMs } = promoNextWeek(nowMs);
  const weekStart = admin.firestore.Timestamp.fromMillis(startMs);
  const snap = await db.collection("promo_bookings")
    .where("weekStart", "==", weekStart).get();
  const occupying = snap.docs.map((d) => d.data())
    .filter((b) => isPromoOccupying(b, nowMs));

  // Live promo-credit balance for the checkout checkbox — computed from the
  // actual unexpired grants (not the denormalized field), so the amount offered
  // matches what a booking would really apply, even if the daily sweep is behind.
  let promoCreditBalance = 0;
  if (boutiqueId) {
    const creditsSnap = await db.collection("boutiques").doc(boutiqueId)
      .collection("promoCredits").where("remainingFils", ">", 0).get();
    const grants = creditsSnap.docs.map((d) => ({
      remainingFils: Number(d.data().remainingFils) || 0,
      expiresAtMs: toMillisOr0(d.data().expiresAt) || null,
    }));
    promoCreditBalance = filsToKwd(spendableBalanceFils(grants, nowMs));
  }

  return {
    weekStart: startMs,
    weekEnd: endMs,
    promoCreditBalance,
    ...computePromoAvailability(occupying, boutiqueId),
  };
});

// ================= PROMO BOOKINGS: BANNER APPROVAL =================
//
// Home banners are paid but held (paid_pending_review) until a super admin
// approves the creative — the one placement whose public content gets a human
// check. Approval flips the booking to active; the scheduled activator then
// publishes the hero_banners doc when the banner's day-window opens (so, like
// every placement, it renders only during its booked days).

exports.approvePromoBanner = onCall({ maxInstances: 2 }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be logged in.");
  if (!await isSuperAdminUser(request.auth.uid)) {
    throw new HttpsError("permission-denied", "Super admins only.");
  }
  const { bookingId } = request.data || {};
  if (!bookingId || typeof bookingId !== "string") {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }
  const ref = db.collection("promo_bookings").doc(bookingId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Booking not found.");
  const booking = snap.data();
  if (booking.placementType !== "home_banner") {
    throw new HttpsError("failed-precondition", "Not a banner booking.");
  }
  if (booking.status !== "paid_pending_review") {
    throw new HttpsError("failed-precondition", `Booking is ${booking.status}.`);
  }

  await ref.update({
    status: "active",
    renderingApplied: false, // the activator publishes the banner at window start
    approvedAt: admin.firestore.FieldValue.serverTimestamp(),
    activatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { success: true };
});

exports.rejectPromoBanner = onCall({ maxInstances: 2 }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be logged in.");
  if (!await isSuperAdminUser(request.auth.uid)) {
    throw new HttpsError("permission-denied", "Super admins only.");
  }
  const uid = request.auth.uid;
  const { bookingId, reason } = request.data || {};
  if (!bookingId || typeof bookingId !== "string") {
    throw new HttpsError("invalid-argument", "bookingId is required.");
  }
  const ref = db.collection("promo_bookings").doc(bookingId);

  // One transaction so the reject + any credit refund are atomic and idempotent
  // (guarded by the paid_pending_review status and a creditRefunded flag).
  const refundedFils = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Booking not found.");
    const booking = snap.data();
    if (booking.status !== "paid_pending_review") {
      throw new HttpsError("failed-precondition", `Booking is ${booking.status}.`);
    }

    // Refund promo credit spent on a rejected banner as FRESH credit (a goodwill
    // re-credit with a new expiry — we don't try to restore the exact source
    // grants, which may since have lapsed). Cash paid via Payzah is still
    // refunded manually (dashboard + "Mark as Refunded"), as before.
    const spentFils = Math.floor(Number(booking.creditSpentFils) || 0);
    let refunded = 0;
    const nowTs = admin.firestore.FieldValue.serverTimestamp();
    if (spentFils > 0 && booking.creditRefunded !== true) {
      const boutiqueRef = db.collection("boutiques").doc(booking.boutiqueId);
      const bqSnap = await tx.get(boutiqueRef);
      if (bqSnap.exists) {
        txAddGrantEntry(tx, boutiqueRef, {
          amountFils: spentFils, type: "admin_adjustment",
          reason: `promo_booking_refund:${bookingId}`, grantedBy: uid,
          expiresAtMs: Date.now() + CREDIT_EXPIRY_DAYS * ONE_DAY_MS,
        });
        tx.update(boutiqueRef, {
          promoCreditBalance: applyFilsDelta(bqSnap.data().promoCreditBalance, spentFils),
          updatedAt: nowTs,
        });
        refunded = spentFils;
      }
    }

    tx.update(ref, {
      status: "rejected",
      rejectionReason: reason ? String(reason).slice(0, 500) : null,
      ...(refunded > 0 ? { creditRefunded: true } : {}),
      updatedAt: nowTs,
    });
    return refunded;
  });

  logger.info("Promo banner rejected", { bookingId, refundedKwd: filsToKwd(refundedFils) });
  return { success: true, creditRefunded: filsToKwd(refundedFils) };
});

// ================= FOUNDING-PARTNER PROMO CREDIT: LEDGER WRITES =================
//
// The jobs below are low-frequency by nature: the recharge is a ONE-TIME launch
// action, the Week-2 grant and expiry sweep run once a day, and adjustments are
// occasional admin work. None of them need burst concurrency.
//
// Free promo credit for founding-partner boutiques, spendable on any placement.
// The subcollection boutiques/{id}/promoCredits is the full audit ledger (every
// grant/spend/expiry/adjustment); boutiques/{id}.promoCreditBalance is the
// denormalized live total the app reads at checkout. Both are SERVER-ONLY (see
// firestore.rules) — only the functions below and the createPromoBooking spend
// (Step 3) ever write them, all via the admin SDK. Every calculation goes
// through the pure, unit-tested helpers in ./promo_credit.
//
// Balance maintenance is drift-free: each mutation moves promoCreditBalance by an
// INTEGER-fils delta (applyFilsDelta), never by a floating-point KWD increment.
// The stored balance is a fast-read hint that can briefly overstate by a just-
// expired-but-not-yet-swept grant; the AUTHORITATIVE spend allocation always
// re-reads live grants and filters expiry, so credit that has lapsed is never
// spent regardless of the display value.

// 7 days between the Week-1 (launch) and Week-2 founding grants. Distinct from
// CREDIT_EXPIRY_DAYS (grant lifetime) even though both are currently 7.
const FOUNDING_WEEK_GAP_MS = 7 * ONE_DAY_MS;

// Write a positive grant-like entry (grant or top-up) to a boutique's ledger
// inside a transaction. remainingFils starts equal to the amount; the balance is
// bumped by the caller. Returns the new entry ref.
function txAddGrantEntry(tx, boutiqueRef, { amountFils, type, reason, grantedBy, expiresAtMs }) {
  const ref = boutiqueRef.collection("promoCredits").doc();
  tx.set(ref, {
    amount: filsToKwd(amountFils),
    amountFils,
    remainingFils: amountFils,
    type,
    reason,
    grantedBy: grantedBy || null,
    expiresAt: expiresAtMs == null ? null : admin.firestore.Timestamp.fromMillis(expiresAtMs),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return ref;
}

// Write a negative ledger entry (spend/expiry/clawback) with the allocation trail
// of which grants it drew from. Spends carry no remaining balance of their own.
function txAddSpendEntry(tx, boutiqueRef, { amountFils, type, reason, grantedBy, allocations }) {
  const ref = boutiqueRef.collection("promoCredits").doc();
  tx.set(ref, {
    amount: filsToKwd(amountFils),
    amountFils,
    remainingFils: null,
    type,
    reason,
    grantedBy: grantedBy || null,
    expiresAt: null,
    allocations: allocations || [],
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return ref;
}

// Map a promoCredits doc snapshot to the plain shape allocateCreditFifo expects.
function grantToAllocInput(doc) {
  const d = doc.data();
  return {
    id: doc.id,
    remainingFils: Number(d.remainingFils) || 0,
    expiresAtMs: toMillisOr0(d.expiresAt) || null,
    createdAtMs: toMillisOr0(d.createdAt) || 0,
  };
}

// The one-time launch action: grant Week 1 (6 KWD) to every boutique still
// pending its founding credit, and stamp each so the daily scheduler grants
// Week 2 in 7 days. Superadmin-only. Idempotent — a boutique whose pending flag
// is already cleared is skipped, so a re-run (or a crash mid-run) never double-
// grants. Each boutique is its own transaction (flag flip + grant are atomic).
exports.rechargeFoundingPartnerCredits = onCall({ maxInstances: 2 }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be logged in.");
  const uid = request.auth.uid;
  if (!await isSuperAdminUser(uid)) {
    throw new HttpsError("permission-denied", "Super admins only.");
  }

  const pending = await db.collection("boutiques")
    .where("promoCreditPending", "==", true).get();

  let recharged = 0;
  let skipped = 0;
  for (const doc of pending.docs) {
    try {
      const applied = await db.runTransaction(async (tx) => {
        const snap = await tx.get(doc.ref);
        if (!snap.exists) return false;
        const data = snap.data();
        if (data.promoCreditPending !== true) return false; // already recharged
        const nowMs = Date.now();
        const amountFils = kwdToFils(FOUNDING_WEEK1_KWD);
        txAddGrantEntry(tx, doc.ref, {
          amountFils, type: "grant", reason: "founding_week1",
          grantedBy: uid, expiresAtMs: nowMs + CREDIT_EXPIRY_DAYS * ONE_DAY_MS,
        });
        tx.update(doc.ref, {
          promoCreditBalance: applyFilsDelta(data.promoCreditBalance, amountFils),
          promoCreditPending: false,
          promoCreditWeek2Pending: true,
          promoCreditWeek2DueAt: admin.firestore.Timestamp.fromMillis(nowMs + FOUNDING_WEEK_GAP_MS),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return true;
      });
      applied ? recharged++ : skipped++;
    } catch (err) {
      logger.error("Founding recharge failed for boutique", { id: doc.id, error: String(err) });
      skipped++;
    }
  }
  logger.info("Founding-partner recharge complete", { recharged, skipped });
  return { recharged, skipped };
});

// Daily: grant Week 2 (3 KWD) to each boutique whose Week-2 grant has come due
// (stamped by the launch recharge 7 days earlier). Idempotent via the pending
// flag, one transaction per boutique.
exports.grantFoundingWeek2Credits = onSchedule(
  { schedule: "every 24 hours", maxInstances: 1 },
  async () => {
  const now = admin.firestore.Timestamp.now();
  const due = await db.collection("boutiques")
    .where("promoCreditWeek2Pending", "==", true)
    .where("promoCreditWeek2DueAt", "<=", now)
    .limit(200).get();

  for (const doc of due.docs) {
    try {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(doc.ref);
        if (!snap.exists) return;
        const data = snap.data();
        if (data.promoCreditWeek2Pending !== true) return; // already granted
        const amountFils = kwdToFils(FOUNDING_WEEK2_KWD);
        txAddGrantEntry(tx, doc.ref, {
          amountFils, type: "grant", reason: "founding_week2_launch_recharge",
          grantedBy: null, expiresAtMs: Date.now() + CREDIT_EXPIRY_DAYS * ONE_DAY_MS,
        });
        tx.update(doc.ref, {
          promoCreditBalance: applyFilsDelta(data.promoCreditBalance, amountFils),
          promoCreditWeek2Pending: false,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    } catch (err) {
      logger.error("Week-2 founding grant failed", { id: doc.id, error: String(err) });
    }
  }
});

// Daily: expire lapsed credit. For each grant-like entry that still holds credit
// but has passed its expiry, write an offsetting `expiry` entry for the unused
// remainder, zero the grant's remaining, and decrement the boutique's balance —
// keeping the full ledger (the grant's original amount is never mutated). The
// query returns exactly unconsumed, expired, dated grants (remainingFils > 0
// skips spends/consumed; expiresAt <= now skips never-expiry and live grants).
exports.sweepExpiredPromoCredits = onSchedule(
  { schedule: "every 24 hours", maxInstances: 1 },
  async () => {
  const now = admin.firestore.Timestamp.now();
  const snap = await db.collectionGroup("promoCredits")
    .where("remainingFils", ">", 0)
    .where("expiresAt", "<=", now)
    .limit(300).get();

  for (const doc of snap.docs) {
    try {
      await db.runTransaction(async (tx) => {
        const gSnap = await tx.get(doc.ref);
        if (!gSnap.exists) return;
        const g = gSnap.data();
        const remaining = Math.floor(Number(g.remainingFils) || 0);
        if (remaining <= 0) return; // swept by a concurrent run
        const expMs = toMillisOr0(g.expiresAt);
        if (!(expMs > 0 && expMs <= Date.now())) return; // not actually expired
        const boutiqueRef = doc.ref.parent.parent; // boutiques/{id}
        if (!boutiqueRef) return;
        const bSnap = await tx.get(boutiqueRef);
        if (!bSnap.exists) return;

        txAddSpendEntry(tx, boutiqueRef, {
          amountFils: -remaining, type: "expiry", reason: "expiry", grantedBy: null,
          allocations: [{ creditId: doc.id, fils: remaining }],
        });
        tx.update(doc.ref, {
          remainingFils: 0,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        tx.update(boutiqueRef, {
          promoCreditBalance: applyFilsDelta(bSnap.data().promoCreditBalance, -remaining),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    } catch (err) {
      logger.error("Promo-credit sweep failed for entry", { id: doc.id, error: String(err) });
    }
  }
});

// Manual credit adjustment (superadmin): goodwill top-up, mid-cohort join, or a
// dispute clawback — the `admin_adjustment` path, reusing the same ledger
// mechanism as automated grants/spends (no separate code path). A positive
// amount writes a new grant-like entry (optional expiry; default 7 days, pass
// expiresInDays:0 for never). A negative amount claws credit back FIFO against
// live grants exactly like a spend, clamped to the live balance (can't go
// negative). Returns the actually-applied amount and the new balance.
exports.adjustPromoCredit = onCall({ maxInstances: 2 }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Must be logged in.");
  const uid = request.auth.uid;
  if (!await isSuperAdminUser(uid)) {
    throw new HttpsError("permission-denied", "Super admins only.");
  }

  const data = request.data || {};
  const boutiqueId = String(data.boutiqueId || "");
  const amountKwd = Number(data.amount);
  const reason = (String(data.reason || "").slice(0, 200)) || "admin_adjustment";
  if (!boutiqueId) throw new HttpsError("invalid-argument", "boutiqueId is required.");
  if (!Number.isFinite(amountKwd) || amountKwd === 0) {
    throw new HttpsError("invalid-argument", "amount must be a non-zero number.");
  }
  const amountFils = kwdToFils(amountKwd);
  if (Math.abs(amountFils) > kwdToFils(1000)) {
    throw new HttpsError("invalid-argument", "amount is out of range (max 1000 KWD).");
  }

  // Optional expiry for a top-up. Default matches founding grants; 0/null = never.
  let expiresAtMs = null;
  if (amountFils > 0) {
    const raw = data.expiresInDays;
    if (raw === null || raw === 0) {
      expiresAtMs = null;
    } else if (raw === undefined) {
      expiresAtMs = Date.now() + CREDIT_EXPIRY_DAYS * ONE_DAY_MS;
    } else {
      const days = Number(raw);
      if (!(Number.isFinite(days) && days > 0 && days <= 3650)) {
        throw new HttpsError("invalid-argument", "expiresInDays must be 0 (never) or 1–3650.");
      }
      expiresAtMs = Date.now() + days * ONE_DAY_MS;
    }
  }

  const boutiqueRef = db.collection("boutiques").doc(boutiqueId);
  const result = await db.runTransaction(async (tx) => {
    const bSnap = await tx.get(boutiqueRef);
    if (!bSnap.exists) throw new HttpsError("not-found", "Boutique not found.");
    const bData = bSnap.data();

    if (amountFils > 0) {
      txAddGrantEntry(tx, boutiqueRef, {
        amountFils, type: "admin_adjustment", reason, grantedBy: uid, expiresAtMs,
      });
      const newBalance = applyFilsDelta(bData.promoCreditBalance, amountFils);
      tx.update(boutiqueRef, {
        promoCreditBalance: newBalance,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { applied: filsToKwd(amountFils), newBalance };
    }

    // Clawback — draw the negative amount down against live grants FIFO.
    const grantsSnap = await tx.get(
      boutiqueRef.collection("promoCredits").where("remainingFils", ">", 0));
    const grants = grantsSnap.docs.map(grantToAllocInput);
    const alloc = allocateCreditFifo(grants, Math.abs(amountFils), Date.now());
    if (alloc.allocatedFils === 0) {
      return { applied: 0, newBalance: filsToKwd(kwdToFils(bData.promoCreditBalance || 0)) };
    }
    const remainById = {};
    for (const g of grants) remainById[g.id] = g.remainingFils;
    for (const a of alloc.allocations) {
      tx.update(boutiqueRef.collection("promoCredits").doc(a.creditId), {
        remainingFils: remainById[a.creditId] - a.fils,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    txAddSpendEntry(tx, boutiqueRef, {
      amountFils: -alloc.allocatedFils, type: "admin_adjustment", reason,
      grantedBy: uid, allocations: alloc.allocations,
    });
    const newBalance = applyFilsDelta(bData.promoCreditBalance, -alloc.allocatedFils);
    tx.update(boutiqueRef, {
      promoCreditBalance: newBalance,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { applied: -filsToKwd(alloc.allocatedFils), newBalance };
  });

  logger.info("Promo-credit adjusted", { boutiqueId, requested: amountKwd, ...result });
  return result;
});

// ================= PROMO SLOTS (legacy — superseded by promo_bookings) =======
// NOTE: initiatePromoSlotPayment / promoSlotPaymentWebhook target MyFatoorah and
// are replaced by createPromoBooking + the Payzah engine (Step 3+). Retired in
// Steps 5/8 once the client no longer calls them. Left in place for now so the
// deploy stays green.

exports.initiatePromoSlotPayment = onCall({ maxInstances: 2 }, async (request) => {
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

exports.expirePromoSlots = onSchedule(
  { schedule: "every 1 hours", maxInstances: 1 },
  async () => {
  const now = admin.firestore.Timestamp.now();
  const snap = await db.collection("promo_slots")
    .where("status", "==", "active").where("expiresAt", "<", now).limit(200).get();
  const batch = db.batch();
  snap.docs.forEach(doc => batch.update(doc.ref, { status: "expired" }));
  if (snap.docs.length > 0) await batch.commit();
});

exports.adminActivatePromoSlot = onCall({ maxInstances: 2 }, async (request) => {
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