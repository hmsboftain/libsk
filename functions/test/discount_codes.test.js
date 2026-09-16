"use strict";

// Unit tests for ../discount_codes.js — the discount-code rule createOrder and
// validateDiscountCode share. Run with `npm test` (functions/).
//   * scope: a code only on its own boutique's order, rejected otherwise — and a
//     code with no boutiqueId rejected outright (there are no platform codes)
//   * delivery: no code, however large, ever reduces the delivery fee
//   * regression: single-boutique orders price EXACTLY as the pre-refactor code

const { test } = require("node:test");
const assert = require("node:assert/strict");

const {
  DISCOUNT_NOT_VALID_FOR_CART,
  DiscountScopeError,
  codeFitsBoutiques,
  discountOnSubtotal,
  discountForOrder,
} = require("../discount_codes");
const { resolveVendorSplit } = require("../payzah_commission");

const item = (boutiqueId, price, quantity = 1) => ({ boutiqueId, price, quantity });
const codeA10pct = { boutiqueId: "A", type: "percentage", value: 10 };
const codeA2flat = { boutiqueId: "A", type: "flat", value: 2 };
const noBoutique15pct = { type: "percentage", value: 15 }; // malformed: no boutiqueId

// ── scope ─────────────────────────────────────────────────────────────────────

test("boutique A's code on a boutique A order applies", () => {
  assert.equal(discountForOrder(codeA10pct, [item("A", 7.5, 2), item("A", 5)]), 2);
  assert.equal(discountForOrder(codeA2flat, [item("A", 7.5)]), 2);
});

test("boutique A's code on a boutique B order is REJECTED, not silently zeroed", () => {
  for (const code of [codeA10pct, codeA2flat]) {
    assert.throws(() => discountForOrder(code, [item("B", 10)]), (err) => {
      assert.ok(err instanceof DiscountScopeError);
      assert.equal(err.message, DISCOUNT_NOT_VALID_FOR_CART);
      return true;
    });
  }
});

test("boutique A's code on a mixed A+B order is REJECTED (not a partial discount)", () => {
  assert.throws(() => discountForOrder(codeA10pct, [item("A", 10), item("B", 10)]), DiscountScopeError);
});

test("a code with NO boutiqueId is rejected outright — never treated as platform-wide", () => {
  for (const code of [noBoutique15pct, { ...noBoutique15pct, boutiqueId: "" }, { ...noBoutique15pct, boutiqueId: null }]) {
    for (const cart of [[item("A", 10)], [item("B", 10)], [item("A", 10), item("B", 10)]]) {
      assert.throws(() => discountForOrder(code, cart), (err) => {
        assert.ok(err instanceof DiscountScopeError);
        assert.equal(err.message, DISCOUNT_NOT_VALID_FOR_CART);
        return true;
      }, JSON.stringify({ code, cart }));
    }
  }
});

test("codeFitsBoutiques (the apply-time check) matches the order-time rule", () => {
  assert.equal(codeFitsBoutiques(codeA10pct, ["A"]), true);
  assert.equal(codeFitsBoutiques(codeA10pct, ["B"]), false);
  assert.equal(codeFitsBoutiques(codeA10pct, ["A", "B"]), false);
  assert.equal(codeFitsBoutiques(codeA10pct, []), false);        // no cart info -> no boutique code
  assert.equal(codeFitsBoutiques(codeA10pct, undefined), false);
  // A code without a boutiqueId fits no cart at all.
  assert.equal(codeFitsBoutiques(noBoutique15pct, ["A"]), false);
  assert.equal(codeFitsBoutiques(noBoutique15pct, ["A", "B"]), false);
  assert.equal(codeFitsBoutiques(noBoutique15pct, []), false);
  assert.equal(codeFitsBoutiques({ ...noBoutique15pct, boutiqueId: "" }, [""]), false);
});

test("an order with nothing to discount is rejected", () => {
  assert.throws(() => discountForOrder(codeA10pct, [item("A", 0)]), DiscountScopeError);
});

// ── delivery is never discountable ───────────────────────────────────────────

test("a flat code larger than the items is capped at the item subtotal", () => {
  const big = { boutiqueId: "A", type: "flat", value: 50 };
  assert.equal(discountForOrder(big, [item("A", 10)]), 10);
  assert.equal(discountOnSubtotal(big, 10), 10);
});

test("a 100% code zeroes the items and nothing else", () => {
  assert.equal(discountForOrder({ boutiqueId: "A", type: "percentage", value: 100 }, [item("A", 12.345)]), 12.345);
});

test("the discount never exceeds the subtotal, for any code, so the total never dips below delivery", () => {
  const deliveryCost = 2;
  for (const subtotal of [0.5, 1, 7.5, 10, 13, 99.999]) {
    for (const code of [
      { type: "percentage", value: 1 }, { type: "percentage", value: 33 }, { type: "percentage", value: 100 },
      { type: "percentage", value: 250 }, // a rule-violating value can't slip past the cap either
      { type: "flat", value: 0.25 }, { type: "flat", value: 5 }, { type: "flat", value: 1000 },
    ]) {
      const discount = discountOnSubtotal(code, subtotal);
      assert.ok(discount >= 0 && discount <= subtotal, JSON.stringify({ subtotal, code, discount }));
      const total = subtotal + deliveryCost - discount; // createOrder's total
      assert.ok(total >= deliveryCost - 1e-9, JSON.stringify({ subtotal, code, total }));
    }
  }
});

// A payment attempt exactly as createOrder writes one, from the same inputs.
function attemptFor(items, code, deliveryCost) {
  const subtotal = items.reduce((s, i) => s + i.price * i.quantity, 0);
  const discountAmount = code ? discountForOrder(code, items) : 0;
  return {
    boutiqueIds: [...new Set(items.map((i) => i.boutiqueId))],
    subtotal, discountAmount, deliveryCost,
    amount: subtotal + deliveryCost - discountAmount,
  };
}
const splitDb = (pct = 15) => ({
  collection: (name) => ({ doc: () => ({ get: async () => ({
    exists: true,
    data: () => (name === "boutiqueSecrets" ? { payzahVendorKey: "vk" } : { commissionPercent: pct }),
  }) }) }),
});

test("end to end: an oversized code leaves the full delivery fee on LIBSK's side", async () => {
  // 10.000 of items, a 50.000 flat code (capped to 10.000), 2.000 delivery.
  const attempt = attemptFor([item("A", 10)], { boutiqueId: "A", type: "flat", value: 50 }, 2);
  assert.equal(attempt.discountAmount, 10);
  assert.equal(attempt.amount, 2); // the customer still pays the whole delivery fee
  const split = await resolveVendorSplit(splitDb(), attempt, "1");
  assert.equal(split.deliveryFils, 2000);   // delivery untouched by the discount
  assert.equal(split.baseFils, 0);          // the discount consumed the items only
  assert.equal(split.commissionFils, 1850); // 0 - 0.150 fee + 2.000 delivery
});

test("end to end: delivery is identical with and without a discount code", async () => {
  const items = [item("A", 7.5, 2)];
  const plain = await resolveVendorSplit(splitDb(), attemptFor(items, null, 2.5), "1");
  const discounted = await resolveVendorSplit(splitDb(), attemptFor(items, codeA10pct, 2.5), "1");
  assert.equal(discounted.deliveryFils, plain.deliveryFils);
  assert.equal(discounted.deliveryFils, 2500);
});

// ── regression: exactly the pre-refactor arithmetic ──────────────────────────

// VERBATIM copy of createOrder's inline discount block before this change
// (single-boutique orders are the only real ones — checkout enforces it).
function legacyCreateOrderDiscount(codeData, verifiedItems, verifiedSubtotal) {
  const codeBoutiqueId = String(codeData.boutiqueId || "");
  const discountableSubtotal = codeBoutiqueId
    ? verifiedItems
        .filter((i) => i.boutiqueId === codeBoutiqueId)
        .reduce((sum, i) => sum + i.price * i.quantity, 0)
    : verifiedSubtotal;
  if (discountableSubtotal <= 0) throw new Error("not valid");
  let discountAmount;
  const codeValue = Number(codeData.value) || 0;
  if (codeData.type === "percentage") {
    discountAmount = parseFloat(((discountableSubtotal * codeValue) / 100).toFixed(3));
  } else {
    discountAmount = Math.min(codeValue, discountableSubtotal);
  }
  discountAmount = Math.min(discountAmount, discountableSubtotal);
  return Math.max(0, Math.min(discountAmount, verifiedSubtotal));
}

test("normal discounted orders: identical to the pre-refactor createOrder, to the last digit", () => {
  const carts = [
    [item("A", 7.5)], [item("A", 13, 1)], [item("A", 12.345, 3)], [item("A", 8.75, 2), item("A", 11.25)],
    [item("A", 0.99, 7)], [item("A", 45.678), item("A", 1.001, 4)], [item("A", 10.005, 3)],
  ];
  const codes = [
    { type: "percentage", value: 5 }, { type: "percentage", value: 12.5 }, { type: "percentage", value: 33 },
    { type: "percentage", value: 100 }, { type: "flat", value: 0.5 }, { type: "flat", value: 2.5 },
    { type: "flat", value: 7.777 }, { type: "flat", value: 500 },
  ];
  let checked = 0;
  for (const cart of carts) {
    let verifiedSubtotal = 0; // built the way createOrder builds it: same loop, same order
    for (const i of cart) verifiedSubtotal += i.price * i.quantity;
    for (const c of codes) {
      const code = { ...c, boutiqueId: "A" };
      const want = legacyCreateOrderDiscount(code, cart, verifiedSubtotal);
      assert.equal(discountForOrder(code, cart), want, JSON.stringify({ cart, code }));
      checked += 1;
    }
  }
  assert.equal(checked, 7 * 8);
});

test("normal discounted order through the vendor split matches the formula exactly", async () => {
  // 2 x 7.500 items, 10% boutique code, 2.000 delivery, 15%, K-Net.
  const attempt = attemptFor([item("A", 7.5, 2)], codeA10pct, 2);
  assert.equal(attempt.discountAmount, 1.5);
  assert.equal(attempt.amount, 15.5);
  const split = await resolveVendorSplit(splitDb(15), attempt, "1");
  // base = 15.000 - 1.500 = 13.500; LIBSK = 2.025 - 0.150 + 2.000; boutique = 13.500 x 0.85
  assert.equal(split.baseFils, 13500);
  assert.equal(split.commissionFils, 3875);
  assert.equal(15500 - split.feeFils - split.commissionFils, 11475);
});
