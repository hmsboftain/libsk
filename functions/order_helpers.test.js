const test = require("node:test");
const assert = require("node:assert/strict");

const {
  getDeliveryCost,
  getEffectiveProductPrice,
  kwdToMinorUnits,
  normalizeOrderItems,
  validatePaymentIntentForOrder,
  validatePaymentIntentOwnership,
} = require("./order_helpers");

function succeededPaymentIntent(overrides = {}) {
  return {
    id: "pi_123",
    status: "succeeded",
    currency: "kwd",
    amount: 4500,
    metadata: { uid: "user_1" },
    latest_charge: {
      amount: 4500,
      amount_captured: 4500,
      amount_refunded: 0,
      refunded: false,
    },
    ...overrides,
  };
}

test("validates a succeeded same-user exact KWD PaymentIntent", () => {
  const result = validatePaymentIntentForOrder(succeededPaymentIntent(), {
    uid: "user_1",
    expectedAmount: 4500,
  });

  assert.deepEqual(result, {
    id: "pi_123",
    amount: 4500,
    currency: "kwd",
  });
});

test("rejects unpaid or underpaid PaymentIntents before order writes", () => {
  assert.throws(
    () => validatePaymentIntentForOrder(
      succeededPaymentIntent({ status: "requires_payment_method" }),
      { uid: "user_1", expectedAmount: 4500 },
    ),
    /Payment has not completed/,
  );

  assert.throws(
    () => validatePaymentIntentForOrder(
      succeededPaymentIntent({ amount: 4400 }),
      { uid: "user_1", expectedAmount: 4500 },
    ),
    /Payment amount does not match/,
  );
});

test("rejects another user's or refunded PaymentIntent", () => {
  assert.throws(
    () => validatePaymentIntentOwnership(
      succeededPaymentIntent({ metadata: { uid: "other_user" } }),
      { uid: "user_1" },
    ),
    /Payment does not belong/,
  );

  assert.throws(
    () => validatePaymentIntentForOrder(
      succeededPaymentIntent({
        latest_charge: {
          amount: 4500,
          amount_captured: 4500,
          amount_refunded: 4500,
          refunded: true,
        },
      }),
      { uid: "user_1", expectedAmount: 4500 },
    ),
    /Payment has already been refunded/,
  );
});

test("server-side quote helpers use KWD minor units, sale price, and aggregate stock keys", () => {
  assert.equal(getDeliveryCost("Regular Delivery"), 3);
  assert.equal(getDeliveryCost("Same Day Delivery"), 5);
  assert.equal(getDeliveryCost("Made to Order"), 0);
  assert.equal(kwdToMinorUnits(7.125), 7125);
  assert.equal(getEffectiveProductPrice({ price: 12, salePrice: 9.5 }), 9.5);
  assert.equal(getEffectiveProductPrice({ price: 12, salePrice: 14 }), 12);

  assert.deepEqual(
    normalizeOrderItems([
      { boutiqueId: "b1", productId: "p1", quantity: 2 },
      { boutiqueId: "b1", productId: "p1", quantity: 3 },
    ]),
    {
      b1__p1: { boutiqueId: "b1", productId: "p1", qty: 5 },
    },
  );
});
