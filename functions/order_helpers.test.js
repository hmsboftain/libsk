const test = require("node:test");
const assert = require("node:assert/strict");
const {
  ORDER_CURRENCY,
  getDeliveryCost,
  calculateKwdAmount,
  getPaymentIntentValidationError,
} = require("./order_helpers");

test("maps only supported delivery methods to server prices", () => {
  assert.equal(getDeliveryCost("Regular Delivery"), 3);
  assert.equal(getDeliveryCost("Same Day Delivery"), 5);
  assert.equal(getDeliveryCost(""), null);
  assert.equal(getDeliveryCost("Free Delivery"), null);
});

test("converts KWD totals to Stripe fils", () => {
  assert.equal(calculateKwdAmount(1), 1000);
  assert.equal(calculateKwdAmount(12.345), 12345);
  assert.equal(calculateKwdAmount(12.3456), 12346);
});

test("accepts only succeeded same-user payment intents for the exact amount", () => {
  const paymentIntent = {
    status: "succeeded",
    currency: ORDER_CURRENCY,
    amount: 15000,
    metadata: {uid: "user_1"},
  };

  assert.equal(
    getPaymentIntentValidationError(paymentIntent, {
      uid: "user_1",
      expectedAmount: 15000,
    }),
    null,
  );

  assert.equal(
    getPaymentIntentValidationError(
      {...paymentIntent, status: "requires_payment_method"},
      {uid: "user_1", expectedAmount: 15000},
    ),
    "Payment was not completed.",
  );

  assert.equal(
    getPaymentIntentValidationError(
      {...paymentIntent, amount: 14999},
      {uid: "user_1", expectedAmount: 15000},
    ),
    "Payment amount does not match the order total.",
  );

  assert.equal(
    getPaymentIntentValidationError(paymentIntent, {
      uid: "user_2",
      expectedAmount: 15000,
    }),
    "Payment does not belong to this user.",
  );
});
