class OrderValidationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "OrderValidationError";
    this.code = code;
  }
}

const KWD_MINOR_UNITS = 1000;
const SUPPORTED_ORDER_CURRENCY = "kwd";
const ALLOWED_DELIVERY_METHODS = [
  "Regular Delivery",
  "Same Day Delivery",
  "Made to Order",
];

function getDeliveryCost(deliveryMethod) {
  if (deliveryMethod === "Same Day Delivery") return 5;
  if (deliveryMethod === "Made to Order") return 0;
  if (deliveryMethod === "Regular Delivery") return 3;
  throw new OrderValidationError("invalid-argument", "Invalid delivery method.");
}

function kwdToMinorUnits(total) {
  return Math.round(Number(total || 0) * KWD_MINOR_UNITS);
}

function productKeyOf(boutiqueId, productId) {
  return `${boutiqueId}__${productId}`;
}

function getEffectiveProductPrice(productData) {
  const basePrice = Number(productData.price) || 0;
  const sale = Number(productData.salePrice);
  return Number.isFinite(sale) && sale > 0 && sale < basePrice
    ? sale
    : basePrice;
}

function normalizeOrderItems(items) {
  if (!items || !Array.isArray(items) || items.length === 0) {
    throw new OrderValidationError("invalid-argument", "Items must be a non-empty array.");
  }
  if (items.length > 50) {
    throw new OrderValidationError("invalid-argument", "Order cannot contain more than 50 items.");
  }

  const productAgg = {};
  for (const item of items) {
    const boutiqueId = String(item.boutiqueId || "");
    const productId = String(item.productId || "");
    const quantity = Math.max(1, Math.floor(Number(item.quantity) || 1));

    if (!boutiqueId || !productId) {
      throw new OrderValidationError("invalid-argument", "Invalid product information.");
    }
    if (quantity > 100) {
      throw new OrderValidationError("invalid-argument", "Quantity cannot exceed 100 per item.");
    }

    const key = productKeyOf(boutiqueId, productId);
    if (!productAgg[key]) productAgg[key] = { boutiqueId, productId, qty: 0 };
    productAgg[key].qty += quantity;
  }

  return productAgg;
}

function isPaymentIntentRefunded(paymentIntent) {
  const latestCharge = paymentIntent && paymentIntent.latest_charge;
  if (latestCharge && typeof latestCharge === "object") {
    if (latestCharge.refunded === true) return true;
    const refunded = Number(latestCharge.amount_refunded) || 0;
    const captured = Number(latestCharge.amount_captured || latestCharge.amount) || 0;
    if (captured > 0 && refunded >= captured) return true;
  }

  const charges = paymentIntent && paymentIntent.charges && paymentIntent.charges.data;
  if (Array.isArray(charges)) {
    return charges.some((charge) => {
      if (charge.refunded === true) return true;
      const refunded = Number(charge.amount_refunded) || 0;
      const captured = Number(charge.amount_captured || charge.amount) || 0;
      return captured > 0 && refunded >= captured;
    });
  }

  return false;
}

function validatePaymentIntentOwnership(paymentIntent, { uid }) {
  if (!paymentIntent || typeof paymentIntent.id !== "string") {
    throw new OrderValidationError("failed-precondition", "Payment could not be verified.");
  }
  if (paymentIntent.status !== "succeeded") {
    throw new OrderValidationError("failed-precondition", "Payment has not completed.");
  }
  if (String(paymentIntent.currency || "").toLowerCase() !== SUPPORTED_ORDER_CURRENCY) {
    throw new OrderValidationError("failed-precondition", "Payment currency does not match this order.");
  }
  if (!paymentIntent.metadata || paymentIntent.metadata.uid !== uid) {
    throw new OrderValidationError("permission-denied", "Payment does not belong to this account.");
  }
  if (isPaymentIntentRefunded(paymentIntent)) {
    throw new OrderValidationError("failed-precondition", "Payment has already been refunded.");
  }

  return {
    id: paymentIntent.id,
    amount: Number(paymentIntent.amount),
    currency: SUPPORTED_ORDER_CURRENCY,
  };
}

function validatePaymentIntentForOrder(paymentIntent, { uid, expectedAmount }) {
  validatePaymentIntentOwnership(paymentIntent, { uid });
  if (Number(paymentIntent.amount) !== expectedAmount) {
    throw new OrderValidationError("failed-precondition", "Payment amount does not match this order.");
  }

  return {
    id: paymentIntent.id,
    amount: Number(paymentIntent.amount),
    currency: SUPPORTED_ORDER_CURRENCY,
  };
}

module.exports = {
  ALLOWED_DELIVERY_METHODS,
  SUPPORTED_ORDER_CURRENCY,
  OrderValidationError,
  getDeliveryCost,
  getEffectiveProductPrice,
  isPaymentIntentRefunded,
  kwdToMinorUnits,
  normalizeOrderItems,
  productKeyOf,
  validatePaymentIntentForOrder,
  validatePaymentIntentOwnership,
};
