const assert = require("node:assert/strict");
const test = require("node:test");

const {_test} = require("./index");

function assertHttpsError(fn, code) {
  assert.throws(fn, (error) => error && error.code === code);
}

test("delivery costs and KWD amounts are server-derived", () => {
  assert.equal(_test.getDeliveryCost("Regular Delivery"), 3);
  assert.equal(_test.getDeliveryCost("Same Day Delivery"), 5);
  assert.equal(_test.calculatePaymentAmount(8, "kwd"), 8000);
  assert.equal(_test.calculatePaymentAmount(8.125, "kwd"), 8125);

  assertHttpsError(
    () => _test.getDeliveryCost("Free Delivery"),
    "invalid-argument",
  );
  assertHttpsError(
    () => _test.calculatePaymentAmount(8, "usd"),
    "invalid-argument",
  );
});

test("payment intent validation rejects mismatched or incomplete charges", () => {
  const validIntent = {
    status: "succeeded",
    currency: "kwd",
    amount_received: 8000,
    metadata: {uid: "user-1"},
  };

  assert.doesNotThrow(() => _test.validatePaymentIntentForOrder(
    validIntent,
    {uid: "user-1", expectedAmount: 8000, currency: "kwd"},
  ));

  assertHttpsError(
    () => _test.validatePaymentIntentForOrder(
      {...validIntent, metadata: {uid: "user-2"}},
      {uid: "user-1", expectedAmount: 8000, currency: "kwd"},
    ),
    "permission-denied",
  );
  assertHttpsError(
    () => _test.validatePaymentIntentForOrder(
      {...validIntent, status: "requires_payment_method"},
      {uid: "user-1", expectedAmount: 8000, currency: "kwd"},
    ),
    "failed-precondition",
  );
  assertHttpsError(
    () => _test.validatePaymentIntentForOrder(
      {...validIntent, currency: "usd"},
      {uid: "user-1", expectedAmount: 8000, currency: "kwd"},
    ),
    "failed-precondition",
  );
  assertHttpsError(
    () => _test.validatePaymentIntentForOrder(
      {...validIntent, amount_received: 3000},
      {uid: "user-1", expectedAmount: 8000, currency: "kwd"},
    ),
    "failed-precondition",
  );
});

test("duplicate product lines are aggregated before stock decrement", () => {
  const groups = _test.groupQuantitiesByProduct([
    {boutiqueId: "b1", productId: "p1", quantity: 1},
    {boutiqueId: "b1", productId: "p1", quantity: 3},
    {boutiqueId: "b1", productId: "p2", quantity: 2},
  ]);

  assert.equal(groups.size, 2);
  assert.equal(groups.get("b1/p1").quantity, 4);
  assert.equal(groups.get("b1/p1").items.length, 2);
  assert.equal(groups.get("b1/p2").quantity, 2);
});
