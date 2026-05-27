const ORDER_CURRENCY = "kwd";

const DELIVERY_COST_BY_METHOD = Object.freeze({
  "Regular Delivery": 3,
  "Same Day Delivery": 5,
});

function getDeliveryCost(deliveryMethod) {
  return DELIVERY_COST_BY_METHOD[deliveryMethod];
}

function calculateStripeAmount(total, currency = ORDER_CURRENCY) {
  const multiplier = currency.toLowerCase() === "kwd" ? 1000 : 100;
  return Math.round(total * multiplier);
}

function validatePaymentIntentForOrder(paymentIntent, expected) {
  if (!paymentIntent) {
    return "Payment could not be verified.";
  }

  if (paymentIntent.status !== "succeeded") {
    return "Payment has not completed.";
  }

  const expectedCurrency = expected.currency.toLowerCase();
  if (String(paymentIntent.currency || "").toLowerCase() !== expectedCurrency) {
    return "Payment currency does not match the order.";
  }

  if (Number(paymentIntent.amount) !== expected.amount) {
    return "Payment amount does not match the order total.";
  }

  if (paymentIntent.metadata?.uid !== expected.uid) {
    return "Payment does not belong to this user.";
  }

  return null;
}

module.exports = {
  ORDER_CURRENCY,
  calculateStripeAmount,
  getDeliveryCost,
  validatePaymentIntentForOrder,
};
