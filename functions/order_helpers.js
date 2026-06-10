const {HttpsError} = require("firebase-functions/v2/https");

const ORDER_CURRENCY = "kwd";
const ALLOWED_DELIVERY_METHODS = ["Regular Delivery", "Same Day Delivery"];

function getDeliveryCost(deliveryMethod) {
  if (!ALLOWED_DELIVERY_METHODS.includes(deliveryMethod)) {
    throw new HttpsError("invalid-argument", "Invalid delivery method.");
  }

  return deliveryMethod === "Regular Delivery" ? 3 : 5;
}

function normalizeCurrency(currency) {
  if (!currency || typeof currency !== "string") {
    throw new HttpsError("invalid-argument", "Currency is required.");
  }

  const normalized = currency.toLowerCase();
  if (normalized !== ORDER_CURRENCY) {
    throw new HttpsError("invalid-argument", "Unsupported currency.");
  }

  return normalized;
}

function toStripeAmount(total, currency = ORDER_CURRENCY) {
  const multiplier = currency === "kwd" ? 1000 : 100;
  const amount = Math.round(Number(total) * multiplier);

  if (!Number.isFinite(amount) || amount <= 0) {
    throw new HttpsError(
      "invalid-argument",
      "Order total must be greater than zero.",
    );
  }

  return amount;
}

function normalizeQuantity(value) {
  const quantity = Math.max(1, Math.floor(Number(value) || 1));
  if (quantity > 100) {
    throw new HttpsError(
      "invalid-argument",
      "Quantity cannot exceed 100 per item.",
    );
  }
  return quantity;
}

function productKey(boutiqueId, productId) {
  return `${boutiqueId}/${productId}`;
}

function normalizeOrderItems(items) {
  if (!items || !Array.isArray(items) || items.length === 0) {
    throw new HttpsError("invalid-argument", "Items must be a non-empty array.");
  }

  if (items.length > 50) {
    throw new HttpsError(
      "invalid-argument",
      "Order cannot contain more than 50 items.",
    );
  }

  const byProduct = new Map();

  for (const item of items) {
    const boutiqueId = String(item.boutiqueId || "");
    const productId = String(item.productId || "");
    const quantity = normalizeQuantity(item.quantity);

    if (!boutiqueId || !productId) {
      throw new HttpsError("invalid-argument", "Invalid product information.");
    }

    const key = productKey(boutiqueId, productId);
    const existing = byProduct.get(key);

    if (existing) {
      existing.quantity += quantity;
      if (existing.quantity > 100) {
        throw new HttpsError(
          "invalid-argument",
          "Quantity cannot exceed 100 per item.",
        );
      }
      continue;
    }

    byProduct.set(key, {
      key,
      boutiqueId,
      productId,
      quantity,
      sourceItem: item,
    });
  }

  return Array.from(byProduct.values());
}

function validatePaymentIntentId(paymentIntentId) {
  if (
    typeof paymentIntentId !== "string" ||
    paymentIntentId.trim() === "" ||
    paymentIntentId.length > 200
  ) {
    throw new HttpsError("invalid-argument", "Invalid paymentIntentId.");
  }

  return paymentIntentId;
}

function validatePaymentIntent(
  paymentIntent,
  {paymentIntentId, uid, expectedAmount, currency = ORDER_CURRENCY},
) {
  if (!paymentIntent || paymentIntent.id !== paymentIntentId) {
    throw new HttpsError(
      "failed-precondition",
      "Payment could not be verified.",
    );
  }

  if (paymentIntent.status !== "succeeded") {
    throw new HttpsError(
      "failed-precondition",
      "Payment has not completed successfully.",
    );
  }

  if (String(paymentIntent.currency || "").toLowerCase() !== currency) {
    throw new HttpsError(
      "failed-precondition",
      "Payment currency does not match this order.",
    );
  }

  if (Number(paymentIntent.amount) !== expectedAmount) {
    throw new HttpsError(
      "failed-precondition",
      "Payment amount does not match this order.",
    );
  }

  const metadataUid = paymentIntent.metadata && paymentIntent.metadata.uid;
  if (metadataUid !== uid) {
    throw new HttpsError(
      "permission-denied",
      "Payment does not belong to this user.",
    );
  }
}

module.exports = {
  ORDER_CURRENCY,
  ALLOWED_DELIVERY_METHODS,
  getDeliveryCost,
  normalizeCurrency,
  normalizeOrderItems,
  productKey,
  toStripeAmount,
  validatePaymentIntent,
  validatePaymentIntentId,
};
