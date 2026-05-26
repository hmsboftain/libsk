const assert = require("node:assert/strict");
const test = require("node:test");

const {
  ORDER_CURRENCY,
  getDeliveryCost,
  isSupportedDeliveryMethod,
  isSupportedOrderCurrency,
  normalizeOrderCurrency,
  toStripeAmount,
} = require("../order_utils");

test("uses KWD as the only order currency", () => {
  assert.equal(ORDER_CURRENCY, "kwd");
  assert.equal(normalizeOrderCurrency("KWD"), "kwd");
  assert.equal(isSupportedOrderCurrency("kwd"), true);
  assert.equal(isSupportedOrderCurrency("usd"), false);
});

test("calculates KWD amounts in fils", () => {
  assert.equal(toStripeAmount(8, "kwd"), 8000);
  assert.equal(toStripeAmount(12.345, "kwd"), 12345);
});

test("uses server-owned delivery costs", () => {
  assert.equal(isSupportedDeliveryMethod("Regular Delivery"), true);
  assert.equal(isSupportedDeliveryMethod("Same Day Delivery"), true);
  assert.equal(isSupportedDeliveryMethod("Pickup"), false);
  assert.equal(getDeliveryCost("Regular Delivery"), 3);
  assert.equal(getDeliveryCost("Same Day Delivery"), 5);
});
