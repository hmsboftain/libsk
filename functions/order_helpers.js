const ORDER_SUBTOTAL_LIMIT_KWD = 5000;
const KWD_MULTIPLIER = 1000;

class CheckoutValidationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "CheckoutValidationError";
    this.code = code;
  }
}

function validationError(code, message) {
  return new CheckoutValidationError(code, message);
}

function normalizeCurrency(currency) {
  if (!currency || typeof currency !== "string") {
    throw validationError("invalid-argument", "Currency is required.");
  }

  const normalized = currency.toLowerCase();
  if (normalized !== "kwd") {
    throw validationError("invalid-argument", "Unsupported currency.");
  }

  return normalized;
}

function getDeliveryCost(deliveryMethod) {
  if (deliveryMethod === "Regular Delivery") return 3;
  if (deliveryMethod === "Same Day Delivery") return 5;

  throw validationError("invalid-argument", "Invalid delivery method.");
}

function getPaymentDeliveryMethod(data) {
  const deliveryMethod = data.deliveryMethod || "";
  if (deliveryMethod) {
    getDeliveryCost(deliveryMethod);
    return deliveryMethod;
  }

  const deliveryCost = Number(data.deliveryCost);
  if (deliveryCost === 3) return "Regular Delivery";
  if (deliveryCost === 5) return "Same Day Delivery";

  throw validationError("invalid-argument", "Invalid delivery method.");
}

function normalizeOrderItems(items) {
  if (!items || !Array.isArray(items) || items.length === 0) {
    throw validationError(
      "invalid-argument",
      "Items must be a non-empty array.",
    );
  }

  if (items.length > 50) {
    throw validationError(
      "invalid-argument",
      "Order cannot contain more than 50 items.",
    );
  }

  return items.map((item) => {
    const boutiqueId = String(item.boutiqueId || "");
    const productId = String(item.productId || "");
    const quantity = Math.max(1, Math.floor(Number(item.quantity) || 1));

    if (!boutiqueId || !productId) {
      throw validationError(
        "invalid-argument",
        "Each item must have boutiqueId and productId.",
      );
    }

    if (quantity > 100) {
      throw validationError(
        "invalid-argument",
        "Quantity cannot exceed 100 per item.",
      );
    }

    return {
      original: item,
      boutiqueId,
      productId,
      quantity,
      key: `${boutiqueId}/${productId}`,
    };
  });
}

function aggregateItemQuantities(normalizedItems) {
  const aggregates = new Map();

  for (const item of normalizedItems) {
    const current = aggregates.get(item.key) || {
      boutiqueId: item.boutiqueId,
      productId: item.productId,
      quantity: 0,
    };
    current.quantity += item.quantity;
    aggregates.set(item.key, current);
  }

  return aggregates;
}

function assertSubtotalWithinLimit(subtotal) {
  if (subtotal > ORDER_SUBTOTAL_LIMIT_KWD) {
    throw validationError(
      "invalid-argument",
      "Order total cannot exceed KD 5,000.",
    );
  }
}

function toKwdAmount(total) {
  return Math.round(total * KWD_MULTIPLIER);
}

function validatePaymentIntentForOrder(paymentIntent, expected) {
  if (!paymentIntent || typeof paymentIntent !== "object") {
    throw validationError("invalid-argument", "Invalid payment intent.");
  }

  if (paymentIntent.status !== "succeeded") {
    throw validationError(
      "failed-precondition",
      "Payment has not been completed.",
    );
  }

  if (paymentIntent.currency !== expected.currency) {
    throw validationError(
      "failed-precondition",
      "Payment currency does not match this order.",
    );
  }

  if (paymentIntent.amount !== expected.amount) {
    throw validationError(
      "failed-precondition",
      "Payment amount does not match this order.",
    );
  }

  const metadataUid = paymentIntent.metadata && paymentIntent.metadata.uid;
  if (metadataUid !== expected.uid) {
    throw validationError(
      "permission-denied",
      "Payment does not belong to this user.",
    );
  }
}

module.exports = {
  CheckoutValidationError,
  ORDER_SUBTOTAL_LIMIT_KWD,
  aggregateItemQuantities,
  assertSubtotalWithinLimit,
  getDeliveryCost,
  getPaymentDeliveryMethod,
  normalizeCurrency,
  normalizeOrderItems,
  toKwdAmount,
  validatePaymentIntentForOrder,
};
