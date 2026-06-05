const assert = require("node:assert/strict");
const {describe, it} = require("node:test");

const {
  OrderValidationError,
  aggregateItems,
  assertPaymentIntentMatchesOrder,
  normalizeCurrency,
  resolveDeliveryDetails,
  toStripeAmount,
} = require("./order_helpers");

function assertValidationError(fn, code, message) {
  assert.throws(
    fn,
    (error) => (
      error instanceof OrderValidationError &&
      error.code === code &&
      error.message === message
    ),
  );
}

describe("order helper validation", () => {
  it("derives canonical delivery cost from a delivery method", () => {
    assert.deepEqual(
      resolveDeliveryDetails({
        deliveryMethod: "Same Day Delivery",
        deliveryCost: -99,
      }),
      {deliveryMethod: "Same Day Delivery", deliveryCost: 5},
    );
  });

  it("keeps old clients working only for recognized delivery costs", () => {
    assert.deepEqual(
      resolveDeliveryDetails({deliveryCost: 3}),
      {deliveryMethod: "Regular Delivery", deliveryCost: 3},
    );

    assertValidationError(
      () => resolveDeliveryDetails({deliveryCost: -99}),
      "invalid-argument",
      "Invalid delivery method.",
    );
  });

  it("only accepts KWD because product prices are stored in KWD", () => {
    assert.equal(normalizeCurrency("KWD"), "kwd");
    assertValidationError(
      () => normalizeCurrency("usd"),
      "invalid-argument",
      "Unsupported currency.",
    );
  });

  it("converts KWD totals into Stripe minor units", () => {
    assert.deepEqual(toStripeAmount(12.345, "kwd"), {
      amount: 12345,
      currency: "kwd",
    });
  });

  it("aggregates duplicate products before stock updates", () => {
    const result = aggregateItems([
      {boutiqueId: "b1", productId: "p1", quantity: 2, size: "S"},
      {boutiqueId: "b1", productId: "p1", quantity: 3, size: "M"},
      {boutiqueId: "b2", productId: "p2", quantity: 1},
    ]);

    assert.deepEqual(result.aggregateItems, [
      {boutiqueId: "b1", productId: "p1", quantity: 5},
      {boutiqueId: "b2", productId: "p2", quantity: 1},
    ]);
    assert.equal(result.normalizedItems.length, 3);
  });

  it("rejects split duplicate quantities above the per-product limit", () => {
    assertValidationError(
      () => aggregateItems([
        {boutiqueId: "b1", productId: "p1", quantity: 60},
        {boutiqueId: "b1", productId: "p1", quantity: 41},
      ]),
      "invalid-argument",
      "Quantity cannot exceed 100 per product.",
    );
  });

  it("accepts only succeeded same-user payment intents for the exact amount", () => {
    assert.doesNotThrow(() => assertPaymentIntentMatchesOrder(
      {
        status: "succeeded",
        amount: 8000,
        amount_received: 8000,
        currency: "kwd",
        metadata: {uid: "user_1"},
      },
      {uid: "user_1", expectedAmount: 8000, currency: "kwd"},
    ));
  });

  it("rejects unpaid, underpaid, wrong-currency, or wrong-user payments", () => {
    assertValidationError(
      () => assertPaymentIntentMatchesOrder(
        {
          status: "requires_payment_method",
          amount: 8000,
          currency: "kwd",
          metadata: {uid: "user_1"},
        },
        {uid: "user_1", expectedAmount: 8000, currency: "kwd"},
      ),
      "failed-precondition",
      "Payment has not been completed.",
    );

    assertValidationError(
      () => assertPaymentIntentMatchesOrder(
        {
          status: "succeeded",
          amount: 1000,
          amount_received: 1000,
          currency: "kwd",
          metadata: {uid: "user_1"},
        },
        {uid: "user_1", expectedAmount: 8000, currency: "kwd"},
      ),
      "failed-precondition",
      "Payment amount does not match order total.",
    );

    assertValidationError(
      () => assertPaymentIntentMatchesOrder(
        {
          status: "succeeded",
          amount: 8000,
          amount_received: 8000,
          currency: "usd",
          metadata: {uid: "user_1"},
        },
        {uid: "user_1", expectedAmount: 8000, currency: "kwd"},
      ),
      "failed-precondition",
      "Payment currency does not match order.",
    );

    assertValidationError(
      () => assertPaymentIntentMatchesOrder(
        {
          status: "succeeded",
          amount: 8000,
          amount_received: 8000,
          currency: "kwd",
          metadata: {uid: "user_2"},
        },
        {uid: "user_1", expectedAmount: 8000, currency: "kwd"},
      ),
      "permission-denied",
      "Payment does not belong to this user.",
    );
  });
});
