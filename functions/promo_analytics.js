/**
 * Pure logic for promo ad analytics: click validation, click de-duplication and
 * click→purchase attribution. No I/O and no firebase-admin import, so every rule
 * here is unit-tested directly against the real module the Cloud Functions call
 * (see test/promo_analytics.test.js) — same split as promo_credit.js.
 *
 * The model, in one paragraph: a rendered placement carries a provenance stamp
 * naming the booking that paid for it (see the stamp comment in index.js). A tap
 * on a stamped surface becomes a click event. If the same person buys the
 * promoted product — or anything from the promoted boutique — within
 * ATTRIBUTION_WINDOW_MS of that click, the sale is credited to that booking.
 * Impressions are deliberately not tracked, so there is no click-through rate:
 * "conversion" here means attributed orders ÷ clicks.
 */

// Click→purchase attribution window. Long enough to catch "saw it, came back
// later"; short enough that an unrelated purchase days later isn't credited to
// an ad the customer has long forgotten.
const ATTRIBUTION_WINDOW_MS = 48 * 60 * 60 * 1000;

// Repeat taps by the same person on the same booking collapse into one click
// inside this bucket. This is what stops an owner inflating their own numbers by
// hammering their banner, and caps write amplification from a rage-tapping user.
// It makes "clicks" mean "clicks, de-duplicated per person per booking per 30
// min" — the honest ad-dashboard metric, and the one the UI must label.
const CLICK_DEDUP_WINDOW_MS = 30 * 60 * 1000;

// Order statuses where the money is considered collected. Mirrors ORDER_STATUSES
// in index.js MINUS "Cancelled", PLUS "Refunded" — which is a real status set by
// the dispute/superadmin path (firestore_service.markOrderRefundedAsAdmin) even
// though it is absent from the updateOrderStatus allowlist. "Pending Payment" is
// deliberately NOT paid: Payzah orders are created pending and only flip to
// Placed once reconciled, so attributing on creation would credit abandoned
// checkouts as sales.
const PAID_ORDER_STATUSES = ["Placed", "Confirmed", "On the Way", "Delivered"];

// Leaving a paid state for one of these backs the attribution out again.
const REVERSED_ORDER_STATUSES = ["Cancelled", "Refunded"];

const isPaidOrderStatus = (s) => PAID_ORDER_STATUSES.includes(s);
const isReversedOrderStatus = (s) => REVERSED_ORDER_STATUSES.includes(s);

// Accepts a Firestore Timestamp (live data) or epoch ms (tests) — same tolerance
// as isPromoOccupying in index.js.
function toMillis(v) {
  if (!v) return 0;
  if (typeof v.toMillis === "function") return v.toMillis();
  return Number(v) || 0;
}

/**
 * Deterministic click-event id — the de-dup mechanism. Writing with .create()
 * makes a repeat tap inside the same bucket fail with ALREADY_EXISTS, which
 * throttles the counter with no extra read.
 */
function clickEventId(bookingId, clickerId, nowMs) {
  const bucket = Math.floor(nowMs / CLICK_DEDUP_WINDOW_MS);
  return `${bookingId}_${clickerId}_${bucket}`;
}

/**
 * Which placements are scoped to a product vs. a whole boutique. Boutique-scoped
 * clicks credit ANY purchase from that boutique inside the window, because the
 * placement sells the boutique, not one item.
 */
const PLACEMENT_SUBJECT = {
  featured_product: "product",
  feed_sponsored: "product",
  top_of_category: "product",
  featured_boutique: "boutique",
  home_banner: "boutique",
};

const subjectTypeFor = (placementType) => PLACEMENT_SUBJECT[placementType] || null;

/**
 * Does `booking` actually render `subject` through `placementType` at nowMs?
 *
 * The client sends the bookingId it read from the stamp, so this is the gate that
 * stops a crafted client dumping clicks onto an arbitrary booking — which would
 * corrupt a competitor's stats or flatter its own. Everything is re-derived from
 * the booking document; nothing about the claim is trusted.
 *
 * Returns { ok: true } or { ok: false, reason } — reason is for logs, never shown.
 */
function validateClick(booking, { placementType, subjectId, category }, nowMs) {
  if (!booking) return { ok: false, reason: "no-booking" };
  if (booking.placementType !== placementType) {
    return { ok: false, reason: "placement-mismatch" };
  }
  // Only 'active' renders. A paid_pending_review banner has not been approved and
  // is not on screen, so it cannot legitimately be clicked.
  if (booking.status !== "active") return { ok: false, reason: "not-active" };

  const startMs = toMillis(booking.dayStart || booking.weekStart);
  const endMs = toMillis(booking.dayEnd || booking.weekEnd);
  if (!(startMs && endMs)) return { ok: false, reason: "no-window" };
  if (nowMs < startMs || nowMs >= endMs) return { ok: false, reason: "outside-window" };

  const subjectType = subjectTypeFor(placementType);
  if (!subjectType) return { ok: false, reason: "unknown-placement" };

  if (subjectType === "boutique") {
    return booking.boutiqueId === subjectId
      ? { ok: true } : { ok: false, reason: "boutique-mismatch" };
  }

  if (placementType === "top_of_category") {
    const pins = booking.categoryPins || [];
    const pin = pins.find((p) => p && p.category === category);
    if (!pin) return { ok: false, reason: "category-not-pinned" };
    return (pin.productIds || []).includes(subjectId)
      ? { ok: true } : { ok: false, reason: "product-not-pinned" };
  }

  return (booking.targetProductIds || []).includes(subjectId)
    ? { ok: true } : { ok: false, reason: "product-not-targeted" };
}

/**
 * Line-item revenue in fils. Prices are KWD decimals on the order (see
 * createOrder's verifiedItems); fils keeps the arithmetic integral, matching how
 * the credit ledger already stores money.
 */
function itemRevenueFils(item) {
  const price = Number(item.price) || 0;
  const qty = Math.max(1, Math.floor(Number(item.quantity) || 1));
  return Math.round(price * 1000) * qty;
}

/**
 * Does `click` qualify to have driven `item`?
 *   - it must have happened BEFORE the purchase, within the window
 *   - a product-scoped click must name that exact product
 *   - a boutique-scoped click must name that item's boutique
 */
function clickQualifiesForItem(click, item, orderMs) {
  const clickedMs = toMillis(click.clickedAt);
  if (!clickedMs) return false;
  if (clickedMs > orderMs) return false;                      // click after purchase
  if (orderMs - clickedMs > ATTRIBUTION_WINDOW_MS) return false; // outside 48h
  if (click.subjectType === "boutique") return click.subjectId === item.boutiqueId;
  return click.subjectId === item.productId;
}

/**
 * Attribute one order's line items across bookings — LAST CLICK WINS.
 *
 * Resolved PER LINE ITEM, not per order: if a customer clicks a featured_product
 * ad for A and later a featured_boutique ad, then buys both A and something else
 * in one basket, per-order last-click would hand the whole basket to the boutique
 * ad and rob the ad that actually sold A. Per item, each item's revenue is
 * credited exactly once, to the most recent ad that could plausibly have driven
 * it — so booking totals still sum to the order total and no sale is double-sold.
 *
 * Ties on the same millisecond break by click id, purely so a replay produces an
 * identical result.
 *
 * @param clicks recent click events for this customer (already window-filtered
 *               loosely; this re-checks precisely)
 * @param items  the order's line items ({ productId, boutiqueId, price, quantity })
 * @param orderMs when the order became paid
 * @returns [{ bookingId, boutiqueId, placementType, revenueFils, clickId, items:[productId] }]
 *          one entry per credited booking, revenue summed over its items.
 */
function attributeOrder(clicks, items, orderMs) {
  const byBooking = new Map();

  for (const item of items || []) {
    const candidates = (clicks || []).filter((c) => clickQualifiesForItem(c, item, orderMs));
    if (!candidates.length) continue;

    candidates.sort((a, b) => {
      const d = toMillis(b.clickedAt) - toMillis(a.clickedAt);
      return d !== 0 ? d : String(a.id).localeCompare(String(b.id));
    });
    const winner = candidates[0];

    const entry = byBooking.get(winner.bookingId) || {
      bookingId: winner.bookingId,
      boutiqueId: winner.boutiqueId,
      placementType: winner.placementType,
      revenueFils: 0,
      clickId: winner.id,
      items: [],
    };
    entry.revenueFils += itemRevenueFils(item);
    entry.items.push(item.productId);
    byBooking.set(winner.bookingId, entry);
  }

  return Array.from(byBooking.values());
}

module.exports = {
  ATTRIBUTION_WINDOW_MS,
  CLICK_DEDUP_WINDOW_MS,
  PAID_ORDER_STATUSES,
  REVERSED_ORDER_STATUSES,
  isPaidOrderStatus,
  isReversedOrderStatus,
  clickEventId,
  subjectTypeFor,
  validateClick,
  itemRevenueFils,
  clickQualifiesForItem,
  attributeOrder,
};
