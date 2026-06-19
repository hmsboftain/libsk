const DELIVERY_COST_BY_METHOD = Object.freeze({
  "Regular Delivery": 3,
  "Same Day Delivery": 5,
});

const KWD_MULTIPLIER = 1000;

function getDeliveryCostForMethod(deliveryMethod) {
  if (!Object.prototype.hasOwnProperty.call(
    DELIVERY_COST_BY_METHOD,
    deliveryMethod,
  )) {
    throw new Error("Invalid delivery method.");
  }

  return DELIVERY_COST_BY_METHOD[deliveryMethod];
}

function getDeliveryCostForPaymentIntent(deliveryMethod, legacyDeliveryCost) {
  if (deliveryMethod) {
    return getDeliveryCostForMethod(deliveryMethod);
  }

  const deliveryCost = Number(legacyDeliveryCost);
  if (deliveryCost === DELIVERY_COST_BY_METHOD["Regular Delivery"] ||
      deliveryCost === DELIVERY_COST_BY_METHOD["Same Day Delivery"]) {
    return deliveryCost;
  }

  throw new Error("Invalid delivery method.");
}

function normalizeOrderItemInput(item) {
  const boutiqueId = String(item?.boutiqueId || "");
  const productId = String(item?.productId || "");
  const quantity = Math.max(1, Math.floor(Number(item?.quantity) || 1));

  if (!boutiqueId || !productId) {
    throw new Error("Each item must have boutiqueId and productId.");
  }

  if (quantity > 100) {
    throw new Error("Quantity cannot exceed 100 per item.");
  }

  return {
    boutiqueId,
    productId,
    quantity,
    original: item || {},
  };
}

function normalizeOrderItems(items) {
  if (!Array.isArray(items) || items.length === 0) {
    throw new Error("Items must be a non-empty array.");
  }

  if (items.length > 50) {
    throw new Error("Order cannot contain more than 50 items.");
  }

  return items.map(normalizeOrderItemInput);
}

function productKey(boutiqueId, productId) {
  return JSON.stringify([boutiqueId, productId]);
}

function buildStockRequests(normalizedItems) {
  const byProduct = new Map();

  for (const item of normalizedItems) {
    const key = productKey(item.boutiqueId, item.productId);
    const current = byProduct.get(key) || {
      boutiqueId: item.boutiqueId,
      productId: item.productId,
      quantity: 0,
    };

    current.quantity += item.quantity;
    byProduct.set(key, current);
  }

  return Array.from(byProduct.values());
}

function computeExpectedAmount(subtotal, deliveryCost, currency = "kwd") {
  if (String(currency).toLowerCase() !== "kwd") {
    throw new Error("Unsupported currency.");
  }

  return Math.round((Number(subtotal) + Number(deliveryCost)) * KWD_MULTIPLIER);
}

function isPaymentIntentRefunded(paymentIntent) {
  const latestCharge = paymentIntent?.latest_charge;

  if (latestCharge && typeof latestCharge === "object") {
    return latestCharge.refunded === true ||
      Number(latestCharge.amount_refunded || 0) > 0;
  }

  const charges = paymentIntent?.charges?.data;
  if (Array.isArray(charges)) {
    return charges.some((charge) => charge.refunded === true ||
      Number(charge.amount_refunded || 0) > 0);
  }

  return false;
}

module.exports = {
  DELIVERY_COST_BY_METHOD,
  buildStockRequests,
  computeExpectedAmount,
  getDeliveryCostForMethod,
  getDeliveryCostForPaymentIntent,
  isPaymentIntentRefunded,
  normalizeOrderItems,
  productKey,
};
