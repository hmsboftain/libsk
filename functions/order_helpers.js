const KWD_CURRENCY = "kwd";
const KWD_MULTIPLIER = 1000;

const DELIVERY_COSTS = {
  "Regular Delivery": 3,
  "Same Day Delivery": 5,
  "Made to Order": 0,
};

const ALLOWED_DELIVERY_METHODS = Object.keys(DELIVERY_COSTS);

function productKeyOf(boutiqueId, productId) {
  return `${boutiqueId}__${productId}`;
}

function getDeliveryCost(deliveryMethod) {
  return DELIVERY_COSTS[deliveryMethod];
}

function roundKwd(value) {
  return parseFloat((Number(value) || 0).toFixed(3));
}

function toStripeAmountKwd(value) {
  return Math.round(roundKwd(value) * KWD_MULTIPLIER);
}

function effectiveProductPrice(productData) {
  const basePrice = Number(productData.price) || 0;
  const sale = Number(productData.salePrice);
  return Number.isFinite(sale) && sale > 0 && sale < basePrice
    ? sale
    : basePrice;
}

function aggregateItems(items) {
  const productAgg = {};
  for (const item of items) {
    const boutiqueId = String(item.boutiqueId || "");
    const productId = String(item.productId || "");
    const quantity = Math.max(1, Math.floor(Number(item.quantity) || 1));
    const key = productKeyOf(boutiqueId, productId);
    if (!productAgg[key]) productAgg[key] = {boutiqueId, productId, qty: 0};
    productAgg[key].qty += quantity;
  }
  return productAgg;
}

function isPaymentIntentRefunded(paymentIntent) {
  const charge = paymentIntent && paymentIntent.latest_charge;
  return Boolean(
    charge &&
      typeof charge === "object" &&
      (charge.refunded === true || Number(charge.amount_refunded || 0) > 0),
  );
}

function validatePaymentIntentForOrder(paymentIntent, expected) {
  if (!paymentIntent) {
    return {ok: false, message: "Payment could not be verified."};
  }
  if (paymentIntent.status !== "succeeded") {
    return {ok: false, message: "Payment has not been completed."};
  }
  if (String(paymentIntent.currency || "").toLowerCase() !== KWD_CURRENCY) {
    return {ok: false, message: "Payment currency does not match the order."};
  }
  if (Number(paymentIntent.amount) !== expected.amount) {
    return {ok: false, message: "Payment amount does not match the order."};
  }
  if (String((paymentIntent.metadata || {}).uid || "") !== expected.uid) {
    return {ok: false, message: "Payment does not belong to this user."};
  }
  if (isPaymentIntentRefunded(paymentIntent)) {
    return {ok: false, message: "Payment has already been refunded."};
  }
  return {ok: true};
}

module.exports = {
  ALLOWED_DELIVERY_METHODS,
  KWD_CURRENCY,
  aggregateItems,
  effectiveProductPrice,
  getDeliveryCost,
  isPaymentIntentRefunded,
  productKeyOf,
  roundKwd,
  toStripeAmountKwd,
  validatePaymentIntentForOrder,
};
