const ORDER_CURRENCY = "kwd";
const KWD_MULTIPLIER = 1000;
const MAX_ORDER_ITEMS = 50;
const MAX_QUANTITY_PER_PRODUCT = 100;
const MAX_SUBTOTAL_KWD = 5000;

const DELIVERY_COST_BY_METHOD = Object.freeze({
  "Regular Delivery": 3,
  "Same Day Delivery": 5,
});

class OrderValidationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "OrderValidationError";
    this.code = code;
  }
}

function validationError(code, message) {
  return new OrderValidationError(code, message);
}

function normalizeCurrency(currency) {
  const normalized = String(currency || ORDER_CURRENCY).trim().toLowerCase();

  if (normalized !== ORDER_CURRENCY) {
    throw validationError("invalid-argument", "Unsupported currency.");
  }

  return ORDER_CURRENCY;
}

function resolveDeliveryMethod(data = {}) {
  const deliveryMethod = String(data.deliveryMethod || "").trim();

  if (Object.prototype.hasOwnProperty.call(
    DELIVERY_COST_BY_METHOD,
    deliveryMethod,
  )) {
    return deliveryMethod;
  }

  // Backward-compatible with older clients, but still server-constrained.
  const deliveryCost = Number(data.deliveryCost);
  if (Number.isFinite(deliveryCost)) {
    for (const [method, cost] of Object.entries(DELIVERY_COST_BY_METHOD)) {
      if (deliveryCost === cost) {
        return method;
      }
    }
  }

  throw validationError("invalid-argument", "Invalid delivery method.");
}

function getDeliveryCost(deliveryMethod) {
  const cost = DELIVERY_COST_BY_METHOD[deliveryMethod];

  if (typeof cost !== "number") {
    throw validationError("invalid-argument", "Invalid delivery method.");
  }

  return cost;
}

function normalizeQuantity(quantity) {
  const normalized = Math.max(1, Math.floor(Number(quantity) || 1));

  if (normalized > MAX_QUANTITY_PER_PRODUCT) {
    throw validationError(
      "invalid-argument",
      "Quantity cannot exceed 100 per item.",
    );
  }

  return normalized;
}

function normalizeOrderItems(items) {
  if (!Array.isArray(items) || items.length === 0) {
    throw validationError(
      "invalid-argument",
      "Items must be a non-empty array.",
    );
  }

  if (items.length > MAX_ORDER_ITEMS) {
    throw validationError(
      "invalid-argument",
      "Order cannot contain more than 50 items.",
    );
  }

  const normalizedItems = [];
  const aggregateByProduct = new Map();

  for (const item of items) {
    const boutiqueId = String(item.boutiqueId || "").trim();
    const productId = String(item.productId || "").trim();
    const quantity = normalizeQuantity(item.quantity);

    if (!boutiqueId || !productId) {
      throw validationError(
        "invalid-argument",
        "Each item must have boutiqueId and productId.",
      );
    }

    const normalizedItem = {
      ...item,
      boutiqueId,
      productId,
      quantity,
    };
    normalizedItems.push(normalizedItem);

    const key = `${boutiqueId}/${productId}`;
    const aggregate = aggregateByProduct.get(key) || {
      key,
      boutiqueId,
      productId,
      quantity: 0,
    };

    aggregate.quantity += quantity;
    if (aggregate.quantity > MAX_QUANTITY_PER_PRODUCT) {
      throw validationError(
        "invalid-argument",
        "Quantity cannot exceed 100 per product.",
      );
    }

    aggregateByProduct.set(key, aggregate);
  }

  return {
    items: normalizedItems,
    aggregates: Array.from(aggregateByProduct.values()),
  };
}

function calculateExpectedPayment(subtotal, deliveryMethod) {
  if (subtotal > MAX_SUBTOTAL_KWD) {
    throw validationError(
      "invalid-argument",
      "Order total cannot exceed KD 5,000.",
    );
  }

  const deliveryCost = getDeliveryCost(deliveryMethod);
  const total = subtotal + deliveryCost;
  const amount = Math.round(total * KWD_MULTIPLIER);

  if (amount <= 0) {
    throw validationError(
      "invalid-argument",
      "Order total must be greater than zero.",
    );
  }

  return {
    deliveryCost,
    total,
    amount,
    currency: ORDER_CURRENCY,
  };
}

function assertPaymentIntentMatches(paymentIntent, uid, expectedAmount) {
  if (!paymentIntent || typeof paymentIntent !== "object") {
    throw validationError("invalid-argument", "Invalid payment intent.");
  }

  if (paymentIntent.status !== "succeeded") {
    throw validationError(
      "failed-precondition",
      "Payment has not been completed.",
    );
  }

  const metadataUid = paymentIntent.metadata &&
    String(paymentIntent.metadata.uid || "");
  if (metadataUid !== uid) {
    throw validationError(
      "permission-denied",
      "Payment intent does not belong to this user.",
    );
  }

  if (String(paymentIntent.currency || "").toLowerCase() !== ORDER_CURRENCY) {
    throw validationError("invalid-argument", "Unsupported currency.");
  }

  if (Number(paymentIntent.amount) !== expectedAmount) {
    throw validationError(
      "failed-precondition",
      "Payment amount does not match the order total.",
    );
  }

  if (
    paymentIntent.amount_received !== undefined &&
    Number(paymentIntent.amount_received) < expectedAmount
  ) {
    throw validationError(
      "failed-precondition",
      "Payment amount does not match the order total.",
    );
  }
}

function shouldRefundPaymentIntent(paymentIntent, uid) {
  if (!paymentIntent || typeof paymentIntent !== "object") {
    return false;
  }

  const metadataUid = paymentIntent.metadata &&
    String(paymentIntent.metadata.uid || "");

  return paymentIntent.status === "succeeded" &&
    metadataUid === uid &&
    String(paymentIntent.currency || "").toLowerCase() === ORDER_CURRENCY;
}

function toHttpsError(error, HttpsError) {
  if (error instanceof OrderValidationError) {
    return new HttpsError(error.code, error.message);
  }

  return error;
}

module.exports = {
  DELIVERY_COST_BY_METHOD,
  ORDER_CURRENCY,
  OrderValidationError,
  assertPaymentIntentMatches,
  calculateExpectedPayment,
  getDeliveryCost,
  normalizeCurrency,
  normalizeOrderItems,
  resolveDeliveryMethod,
  shouldRefundPaymentIntent,
  toHttpsError,
};
