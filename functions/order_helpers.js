const ALLOWED_DELIVERY_METHODS = [
  "Regular Delivery",
  "Same Day Delivery",
  "Made to Order",
];

function roundKwd(value) {
  return parseFloat((Number(value) || 0).toFixed(3));
}

function kwdToStripeAmount(value) {
  return Math.round(roundKwd(value) * 1000);
}

function normalizeDeliveryMethod(deliveryMethod, legacyDeliveryCost = null) {
  const method = String(deliveryMethod || "");
  if (ALLOWED_DELIVERY_METHODS.includes(method)) return method;

  // Older app builds sent only deliveryCost when creating the PaymentIntent.
  // Keep that constrained mapping so payment setup still uses server prices.
  const cost = Number(legacyDeliveryCost);
  if (Number.isFinite(cost)) {
    if (cost === 5) return "Same Day Delivery";
    if (cost === 0) return "Made to Order";
    if (cost === 3) return "Regular Delivery";
  }

  return "";
}

function deliveryCostForMethod(deliveryMethod) {
  if (deliveryMethod === "Same Day Delivery") return 5;
  if (deliveryMethod === "Made to Order") return 0;
  if (deliveryMethod === "Regular Delivery") return 3;
  throw new Error("Invalid delivery method.");
}

function effectiveProductPrice(productData) {
  const basePrice = Number(productData.price) || 0;
  const sale = Number(productData.salePrice);
  return Number.isFinite(sale) && sale > 0 && sale < basePrice
    ? sale
    : basePrice;
}

function paymentIntentHasRefund(paymentIntent) {
  const latestCharge = paymentIntent && paymentIntent.latest_charge;
  if (!latestCharge || typeof latestCharge !== "object") return false;
  return latestCharge.refunded === true ||
    (Number(latestCharge.amount_refunded) || 0) > 0;
}

function paymentIntentMismatchReason({paymentIntent, uid, expectedAmount}) {
  if (!paymentIntent || typeof paymentIntent.id !== "string") {
    return "Payment could not be verified.";
  }
  if (paymentIntent.status !== "succeeded") {
    return "Payment has not completed.";
  }
  if (String(paymentIntent.currency || "").toLowerCase() !== "kwd") {
    return "Payment currency does not match the order.";
  }
  if (String(paymentIntent.metadata && paymentIntent.metadata.uid || "") !== uid) {
    return "Payment does not belong to this user.";
  }
  if (Number(paymentIntent.amount) !== expectedAmount) {
    return "Payment amount does not match the order total.";
  }
  if (paymentIntentHasRefund(paymentIntent)) {
    return "Payment has already been refunded.";
  }
  return null;
}

module.exports = {
  ALLOWED_DELIVERY_METHODS,
  deliveryCostForMethod,
  effectiveProductPrice,
  kwdToStripeAmount,
  normalizeDeliveryMethod,
  paymentIntentHasRefund,
  paymentIntentMismatchReason,
  roundKwd,
};
