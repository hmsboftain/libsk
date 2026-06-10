const assert = require("node:assert/strict");
const test = require("node:test");

const {
  ORDER_CURRENCY,
  getDeliveryCost,
  normalizeCurrency,
  normalizeOrderItems,
  toStripeAmount,
  validatePaymentIntent,
  validatePaymentIntentId,
} = require("./order_helpers");

function assertHttpsError(fn, code) {
  assert.throws(fn, (error) => error && error.code === code);
}

test("normalizes duplicate product lines for stock checks", () => {
  const items = normalizeOrderItems([
    {boutiqueId: "boutique-a", productId: "product-a", quantity: 2},
    {boutiqueId: "boutique-a", productId: "product-a", quantity: 3},
    {boutiqueId: "boutique-a", productId: "product-b", quantity: 1},
  ]);

  assert.equal(items.length, 2);
  assert.deepEqual(
    items.map((item) => [item.boutiqueId, item.productId, item.quantity]),
    [
      ["boutique-a", "product-a", 5],
      ["boutique-a", "product-b", 1],
    ],
  );
});

test("rejects combined duplicate product quantities above the item cap", () => {
  assertHttpsError(() => normalizeOrderItems([
    {boutiqueId: "boutique-a", productId: "product-a", quantity: 60},
    {boutiqueId: "boutique-a", productId: "product-a", quantity: 41},
  ]), "invalid-argument");
});

test("derives delivery and Stripe amount from server-controlled KWD values", () => {
  assert.equal(normalizeCurrency("KWD"), ORDER_CURRENCY);
  assert.equal(getDeliveryCost("Regular Delivery"), 3);
  assert.equal(getDeliveryCost("Same Day Delivery"), 5);
  assert.equal(toStripeAmount(12.345, ORDER_CURRENCY), 12345);
  assertHttpsError(() => normalizeCurrency("usd"), "invalid-argument");
  assertHttpsError(() => getDeliveryCost("Free Delivery"), "invalid-argument");
});

test("requires a non-empty payment intent id", () => {
  assert.equal(validatePaymentIntentId("pi_123"), "pi_123");
  assertHttpsError(() => validatePaymentIntentId(""), "invalid-argument");
});

test("validates a succeeded same-user exact-amount payment intent", () => {
  assert.doesNotThrow(() => validatePaymentIntent({
    id: "pi_123",
    status: "succeeded",
    currency: "kwd",
    amount: 8000,
    metadata: {uid: "user-a"},
  }, {
    paymentIntentId: "pi_123",
    uid: "user-a",
    expectedAmount: 8000,
    currency: ORDER_CURRENCY,
  }));
});

test("rejects untrusted or mismatched payment intents", () => {
  const baseIntent = {
    id: "pi_123",
    status: "succeeded",
    currency: "kwd",
    amount: 8000,
    metadata: {uid: "user-a"},
  };
  const options = {
    paymentIntentId: "pi_123",
    uid: "user-a",
    expectedAmount: 8000,
    currency: ORDER_CURRENCY,
  };

  assertHttpsError(() => validatePaymentIntent(
    {...baseIntent, status: "requires_payment_method"},
    options,
  ), "failed-precondition");
  assertHttpsError(() => validatePaymentIntent(
    {...baseIntent, amount: 7000},
    options,
  ), "failed-precondition");
  assertHttpsError(() => validatePaymentIntent(
    {...baseIntent, currency: "usd"},
    options,
  ), "failed-precondition");
  assertHttpsError(() => validatePaymentIntent(
    {...baseIntent, metadata: {uid: "user-b"}},
    options,
  ), "permission-denied");
});
