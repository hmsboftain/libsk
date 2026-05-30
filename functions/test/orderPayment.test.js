process.env.NODE_ENV = "test";

const test = require("node:test");
const assert = require("node:assert/strict");

const { _test } = require("../index");

function assertHttpsError(fn, code) {
  assert.throws(
    fn,
    (error) => error && error.code === code,
  );
}

test("resolves delivery fees from server-owned delivery methods", () => {
  assert.equal(_test.getDeliveryCost("Regular Delivery"), 3);
  assert.equal(_test.getDeliveryCost("Same Day Delivery"), 5);
  assert.equal(
    _test.resolveDeliveryMethod({deliveryMethod: "Same Day Delivery"}),
    "Same Day Delivery",
  );
  assert.equal(_test.resolveDeliveryMethod({deliveryCost: 3}), "Regular Delivery");
  assertHttpsError(
    () => _test.resolveDeliveryMethod({deliveryCost: 0}),
    "invalid-argument",
  );
});

test("buildOrderItemRequests aggregates stock checks per product", () => {
  const result = _test.buildOrderItemRequests([
    {boutiqueId: "boutique-a", productId: "sku-1", quantity: 3},
    {boutiqueId: "boutique-a", productId: "sku-1", quantity: 4},
    {boutiqueId: "boutique-a", productId: "sku-2", quantity: 1},
  ]);

  assert.equal(result.itemRequests.length, 3);
  assert.deepEqual(result.productRequests, [
    {boutiqueId: "boutique-a", productId: "sku-1", totalQuantity: 7},
    {boutiqueId: "boutique-a", productId: "sku-2", totalQuantity: 1},
  ]);
});

test("validates Stripe PaymentIntent ownership, status, amount, and currency", () => {
  const paymentIntent = {
    status: "succeeded",
    amount: 8000,
    currency: "kwd",
    metadata: {uid: "user-1"},
  };

  assert.doesNotThrow(() => _test.validatePaymentIntentForOrder(paymentIntent, {
    uid: "user-1",
    expectedAmount: 8000,
    expectedCurrency: "kwd",
  }));

  assertHttpsError(
    () => _test.validatePaymentIntentForOrder(
      {...paymentIntent, status: "requires_payment_method"},
      {uid: "user-1", expectedAmount: 8000, expectedCurrency: "kwd"},
    ),
    "failed-precondition",
  );
  assertHttpsError(
    () => _test.validatePaymentIntentForOrder(
      {...paymentIntent, amount: 3000},
      {uid: "user-1", expectedAmount: 8000, expectedCurrency: "kwd"},
    ),
    "failed-precondition",
  );
  assertHttpsError(
    () => _test.validatePaymentIntentForOrder(
      {...paymentIntent, metadata: {uid: "user-2"}},
      {uid: "user-1", expectedAmount: 8000, expectedCurrency: "kwd"},
    ),
    "permission-denied",
  );
});

test("normalizes KWD amounts for Stripe minor units", () => {
  assert.equal(_test.normalizeCurrency("KWD"), "kwd");
  assert.equal(_test.stripeAmountForTotal(8, "kwd"), 8000);
  assert.equal(_test.stripeAmountForTotal(8.125, "kwd"), 8125);
});

test("requires a Stripe PaymentIntent id shape that is safe as a lock doc id", () => {
  assert.doesNotThrow(() => _test.validatePaymentIntentId("pi_123abc_DEF"));
  assertHttpsError(() => _test.validatePaymentIntentId(""), "invalid-argument");
  assertHttpsError(() => _test.validatePaymentIntentId("seti_123"), "invalid-argument");
  assertHttpsError(() => _test.validatePaymentIntentId("pi_bad/slash"), "invalid-argument");
});
