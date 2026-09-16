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
