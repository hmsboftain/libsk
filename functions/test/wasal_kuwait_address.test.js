"use strict";

// Unit tests for wasal.isKuwaitAddress — the pure country gate createOrder uses
// to keep orders inside Wasal's Kuwait-only delivery coverage. Run with
// `npm test` (functions/) — Node's built-in runner, no deps. A green run means
// a known-good Kuwait address still passes and every non-Kuwait / missing shape
// is rejected.

const { test } = require("node:test");
const assert = require("node:assert/strict");

const { isKuwaitAddress } = require("../wasal");

// ── Kuwait addresses that MUST still pass (no regression) ────────────────────

test("Kuwait dropdown address (type:kuwait + Wasal IDs) passes", () => {
  assert.equal(
    isKuwaitAddress({
      type: "kuwait",
      governorate: "Al Asimah",
      area: "Sharq",
      block: "3",
      street: "12",
      house: "5",
      wasalGovernorateId: "gov_1",
      wasalNeighborhoodId: "nb_9",
    }),
    true,
  );
});

test("Legacy free-text Kuwait address (type:kuwait, no Wasal IDs) passes", () => {
  assert.equal(
    isKuwaitAddress({ type: "kuwait", governorate: "Hawalli", block: "1" }),
    true,
  );
});

test("Legacy address with no type at all is treated as Kuwait", () => {
  assert.equal(isKuwaitAddress({ block: "1", street: "2", house: "3" }), true);
});

test("Kuwait address carrying an explicit KW country still passes", () => {
  assert.equal(isKuwaitAddress({ type: "kuwait", countryCode: "KW" }), true);
  assert.equal(isKuwaitAddress({ type: "kuwait", country: "Kuwait" }), true);
});

// ── Non-Kuwait / undeliverable addresses that MUST be rejected ───────────────

test("International address (type:international, non-KW countryCode) is rejected", () => {
  assert.equal(
    isKuwaitAddress({
      type: "international",
      addressLine1: "10 Downing St",
      city: "Riyadh",
      countryCode: "SA",
    }),
    false,
  );
});

test("Kuwait-shaped address with a non-KW country field is rejected", () => {
  assert.equal(isKuwaitAddress({ type: "kuwait", countryCode: "AE" }), false);
  assert.equal(isKuwaitAddress({ type: "kuwait", country: "Bahrain" }), false);
});

test("International-form address is rejected even if countryCode says KW", () => {
  // The international form is only reachable when the selected country is not
  // Kuwait, so a KW countryCode there cannot occur in practice. The type shape
  // rejects it regardless — the safe direction for a can't-happen input.
  assert.equal(isKuwaitAddress({ type: "international", countryCode: "KW" }), false);
});

test("Missing / malformed address is rejected", () => {
  assert.equal(isKuwaitAddress(null), false);
  assert.equal(isKuwaitAddress(undefined), false);
  assert.equal(isKuwaitAddress("Kuwait"), false);
  assert.equal(isKuwaitAddress(42), false);
});

test("countryCode matching is case/whitespace tolerant", () => {
  assert.equal(isKuwaitAddress({ type: "kuwait", countryCode: " kw " }), true);
  assert.equal(isKuwaitAddress({ type: "Kuwait", countryCode: "kuwait" }), true);
  assert.equal(isKuwaitAddress({ type: "INTERNATIONAL", countryCode: "sa" }), false);
});
