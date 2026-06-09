"use strict";

const DELIVERY_COSTS = Object.freeze({
  "Regular Delivery": 3,
  "Same Day Delivery": 5,
});

function getDeliveryCost(deliveryMethod) {
  if (!Object.prototype.hasOwnProperty.call(DELIVERY_COSTS, deliveryMethod)) {
    return null;
  }
  return DELIVERY_COSTS[deliveryMethod];
}

function normalizeOrderItems(items) {
  if (!Array.isArray(items) || items.length === 0) {
    throw new Error("Items must be a non-empty array.");
  }

  if (items.length > 50) {
    throw new Error("Order cannot contain more than 50 items.");
  }

  return items.map((item) => {
    const boutiqueId = String(item.boutiqueId || "");
    const productId = String(item.productId || "");
    const quantity = Math.max(1, Math.floor(Number(item.quantity) || 1));

    if (!boutiqueId || !productId) {
      throw new Error("Each item must have boutiqueId and productId.");
    }

    if (quantity > 100) {
      throw new Error("Quantity cannot exceed 100 per item.");
    }

    return {
      ...item,
      boutiqueId,
      productId,
      quantity,
    };
  });
}

function groupOrderItemsByProduct(items) {
  const groups = new Map();

  for (const item of items) {
    const key = `${item.boutiqueId}/${item.productId}`;
    const existing = groups.get(key);

    if (existing) {
      existing.totalQuantity += item.quantity;
      existing.items.push(item);
    } else {
      groups.set(key, {
        key,
        boutiqueId: item.boutiqueId,
        productId: item.productId,
        totalQuantity: item.quantity,
        items: [item],
      });
    }
  }

  return Array.from(groups.values());
}

function calculateKwdAmount(total) {
  return Math.round(Number(total) * 1000);
}

function getPaymentIntentMismatchReason(paymentIntent, expected) {
  if (!paymentIntent || typeof paymentIntent !== "object") {
    return "Payment could not be verified.";
  }

  if (paymentIntent.status !== "succeeded") {
    return "Payment has not completed.";
  }

  if (String(paymentIntent.currency || "").toLowerCase() !== expected.currency) {
    return "Payment currency does not match the order.";
  }

  const metadataUid = paymentIntent.metadata && paymentIntent.metadata.uid;
  if (metadataUid !== expected.uid) {
    return "Payment does not belong to this user.";
  }

  if (expected.amount !== undefined) {
    const paidAmount = Number(paymentIntent.amount_received || paymentIntent.amount || 0);
    if (paidAmount !== expected.amount) {
      return "Payment amount does not match the order total.";
    }
  }

  return null;
}

module.exports = {
  calculateKwdAmount,
  getDeliveryCost,
  getPaymentIntentMismatchReason,
  groupOrderItemsByProduct,
  normalizeOrderItems,
};
