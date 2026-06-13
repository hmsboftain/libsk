const assert = require("node:assert/strict");
const test = require("node:test");

const {
  ORDER_CURRENCY,
  deliveryCostFor,
  normalizeOrderItems,
  stripeMinorUnits,
  validatePaymentIntent,
} = require("./order_helpers");

test("normalizeOrderItems aggregates duplicate product quantities", () => {
  const {normalizedItems, aggregates} = normalizeOrderItems([
    {boutiqueId: "boutique-a", productId: "product-1", quantity: 4},
    {boutiqueId: "boutique-a", productId: "product-1", quantity: 6},
    {boutiqueId: "boutique-a", productId: "product-2", quantity: 1},
  ]);

  assert.equal(normalizedItems.length, 3);
  assert.deepEqual(aggregates, [
    {
      key: "boutique-a/product-1",
      boutiqueId: "boutique-a",
      productId: "product-1",
      quantity: 10,
    },
    {
      key: "boutique-a/product-2",
      boutiqueId: "boutique-a",
      productId: "product-2",
      quantity: 1,
    },
  ]);
});

test("normalizeOrderItems rejects aggregate product quantities above limit", () => {
  assert.throws(
    () => normalizeOrderItems([
      {boutiqueId: "boutique-a", productId: "product-1", quantity: 60},
      {boutiqueId: "boutique-a", productId: "product-1", quantity: 41},
    ]),
    /Quantity cannot exceed 100 per product/,
  );
});

test("deliveryCostFor only accepts server-known delivery methods", () => {
  assert.equal(deliveryCostFor("Regular Delivery"), 3);
  assert.equal(deliveryCostFor("Same Day Delivery"), 5);
  assert.throws(() => deliveryCostFor("Free Delivery"), /Invalid delivery method/);
});

test("validatePaymentIntent requires succeeded same-user exact KWD payment", () => {
  const amount = stripeMinorUnits(12.345, ORDER_CURRENCY);
  const paymentIntent = {
    status: "succeeded",
    currency: "kwd",
    amount_received: amount,
    metadata: {uid: "user-1"},
  };

  assert.deepEqual(
    validatePaymentIntent(paymentIntent, {
      uid: "user-1",
      amount,
      currency: ORDER_CURRENCY,
    }),
    {ok: true},
  );

  assert.equal(
    validatePaymentIntent(
      {...paymentIntent, metadata: {uid: "user-2"}},
      {uid: "user-1", amount, currency: ORDER_CURRENCY},
    ).ok,
    false,
  );
  assert.equal(
    validatePaymentIntent(
      {...paymentIntent, amount_received: amount - 1},
      {uid: "user-1", amount, currency: ORDER_CURRENCY},
    ).ok,
    false,
  );
  assert.equal(
    validatePaymentIntent(
      {...paymentIntent, status: "requires_payment_method"},
      {uid: "user-1", amount, currency: ORDER_CURRENCY},
    ).ok,
    false,
  );
});
