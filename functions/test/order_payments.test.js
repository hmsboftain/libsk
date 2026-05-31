const assert = require("node:assert/strict");
const test = require("node:test");

const {
  getDeliveryCostForMethod,
  getStripeAmount,
  validatePaymentIntentForOrder,
} = require("../index").__test__;

function matchingPaymentIntent(overrides = {}) {
  return {
    status: "succeeded",
    currency: "kwd",
    amount: 8000,
    amount_received: 8000,
    metadata: {uid: "user_1"},
    ...overrides,
  };
}

function assertHttpsCode(fn, code) {
  assert.throws(fn, (error) => {
    assert.equal(error.code, code);
    return true;
  });
}

test("maps allowed delivery methods to server-side fees", () => {
  assert.equal(getDeliveryCostForMethod("Regular Delivery"), 3);
  assert.equal(getDeliveryCostForMethod("Same Day Delivery"), 5);
  assertHttpsCode(
    () => getDeliveryCostForMethod("Free Delivery"),
    "invalid-argument",
  );
});

test("converts KWD totals to Stripe minor units", () => {
  assert.equal(getStripeAmount(8, "kwd"), 8000);
  assert.equal(getStripeAmount(8.125, "kwd"), 8125);
});

test("accepts a succeeded payment intent for the same user and amount", () => {
  assert.doesNotThrow(() => validatePaymentIntentForOrder(
    matchingPaymentIntent(),
    {uid: "user_1", expectedAmount: 8000, currency: "kwd"},
  ));
});

test("rejects incomplete payment intents", () => {
  assertHttpsCode(() => validatePaymentIntentForOrder(
    matchingPaymentIntent({status: "requires_payment_method"}),
    {uid: "user_1", expectedAmount: 8000, currency: "kwd"},
  ), "failed-precondition");
});

test("rejects payment intents with mismatched amounts", () => {
  assertHttpsCode(() => validatePaymentIntentForOrder(
    matchingPaymentIntent({amount_received: 7000}),
    {uid: "user_1", expectedAmount: 8000, currency: "kwd"},
  ), "failed-precondition");
});

test("rejects payment intents owned by another user", () => {
  assertHttpsCode(() => validatePaymentIntentForOrder(
    matchingPaymentIntent({metadata: {uid: "user_2"}}),
    {uid: "user_1", expectedAmount: 8000, currency: "kwd"},
  ), "permission-denied");
});

test("rejects payment intents in a different currency", () => {
  assertHttpsCode(() => validatePaymentIntentForOrder(
    matchingPaymentIntent({currency: "usd"}),
    {uid: "user_1", expectedAmount: 8000, currency: "kwd"},
  ), "failed-precondition");
});
