const test = require("node:test");
const assert = require("node:assert/strict");

const {
  PAYMENT_CURRENCY,
  OrderValidationError,
  getDeliveryCost,
  getEffectivePrice,
  latestChargeHasRefund,
  toMinorUnits,
  validatePaymentIntentId,
  verifyPaymentIntent,
} = require("./order_helpers");

function succeededIntent(overrides = {}) {
  return {
    status: "succeeded",
    currency: PAYMENT_CURRENCY,
    amount_received: 15500,
    metadata: { uid: "user_123" },
    latest_charge: { amount_refunded: 0 },
    ...overrides,
  };
}

test("uses valid sale price below regular price", () => {
  assert.equal(getEffectivePrice({ price: 10, salePrice: 7.5 }), 7.5);
  assert.equal(getEffectivePrice({ price: 10, salePrice: 12 }), 10);
  assert.equal(getEffectivePrice({ price: 10, salePrice: 0 }), 10);
});

test("derives delivery cost from delivery method only", () => {
  assert.equal(getDeliveryCost("Same Day Delivery"), 5);
  assert.equal(getDeliveryCost("Made to Order"), 0);
  assert.equal(getDeliveryCost("Regular Delivery"), 3);
  assert.equal(getDeliveryCost("unexpected"), 3);
});

test("converts KWD totals into thousand-fils minor units", () => {
  assert.equal(toMinorUnits(12.345, PAYMENT_CURRENCY), 12345);
  assert.equal(toMinorUnits(12.3456, PAYMENT_CURRENCY), 12346);
});

test("rejects empty payment intent ids", () => {
  assert.throws(
    () => validatePaymentIntentId(""),
    (error) => error instanceof OrderValidationError &&
      error.code === "invalid-argument",
  );
});

test("accepts same-user succeeded payment for exact amount and currency", () => {
  assert.doesNotThrow(() => verifyPaymentIntent(succeededIntent(), {
    uid: "user_123",
    expectedAmount: 15500,
    expectedCurrency: PAYMENT_CURRENCY,
  }));
});

test("rejects payment intents that are not succeeded", () => {
  assert.throws(
    () => verifyPaymentIntent(succeededIntent({ status: "requires_payment_method" }), {
      uid: "user_123",
      expectedAmount: 15500,
      expectedCurrency: PAYMENT_CURRENCY,
    }),
    (error) => error instanceof OrderValidationError &&
      error.code === "failed-precondition",
  );
});

test("rejects payment intents for a different user", () => {
  assert.throws(
    () => verifyPaymentIntent(succeededIntent(), {
      uid: "attacker",
      expectedAmount: 15500,
      expectedCurrency: PAYMENT_CURRENCY,
    }),
    (error) => error instanceof OrderValidationError &&
      error.code === "permission-denied",
  );
});

test("rejects payment intents with mismatched amount or currency", () => {
  assert.throws(
    () => verifyPaymentIntent(succeededIntent(), {
      uid: "user_123",
      expectedAmount: 15000,
      expectedCurrency: PAYMENT_CURRENCY,
    }),
    (error) => error instanceof OrderValidationError &&
      error.code === "failed-precondition",
  );

  assert.throws(
    () => verifyPaymentIntent(succeededIntent({ currency: "usd" }), {
      uid: "user_123",
      expectedAmount: 15500,
      expectedCurrency: PAYMENT_CURRENCY,
    }),
    (error) => error instanceof OrderValidationError &&
      error.code === "failed-precondition",
  );
});

test("rejects refunded payment intents", () => {
  const intent = succeededIntent({
    latest_charge: { amount_refunded: 15500 },
  });

  assert.equal(latestChargeHasRefund(intent), true);
  assert.throws(
    () => verifyPaymentIntent(intent, {
      uid: "user_123",
      expectedAmount: 15500,
      expectedCurrency: PAYMENT_CURRENCY,
    }),
    (error) => error instanceof OrderValidationError &&
      error.code === "failed-precondition",
  );
});
