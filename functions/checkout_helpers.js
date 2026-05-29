const {HttpsError} = require("firebase-functions/v2/https");

const CHECKOUT_CURRENCY = "kwd";
const KWD_AMOUNT_MULTIPLIER = 1000;

const DELIVERY_COST_BY_METHOD = {
  "Regular Delivery": 3,
  "Same Day Delivery": 5,
};

function getDeliveryCost(deliveryMethod) {
  if (!Object.prototype.hasOwnProperty.call(
    DELIVERY_COST_BY_METHOD,
    deliveryMethod,
  )) {
    throw new HttpsError("invalid-argument", "Invalid delivery method.");
  }

  return DELIVERY_COST_BY_METHOD[deliveryMethod];
}

function productKey(boutiqueId, productId) {
  return `${boutiqueId}/${productId}`;
}

function normalizeOrderItems(items) {
  if (!items || !Array.isArray(items) || items.length === 0) {
    throw new HttpsError("invalid-argument", "Items must be a non-empty array.");
  }

  if (items.length > 50) {
    throw new HttpsError("invalid-argument", "Order cannot contain more than 50 items.");
  }

  const normalizedItems = [];
  const productRequests = new Map();

  for (const item of items) {
    const boutiqueId = String(item.boutiqueId || "").trim();
    const productId = String(item.productId || "").trim();
    const rawQuantity = Number(item.quantity);
    const quantity = Math.max(
      1,
      Math.floor(Number.isFinite(rawQuantity) ? rawQuantity : 1),
    );

    if (!boutiqueId || !productId) {
      throw new HttpsError("invalid-argument", "Invalid product information.");
    }

    if (quantity > 100) {
      throw new HttpsError("invalid-argument", "Quantity cannot exceed 100 per item.");
    }

    const normalized = {
      productId,
      boutiqueId,
      title: String(item.title || ""),
      imageUrl: String(item.imageUrl || ""),
      description: String(item.description || ""),
      size: String(item.size || ""),
      color: String(item.color || "").trim(),
      quantity,
    };
    normalizedItems.push(normalized);

    const key = productKey(boutiqueId, productId);
    const existing = productRequests.get(key) || {
      boutiqueId,
      productId,
      quantity: 0,
    };
    existing.quantity += quantity;
    productRequests.set(key, existing);
  }

  return {
    normalizedItems,
    productRequests: Array.from(productRequests.values()),
  };
}

function stripeAmountFromKwd(total) {
  return Math.round(total * KWD_AMOUNT_MULTIPLIER);
}

function assertPaymentIntentMatchesOrder(
  paymentIntent,
  {uid, expectedAmount, currency = CHECKOUT_CURRENCY},
) {
  if (!paymentIntent || typeof paymentIntent !== "object") {
    throw new HttpsError("failed-precondition", "Payment could not be verified.");
  }

  if (paymentIntent.status !== "succeeded") {
    throw new HttpsError("failed-precondition", "Payment has not completed.");
  }

  if (String(paymentIntent.currency || "").toLowerCase() !== currency) {
    throw new HttpsError("failed-precondition", "Payment currency does not match this order.");
  }

  if (Number(paymentIntent.amount) !== expectedAmount) {
    throw new HttpsError("failed-precondition", "Payment amount does not match this order.");
  }

  const metadataUid = paymentIntent.metadata && paymentIntent.metadata.firebaseUid;
  if (metadataUid !== uid) {
    throw new HttpsError("permission-denied", "Payment does not belong to this user.");
  }
}

module.exports = {
  CHECKOUT_CURRENCY,
  getDeliveryCost,
  normalizeOrderItems,
  productKey,
  stripeAmountFromKwd,
  assertPaymentIntentMatchesOrder,
};
