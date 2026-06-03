const assert = require("node:assert/strict");
const test = require("node:test");

const {
  CheckoutValidationError,
  aggregateItemQuantities,
  assertSubtotalWithinLimit,
  getPaymentDeliveryMethod,
  normalizeCurrency,
  normalizeOrderItems,
  toKwdAmount,
  validatePaymentIntentForOrder,
} = require("./order_helpers");

function assertCheckoutError(fn, code) {
  assert.throws(
    fn,
    (error) => {
      assert.ok(error instanceof CheckoutValidationError);
      assert.equal(error.code, code);
      return true;
    },
  );
}

test("aggregates duplicate product quantities before stock checks", () => {
  const items = normalizeOrderItems([
    {boutiqueId: "boutique-a", productId: "product-1", quantity: 2},
    {boutiqueId: "boutique-a", productId: "product-1", quantity: 3},
    {boutiqueId: "boutique-a", productId: "product-2", quantity: 1},
  ]);

  const aggregates = aggregateItemQuantities(items);

  assert.equal(aggregates.size, 2);
  assert.equal(aggregates.get("boutique-a/product-1").quantity, 5);
  assert.equal(aggregates.get("boutique-a/product-2").quantity, 1);
});

test("rejects oversized carts before payment intent creation", () => {
  const items = Array.from({length: 51}, (_, index) => ({
    boutiqueId: "boutique-a",
    productId: `product-${index}`,
    quantity: 1,
  }));

  assertCheckoutError(() => normalizeOrderItems(items), "invalid-argument");
});

test("enforces the KD 5,000 subtotal cap before charging", () => {
  assert.doesNotThrow(() => assertSubtotalWithinLimit(5000));
  assertCheckoutError(() => assertSubtotalWithinLimit(5000.001), "invalid-argument");
});

test("uses delivery method instead of trusting arbitrary delivery cost", () => {
  assert.equal(
    getPaymentDeliveryMethod({deliveryMethod: "Regular Delivery", deliveryCost: 0}),
    "Regular Delivery",
  );
  assert.equal(getPaymentDeliveryMethod({deliveryCost: 5}), "Same Day Delivery");
  assertCheckoutError(() => getPaymentDeliveryMethod({deliveryCost: 0}), "invalid-argument");
});

test("only allows KWD checkout currency", () => {
  assert.equal(normalizeCurrency("KWD"), "kwd");
  assertCheckoutError(() => normalizeCurrency("usd"), "invalid-argument");
});

test("validates succeeded same-user payment intent for exact KWD amount", () => {
  const paymentIntent = {
    status: "succeeded",
    currency: "kwd",
    amount: toKwdAmount(12.345),
    metadata: {uid: "user-1"},
  };

  assert.doesNotThrow(() => validatePaymentIntentForOrder(paymentIntent, {
    uid: "user-1",
    currency: "kwd",
    amount: 12345,
  }));

  assertCheckoutError(
    () => validatePaymentIntentForOrder(
      {...paymentIntent, metadata: {uid: "user-2"}},
      {uid: "user-1", currency: "kwd", amount: 12345},
    ),
    "permission-denied",
  );
  assertCheckoutError(
    () => validatePaymentIntentForOrder(
      {...paymentIntent, amount: 12344},
      {uid: "user-1", currency: "kwd", amount: 12345},
    ),
    "failed-precondition",
  );
});
