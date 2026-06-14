const ORDER_CURRENCY = "kwd";
const MAX_ITEMS_PER_ORDER = 50;
const MAX_QUANTITY_PER_PRODUCT = 100;
const MAX_ORDER_SUBTOTAL = 5000;

const DELIVERY_COSTS = Object.freeze({
  "Regular Delivery": 3,
  "Same Day Delivery": 5,
});

function deliveryCostFor(method) {
  if (!Object.prototype.hasOwnProperty.call(DELIVERY_COSTS, method)) {
    throw new Error("Invalid delivery method.");
  }
  return DELIVERY_COSTS[method];
}

function normalizeQuantity(value) {
  return Math.max(1, Math.floor(Number(value) || 1));
}

function productKey(boutiqueId, productId) {
  return `${boutiqueId}/${productId}`;
}

function normalizeOrderItems(items) {
  if (!items || !Array.isArray(items) || items.length === 0) {
    throw new Error("Items must be a non-empty array.");
  }

  if (items.length > MAX_ITEMS_PER_ORDER) {
    throw new Error("Order cannot contain more than 50 items.");
  }

  const normalizedItems = [];
  const aggregatesByKey = new Map();

  for (const item of items) {
    const boutiqueId = String(item.boutiqueId || "");
    const productId = String(item.productId || "");
    const quantity = normalizeQuantity(item.quantity);

    if (!boutiqueId || !productId) {
      throw new Error("Invalid product information.");
    }

    if (quantity > MAX_QUANTITY_PER_PRODUCT) {
      throw new Error("Quantity cannot exceed 100 per product.");
    }

    const key = productKey(boutiqueId, productId);
    const existing = aggregatesByKey.get(key) || {
      key,
      boutiqueId,
      productId,
      quantity: 0,
    };
    existing.quantity += quantity;

    if (existing.quantity > MAX_QUANTITY_PER_PRODUCT) {
      throw new Error("Quantity cannot exceed 100 per product.");
    }

    aggregatesByKey.set(key, existing);
    normalizedItems.push({
      key,
      boutiqueId,
      productId,
      quantity,
      source: item,
    });
  }

  return {
    normalizedItems,
    aggregates: Array.from(aggregatesByKey.values()),
  };
}

function stripeMinorUnits(total, currency = ORDER_CURRENCY) {
  return Math.round(total * (currency.toLowerCase() === "kwd" ? 1000 : 100));
}

function paymentIntentHasRefund(paymentIntent) {
  const charges = [];
  const latestCharge = paymentIntent && paymentIntent.latest_charge;

  if (latestCharge && typeof latestCharge === "object") {
    charges.push(latestCharge);
  }

  if (
    paymentIntent &&
    paymentIntent.charges &&
    Array.isArray(paymentIntent.charges.data)
  ) {
    charges.push(...paymentIntent.charges.data);
  }

  return charges.some((charge) =>
    charge &&
    (charge.refunded === true || Number(charge.amount_refunded || 0) > 0),
  );
}

function validatePaymentIntent(paymentIntent, {uid, amount, currency}) {
  if (!paymentIntent || typeof paymentIntent !== "object") {
    return {ok: false, reason: "Payment could not be verified."};
  }

  if (paymentIntent.status !== "succeeded") {
    return {ok: false, reason: "Payment has not completed."};
  }

  if (String(paymentIntent.currency || "").toLowerCase() !== currency) {
    return {ok: false, reason: "Payment currency does not match the order."};
  }

  const metadataUid = paymentIntent.metadata && paymentIntent.metadata.uid;
  if (metadataUid !== uid) {
    return {ok: false, reason: "Payment does not belong to this user."};
  }

  if (paymentIntentHasRefund(paymentIntent)) {
    return {ok: false, reason: "Payment has already been refunded."};
  }

  const receivedAmount = Number(
    paymentIntent.amount_received || paymentIntent.amount || 0,
  );
  if (receivedAmount !== amount) {
    return {ok: false, reason: "Payment amount does not match the order."};
  }

  return {ok: true};
}

module.exports = {
  DELIVERY_COSTS,
  MAX_ORDER_SUBTOTAL,
  ORDER_CURRENCY,
  deliveryCostFor,
  normalizeOrderItems,
  paymentIntentHasRefund,
  stripeMinorUnits,
  validatePaymentIntent,
};
