// Unit tests for the pure ad-analytics logic in ../promo_analytics.js.
// Run with `npm test` (functions/) — Node's built-in runner, no deps.
// These exercise the REAL module the Cloud Functions call, so a green run means
// the click-validation and attribution rules index.js relies on are correct.

const { test } = require("node:test");
const assert = require("node:assert/strict");

const {
  ATTRIBUTION_WINDOW_MS,
  isPaidOrderStatus,
  isReversedOrderStatus,
  clickEventId,
  subjectTypeFor,
  validateClick,
  itemRevenueFils,
  attributeOrder,
} = require("../promo_analytics");

const HOUR = 60 * 60 * 1000;
const NOW = 1_700_000_000_000; // fixed clock for determinism

// A booking that is live right now: active, window open, targets product p1.
const liveBooking = (over = {}) => ({
  status: "active",
  placementType: "featured_product",
  boutiqueId: "b1",
  targetProductIds: ["p1"],
  dayStart: NOW - HOUR,
  dayEnd: NOW + HOUR,
  ...over,
});

const click = (over = {}) => ({
  id: "c1",
  bookingId: "bk1",
  boutiqueId: "b1",
  placementType: "featured_product",
  subjectType: "product",
  subjectId: "p1",
  clickedAt: NOW - HOUR,
  ...over,
});

const item = (over = {}) => ({
  productId: "p1", boutiqueId: "b1", price: 12.5, quantity: 1, ...over,
});

// ─────────────────────────── order status vocabulary ───────────────────────────

test("paid statuses match the real order vocabulary", () => {
  for (const s of ["Placed", "Confirmed", "On the Way", "Delivered"]) {
    assert.equal(isPaidOrderStatus(s), true, `${s} should be paid`);
  }
});

test("Pending Payment is NOT paid — Payzah orders start there before reconciling", () => {
  assert.equal(isPaidOrderStatus("Pending Payment"), false);
});

test("Cancelled and Refunded reverse; Refunded is real despite being absent from ORDER_STATUSES", () => {
  assert.equal(isReversedOrderStatus("Cancelled"), true);
  assert.equal(isReversedOrderStatus("Refunded"), true);
  assert.equal(isPaidOrderStatus("Cancelled"), false);
  assert.equal(isPaidOrderStatus("Refunded"), false);
});

// ─────────────────────────── click de-duplication ───────────────────────────

test("same person + booking inside the 30-min bucket collapses to one id", () => {
  const a = clickEventId("bk1", "u1", NOW);
  const b = clickEventId("bk1", "u1", NOW + 60_000); // 1 min later
  assert.equal(a, b);
});

test("different bucket, booking or person all yield distinct ids", () => {
  const base = clickEventId("bk1", "u1", NOW);
  assert.notEqual(base, clickEventId("bk1", "u1", NOW + 31 * 60_000));
  assert.notEqual(base, clickEventId("bk2", "u1", NOW));
  assert.notEqual(base, clickEventId("bk1", "u2", NOW));
});

// ─────────────────────────── placement subject scoping ───────────────────────────

test("placements scope to product or boutique as the ad actually sells", () => {
  assert.equal(subjectTypeFor("featured_product"), "product");
  assert.equal(subjectTypeFor("feed_sponsored"), "product");
  assert.equal(subjectTypeFor("top_of_category"), "product");
  assert.equal(subjectTypeFor("featured_boutique"), "boutique");
  assert.equal(subjectTypeFor("home_banner"), "boutique");
});

// ─────────────────────────── click validation (anti-spoof) ───────────────────────────

test("a genuine click on a live booking validates", () => {
  const r = validateClick(liveBooking(), {
    placementType: "featured_product", subjectId: "p1",
  }, NOW);
  assert.equal(r.ok, true);
});

test("a client cannot attribute a click to a product the booking never targeted", () => {
  const r = validateClick(liveBooking(), {
    placementType: "featured_product", subjectId: "p999",
  }, NOW);
  assert.equal(r.ok, false);
  assert.equal(r.reason, "product-not-targeted");
});

test("a client cannot claim a different placement than the booking bought", () => {
  const r = validateClick(liveBooking(), {
    placementType: "home_banner", subjectId: "p1",
  }, NOW);
  assert.equal(r.ok, false);
  assert.equal(r.reason, "placement-mismatch");
});

test("clicks outside the booked window are rejected at both edges", () => {
  const req = { placementType: "featured_product", subjectId: "p1" };
  assert.equal(validateClick(liveBooking(), req, NOW - 2 * HOUR).reason, "outside-window");
  assert.equal(validateClick(liveBooking(), req, NOW + 2 * HOUR).reason, "outside-window");
});

test("dayEnd is exclusive — a click at the closing instant does not count", () => {
  const r = validateClick(liveBooking(), {
    placementType: "featured_product", subjectId: "p1",
  }, NOW + HOUR);
  assert.equal(r.ok, false);
});

test("a banner still awaiting approval is not on screen, so cannot be clicked", () => {
  const r = validateClick(liveBooking({ status: "paid_pending_review" }), {
    placementType: "featured_product", subjectId: "p1",
  }, NOW);
  assert.equal(r.reason, "not-active");
});

test("cancelled and expired bookings reject clicks", () => {
  for (const status of ["cancelled", "expired", "pending_payment", "rejected"]) {
    const r = validateClick(liveBooking({ status }), {
      placementType: "featured_product", subjectId: "p1",
    }, NOW);
    assert.equal(r.ok, false, `${status} must not accept clicks`);
  }
});

test("boutique-scoped placements validate against the booking's boutique", () => {
  const b = liveBooking({ placementType: "featured_boutique", boutiqueId: "b1" });
  assert.equal(validateClick(b, { placementType: "featured_boutique", subjectId: "b1" }, NOW).ok, true);
  assert.equal(validateClick(b, { placementType: "featured_boutique", subjectId: "b2" }, NOW).reason,
    "boutique-mismatch");
});

test("top_of_category validates the product is pinned in THAT category", () => {
  const b = liveBooking({
    placementType: "top_of_category",
    categoryPins: [{ category: "Dresses", productIds: ["p1"] }],
  });
  assert.equal(validateClick(b,
    { placementType: "top_of_category", subjectId: "p1", category: "Dresses" }, NOW).ok, true);
  // Right product, wrong category — the booking never bought that category.
  assert.equal(validateClick(b,
    { placementType: "top_of_category", subjectId: "p1", category: "Tops" }, NOW).reason,
    "category-not-pinned");
  // Right category, product not in the pin.
  assert.equal(validateClick(b,
    { placementType: "top_of_category", subjectId: "p9", category: "Dresses" }, NOW).reason,
    "product-not-pinned");
});

test("categories with punctuation survive validation (Dra'a, Blouses & Shirts)", () => {
  const b = liveBooking({
    placementType: "top_of_category",
    categoryPins: [{ category: "Blouses & Shirts", productIds: ["p1"] }],
  });
  assert.equal(validateClick(b,
    { placementType: "top_of_category", subjectId: "p1", category: "Blouses & Shirts" }, NOW).ok,
    true);
});

// ─────────────────────────── revenue maths ───────────────────────────

test("line revenue converts KWD to fils and multiplies by quantity", () => {
  assert.equal(itemRevenueFils({ price: 12.5, quantity: 2 }), 25_000);
  assert.equal(itemRevenueFils({ price: 7.5, quantity: 1 }), 7_500);
  assert.equal(itemRevenueFils({ price: 13, quantity: 3 }), 39_000);
});

test("missing quantity is treated as one unit", () => {
  assert.equal(itemRevenueFils({ price: 6 }), 6_000);
});

// ─────────────────────────── attribution ───────────────────────────

test("a click then a purchase inside 48h attributes the sale", () => {
  const out = attributeOrder([click()], [item()], NOW);
  assert.equal(out.length, 1);
  assert.equal(out[0].bookingId, "bk1");
  assert.equal(out[0].revenueFils, 12_500);
});

test("a purchase just inside 48h attributes; just outside does not", () => {
  const inside = attributeOrder(
    [click({ clickedAt: NOW - ATTRIBUTION_WINDOW_MS + 1000 })], [item()], NOW);
  assert.equal(inside.length, 1);

  const outside = attributeOrder(
    [click({ clickedAt: NOW - ATTRIBUTION_WINDOW_MS - 1000 })], [item()], NOW);
  assert.equal(outside.length, 0, "a click older than the window must not be credited");
});

test("a click AFTER the purchase never attributes", () => {
  const out = attributeOrder([click({ clickedAt: NOW + HOUR })], [item()], NOW);
  assert.equal(out.length, 0);
});

test("buying a product the ad never promoted attributes nothing", () => {
  const out = attributeOrder([click({ subjectId: "p1" })], [item({ productId: "p2" })], NOW);
  assert.equal(out.length, 0);
});

test("last click wins between two bookings promoting the same product", () => {
  const older = click({ id: "c1", bookingId: "bkOLD", clickedAt: NOW - 5 * HOUR });
  const newer = click({ id: "c2", bookingId: "bkNEW", clickedAt: NOW - 1 * HOUR });
  const out = attributeOrder([older, newer], [item()], NOW);
  assert.equal(out.length, 1);
  assert.equal(out[0].bookingId, "bkNEW");
});

test("a boutique-scoped click credits any purchase from that boutique", () => {
  const c = click({
    placementType: "featured_boutique", subjectType: "boutique", subjectId: "b1",
  });
  const out = attributeOrder([c], [item({ productId: "anything" })], NOW);
  assert.equal(out.length, 1);
  assert.equal(out[0].revenueFils, 12_500);
});

test("a boutique-scoped click does NOT credit a different boutique's item", () => {
  const c = click({
    placementType: "featured_boutique", subjectType: "boutique", subjectId: "b1",
  });
  const out = attributeOrder([c], [item({ boutiqueId: "b2" })], NOW);
  assert.equal(out.length, 0);
});

test("last click is resolved PER ITEM, so a basket does not rob the ad that sold each line", () => {
  // Clicked the product ad for p1 first, then a boutique ad; bought both.
  const productClick = click({
    id: "c1", bookingId: "bkProduct", subjectId: "p1", clickedAt: NOW - 5 * HOUR,
  });
  const boutiqueClick = click({
    id: "c2", bookingId: "bkBoutique", placementType: "featured_boutique",
    subjectType: "boutique", subjectId: "b1", clickedAt: NOW - 1 * HOUR,
  });
  const out = attributeOrder(
    [productClick, boutiqueClick],
    [item({ productId: "p1", price: 10 }), item({ productId: "p2", price: 20 })],
    NOW,
  );

  const byId = Object.fromEntries(out.map((e) => [e.bookingId, e]));
  // p2 only matches the boutique ad. p1 matches BOTH, and the boutique click is
  // more recent, so last-click hands p1 to the boutique ad too.
  assert.equal(byId.bkBoutique.revenueFils, 30_000);
  assert.equal(byId.bkProduct, undefined);

  // Total credited never exceeds the basket.
  const total = out.reduce((s, e) => s + e.revenueFils, 0);
  assert.equal(total, 30_000);
});

test("each item's revenue is credited exactly once across bookings", () => {
  const c1 = click({ id: "c1", bookingId: "bkA", subjectId: "p1", clickedAt: NOW - 3 * HOUR });
  const c2 = click({ id: "c2", bookingId: "bkB", subjectId: "p2", clickedAt: NOW - 2 * HOUR });
  const out = attributeOrder(
    [c1, c2],
    [item({ productId: "p1", price: 10 }), item({ productId: "p2", price: 20 })],
    NOW,
  );
  const total = out.reduce((s, e) => s + e.revenueFils, 0);
  assert.equal(total, 30_000);
  assert.equal(out.length, 2);
});

test("repeated clicks on one booking credit the order once, not once per click", () => {
  const c1 = click({ id: "c1", clickedAt: NOW - 3 * HOUR });
  const c2 = click({ id: "c2", clickedAt: NOW - 2 * HOUR });
  const out = attributeOrder([c1, c2], [item()], NOW);
  assert.equal(out.length, 1);
  assert.equal(out[0].revenueFils, 12_500);
});

test("simultaneous clicks break the tie deterministically", () => {
  const a = click({ id: "cA", bookingId: "bkA", clickedAt: NOW - HOUR });
  const b = click({ id: "cB", bookingId: "bkB", clickedAt: NOW - HOUR });
  const first = attributeOrder([a, b], [item()], NOW);
  const second = attributeOrder([b, a], [item()], NOW); // input order flipped
  assert.equal(first[0].bookingId, second[0].bookingId);
});

test("no clicks, no items, or empty inputs attribute nothing", () => {
  assert.deepEqual(attributeOrder([], [item()], NOW), []);
  assert.deepEqual(attributeOrder([click()], [], NOW), []);
  assert.deepEqual(attributeOrder(undefined, undefined, NOW), []);
});

test("quantity flows into attributed revenue", () => {
  const out = attributeOrder([click()], [item({ price: 7.5, quantity: 4 })], NOW);
  assert.equal(out[0].revenueFils, 30_000);
});
