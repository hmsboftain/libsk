const ORDER_CURRENCY = "kwd";

const DELIVERY_COST_BY_METHOD = Object.freeze({
  "Regular Delivery": 3,
  "Same Day Delivery": 5,
});

function makeDefaultError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function getDeliveryCost(data = {}, makeError = makeDefaultError) {
  const deliveryMethod = String(data.deliveryMethod || "").trim();
  if (Object.prototype.hasOwnProperty.call(DELIVERY_COST_BY_METHOD, deliveryMethod)) {
    return DELIVERY_COST_BY_METHOD[deliveryMethod];
  }

  // Older clients sent only deliveryCost. Keep them working, but only for the
  // two server-known delivery prices so callers cannot understate delivery.
  const legacyDeliveryCost = Number(data.deliveryCost);
  if (Object.values(DELIVERY_COST_BY_METHOD).includes(legacyDeliveryCost)) {
    return legacyDeliveryCost;
  }

  throw makeError("invalid-argument", "Invalid delivery method.");
}

function validateCurrency(currency, makeError = makeDefaultError) {
  const requestedCurrency = String(currency || ORDER_CURRENCY).toLowerCase();
  if (requestedCurrency !== ORDER_CURRENCY) {
    throw makeError("invalid-argument", "Unsupported currency.");
  }
  return ORDER_CURRENCY;
}

function toMinorUnits(amount, currency = ORDER_CURRENCY) {
  const multiplier = currency === ORDER_CURRENCY ? 1000 : 100;
  return Math.round(Number(amount) * multiplier);
}

function normalizeQuantity(value) {
  return Math.max(1, Math.floor(Number(value) || 1));
}

function productKey(boutiqueId, productId) {
  return `${boutiqueId}/${productId}`;
}

function aggregateLineQuantities(
  items,
  makeError = makeDefaultError,
  maxItems = 50,
) {
  if (!items || !Array.isArray(items) || items.length === 0) {
    throw makeError("invalid-argument", "Items must be a non-empty array.");
  }

  if (items.length > maxItems) {
    throw makeError(
      "invalid-argument",
      `Order cannot contain more than ${maxItems} items.`,
    );
  }

  const lines = [];
  const aggregateByKey = new Map();

  for (const item of items) {
    const boutiqueId = String(item.boutiqueId || "");
    const productId = String(item.productId || "");
    const quantity = normalizeQuantity(item.quantity);

    if (!boutiqueId || !productId) {
      throw makeError("invalid-argument", "Each item must have boutiqueId and productId.");
    }

    if (quantity > 100) {
      throw makeError("invalid-argument", "Quantity cannot exceed 100 per item.");
    }

    const key = productKey(boutiqueId, productId);
    const existing = aggregateByKey.get(key);
    if (existing) {
      existing.quantity += quantity;
    } else {
      aggregateByKey.set(key, {key, boutiqueId, productId, quantity});
    }

    lines.push({...item, key, boutiqueId, productId, quantity});
  }

  return {
    lines,
    aggregates: Array.from(aggregateByKey.values()),
  };
}

function getRefundedAmount(paymentIntent) {
  const latestCharge = paymentIntent.latest_charge;
  if (!latestCharge || typeof latestCharge !== "object") {
    return 0;
  }

  return Number(latestCharge.amount_refunded || 0);
}

function validatePaymentIntentForOrder(
  paymentIntent,
  {uid, amount, currency = ORDER_CURRENCY},
  makeError = makeDefaultError,
) {
  if (!paymentIntent || typeof paymentIntent !== "object") {
    throw makeError("invalid-argument", "Payment could not be verified.");
  }

  if (paymentIntent.status !== "succeeded") {
    throw makeError("failed-precondition", "Payment has not been completed.");
  }

  const metadataUid = paymentIntent.metadata && paymentIntent.metadata.uid;
  if (metadataUid !== uid) {
    throw makeError("permission-denied", "Payment does not belong to this user.");
  }

  if (String(paymentIntent.currency || "").toLowerCase() !== currency) {
    throw makeError("failed-precondition", "Payment currency does not match order.");
  }

  const paidAmount = Number(paymentIntent.amount_received || paymentIntent.amount || 0);
  if (paidAmount !== amount) {
    throw makeError("failed-precondition", "Payment amount does not match order total.");
  }

  const latestCharge = paymentIntent.latest_charge;
  const refunded = latestCharge && typeof latestCharge === "object" &&
    (latestCharge.refunded === true || getRefundedAmount(paymentIntent) >= paidAmount);
  if (refunded) {
    throw makeError("failed-precondition", "Payment has already been refunded.");
  }

  return true;
}

module.exports = {
  ORDER_CURRENCY,
  DELIVERY_COST_BY_METHOD,
  getDeliveryCost,
  validateCurrency,
  toMinorUnits,
  normalizeQuantity,
  productKey,
  aggregateLineQuantities,
  validatePaymentIntentForOrder,
};
