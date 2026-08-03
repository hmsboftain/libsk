"use strict";

// ================= WASAL DELIVERY — API CLIENT + PURE HELPERS =================
//
// Thin client for the Wasal Merchant Integration API (docs: wasal.org/docs).
// All HTTP goes through wasalRequest(); pure logic (status mapping, webhook
// signature verification, address matching, pricing-zone resolution) is kept
// side-effect free so it can be unit tested in test/wasal.test.js.
//
// Key facts (from the integration docs):
// - Base URL https://www.wasal.org/api/v1, endpoints under /integration/merchant/
// - Bearer auth: pk_test_ (sandbox, isolated, no wallet/webhooks) or pk_live_
// - Response envelope: { success, data } / { success:false, message, code, errors }
// - Rate limit: 600 requests per 15-minute window per key
// - Webhooks are HMAC-SHA256 signed: X-Wasal-Signature: sha256=<hex(rawBody)>

const crypto = require("crypto");

const WASAL_BASE_URL = "https://www.wasal.org/api/v1";
const MERCHANT_PREFIX = "/integration/merchant";

// Full Wasal order lifecycle, for reference and validation.
const WASAL_STATUSES = [
  "draft", "pending", "assigned", "on_way_to_merchant", "picked_up",
  "in_transit", "delivered", "failed", "returned", "cancelled",
];

// Wasal statuses that are terminal — no further transitions.
const WASAL_TERMINAL_STATUSES = ["delivered", "failed", "returned", "cancelled"];

class WasalError extends Error {
  constructor(message, { status, code, errors } = {}) {
    super(message || "Wasal API error");
    this.name = "WasalError";
    this.status = status || 0;
    this.code = code || "UNKNOWN";
    this.errors = errors || null;
  }
}

/**
 * Perform a Wasal API request. `apiKey` may be null for the public endpoints
 * (area lookup, order tracking). Throws WasalError on any non-success reply.
 */
async function wasalRequest(apiKey, method, path, { body, query } = {}) {
  const url = new URL(WASAL_BASE_URL + MERCHANT_PREFIX + path);
  if (query) {
    for (const [k, v] of Object.entries(query)) {
      if (v !== undefined && v !== null && v !== "") url.searchParams.set(k, String(v));
    }
  }
  const res = await fetch(url, {
    method,
    headers: {
      ...(apiKey ? { Authorization: `Bearer ${apiKey}` } : {}),
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  let json = null;
  try { json = await res.json(); } catch (_) { /* non-JSON reply */ }

  if (!res.ok || !json || json.success !== true) {
    throw new WasalError(
      (json && json.message) || `Wasal request failed (HTTP ${res.status})`,
      { status: res.status, code: json && json.code, errors: json && json.errors },
    );
  }
  return json.data;
}

// ── Client factory ────────────────────────────────────────────────────────────

/** Build a Wasal client bound to one API key. */
function createWasalClient(apiKey) {
  return {
    // Areas (public — no key required, but harmless to send one)
    listGovernorates: () =>
      wasalRequest(null, "GET", "/governorate-area", { query: { featureType: "Governorate" } }),
    listNeighborhoods: (governorateId) =>
      wasalRequest(null, "GET", "/governorate-area", {
        query: { featureType: "Neighborhood", governorateId },
      }),
    listBlocks: (neighborhoodId) =>
      wasalRequest(null, "GET", "/governorate-area", {
        query: { featureType: "Block", neighborhoodId },
      }),

    // Pricing zones for this merchant
    getPricing: () => wasalRequest(apiKey, "GET", "/pricing"),

    // Branches
    listBranches: (params = {}) => wasalRequest(apiKey, "GET", "/branch", { query: params }),

    // Customers
    upsertCustomer: ({ phoneNumber, name, email }) =>
      wasalRequest(apiKey, "POST", "/customer/upsert", { body: { phoneNumber, name, email } }),
    getCustomer: (customerId) => wasalRequest(apiKey, "GET", `/customer/${customerId}`),
    addCustomerAddress: (customerId, address) =>
      wasalRequest(apiKey, "POST", `/customer/${customerId}/address`, { body: address }),
    updateCustomerAddress: (customerId, addressId, address) =>
      wasalRequest(apiKey, "PUT", `/customer/${customerId}/address/${addressId}`, { body: address }),

    // Orders
    createOrder: (order) => wasalRequest(apiKey, "POST", "/order", { body: order }),
    getOrder: (orderId) => wasalRequest(apiKey, "GET", `/order/${orderId}`),
    cancelOrder: (orderId) => wasalRequest(apiKey, "PUT", `/order/${orderId}/cancel`),
    getOrderHistory: (orderId) => wasalRequest(apiKey, "GET", `/order/${orderId}/history`),

    // Webhook management
    registerWebhook: ({ url, events }) =>
      wasalRequest(apiKey, "POST", "/webhook", { body: { url, ...(events ? { events } : {}) } }),
    listWebhooks: () => wasalRequest(apiKey, "GET", "/webhook"),
    testWebhook: (webhookId) => wasalRequest(apiKey, "POST", `/webhook/${webhookId}/test`),

    // Sandbox only — advance an order through its lifecycle without a driver.
    advanceSandboxStatus: (orderId, status) =>
      wasalRequest(apiKey, "PUT", `/sandbox/order/${orderId}/advance-status`, { body: { status } }),
  };
}

// ── Pure helpers ──────────────────────────────────────────────────────────────

/**
 * Verify an X-Wasal-Signature header ("sha256=<hex>") against the raw request
 * body using the webhook secret. Constant-time; returns false on any mismatch
 * or malformed input rather than throwing.
 */
function verifyWebhookSignature(rawBody, secret, signatureHeader) {
  if (!rawBody || !secret || typeof signatureHeader !== "string") return false;
  const expected = "sha256=" + crypto
    .createHmac("sha256", secret)
    .update(rawBody)
    .digest("hex");
  const a = Buffer.from(signatureHeader);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

/**
 * Map a Wasal delivery status to the LIBSK order status it should advance the
 * order to, or null when the LIBSK status should not change (e.g. the driver
 * is still heading to the boutique — the order is Confirmed either way).
 *
 * LIBSK statuses: Placed → Confirmed → On the Way → Delivered / Cancelled.
 * failed / returned / cancelled keep the LIBSK status: a cancelled or failed
 * DELIVERY is not a cancelled ORDER — it is surfaced to the boutique via
 * wasalStatus so a human can resolve it (re-dispatch or refund). Cancellation
 * flows LIBSK → Wasal (updateOrderStatus cancels the delivery), never back.
 */
function mapWasalToLibskStatus(wasalStatus) {
  switch (wasalStatus) {
    case "picked_up":
    case "in_transit":
      return "On the Way";
    case "delivered":
      return "Delivered";
    default:
      return null;
  }
}

/**
 * Find an existing Wasal customer address matching a LIBSK address, so repeat
 * orders reuse it instead of hitting the 5-address cap. Match is on the fields
 * that make an address physically distinct.
 */
function findMatchingAddress(wasalAddresses, target) {
  if (!Array.isArray(wasalAddresses)) return null;
  const norm = (v) => String(v || "").trim().toLowerCase();
  return wasalAddresses.find((a) =>
    norm(a.governorateId) === norm(target.governorateId) &&
    norm(a.neighborhoodId) === norm(target.neighborhoodId) &&
    norm(a.blockId) === norm(target.blockId) &&
    norm(a.houseNumber) === norm(target.houseNumber) &&
    norm(a.floorNumber) === norm(target.floorNumber) &&
    norm(a.apartmentNumber) === norm(target.apartmentNumber),
  ) || null;
}

/**
 * Resolve the delivery fee for an area from the merchant's pricing zones.
 *
 * Real /pricing response shape (verified against the live sandbox,
 * 2026-08-01): data.list[] of flat records —
 *   { destinationGovernorateId: "<id>", neighborhoodId: "<id>"|null,
 *     deliveryFee: 1.2, serviceType: "b2c", ... }
 * A record with a neighborhoodId prices that specific neighborhood; with
 * neighborhoodId null it prices the whole governorate. Specific beats
 * general. Returns a number (KWD) or null when no zone matches — callers
 * must fall back to the flat default fee.
 */
function resolveZoneFee(pricingData, { governorateId, neighborhoodId }) {
  const zones =
    (pricingData && (pricingData.list || pricingData.zones || pricingData.pricing)) ||
    (Array.isArray(pricingData) ? pricingData : null);
  if (!Array.isArray(zones)) return null;

  const norm = (v) => String(v || "").trim().toLowerCase();
  const wantN = norm(neighborhoodId);
  const wantG = norm(governorateId);

  const feeOf = (zone) => {
    for (const key of ["deliveryFee", "fee", "price", "amount"]) {
      if (typeof zone[key] === "number") return zone[key];
      const parsed = parseFloat(zone[key]);
      if (!Number.isNaN(parsed) && zone[key] !== undefined && zone[key] !== null) return parsed;
    }
    return null;
  };

  let governorateFee = null;
  for (const zone of zones) {
    const zoneG = norm(zone.destinationGovernorateId || zone.governorateId);
    const zoneN = norm(zone.neighborhoodId);

    // Exact neighborhood zone — most specific, wins immediately.
    if (wantN && zoneN && zoneN === wantN) {
      const fee = feeOf(zone);
      if (fee !== null) return fee;
    }
    // Governorate-wide zone (no neighborhood restriction) — kept as fallback.
    if (wantG && zoneG === wantG && !zoneN && governorateFee === null) {
      governorateFee = feeOf(zone);
    }
  }
  return governorateFee;
}

/**
 * Match a customer's free-text block number ("4", "04", "Block 4") against
 * the Wasal/PACI block list for their neighborhood. blockId MUST be a real
 * PACI area reference — sending free text is rejected with "Invalid PACI
 * location reference". Returns the block's sourceId, or null when no block
 * matches (callers then omit blockId; it is optional).
 */
function matchBlockId(blockList, blockText) {
  if (!Array.isArray(blockList)) return null;
  const wanted = String(blockText || "")
    .toLowerCase().replace(/block|قطعة/g, "").trim().replace(/^0+(?=\d)/, "");
  if (!wanted) return null;
  const norm = (v) =>
    String(v || "").toLowerCase().replace(/block|قطعة/g, "").trim().replace(/^0+(?=\d)/, "");
  const hit = blockList.find((b) =>
    norm(b.title && b.title.en) === wanted || norm(b.title && b.title.ar) === wanted,
  );
  return hit ? String(hit.sourceId) : null;
}

/**
 * Normalize a phone number for Wasal. Kuwait local numbers are 8 digits;
 * prefix +965 when no country code is present. Returns null for anything
 * that can't plausibly be dialed.
 */
function normalizeKuwaitPhone(raw) {
  const s = String(raw || "").replace(/[\s\-()]/g, "");
  if (!s) return null;
  if (s.startsWith("+")) return /^\+\d{8,15}$/.test(s) ? s : null;
  if (/^965\d{8}$/.test(s)) return `+${s}`;
  if (/^\d{8}$/.test(s)) return `+965${s}`;
  return /^\d{8,15}$/.test(s) ? `+${s}` : null;
}

/**
 * Overall LIBSK order status for a (possibly multi-boutique) order given the
 * per-Wasal-order status map { wasalOrderId: wasalStatus }. Returns
 * "Delivered" only when every delivery reached `delivered`; null otherwise
 * (the per-boutique webhook handler advances intermediate statuses itself).
 */
function overallDeliveryStatus(wasalStatuses) {
  const values = Object.values(wasalStatuses || {});
  if (values.length === 0) return null;
  if (values.every((s) => s === "delivered")) return "Delivered";
  return null;
}

module.exports = {
  WASAL_BASE_URL,
  MERCHANT_PREFIX,
  WASAL_STATUSES,
  WASAL_TERMINAL_STATUSES,
  WasalError,
  wasalRequest,
  createWasalClient,
  verifyWebhookSignature,
  mapWasalToLibskStatus,
  normalizeKuwaitPhone,
  matchBlockId,
  findMatchingAddress,
  resolveZoneFee,
  overallDeliveryStatus,
};
