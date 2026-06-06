const assert = require("node:assert/strict");
const test = require("node:test");
const {
  CheckoutValidationError,
  aggregateItemsByProduct,
  assertPaymentIntentMatches,
  assertPaymentIntentReadyForUser,
  calculatePaymentAmount,
  getDeliveryDetailsFromPaymentData,
  normalizeOrderItems,
  normalizePaymentCurrency,
} = require("./order_helpers");

function expectCheckoutError(fn, code, message) {
  assert.throws(
    fn,
    (error) => {
      assert.equal(error instanceof CheckoutValidationError, true);
      assert.equal(error.code, code);
      if (message) {
        assert.match(error.message, message);
      }
      return true;
    },
  );
}

test("derives delivery only from known server tiers", () => {
  assert.deepEqual(
    getDeliveryDetailsFromPaymentData({deliveryMethod: "Regular Delivery"}),
    {method: "Regular Delivery", cost: 3},
  );
  assert.deepEqual(
    getDeliveryDetailsFromPaymentData({deliveryCost: 5}),
    {method: "Same Day Delivery", cost: 5},
  );
  expectCheckoutError(
    () => getDeliveryDetailsFromPaymentData({deliveryCost: 0}),
    "invalid-argument",
    /Invalid delivery method/,
  );
});

test("accepts only KWD payment currency", () => {
  assert.equal(normalizePaymentCurrency("KWD"), "kwd");
  expectCheckoutError(
    () => normalizePaymentCurrency("usd"),
    "invalid-argument",
    /Unsupported currency/,
  );
});

test("normalizes items and aggregates stock per product", () => {
  const items = normalizeOrderItems([
    {boutiqueId: "b1", productId: "p1", quantity: 2},
    {boutiqueId: "b1", productId: "p1", quantity: 3},
    {boutiqueId: "b1", productId: "p2", quantity: 1},
  ]);

  assert.deepEqual(aggregateItemsByProduct(items), [
    {boutiqueId: "b1", productId: "p1", quantity: 5},
    {boutiqueId: "b1", productId: "p2", quantity: 1},
  ]);
});

test("calculates KWD minor-unit amounts and rejects capped totals", () => {
  assert.deepEqual(calculatePaymentAmount(10.25, 3), {
    total: 13.25,
    amount: 13250,
  });
  expectCheckoutError(
    () => calculatePaymentAmount(5000.01, 3),
    "invalid-argument",
    /cannot exceed/,
  );
});

test("verifies succeeded same-user payment before order write", () => {
  const paymentIntent = {
    status: "succeeded",
    currency: "kwd",
    amount: 13250,
    metadata: {uid: "user_1"},
  };

  assert.doesNotThrow(() => assertPaymentIntentReadyForUser(paymentIntent, {
    uid: "user_1",
    currency: "kwd",
  }));
  assert.doesNotThrow(() => assertPaymentIntentMatches(paymentIntent, {
    uid: "user_1",
    currency: "kwd",
    amount: 13250,
  }));

  expectCheckoutError(
    () => assertPaymentIntentMatches(paymentIntent, {
      uid: "user_2",
      currency: "kwd",
      amount: 13250,
    }),
    "permission-denied",
    /another user/,
  );
  expectCheckoutError(
    () => assertPaymentIntentMatches(paymentIntent, {
      uid: "user_1",
      currency: "kwd",
      amount: 13000,
    }),
    "failed-precondition",
    /amount/,
  );
});
