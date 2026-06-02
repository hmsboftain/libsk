const ORDER_CURRENCY = "kwd";
const KWD_MULTIPLIER = 1000;

const DELIVERY_COST_BY_METHOD = Object.freeze({
  "Regular Delivery": 3,
  "Same Day Delivery": 5,
});

function getDeliveryCost(deliveryMethod) {
  if (!Object.prototype.hasOwnProperty.call(
    DELIVERY_COST_BY_METHOD,
    deliveryMethod,
  )) {
    return null;
  }

  return DELIVERY_COST_BY_METHOD[deliveryMethod];
}

function calculateKwdAmount(total) {
  return Math.round(total * KWD_MULTIPLIER);
}

function getPaymentIntentValidationError(
  paymentIntent,
  {uid, expectedAmount, currency = ORDER_CURRENCY},
) {
  if (!paymentIntent) {
    return "Payment could not be verified.";
  }

  if (paymentIntent.status !== "succeeded") {
    return "Payment was not completed.";
  }

  if (String(paymentIntent.currency || "").toLowerCase() !== currency) {
    return "Payment currency does not match the order.";
  }

  if (Number(paymentIntent.amount) !== expectedAmount) {
    return "Payment amount does not match the order total.";
  }

  if ((paymentIntent.metadata || {}).uid !== uid) {
    return "Payment does not belong to this user.";
  }

  return null;
}

module.exports = {
  ORDER_CURRENCY,
  KWD_MULTIPLIER,
  getDeliveryCost,
  calculateKwdAmount,
  getPaymentIntentValidationError,
};
