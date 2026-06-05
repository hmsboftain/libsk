const DELIVERY_COSTS = Object.freeze({
  "Regular Delivery": 3,
  "Same Day Delivery": 5,
});

const SUPPORTED_CURRENCY = "kwd";
const KWD_MINOR_UNITS = 1000;

class OrderValidationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "OrderValidationError";
    this.code = code;
  }
}

function fail(code, message) {
  throw new OrderValidationError(code, message);
}

function normalizeCurrency(currency) {
  if (!currency || typeof currency !== "string") {
    fail("invalid-argument", "Currency is required.");
  }

  const normalized = currency.toLowerCase();
  if (normalized !== SUPPORTED_CURRENCY) {
    fail("invalid-argument", "Unsupported currency.");
  }

  return normalized;
}

function resolveDeliveryDetails({deliveryMethod, deliveryCost} = {}) {
  const method = String(deliveryMethod || "").trim();

  if (method) {
    const cost = DELIVERY_COSTS[method];
    if (cost === undefined) {
      fail("invalid-argument", "Invalid delivery method.");
    }
    return {deliveryMethod: method, deliveryCost: cost};
  }

  const numericCost = Number(deliveryCost);
  for (const [candidateMethod, cost] of Object.entries(DELIVERY_COSTS)) {
    if (numericCost === cost) {
      return {deliveryMethod: candidateMethod, deliveryCost: cost};
    }
  }

  fail("invalid-argument", "Invalid delivery method.");
}

function normalizeQuantity(rawQuantity) {
  return Math.max(1, Math.floor(Number(rawQuantity) || 1));
}

function validateItemsArray(items) {
  if (!items || !Array.isArray(items) || items.length === 0) {
    fail("invalid-argument", "Items must be a non-empty array.");
  }

  if (items.length > 50) {
    fail("invalid-argument", "Order cannot contain more than 50 items.");
  }
}

function aggregateItems(items) {
  validateItemsArray(items);

  const aggregate = new Map();
  const normalizedItems = [];

  for (const item of items) {
    const boutiqueId = String(item.boutiqueId || "");
    const productId = String(item.productId || "");
    const quantity = normalizeQuantity(item.quantity);

    if (!boutiqueId || !productId) {
      fail("invalid-argument", "Invalid product information.");
    }

    if (quantity > 100) {
      fail("invalid-argument", "Quantity cannot exceed 100 per item.");
    }

    const key = `${boutiqueId}/${productId}`;
    const previous = aggregate.get(key);
    const totalQuantity = (previous ? previous.quantity : 0) + quantity;
    if (totalQuantity > 100) {
      fail("invalid-argument", "Quantity cannot exceed 100 per product.");
    }

    const normalizedItem = {
      original: item,
      boutiqueId,
      productId,
      quantity,
      key,
    };
    normalizedItems.push(normalizedItem);
    aggregate.set(key, {boutiqueId, productId, quantity: totalQuantity});
  }

  return {
    normalizedItems,
    aggregateItems: Array.from(aggregate.values()),
  };
}

function toStripeAmount(total, currency) {
  const normalizedCurrency = normalizeCurrency(currency);
  const amount = Math.round(Number(total) * KWD_MINOR_UNITS);

  if (!Number.isFinite(amount) || amount <= 0) {
    fail("invalid-argument", "Order total must be greater than zero.");
  }

  return {amount, currency: normalizedCurrency};
}

function assertPaymentIntentMatchesOrder(
  paymentIntent,
  {uid, expectedAmount, currency},
) {
  if (!paymentIntent || typeof paymentIntent !== "object") {
    fail("failed-precondition", "Payment could not be verified.");
  }

  if (paymentIntent.status !== "succeeded") {
    fail("failed-precondition", "Payment has not been completed.");
  }

  const normalizedCurrency = normalizeCurrency(currency);
  if (String(paymentIntent.currency || "").toLowerCase() !== normalizedCurrency) {
    fail("failed-precondition", "Payment currency does not match order.");
  }

  if (Number(paymentIntent.amount) !== expectedAmount) {
    fail("failed-precondition", "Payment amount does not match order total.");
  }

  if (
    paymentIntent.amount_received !== undefined &&
    Number(paymentIntent.amount_received) !== expectedAmount
  ) {
    fail("failed-precondition", "Payment amount does not match order total.");
  }

  const paymentUid = paymentIntent.metadata && paymentIntent.metadata.uid;
  if (paymentUid !== uid) {
    fail("permission-denied", "Payment does not belong to this user.");
  }
}

module.exports = {
  DELIVERY_COSTS,
  SUPPORTED_CURRENCY,
  OrderValidationError,
  aggregateItems,
  assertPaymentIntentMatchesOrder,
  normalizeCurrency,
  resolveDeliveryDetails,
  toStripeAmount,
};
