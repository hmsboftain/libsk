const PAYMENT_CURRENCY = "kwd";
const KWD_MULTIPLIER = 1000;

class OrderValidationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "OrderValidationError";
    this.code = code;
  }
}

function orderError(code, message) {
  return new OrderValidationError(code, message);
}

function getDeliveryCost(deliveryMethod) {
  if (deliveryMethod === "Same Day Delivery") return 5;
  if (deliveryMethod === "Made to Order") return 0;
  return 3;
}

function getEffectivePrice(productData = {}) {
  const basePrice = Number(productData.price) || 0;
  const sale = Number(productData.salePrice);
  return Number.isFinite(sale) && sale > 0 && sale < basePrice
    ? sale
    : basePrice;
}

function toMinorUnits(amount, currency = PAYMENT_CURRENCY) {
  const multiplier = String(currency).toLowerCase() === PAYMENT_CURRENCY
    ? KWD_MULTIPLIER
    : 100;
  return Math.round(Number(amount) * multiplier);
}

function getLatestCharge(paymentIntent) {
  const latestCharge = paymentIntent && paymentIntent.latest_charge;
  return latestCharge && typeof latestCharge === "object"
    ? latestCharge
    : null;
}

function latestChargeHasRefund(paymentIntent) {
  const charge = getLatestCharge(paymentIntent);
  return !!charge && Number(charge.amount_refunded || 0) > 0;
}

function validatePaymentIntentId(paymentIntentId) {
  if (typeof paymentIntentId !== "string" ||
      paymentIntentId.trim().length === 0 ||
      paymentIntentId.length > 200) {
    throw orderError("invalid-argument", "Invalid paymentIntentId.");
  }
}

function verifyPaymentIntent(paymentIntent, {
  uid,
  expectedAmount,
  expectedCurrency = PAYMENT_CURRENCY,
}) {
  if (!paymentIntent || typeof paymentIntent !== "object") {
    throw orderError("failed-precondition", "Payment could not be verified.");
  }
  if (paymentIntent.status !== "succeeded") {
    throw orderError("failed-precondition", "Payment has not completed.");
  }
  if (String(paymentIntent.currency || "").toLowerCase() !== expectedCurrency) {
    throw orderError("failed-precondition", "Payment currency does not match the order.");
  }
  if (Number(paymentIntent.amount_received) !== expectedAmount) {
    throw orderError("failed-precondition", "Payment amount does not match the order.");
  }
  if (String((paymentIntent.metadata || {}).uid || "") !== uid) {
    throw orderError("permission-denied", "Payment does not belong to this user.");
  }
  if (latestChargeHasRefund(paymentIntent)) {
    throw orderError("failed-precondition", "Payment has already been refunded.");
  }
}

module.exports = {
  KWD_MULTIPLIER,
  PAYMENT_CURRENCY,
  OrderValidationError,
  getDeliveryCost,
  getEffectivePrice,
  latestChargeHasRefund,
  orderError,
  toMinorUnits,
  validatePaymentIntentId,
  verifyPaymentIntent,
};
