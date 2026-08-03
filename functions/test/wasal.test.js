"use strict";

// Unit tests for the pure Wasal helpers (no I/O). Run: npm test

const { test } = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");

const {
  verifyWebhookSignature,
  mapWasalToLibskStatus,
  normalizeKuwaitPhone,
  matchBlockId,
  findMatchingAddress,
  resolveZoneFee,
  overallDeliveryStatus,
  WASAL_TERMINAL_STATUSES,
} = require("../wasal");

// ── verifyWebhookSignature ────────────────────────────────────────────────────

function sign(body, secret) {
  return "sha256=" + crypto.createHmac("sha256", secret).update(body).digest("hex");
}

test("accepts a valid signature", () => {
  const body = Buffer.from(JSON.stringify({ event: "ping" }));
  assert.equal(verifyWebhookSignature(body, "s3cret", sign(body, "s3cret")), true);
});

test("rejects a signature made with the wrong secret", () => {
  const body = Buffer.from("{}");
  assert.equal(verifyWebhookSignature(body, "right", sign(body, "wrong")), false);
});

test("rejects a tampered body", () => {
  const body = Buffer.from('{"status":"delivered"}');
  const sig = sign(body, "s");
  assert.equal(verifyWebhookSignature(Buffer.from('{"status":"cancelled"}'), "s", sig), false);
});

test("rejects malformed / missing signature input without throwing", () => {
  const body = Buffer.from("{}");
  assert.equal(verifyWebhookSignature(body, "s", undefined), false);
  assert.equal(verifyWebhookSignature(body, "s", ""), false);
  assert.equal(verifyWebhookSignature(body, "s", "sha256=short"), false);
  assert.equal(verifyWebhookSignature(null, "s", sign(body, "s")), false);
  assert.equal(verifyWebhookSignature(body, "", sign(body, "")), false);
});

// ── mapWasalToLibskStatus ─────────────────────────────────────────────────────

test("physical progress advances the LIBSK status", () => {
  assert.equal(mapWasalToLibskStatus("picked_up"), "On the Way");
  assert.equal(mapWasalToLibskStatus("in_transit"), "On the Way");
  assert.equal(mapWasalToLibskStatus("delivered"), "Delivered");
});

test("pre-pickup and terminal-failure statuses never change the LIBSK status", () => {
  for (const s of ["draft", "pending", "assigned", "on_way_to_merchant",
    "cancelled", "failed", "returned", "", "garbage"]) {
    assert.equal(mapWasalToLibskStatus(s), null, s);
  }
});

// ── normalizeKuwaitPhone ──────────────────────────────────────────────────────

test("prefixes +965 for 8-digit Kuwait numbers", () => {
  assert.equal(normalizeKuwaitPhone("50001234"), "+96550001234");
  assert.equal(normalizeKuwaitPhone("5000 1234"), "+96550001234");
});

test("keeps existing country codes", () => {
  assert.equal(normalizeKuwaitPhone("+96550001234"), "+96550001234");
  assert.equal(normalizeKuwaitPhone("96550001234"), "+96550001234");
  assert.equal(normalizeKuwaitPhone("+971501234567"), "+971501234567");
});

test("rejects undialable input", () => {
  assert.equal(normalizeKuwaitPhone(""), null);
  assert.equal(normalizeKuwaitPhone("abc"), null);
  assert.equal(normalizeKuwaitPhone("123"), null);
  assert.equal(normalizeKuwaitPhone(null), null);
});

// ── matchBlockId ──────────────────────────────────────────────────────────────

const blocks = [
  { sourceId: "B4", title: { en: "4", ar: "٤" } },
  { sourceId: "B12", title: { en: "Block 12", ar: "قطعة 12" } },
];

test("matches plain, zero-padded, and 'Block N' input against PACI titles", () => {
  assert.equal(matchBlockId(blocks, "4"), "B4");
  assert.equal(matchBlockId(blocks, "04"), "B4");
  assert.equal(matchBlockId(blocks, "Block 4"), "B4");
  assert.equal(matchBlockId(blocks, "12"), "B12");
  assert.equal(matchBlockId(blocks, "قطعة 12"), "B12");
});

test("returns null when the block is unknown or input unusable", () => {
  assert.equal(matchBlockId(blocks, "99"), null);
  assert.equal(matchBlockId(blocks, ""), null);
  assert.equal(matchBlockId(undefined, "4"), null);
});

// ── findMatchingAddress ───────────────────────────────────────────────────────

const wasalAddr = (over = {}) => ({
  _id: "a1", governorateId: "G1", neighborhoodId: "N1", blockId: "4",
  houseNumber: "8", floorNumber: "", apartmentNumber: "", ...over,
});

test("matches an identical address ignoring case/whitespace", () => {
  const target = { governorateId: "g1", neighborhoodId: "N1 ", blockId: "4",
    houseNumber: "8", floorNumber: "", apartmentNumber: "" };
  assert.equal(findMatchingAddress([wasalAddr()], target)._id, "a1");
});

test("does not match when a distinguishing field differs", () => {
  const target = { governorateId: "G1", neighborhoodId: "N1", blockId: "4",
    houseNumber: "9", floorNumber: "", apartmentNumber: "" };
  assert.equal(findMatchingAddress([wasalAddr()], target), null);
});

test("handles missing address arrays", () => {
  assert.equal(findMatchingAddress(undefined, {}), null);
});

// ── resolveZoneFee ────────────────────────────────────────────────────────────

// Real record shape captured from the live sandbox /pricing response.
const realZone = (over = {}) => ({
  _id: "6a22b75e336bac72084059dc",
  deliveryPartnerId: "69ca0ec1ba04fea7a5a780d1",
  merchantId: "6a1c5a4965d0d1382152be44",
  branchId: null,
  destinationGovernorateId: "G-JAHRA",
  neighborhoodId: null,
  deliveryFee: 1.2,
  serviceType: "b2c",
  destinationGovernorateNameEn: "Jahra",
  ...over,
});

test("matches a governorate-wide zone (real sandbox shape)", () => {
  const pricing = { list: [realZone()] };
  assert.equal(resolveZoneFee(pricing, { governorateId: "G-JAHRA", neighborhoodId: "N-1" }), 1.2);
});

test("specific neighborhood zone beats the governorate-wide zone", () => {
  const pricing = { list: [
    realZone(),
    realZone({ neighborhoodId: "N-1", deliveryFee: 2.5 }),
  ] };
  assert.equal(resolveZoneFee(pricing, { governorateId: "G-JAHRA", neighborhoodId: "N-1" }), 2.5);
  // Other neighborhoods in the governorate still get the general fee.
  assert.equal(resolveZoneFee(pricing, { governorateId: "G-JAHRA", neighborhoodId: "N-2" }), 1.2);
});

test("a neighborhood-restricted zone never prices other governorate areas", () => {
  const pricing = { list: [realZone({ neighborhoodId: "N-9" })] };
  assert.equal(resolveZoneFee(pricing, { governorateId: "G-JAHRA", neighborhoodId: "N-1" }), null);
});

test("returns null when nothing matches or payload is unusable", () => {
  assert.equal(resolveZoneFee({ list: [] }, { governorateId: "G", neighborhoodId: "N" }), null);
  assert.equal(resolveZoneFee(null, { governorateId: "G", neighborhoodId: "N" }), null);
  assert.equal(resolveZoneFee({ list: [realZone({ destinationGovernorateId: "OTHER" })] },
    { governorateId: "G", neighborhoodId: "N" }), null);
});

// ── overallDeliveryStatus ─────────────────────────────────────────────────────

test("Delivered only when every delivery is delivered", () => {
  assert.equal(overallDeliveryStatus({ a: "delivered", b: "delivered" }), "Delivered");
  assert.equal(overallDeliveryStatus({ a: "delivered", b: "in_transit" }), null);
  assert.equal(overallDeliveryStatus({}), null);
  assert.equal(overallDeliveryStatus(undefined), null);
});

// ── constants sanity ──────────────────────────────────────────────────────────

test("terminal statuses cover the documented set", () => {
  assert.deepEqual([...WASAL_TERMINAL_STATUSES].sort(),
    ["cancelled", "delivered", "failed", "returned"]);
});
