const assert = require("node:assert/strict");
const test = require("node:test");

const {
  assertDiscountAppliesToItems,
  assertKwdCurrency,
  assertPaymentIntentMatches,
  calculateDiscountAmount,
  deliveryCostForMethod,
  toKwdMinorUnits,
} = require("./order_helpers");

test("uses KWD delivery and minor-unit math", () => {
  assert.equal(deliveryCostForMethod("Regular Delivery"), 3);
  assert.equal(deliveryCostForMethod("Same Day Delivery"), 5);
  assert.equal(deliveryCostForMethod("Made to Order"), 0);
  assert.equal(toKwdMinorUnits(10.125), 10125);
  assert.doesNotThrow(() => assertKwdCurrency("kwd"));
  assert.doesNotThrow(() => assertKwdCurrency("KWD"));
  assert.throws(() => assertKwdCurrency("usd"), /Unsupported currency/);
});

test("discount amount is clamped to the verified subtotal", () => {
  assert.equal(calculateDiscountAmount({type: "percentage", value: 15}, 10), 1.5);
  assert.equal(calculateDiscountAmount({type: "fixed", value: 20}, 10), 10);
  assert.equal(calculateDiscountAmount({type: "fixed", value: -5}, 10), 0);
});

test("boutique-scoped discounts must match every order item", () => {
  const codeData = {boutiqueId: "boutique-a"};
  const matchingItems = [
    {boutiqueId: "boutique-a", price: 7.5, quantity: 1},
    {boutiqueId: "boutique-a", price: 2, quantity: 2},
  ];
  const mixedItems = [
    ...matchingItems,
    {boutiqueId: "boutique-b", price: 3, quantity: 1},
  ];

  assert.doesNotThrow(() => assertDiscountAppliesToItems(codeData, matchingItems));
  assert.throws(
    () => assertDiscountAppliesToItems(codeData, mixedItems),
    /does not apply/,
  );
  assert.doesNotThrow(() => assertDiscountAppliesToItems({}, mixedItems));
});

test("payment intent must be succeeded KWD for the caller and exact amount", () => {
  const basePaymentIntent = {
    status: "succeeded",
    currency: "kwd",
    amount: 12500,
    metadata: {uid: "user-1"},
    latest_charge: {refunded: false, amount_refunded: 0},
  };

  assert.doesNotThrow(() =>
    assertPaymentIntentMatches(basePaymentIntent, {
      expectedAmount: 12500,
      uid: "user-1",
    }),
  );
  assert.throws(
    () => assertPaymentIntentMatches({...basePaymentIntent, amount: 12499}, {
      expectedAmount: 12500,
      uid: "user-1",
    }),
    /amount/,
  );
  assert.throws(
    () => assertPaymentIntentMatches({...basePaymentIntent, currency: "usd"}, {
      expectedAmount: 12500,
      uid: "user-1",
    }),
    /currency/,
  );
  assert.throws(
    () => assertPaymentIntentMatches({...basePaymentIntent, metadata: {uid: "user-2"}}, {
      expectedAmount: 12500,
      uid: "user-1",
    }),
    /belong/,
  );
  assert.throws(
    () => assertPaymentIntentMatches({
      ...basePaymentIntent,
      latest_charge: {refunded: true, amount_refunded: 12500},
    }, {
      expectedAmount: 12500,
      uid: "user-1",
    }),
    /refunded/,
  );
});
