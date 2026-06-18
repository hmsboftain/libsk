const test = require("node:test");
const assert = require("node:assert/strict");

const {
  aggregateLineQuantities,
  getDeliveryCost,
  toMinorUnits,
  validateCurrency,
  validatePaymentIntentForOrder,
} = require("./order_helpers");

function makeTestError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function paymentIntent(overrides = {}) {
  return {
    status: "succeeded",
    currency: "kwd",
    amount_received: 12500,
    metadata: {uid: "user_1"},
    latest_charge: {
      refunded: false,
      amount_refunded: 0,
    },
    ...overrides,
  };
}

test("aggregateLineQuantities sums duplicate products for stock checks", () => {
  const result = aggregateLineQuantities([
    {boutiqueId: "boutique_1", productId: "product_1", quantity: 1, size: "S"},
    {boutiqueId: "boutique_1", productId: "product_1", quantity: 2, size: "M"},
    {boutiqueId: "boutique_1", productId: "product_2", quantity: 1},
  ], makeTestError);

  assert.equal(result.lines.length, 3);
  assert.deepEqual(result.aggregates, [
    {
      key: "boutique_1/product_1",
      boutiqueId: "boutique_1",
      productId: "product_1",
      quantity: 3,
    },
    {
      key: "boutique_1/product_2",
      boutiqueId: "boutique_1",
      productId: "product_2",
      quantity: 1,
    },
  ]);
});

test("getDeliveryCost accepts only server-known delivery prices", () => {
  assert.equal(getDeliveryCost({deliveryMethod: "Regular Delivery"}, makeTestError), 3);
  assert.equal(getDeliveryCost({deliveryMethod: "Same Day Delivery"}, makeTestError), 5);
  assert.equal(getDeliveryCost({deliveryCost: 3}, makeTestError), 3);

  assert.throws(
    () => getDeliveryCost({deliveryCost: 0}, makeTestError),
    {code: "invalid-argument"},
  );
});

test("validateCurrency only permits KWD", () => {
  assert.equal(validateCurrency("KWD", makeTestError), "kwd");
  assert.throws(
    () => validateCurrency("usd", makeTestError),
    {code: "invalid-argument"},
  );
});

test("toMinorUnits uses KWD thousandths", () => {
  assert.equal(toMinorUnits(12.5, "kwd"), 12500);
});

test("validatePaymentIntentForOrder accepts exact same-user succeeded payment", () => {
  assert.equal(
    validatePaymentIntentForOrder(
      paymentIntent(),
      {uid: "user_1", amount: 12500, currency: "kwd"},
      makeTestError,
    ),
    true,
  );
});

test("validatePaymentIntentForOrder rejects wrong user payments", () => {
  assert.throws(
    () => validatePaymentIntentForOrder(
      paymentIntent({metadata: {uid: "user_2"}}),
      {uid: "user_1", amount: 12500, currency: "kwd"},
      makeTestError,
    ),
    {code: "permission-denied"},
  );
});

test("validatePaymentIntentForOrder rejects underpaid payments", () => {
  assert.throws(
    () => validatePaymentIntentForOrder(
      paymentIntent({amount_received: 11500}),
      {uid: "user_1", amount: 12500, currency: "kwd"},
      makeTestError,
    ),
    {code: "failed-precondition"},
  );
});

test("validatePaymentIntentForOrder rejects refunded payments", () => {
  assert.throws(
    () => validatePaymentIntentForOrder(
      paymentIntent({
        latest_charge: {
          refunded: true,
          amount_refunded: 12500,
        },
      }),
      {uid: "user_1", amount: 12500, currency: "kwd"},
      makeTestError,
    ),
    {code: "failed-precondition"},
  );
});
