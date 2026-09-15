"use strict";

// ================= DISCOUNT CODES: ORDER SCOPE + AMOUNT =================
//
// The single rule for what a discount code is worth on an order. Shared by
// createOrder (authoritative, inside its price-verification transaction) and
// validateDiscountCode (the apply-time preview), so the two can't drift. Pure —
// unit-tested in test/discount_codes.test.js.
//
// Every discount code belongs to exactly ONE boutique: boutiqueId is required
// (firestore.rules refuses to store a code without one, and only that boutique's
// owner can create it). A code is usable ONLY on an order whose items ALL belong
// to its boutique. Anything else — another boutique's order, a mixed order, or a
// code with no boutiqueId at all — is rejected outright, never silently reduced
// to a partial or zero discount, and never treated as valid everywhere.
//
// The discount comes off the ITEM subtotal only and is capped at it, so it can
// never reach the delivery fee: an order's total is always
// subtotal - discount + delivery, with delivery untouched.

const DISCOUNT_NOT_VALID_FOR_CART = "This discount code is not valid for the items in your cart";

// The code can't be used on this order (another boutique's code, a code with no
// boutique, or nothing to discount). Callers turn it into a user-facing
// rejection.
class DiscountScopeError extends Error {
  constructor() {
    super(DISCOUNT_NOT_VALID_FOR_CART);
    this.name = "DiscountScopeError";
  }
}

// Is this code usable on an order made of items from these boutiques? Only if
// the code has a boutiqueId and the order is non-empty and entirely that
// boutique's. A code with no boutiqueId fits nothing.
function codeFitsBoutiques(codeData, boutiqueIds) {
  const codeBoutiqueId = String((codeData && codeData.boutiqueId) || "");
  if (!codeBoutiqueId) return false;
  const ids = (boutiqueIds || []).map((b) => String(b));
  return ids.length > 0 && ids.every((b) => b === codeBoutiqueId);
}

// The code's discount on an item subtotal (KWD, 3 dp): a percentage of it
// rounded to 3 dp, or the flat value — the arithmetic createOrder has always
// used, so discounted orders price exactly as before (pinned by a regression
// test against the old code).
function discountOnSubtotal(codeData, subtotal) {
  const value = Number(codeData.value) || 0;
  const raw = codeData.type === "percentage"
    ? parseFloat(((subtotal * value) / 100).toFixed(3))
    : value;
  // THE cap, for both kinds of code: never more than the items, so a discount
  // can never reach the delivery fee.
  return Math.max(0, Math.min(raw, subtotal));
}

// The discount a code gives on server-verified order items
// ({ boutiqueId, price, quantity }). Throws DiscountScopeError when the code
// can't be used on this order.
function discountForOrder(codeData, items) {
  if (!codeFitsBoutiques(codeData, items.map((i) => i.boutiqueId))) {
    throw new DiscountScopeError();
  }
  const subtotal = items.reduce((sum, i) => sum + i.price * i.quantity, 0);
  if (!(subtotal > 0)) throw new DiscountScopeError();
  return discountOnSubtotal(codeData, subtotal);
}

module.exports = {
  DISCOUNT_NOT_VALID_FOR_CART,
  DiscountScopeError,
  codeFitsBoutiques,
  discountOnSubtotal,
  discountForOrder,
};
