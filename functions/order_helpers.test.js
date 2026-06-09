"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  calculateKwdAmount,
  getDeliveryCost,
  getPaymentIntentMismatchReason,
  groupOrderItemsByProduct,
  normalizeOrderItems,
  resolveDeliverySelection,
} = require("./order_helpers");

test("groups duplicate product lines before stock checks", () => {
  const items = normalizeOrderItems([
    {boutiqueId: "boutique-a", productId: "sku-1", quantity: 3},
    {boutiqueId: "boutique-a", productId: "sku-1", quantity: 4},
    {boutiqueId: "boutique-a", productId: "sku-2", quantity: 1},
  ]);

  const groups = groupOrderItemsByProduct(items);

  assert.equal(groups.length, 2);
  assert.equal(groups[0].key, "boutique-a/sku-1");
  assert.equal(groups[0].totalQuantity, 7);
  assert.equal(groups[1].key, "boutique-a/sku-2");
  assert.equal(groups[1].totalQuantity, 1);
});

test("validates delivery methods with server-owned prices", () => {
  assert.equal(getDeliveryCost("Regular Delivery"), 3);
  assert.equal(getDeliveryCost("Same Day Delivery"), 5);
  assert.equal(getDeliveryCost("Free Delivery"), null);
});

test("maps only known legacy delivery costs to server delivery methods", () => {
  assert.deepEqual(
    resolveDeliverySelection({deliveryCost: 3}),
    {deliveryMethod: "Regular Delivery", deliveryCost: 3},
  );
  assert.deepEqual(
    resolveDeliverySelection({deliveryCost: 5}),
    {deliveryMethod: "Same Day Delivery", deliveryCost: 5},
  );
  assert.equal(resolveDeliverySelection({deliveryCost: 0}), null);
});

test("rejects payment intents that do not belong to the caller", () => {
  const reason = getPaymentIntentMismatchReason(
    {
      status: "succeeded",
      currency: "kwd",
      amount_received: 8000,
      metadata: {uid: "other-user"},
    },
    {uid: "caller", currency: "kwd", amount: 8000},
  );

  assert.equal(reason, "Payment does not belong to this user.");
});

test("rejects underpaid payment intents for the server-computed total", () => {
  const reason = getPaymentIntentMismatchReason(
    {
      status: "succeeded",
      currency: "kwd",
      amount_received: 3000,
      metadata: {uid: "caller"},
    },
    {uid: "caller", currency: "kwd", amount: calculateKwdAmount(8)},
  );

  assert.equal(reason, "Payment amount does not match the order total.");
});

test("accepts only succeeded KWD payment intents for the caller and exact amount", () => {
  const reason = getPaymentIntentMismatchReason(
    {
      status: "succeeded",
      currency: "kwd",
      amount_received: 8000,
      metadata: {uid: "caller"},
    },
    {uid: "caller", currency: "kwd", amount: calculateKwdAmount(8)},
  );

  assert.equal(reason, null);
});
