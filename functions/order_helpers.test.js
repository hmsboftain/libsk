const assert = require("node:assert/strict");
const test = require("node:test");

const {
  buildStockRequests,
  computeExpectedAmount,
  getDeliveryCostForPaymentIntent,
  isPaymentIntentRefunded,
  normalizeOrderItems,
} = require("./order_helpers");

test("buildStockRequests aggregates duplicate products across cart lines", () => {
  const items = normalizeOrderItems([
    {boutiqueId: "boutique-a", productId: "product-1", quantity: 2, size: "S"},
    {boutiqueId: "boutique-a", productId: "product-1", quantity: 3, size: "M"},
    {boutiqueId: "boutique-a", productId: "product-2", quantity: 1},
  ]);

  assert.deepEqual(buildStockRequests(items), [
    {boutiqueId: "boutique-a", productId: "product-1", quantity: 5},
    {boutiqueId: "boutique-a", productId: "product-2", quantity: 1},
  ]);
});

test("normalizeOrderItems rejects invalid product lines and large quantities", () => {
  assert.throws(
    () => normalizeOrderItems([{boutiqueId: "boutique-a", quantity: 1}]),
    /boutiqueId and productId/,
  );

  assert.throws(
    () => normalizeOrderItems([
      {boutiqueId: "boutique-a", productId: "product-1", quantity: 101},
    ]),
    /Quantity cannot exceed 100/,
  );
});

test("computeExpectedAmount uses KWD minor units and rejects other currencies", () => {
  assert.equal(computeExpectedAmount(12.345, 3, 0, "kwd"), 15345);
  assert.equal(computeExpectedAmount(12.345, 3, 1.2, "kwd"), 14145);
  assert.throws(() => computeExpectedAmount(12, 3, 0, "usd"), /Unsupported/);
});

test("getDeliveryCostForPaymentIntent derives or constrains delivery cost", () => {
  assert.equal(getDeliveryCostForPaymentIntent("Same Day Delivery"), 5);
  assert.equal(getDeliveryCostForPaymentIntent("Made to Order"), 0);
  assert.equal(getDeliveryCostForPaymentIntent("", 3), 3);
  assert.throws(
    () => getDeliveryCostForPaymentIntent("", 2),
    /Invalid delivery method/,
  );
});

test("isPaymentIntentRefunded detects refunds on expanded charges", () => {
  assert.equal(isPaymentIntentRefunded({latest_charge: {refunded: true}}), true);
  assert.equal(
    isPaymentIntentRefunded({latest_charge: {amount_refunded: 1000}}),
    true,
  );
  assert.equal(
    isPaymentIntentRefunded({
      charges: {data: [{amount_refunded: 0}, {amount_refunded: 250}]},
    }),
    true,
  );
  assert.equal(isPaymentIntentRefunded({latest_charge: {amount_refunded: 0}}), false);
});
