class OrderValidationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "OrderValidationError";
    this.code = code;
  }
}

const ORDER_CURRENCY = "kwd";
const KWD_MINOR_UNITS = 1000;

function validationError(code, message) {
  return new OrderValidationError(code, message);
}

function deliveryCostForMethod(deliveryMethod) {
  if (deliveryMethod === "Regular Delivery") return 3;
  if (deliveryMethod === "Same Day Delivery") return 5;

  throw validationError("invalid-argument", "Invalid delivery method.");
}

function deliveryMethodFromPaymentRequest(data) {
  const deliveryMethod = String(data.deliveryMethod || "").trim();
  if (deliveryMethod) {
    deliveryCostForMethod(deliveryMethod);
    return deliveryMethod;
  }

  // Backwards-compatible bridge for older clients while still rejecting
  // manipulated delivery values such as 0.
  const deliveryCost = Number(data.deliveryCost);
  if (deliveryCost === 3) return "Regular Delivery";
  if (deliveryCost === 5) return "Same Day Delivery";

  throw validationError("invalid-argument", "Invalid delivery method.");
}

function calculateKwdAmount(total) {
  return Math.round(Number(total) * KWD_MINOR_UNITS);
}

function normalizeOrderItems(items) {
  if (!Array.isArray(items) || items.length === 0) {
    throw validationError("invalid-argument", "Items must be a non-empty array.");
  }

  if (items.length > 50) {
    throw validationError("invalid-argument", "Order cannot contain more than 50 items.");
  }

  const normalizedItems = [];
  const aggregateByProduct = new Map();

  for (const item of items) {
    const boutiqueId = String(item.boutiqueId || "");
    const productId = String(item.productId || "");
    const quantity = Math.max(1, Math.floor(Number(item.quantity) || 1));

    if (!boutiqueId || !productId) {
      throw validationError("invalid-argument", "Invalid product information.");
    }

    if (quantity > 100) {
      throw validationError("invalid-argument", "Quantity cannot exceed 100 per item.");
    }

    const key = `${boutiqueId}/${productId}`;
    const normalizedItem = {
      source: item,
      boutiqueId,
      productId,
      quantity,
      key,
    };

    normalizedItems.push(normalizedItem);

    const aggregate = aggregateByProduct.get(key) || {
      key,
      boutiqueId,
      productId,
      quantity: 0,
    };
    aggregate.quantity += quantity;
    aggregateByProduct.set(key, aggregate);
  }

  return {
    items: normalizedItems,
    aggregatedItems: Array.from(aggregateByProduct.values()),
  };
}

function verifyStripePaymentIntent(paymentIntent, {uid, expectedAmount}) {
  if (!paymentIntent || typeof paymentIntent !== "object") {
    throw validationError("payment-required", "Payment could not be verified.");
  }

  if (paymentIntent.status !== "succeeded") {
    throw validationError("payment-required", "Payment has not been completed.");
  }

  if (String(paymentIntent.currency || "").toLowerCase() !== ORDER_CURRENCY) {
    throw validationError("failed-precondition", "Payment currency does not match this order.");
  }

  if (paymentIntent.metadata?.uid !== uid) {
    throw validationError("permission-denied", "Payment does not belong to this user.");
  }

  if (Number.isInteger(expectedAmount) && paymentIntent.amount !== expectedAmount) {
    throw validationError("failed-precondition", "Payment amount does not match this order.");
  }
}

module.exports = {
  ORDER_CURRENCY,
  KWD_MINOR_UNITS,
  OrderValidationError,
  calculateKwdAmount,
  deliveryCostForMethod,
  deliveryMethodFromPaymentRequest,
  normalizeOrderItems,
  verifyStripePaymentIntent,
};
