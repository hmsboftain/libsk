const test = require("node:test");
const assert = require("node:assert/strict");

const {
  aggregateItems,
  effectiveProductPrice,
  toStripeAmountKwd,
  validatePaymentIntentForOrder,
} = require("./order_helpers");

test("uses sale price only when it is below the regular price", () => {
  assert.equal(effectiveProductPrice({price: 10, salePrice: 7.5}), 7.5);
  assert.equal(effectiveProductPrice({price: 10, salePrice: 12}), 10);
  assert.equal(effectiveProductPrice({price: 10, salePrice: 0}), 10);
});

test("converts KWD totals to Stripe fils", () => {
  assert.equal(toStripeAmountKwd(7.5), 7500);
  assert.equal(toStripeAmountKwd(10.125), 10125);
  assert.equal(toStripeAmountKwd(10.1234), 10123);
});

test("aggregates duplicate product quantities before stock checks", () => {
  const aggregate = aggregateItems([
    {boutiqueId: "b1", productId: "p1", quantity: 2},
    {boutiqueId: "b1", productId: "p1", quantity: 3},
    {boutiqueId: "b1", productId: "p2", quantity: 1},
  ]);

  assert.equal(aggregate.b1__p1.qty, 5);
  assert.equal(aggregate.b1__p2.qty, 1);
});

test("validates succeeded same-user exact KWD payment intents", () => {
  const paymentIntent = {
    status: "succeeded",
    amount: 12500,
    currency: "kwd",
    metadata: {uid: "user_1"},
    latest_charge: {amount_refunded: 0, refunded: false},
  };

  assert.deepEqual(
    validatePaymentIntentForOrder(paymentIntent, {uid: "user_1", amount: 12500}),
    {ok: true},
  );
  assert.equal(
    validatePaymentIntentForOrder(paymentIntent, {uid: "user_2", amount: 12500}).ok,
    false,
  );
  assert.equal(
    validatePaymentIntentForOrder(paymentIntent, {uid: "user_1", amount: 12501}).ok,
    false,
  );
  assert.equal(
    validatePaymentIntentForOrder({
      ...paymentIntent,
      latest_charge: {amount_refunded: 12500, refunded: true},
    }, {uid: "user_1", amount: 12500}).ok,
    false,
  );
});
