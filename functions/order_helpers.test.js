const assert = require("node:assert/strict");
const test = require("node:test");

const {
  calculateKwdAmount,
  deliveryCostForMethod,
  deliveryMethodFromPaymentRequest,
  normalizeOrderItems,
  verifyStripePaymentIntent,
  OrderValidationError,
} = require("./order_helpers");

test("normalizeOrderItems aggregates duplicate product quantities", () => {
  const result = normalizeOrderItems([
    {boutiqueId: "b1", productId: "p1", quantity: 3, size: "S"},
    {boutiqueId: "b1", productId: "p1", quantity: 2, size: "M"},
    {boutiqueId: "b1", productId: "p2", quantity: 1},
  ]);

  assert.equal(result.items.length, 3);
  assert.deepEqual(result.aggregatedItems, [
    {key: "b1/p1", boutiqueId: "b1", productId: "p1", quantity: 5},
    {key: "b1/p2", boutiqueId: "b1", productId: "p2", quantity: 1},
  ]);
});

test("delivery method is server-authoritative for payment intents", () => {
  assert.equal(deliveryCostForMethod("Regular Delivery"), 3);
  assert.equal(deliveryCostForMethod("Same Day Delivery"), 5);
  assert.equal(
    deliveryMethodFromPaymentRequest({deliveryMethod: "Same Day Delivery"}),
    "Same Day Delivery",
  );
  assert.equal(
    deliveryMethodFromPaymentRequest({deliveryCost: 3}),
    "Regular Delivery",
  );
  assert.throws(
    () => deliveryMethodFromPaymentRequest({deliveryCost: 0}),
    /Invalid delivery method/,
  );
});

test("calculateKwdAmount uses three decimal minor units", () => {
  assert.equal(calculateKwdAmount(12.345), 12345);
  assert.equal(calculateKwdAmount(8), 8000);
});

test("verifyStripePaymentIntent accepts only same-user succeeded exact KWD payments", () => {
  const paymentIntent = {
    status: "succeeded",
    currency: "kwd",
    amount: 8000,
    metadata: {uid: "user-1"},
  };

  assert.doesNotThrow(() => verifyStripePaymentIntent(paymentIntent, {
    uid: "user-1",
    expectedAmount: 8000,
  }));

  assert.throws(
    () => verifyStripePaymentIntent({...paymentIntent, status: "requires_payment_method"}, {
      uid: "user-1",
      expectedAmount: 8000,
    }),
    OrderValidationError,
  );
  assert.throws(
    () => verifyStripePaymentIntent({...paymentIntent, metadata: {uid: "user-2"}}, {
      uid: "user-1",
      expectedAmount: 8000,
    }),
    OrderValidationError,
  );
  assert.throws(
    () => verifyStripePaymentIntent({...paymentIntent, amount: 7000}, {
      uid: "user-1",
      expectedAmount: 8000,
    }),
    OrderValidationError,
  );
  assert.throws(
    () => verifyStripePaymentIntent({...paymentIntent, currency: "usd"}, {
      uid: "user-1",
      expectedAmount: 8000,
    }),
    OrderValidationError,
  );
});
