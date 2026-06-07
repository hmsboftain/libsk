class CheckoutValidationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "CheckoutValidationError";
    this.code = code;
  }
}

const PAYMENT_CURRENCY = "kwd";
const KWD_MINOR_UNITS = 1000;
const MAX_ORDER_ITEMS = 50;
const MAX_ITEM_QUANTITY = 100;
const MAX_SUBTOTAL_KWD = 5000;
const DELIVERY_METHOD_COSTS = new Map([
  ["Regular Delivery", 3],
  ["Same Day Delivery", 5],
]);

function checkoutError(code, message) {
  return new CheckoutValidationError(code, message);
}

function getDeliveryDetailsFromPaymentData(data) {
  const method = String(data.deliveryMethod || "").trim();
  if (DELIVERY_METHOD_COSTS.has(method)) {
    return {
      method,
      cost: DELIVERY_METHOD_COSTS.get(method),
    };
  }

  // Backward-compatible path for already-deployed clients. The cost still must
  // match a server-known delivery tier; arbitrary client delivery prices fail.
  if (Object.prototype.hasOwnProperty.call(data, "deliveryCost")) {
    const cost = Number(data.deliveryCost);
    for (const [knownMethod, knownCost] of DELIVERY_METHOD_COSTS.entries()) {
      if (cost === knownCost) {
        return {
          method: knownMethod,
          cost: knownCost,
        };
      }
    }
  }

  throw checkoutError("invalid-argument", "Invalid delivery method.");
}

function getDeliveryCostForOrder(deliveryMethod) {
  const method = String(deliveryMethod || "").trim();
  if (!DELIVERY_METHOD_COSTS.has(method)) {
    throw checkoutError("invalid-argument", "Invalid delivery method.");
  }

  return DELIVERY_METHOD_COSTS.get(method);
}

function normalizePaymentCurrency(currency = PAYMENT_CURRENCY) {
  const normalized = String(currency || "").trim().toLowerCase();
  if (normalized !== PAYMENT_CURRENCY) {
    throw checkoutError("invalid-argument", "Unsupported currency.");
  }

  return normalized;
}

function normalizeOrderItems(items) {
  if (!Array.isArray(items) || items.length === 0) {
    throw checkoutError("invalid-argument", "Items must be a non-empty array.");
  }

  if (items.length > MAX_ORDER_ITEMS) {
    throw checkoutError(
      "invalid-argument",
      "Order cannot contain more than 50 items.",
    );
  }

  return items.map((item) => {
    const boutiqueId = String(item.boutiqueId || "");
    const productId = String(item.productId || "");
    const quantity = Math.max(1, Math.floor(Number(item.quantity) || 1));

    if (!boutiqueId || !productId) {
      throw checkoutError(
        "invalid-argument",
        "Each item must have boutiqueId and productId.",
      );
    }

    if (quantity > MAX_ITEM_QUANTITY) {
      throw checkoutError(
        "invalid-argument",
        "Quantity cannot exceed 100 per item.",
      );
    }

    return {
      ...item,
      boutiqueId,
      productId,
      quantity,
    };
  });
}

function productKey(boutiqueId, productId) {
  return `${boutiqueId}/${productId}`;
}

function aggregateItemsByProduct(items) {
  const byProduct = new Map();

  for (const item of items) {
    const key = productKey(item.boutiqueId, item.productId);
    const existing = byProduct.get(key);

    if (existing) {
      existing.quantity += item.quantity;
    } else {
      byProduct.set(key, {
        boutiqueId: item.boutiqueId,
        productId: item.productId,
        quantity: item.quantity,
      });
    }
  }

  return Array.from(byProduct.values());
}

function calculatePaymentAmount(subtotal, deliveryCost) {
  const safeSubtotal = Number(subtotal) || 0;
  const safeDeliveryCost = Number(deliveryCost) || 0;

  if (safeSubtotal > MAX_SUBTOTAL_KWD) {
    throw checkoutError(
      "invalid-argument",
      "Order total cannot exceed KD 5,000.",
    );
  }

  const total = safeSubtotal + safeDeliveryCost;
  const amount = Math.round(total * KWD_MINOR_UNITS);

  if (amount <= 0) {
    throw checkoutError(
      "invalid-argument",
      "Order total must be greater than zero.",
    );
  }

  return {
    total,
    amount,
  };
}

function assertPaymentIntentReadyForUser(paymentIntent, expected) {
  if (!paymentIntent || typeof paymentIntent !== "object") {
    throw checkoutError("failed-precondition", "Payment could not be verified.");
  }

  if (paymentIntent.status !== "succeeded") {
    throw checkoutError("failed-precondition", "Payment has not completed.");
  }

  if (String(paymentIntent.currency || "").toLowerCase() !== expected.currency) {
    throw checkoutError("failed-precondition", "Payment currency does not match.");
  }

  const metadataUid = paymentIntent.metadata && paymentIntent.metadata.uid;
  if (metadataUid !== expected.uid) {
    throw checkoutError("permission-denied", "Payment belongs to another user.");
  }
}

function assertPaymentIntentMatches(paymentIntent, expected) {
  assertPaymentIntentReadyForUser(paymentIntent, expected);

  if (Number(paymentIntent.amount) !== expected.amount) {
    throw checkoutError("failed-precondition", "Payment amount does not match.");
  }
}

module.exports = {
  CheckoutValidationError,
  PAYMENT_CURRENCY,
  aggregateItemsByProduct,
  assertPaymentIntentMatches,
  assertPaymentIntentReadyForUser,
  calculatePaymentAmount,
  getDeliveryCostForOrder,
  getDeliveryDetailsFromPaymentData,
  normalizeOrderItems,
  normalizePaymentCurrency,
  productKey,
};
