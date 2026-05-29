const assert = require("node:assert/strict");
const test = require("node:test");

const {
  CHECKOUT_CURRENCY,
  getDeliveryCost,
  normalizeOrderItems,
  stripeAmountFromKwd,
  assertPaymentIntentMatchesOrder,
} = require("../checkout_helpers");

test("normalizeOrderItems aggregates duplicate product quantities", () => {
  const {normalizedItems, productRequests} = normalizeOrderItems([
    {boutiqueId: "boutique-a", productId: "product-1", quantity: 3},
    {boutiqueId: "boutique-a", productId: "product-1", quantity: 4},
    {boutiqueId: "boutique-a", productId: "product-2", quantity: 1},
  ]);

  assert.equal(normalizedItems.length, 3);
  assert.deepEqual(productRequests, [
    {boutiqueId: "boutique-a", productId: "product-1", quantity: 7},
    {boutiqueId: "boutique-a", productId: "product-2", quantity: 1},
  ]);
});

test("delivery fees and KWD Stripe amount are server-derived", () => {
  assert.equal(getDeliveryCost("Regular Delivery"), 3);
  assert.equal(getDeliveryCost("Same Day Delivery"), 5);
  assert.equal(stripeAmountFromKwd(12.345), 12345);
});

test("payment intent must be succeeded, owned by caller, and exact amount", () => {
  const paymentIntent = {
    status: "succeeded",
    currency: CHECKOUT_CURRENCY,
    amount: 8000,
    metadata: {firebaseUid: "user-1"},
  };

  assert.doesNotThrow(() => assertPaymentIntentMatchesOrder(paymentIntent, {
    uid: "user-1",
    expectedAmount: 8000,
  }));

  assert.throws(
    () => assertPaymentIntentMatchesOrder(
      {...paymentIntent, metadata: {firebaseUid: "user-2"}},
      {uid: "user-1", expectedAmount: 8000},
    ),
    /Payment does not belong to this user/,
  );

  assert.throws(
    () => assertPaymentIntentMatchesOrder(
      {...paymentIntent, amount: 7000},
      {uid: "user-1", expectedAmount: 8000},
    ),
    /Payment amount does not match this order/,
  );

  assert.throws(
    () => assertPaymentIntentMatchesOrder(
      {...paymentIntent, status: "requires_payment_method"},
      {uid: "user-1", expectedAmount: 8000},
    ),
    /Payment has not completed/,
  );
});
