const assert = require("node:assert/strict");
const test = require("node:test");

const {
  ORDER_CURRENCY,
  calculateStripeAmount,
  getDeliveryCost,
  validatePaymentIntentForOrder,
} = require("../order_payment");

test("uses KWD as the checkout currency", () => {
  assert.equal(ORDER_CURRENCY, "kwd");
});

test("calculates KWD Stripe amounts using the three-decimal multiplier", () => {
  assert.equal(calculateStripeAmount(12.345, "kwd"), 12345);
  assert.equal(calculateStripeAmount(12.34, "usd"), 1234);
});

test("maps supported delivery methods to server-owned costs", () => {
  assert.equal(getDeliveryCost("Regular Delivery"), 3);
  assert.equal(getDeliveryCost("Same Day Delivery"), 5);
  assert.equal(getDeliveryCost("Free Delivery"), undefined);
});

test("accepts a completed payment intent for the same user and amount", () => {
  const paymentIntent = {
    status: "succeeded",
    currency: "kwd",
    amount: 8000,
    metadata: {uid: "user_123"},
  };

  assert.equal(
    validatePaymentIntentForOrder(paymentIntent, {
      uid: "user_123",
      currency: "kwd",
      amount: 8000,
    }),
    null,
  );
});

test("rejects payment intents that do not match the order", () => {
  const baseIntent = {
    status: "succeeded",
    currency: "kwd",
    amount: 8000,
    metadata: {uid: "user_123"},
  };

  assert.match(
    validatePaymentIntentForOrder(
      {...baseIntent, status: "requires_payment_method"},
      {uid: "user_123", currency: "kwd", amount: 8000},
    ),
    /not completed/,
  );
  assert.match(
    validatePaymentIntentForOrder(
      {...baseIntent, currency: "usd"},
      {uid: "user_123", currency: "kwd", amount: 8000},
    ),
    /currency/,
  );
  assert.match(
    validatePaymentIntentForOrder(
      {...baseIntent, amount: 7999},
      {uid: "user_123", currency: "kwd", amount: 8000},
    ),
    /amount/,
  );
  assert.match(
    validatePaymentIntentForOrder(
      {...baseIntent, metadata: {uid: "other_user"}},
      {uid: "user_123", currency: "kwd", amount: 8000},
    ),
    /belong/,
  );
});
