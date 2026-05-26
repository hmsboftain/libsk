const ORDER_CURRENCY = "kwd";

const DELIVERY_COSTS = {
  "Regular Delivery": 3,
  "Same Day Delivery": 5,
};

function isSupportedDeliveryMethod(deliveryMethod) {
  return Object.prototype.hasOwnProperty.call(
    DELIVERY_COSTS,
    deliveryMethod,
  );
}

function getDeliveryCost(deliveryMethod) {
  return DELIVERY_COSTS[deliveryMethod];
}

function normalizeOrderCurrency(currency) {
  return String(currency || "").trim().toLowerCase();
}

function isSupportedOrderCurrency(currency) {
  return normalizeOrderCurrency(currency) === ORDER_CURRENCY;
}

function getCurrencyMultiplier(currency) {
  if (normalizeOrderCurrency(currency) === "kwd") {
    return 1000;
  }

  return null;
}

function toStripeAmount(total, currency = ORDER_CURRENCY) {
  const multiplier = getCurrencyMultiplier(currency);
  const numericTotal = Number(total);

  if (!multiplier || !Number.isFinite(numericTotal)) {
    return null;
  }

  return Math.round(numericTotal * multiplier);
}

module.exports = {
  DELIVERY_COSTS,
  ORDER_CURRENCY,
  getDeliveryCost,
  isSupportedDeliveryMethod,
  isSupportedOrderCurrency,
  normalizeOrderCurrency,
  toStripeAmount,
};
