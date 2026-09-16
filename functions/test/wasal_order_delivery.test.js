"use strict";

// Unit tests for wasal.resolveOrderDelivery — how createOrder prices an order's
// delivery and decides whether it's Made to Order. Run with `npm test`
// (functions/). A green run means Made to Order never changes the delivery
// charge (it used to zero it: the customer paid nothing while LIBSK paid Wasal),
// and only the product docs — never the client — make an order Made to Order.

const { test } = require("node:test");
const assert = require("node:assert/strict");

const {
  resolveOrderDelivery,
  DeliveryMethodError,
  DELIVERY_STANDARD,
  DELIVERY_MADE_TO_ORDER,
  FLAT_DELIVERY_FEE,
} = require("../wasal");

// Product docs as createOrder's transaction reads them.
const regular = { title: "Linen shirt", price: 12, madeToOrder: false };
const legacyRegular = { title: "Tote", price: 8 }; // older product: no madeToOrder field
const mto = { title: "Custom abaya", price: 45, madeToOrder: true, deliveryTimeframe: "3 weeks" };

const AREA_FEE = 1.25; // the Wasal fee for one pickup to the customer's area

// `in` rather than a default parameter: a default would also replace an
// explicit `wasalAreaFee: undefined`, which is one of the cases under test.
function deliver(products, requestedMethod, opts = {}) {
  return resolveOrderDelivery({
    products,
    requestedMethod,
    wasalAreaFee: "wasalAreaFee" in opts ? opts.wasalAreaFee : AREA_FEE,
    pickupCount: opts.pickupCount ?? 1,
  });
}

// ── Made to Order is charged delivery exactly like any other order ──────────

test("a Made to Order item charges the same delivery as a regular item in the same area", () => {
  const regularOrder = deliver([regular], DELIVERY_STANDARD);
  const mtoOrder = deliver([mto], DELIVERY_MADE_TO_ORDER);
  assert.equal(regularOrder.deliveryCost, 1.25);
  assert.equal(mtoOrder.deliveryCost, regularOrder.deliveryCost);
});

test("a cart mixing Made to Order and regular items charges the normal delivery fee", () => {
  const mixed = deliver([regular, mto, legacyRegular], DELIVERY_MADE_TO_ORDER);
  assert.equal(mixed.deliveryCost, 1.25);
  assert.equal(mixed.madeToOrder, true);
  assert.equal(mixed.deliveryMethod, DELIVERY_MADE_TO_ORDER);
});

test("multi-boutique: the area fee is charged once per pickup, Made to Order or not", () => {
  for (const products of [[regular], [mto], [regular, mto]]) {
    assert.equal(deliver(products, DELIVERY_STANDARD, { pickupCount: 2 }).deliveryCost, 2.5);
  }
});

test("no area price resolved: Made to Order gets the same flat fallback as any order", () => {
  for (const wasalAreaFee of [null, undefined, NaN]) {
    assert.equal(deliver([regular], DELIVERY_STANDARD, { wasalAreaFee }).deliveryCost, FLAT_DELIVERY_FEE);
    assert.equal(deliver([mto], DELIVERY_MADE_TO_ORDER, { wasalAreaFee }).deliveryCost, FLAT_DELIVERY_FEE);
  }
});

test("the fee is rounded to fils (0.1 x 3 pickups is 0.3, not 0.30000000000000004)", () => {
  assert.equal(deliver([mto], DELIVERY_STANDARD, { wasalAreaFee: 0.1, pickupCount: 3 }).deliveryCost, 0.3);
});

test("a zero-priced Wasal zone stays free for every order alike", () => {
  assert.equal(deliver([regular], DELIVERY_STANDARD, { wasalAreaFee: 0 }).deliveryCost, 0);
  assert.equal(deliver([mto], DELIVERY_MADE_TO_ORDER, { wasalAreaFee: 0 }).deliveryCost, 0);
});

// ── Made to Order comes from the product docs, never the client ─────────────

test("a Made to Order claim for a cart with no made-to-order product is rejected", () => {
  for (const products of [[regular], [legacyRegular], [regular, legacyRegular]]) {
    assert.throws(() => deliver(products, DELIVERY_MADE_TO_ORDER), DeliveryMethodError);
  }
});

test("a made-to-order product makes the order Made to Order even if the client said Standard", () => {
  const order = deliver([regular, mto], DELIVERY_STANDARD);
  assert.equal(order.madeToOrder, true);
  assert.equal(order.deliveryMethod, DELIVERY_MADE_TO_ORDER);
});

test("a cart with no made-to-order product is Standard Delivery", () => {
  const order = deliver([regular, legacyRegular], DELIVERY_STANDARD);
  assert.equal(order.madeToOrder, false);
  assert.equal(order.deliveryMethod, DELIVERY_STANDARD);
});

test("only a real boolean true counts as made to order", () => {
  for (const flag of ["true", 1, "yes", null, undefined, false]) {
    const product = { ...regular, madeToOrder: flag };
    assert.equal(deliver([product], DELIVERY_STANDARD).madeToOrder, false, `madeToOrder: ${flag}`);
    assert.throws(() => deliver([product], DELIVERY_MADE_TO_ORDER), DeliveryMethodError);
  }
});
