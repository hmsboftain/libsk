function deliveryCostForMethod(deliveryMethod) {
  if (deliveryMethod === "Same Day Delivery") return 5;
  if (deliveryMethod === "Made to Order") return 0;
  if (deliveryMethod === "Regular Delivery") return 3;
  throw new Error("Invalid delivery method.");
}

function toKwdMinorUnits(total) {
  return Math.round(Number(total) * 1000);
}

function assertKwdCurrency(currency) {
  if (String(currency || "").toLowerCase() !== "kwd") {
    throw new Error("Unsupported currency.");
  }
}

function assertDiscountAppliesToItems(codeData, verifiedItems) {
  const codeBoutiqueId = String(codeData.boutiqueId || "").trim();
  if (!codeBoutiqueId) return;

  const mismatched = verifiedItems.some((item) => item.boutiqueId !== codeBoutiqueId);
  if (mismatched) {
    throw new Error("This discount code does not apply to every item in your cart.");
  }
}

function calculateDiscountAmount(codeData, subtotal) {
  const safeSubtotal = Math.max(0, Number(subtotal) || 0);
  const codeValue = Math.max(0, Number(codeData.value) || 0);

  let discountAmount = 0;
  if (codeData.type === "percentage") {
    discountAmount = parseFloat(((safeSubtotal * codeValue) / 100).toFixed(3));
  } else {
    discountAmount = Math.min(codeValue, safeSubtotal);
  }

  return Math.max(0, Math.min(discountAmount, safeSubtotal));
}

function assertPaymentIntentMatches(paymentIntent, {expectedAmount, uid}) {
  if (!paymentIntent || typeof paymentIntent !== "object") {
    throw new Error("Payment could not be verified.");
  }
  if (paymentIntent.status !== "succeeded") {
    throw new Error("Payment has not completed.");
  }
  if (String(paymentIntent.currency || "").toLowerCase() !== "kwd") {
    throw new Error("Payment currency does not match this order.");
  }
  if (Number(paymentIntent.amount) !== expectedAmount) {
    throw new Error("Payment amount does not match this order.");
  }
  if (String(paymentIntent.metadata?.uid || "") !== uid) {
    throw new Error("Payment does not belong to this user.");
  }

  const latestCharge = paymentIntent.latest_charge;
  if (latestCharge && typeof latestCharge === "object") {
    const amountRefunded = Number(latestCharge.amount_refunded) || 0;
    if (latestCharge.refunded === true || amountRefunded >= Number(paymentIntent.amount)) {
      throw new Error("Payment has already been refunded.");
    }
  }
}

module.exports = {
  assertDiscountAppliesToItems,
  assertKwdCurrency,
  assertPaymentIntentMatches,
  calculateDiscountAmount,
  deliveryCostForMethod,
  toKwdMinorUnits,
};
