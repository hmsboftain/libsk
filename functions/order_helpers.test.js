const test = require("node:test");
const assert = require("node:assert/strict");

const {
  deliveryCostForMethod,
  effectiveProductPrice,
  kwdToStripeAmount,
  normalizeDeliveryMethod,
  paymentIntentMismatchReason,
  roundKwd,
} = require("./order_helpers");

test("uses valid sale prices for server quote amounts", () => {
  assert.equal(effectiveProductPrice({price: 10, salePrice: 7.5}), 7.5);
  assert.equal(effectiveProductPrice({price: 10, salePrice: 10}), 10);
  assert.equal(effectiveProductPrice({price: 10, salePrice: 12}), 10);
  assert.equal(effectiveProductPrice({price: 10, salePrice: null}), 10);
});

test("rounds KWD totals to Stripe fils", () => {
  assert.equal(roundKwd(1.23456), 1.235);
  assert.equal(kwdToStripeAmount(1.23456), 1235);
  assert.equal(kwdToStripeAmount(8.5), 8500);
});

test("normalizes delivery method from explicit method or legacy cost", () => {
  assert.equal(normalizeDeliveryMethod("Same Day Delivery"), "Same Day Delivery");
  assert.equal(normalizeDeliveryMethod("", 5), "Same Day Delivery");
  assert.equal(normalizeDeliveryMethod("", 3), "Regular Delivery");
  assert.equal(normalizeDeliveryMethod("", 0), "Made to Order");
  assert.equal(normalizeDeliveryMethod("", 9), "");
  assert.equal(deliveryCostForMethod("Same Day Delivery"), 5);
  assert.equal(deliveryCostForMethod("Regular Delivery"), 3);
  assert.equal(deliveryCostForMethod("Made to Order"), 0);
});

test("requires a succeeded same-user KWD payment for the exact order amount", () => {
  const paymentIntent = {
    id: "pi_123",
    status: "succeeded",
    currency: "kwd",
    amount: 8500,
    metadata: {uid: "user_1"},
    latest_charge: {amount_refunded: 0, refunded: false},
  };

  assert.equal(
    paymentIntentMismatchReason({
      paymentIntent,
      uid: "user_1",
      expectedAmount: 8500,
    }),
    null,
  );
  assert.equal(
    paymentIntentMismatchReason({
      paymentIntent: {...paymentIntent, status: "requires_payment_method"},
      uid: "user_1",
      expectedAmount: 8500,
    }),
    "Payment has not completed.",
  );
  assert.equal(
    paymentIntentMismatchReason({
      paymentIntent: {...paymentIntent, metadata: {uid: "user_2"}},
      uid: "user_1",
      expectedAmount: 8500,
    }),
    "Payment does not belong to this user.",
  );
  assert.equal(
    paymentIntentMismatchReason({
      paymentIntent: {...paymentIntent, amount: 8400},
      uid: "user_1",
      expectedAmount: 8500,
    }),
    "Payment amount does not match the order total.",
  );
  assert.equal(
    paymentIntentMismatchReason({
      paymentIntent: {...paymentIntent, latest_charge: {amount_refunded: 1}},
      uid: "user_1",
      expectedAmount: 8500,
    }),
    "Payment has already been refunded.",
  );
});
