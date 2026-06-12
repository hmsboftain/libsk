const test = require("node:test");
const assert = require("node:assert/strict");

const {
  assertPaymentIntentMatches,
  calculateExpectedPayment,
  normalizeCurrency,
  normalizeOrderItems,
  resolveDeliveryMethod,
  shouldRefundPaymentIntent,
} = require("./order_helpers");

test("resolves delivery only to server-approved methods", () => {
  assert.equal(
    resolveDeliveryMethod({deliveryMethod: "Same Day Delivery"}),
    "Same Day Delivery",
  );
  assert.equal(resolveDeliveryMethod({deliveryCost: 3}), "Regular Delivery");
  assert.throws(
    () => resolveDeliveryMethod({deliveryCost: 0}),
    /Invalid delivery method/,
  );
});

test("normalizes and aggregates duplicate product quantities", () => {
  const normalized = normalizeOrderItems([
    {boutiqueId: "b1", productId: "p1", quantity: 2, title: "First"},
    {boutiqueId: "b1", productId: "p1", quantity: 3, title: "Second"},
    {boutiqueId: "b1", productId: "p2", quantity: 1},
  ]);

  assert.equal(normalized.items.length, 3);
  assert.deepEqual(
    normalized.aggregates.map((item) => ({
      key: item.key,
      quantity: item.quantity,
    })),
    [
      {key: "b1/p1", quantity: 5},
      {key: "b1/p2", quantity: 1},
    ],
  );
});

test("rejects aggregate quantity cap bypasses", () => {
  assert.throws(
    () => normalizeOrderItems([
      {boutiqueId: "b1", productId: "p1", quantity: 60},
      {boutiqueId: "b1", productId: "p1", quantity: 41},
    ]),
    /Quantity cannot exceed 100 per product/,
  );
});

test("calculates KWD payment amount in fils", () => {
  assert.deepEqual(calculateExpectedPayment(12.345, "Regular Delivery"), {
    deliveryCost: 3,
    total: 15.345,
    amount: 15345,
    currency: "kwd",
  });
  assert.equal(normalizeCurrency("KWD"), "kwd");
  assert.throws(() => normalizeCurrency("usd"), /Unsupported currency/);
});

test("requires succeeded same-user exact-amount payment intents", () => {
  const paymentIntent = {
    status: "succeeded",
    metadata: {uid: "user_1"},
    currency: "kwd",
    amount: 15345,
    amount_received: 15345,
  };

  assert.doesNotThrow(() => {
    assertPaymentIntentMatches(paymentIntent, "user_1", 15345);
  });
  assert.throws(
    () => assertPaymentIntentMatches(paymentIntent, "user_2", 15345),
    /does not belong/,
  );
  assert.throws(
    () => assertPaymentIntentMatches(paymentIntent, "user_1", 16000),
    /does not match/,
  );
});

test("refund eligibility is limited to succeeded same-user KWD payments", () => {
  assert.equal(shouldRefundPaymentIntent({
    status: "succeeded",
    metadata: {uid: "user_1"},
    currency: "kwd",
  }, "user_1"), true);

  assert.equal(shouldRefundPaymentIntent({
    status: "succeeded",
    metadata: {uid: "user_2"},
    currency: "kwd",
  }, "user_1"), false);

  assert.equal(shouldRefundPaymentIntent({
    status: "requires_payment_method",
    metadata: {uid: "user_1"},
    currency: "kwd",
  }, "user_1"), false);
});
