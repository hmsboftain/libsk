"use strict";

// Unit tests for the pure Payzah commission mapping in ../payzah_commission.js.
// Run with `npm test` (functions/) — Node's built-in runner, no deps. These
// exercise the REAL module initializePayzahPayment calls, so a green run means
// the Firestore -> Payzah field mapping and the fallback that protects checkout
// both hold.

const { test } = require("node:test");
const assert = require("node:assert/strict");

const {
  DEFAULT_COMMISSION,
  buildPayzahCommissionFields,
  PAYZAH_FEE_SCHEDULE,
  feeForPaymentType,
  calculateNetCommission,
} = require("../payzah_commission");

// ── boutique WITH commission fields set ───────────────────────────────────────

test("boutique with all fields set: maps camelCase -> snake_case, no fallback", () => {
  const res = buildPayzahCommissionFields({
    commissionType: 2,
    commissionPercent: 15,
    commissionFixed: 0,
    // unrelated fields are ignored
    name: "Some Boutique",
    foundingPartner: false,
  });
  assert.deepEqual(res.fields, {
    commission_type: 2,
    commission_percent: 15,
    commission_fixed: 0,
  });
  assert.equal(res.usedFallback, false);
  assert.deepEqual(res.missingFields, []);
});

test("founding-partner rate (type 2, 12%) passes through unchanged", () => {
  const res = buildPayzahCommissionFields({
    commissionType: 2,
    commissionPercent: 12,
    commissionFixed: 0,
  });
  assert.deepEqual(res.fields, {
    commission_type: 2,
    commission_percent: 12,
    commission_fixed: 0,
  });
  assert.equal(res.usedFallback, false);
});

test("fixed (type 1) and mixed (type 3) commission types are honored", () => {
  const fixed = buildPayzahCommissionFields({
    commissionType: 1,
    commissionPercent: 0,
    commissionFixed: 2.5,
  });
  assert.deepEqual(fixed.fields, {
    commission_type: 1,
    commission_percent: 0,
    commission_fixed: 2.5,
  });
  assert.equal(fixed.usedFallback, false);

  const mixed = buildPayzahCommissionFields({
    commissionType: 3,
    commissionPercent: 10,
    commissionFixed: 1,
  });
  assert.deepEqual(mixed.fields, {
    commission_type: 3,
    commission_percent: 10,
    commission_fixed: 1,
  });
  assert.equal(mixed.usedFallback, false);
});

test("numeric strings from Firestore are coerced to numbers", () => {
  const res = buildPayzahCommissionFields({
    commissionType: "2",
    commissionPercent: "15",
    commissionFixed: "0",
  });
  assert.deepEqual(res.fields, {
    commission_type: 2,
    commission_percent: 15,
    commission_fixed: 0,
  });
  assert.equal(res.usedFallback, false);
});

// ── boutique MISSING commission fields (fallback path) ────────────────────────

test("completely missing config (null) falls back to every default", () => {
  const res = buildPayzahCommissionFields(null);
  assert.deepEqual(res.fields, {
    commission_type: DEFAULT_COMMISSION.commissionType,
    commission_percent: DEFAULT_COMMISSION.commissionPercent,
    commission_fixed: DEFAULT_COMMISSION.commissionFixed,
  });
  assert.equal(res.usedFallback, true);
  assert.deepEqual(
    res.missingFields.sort(),
    ["commissionFixed", "commissionPercent", "commissionType"],
  );
});

test("empty object (legacy boutique with no commission fields) falls back", () => {
  const res = buildPayzahCommissionFields({ name: "Legacy Boutique" });
  assert.equal(res.fields.commission_type, DEFAULT_COMMISSION.commissionType);
  assert.equal(res.fields.commission_percent, DEFAULT_COMMISSION.commissionPercent);
  assert.equal(res.fields.commission_fixed, DEFAULT_COMMISSION.commissionFixed);
  assert.equal(res.usedFallback, true);
});

test("partial config falls back only for the missing field", () => {
  const res = buildPayzahCommissionFields({
    commissionType: 2,
    commissionPercent: 15,
    // commissionFixed missing
  });
  assert.equal(res.fields.commission_type, 2);
  assert.equal(res.fields.commission_percent, 15);
  assert.equal(res.fields.commission_fixed, DEFAULT_COMMISSION.commissionFixed);
  assert.equal(res.usedFallback, true);
  assert.deepEqual(res.missingFields, ["commissionFixed"]);
});

test("invalid values fall back to defaults (never throw, never break checkout)", () => {
  const badType = buildPayzahCommissionFields({
    commissionType: 9, // not 1/2/3
    commissionPercent: 15,
    commissionFixed: 0,
  });
  assert.equal(badType.fields.commission_type, DEFAULT_COMMISSION.commissionType);
  assert.deepEqual(badType.missingFields, ["commissionType"]);

  const negativePercent = buildPayzahCommissionFields({
    commissionType: 2,
    commissionPercent: -5,
    commissionFixed: 0,
  });
  assert.equal(negativePercent.fields.commission_percent, DEFAULT_COMMISSION.commissionPercent);

  const tooHighPercent = buildPayzahCommissionFields({
    commissionType: 2,
    commissionPercent: 150,
    commissionFixed: 0,
  });
  assert.equal(tooHighPercent.fields.commission_percent, DEFAULT_COMMISSION.commissionPercent);

  const nonNumeric = buildPayzahCommissionFields({
    commissionType: "abc",
    commissionPercent: {},
    commissionFixed: "x",
  });
  assert.equal(nonNumeric.fields.commission_type, DEFAULT_COMMISSION.commissionType);
  assert.equal(nonNumeric.fields.commission_percent, DEFAULT_COMMISSION.commissionPercent);
  assert.equal(nonNumeric.fields.commission_fixed, DEFAULT_COMMISSION.commissionFixed);
  assert.equal(nonNumeric.usedFallback, true);
});

// ── field-name mapping contract (Firestore camelCase -> Payzah snake_case) ────

test("output keys are exactly Payzah's snake_case field names", () => {
  const res = buildPayzahCommissionFields({
    commissionType: 2,
    commissionPercent: 12,
    commissionFixed: 0,
  });
  assert.deepEqual(
    Object.keys(res.fields).sort(),
    ["commission_fixed", "commission_percent", "commission_type"],
  );
  // and NOT the camelCase Firestore names
  assert.equal(res.fields.commissionType, undefined);
  assert.equal(res.fields.commissionPercent, undefined);
  assert.equal(res.fields.commissionFixed, undefined);
});

// ── gateway fee / net commission (internal bookkeeping) ───────────────────────
//
// These exercise calculateNetCommission, which index.js persists on every order
// as gatewayFee + netCommission. Boutique payout must NEVER move with the
// payment method; only netCommission absorbs the gateway fee.

test("fee schedule matches Payzah's published rates per payment_type", () => {
  assert.deepEqual(PAYZAH_FEE_SCHEDULE["1"], { fixedFee: 0.150, percentFee: 0 });   // K-Net
  assert.deepEqual(PAYZAH_FEE_SCHEDULE["2"], { fixedFee: 0.000, percentFee: 2.5 }); // Credit
  assert.deepEqual(PAYZAH_FEE_SCHEDULE["3"], { fixedFee: 0.150, percentFee: 0 });   // Apple Pay (debit-mixed placeholder)
});

test("K-Net (payment_type 1): flat 0.150 fee, no percentage", () => {
  // 10.000 KD merchandise, 13.000 charged (3.000 delivery), 15% commission.
  const r = calculateNetCommission(10, 13, 15, "1");
  assert.equal(r.grossCommission, 1.5);   // 10 * 15%
  assert.equal(r.gatewayFee, 0.15);       // 0.150 fixed + 0%
  assert.equal(r.netCommission, 1.35);    // 1.5 - 0.15
  assert.equal(r.boutiquePayout, 8.5);    // 10 - 1.5 (unaffected by the fee)
});

test("Credit card (payment_type 2): 2.5% of the CHARGED total, no fixed", () => {
  const r = calculateNetCommission(10, 13, 15, "2");
  assert.equal(r.grossCommission, 1.5);
  assert.equal(r.gatewayFee, 0.325);      // 13 * 2.5% (charged total, incl. delivery)
  assert.equal(r.netCommission, 1.175);   // 1.5 - 0.325
  assert.equal(r.boutiquePayout, 8.5);    // identical payout to the K-Net order
});

test("Apple Pay (payment_type 3): debit-mixed placeholder — 0.150 fixed, no percentage", () => {
  const r = calculateNetCommission(10, 13, 15, "3");
  assert.equal(r.gatewayFee, 0.15);
  assert.equal(r.netCommission, 1.35);
  assert.equal(r.boutiquePayout, 8.5);
});

test("boutique payout is identical across all three payment methods", () => {
  const knet = calculateNetCommission(25, 28, 15, "1");
  const card = calculateNetCommission(25, 28, 15, "2");
  const apple = calculateNetCommission(25, 28, 15, "3");
  assert.equal(knet.boutiquePayout, card.boutiquePayout);
  assert.equal(card.boutiquePayout, apple.boutiquePayout);
  assert.equal(knet.boutiquePayout, 21.25); // 25 - (25 * 15%)
  // ...but net commission differs because the gateway fee differs.
  assert.notEqual(knet.netCommission, card.netCommission);
});

test("gateway fee is charged on the full total, commission only on the subtotal", () => {
  // Same 20.000 merchandise, but a bigger delivery/charged total: only the fee
  // (credit) should grow — grossCommission and boutiquePayout must not.
  const small = calculateNetCommission(20, 23, 15, "2");
  const large = calculateNetCommission(20, 40, 15, "2");
  assert.equal(small.grossCommission, large.grossCommission);   // both 3.0
  assert.equal(small.boutiquePayout, large.boutiquePayout);     // both 17.0
  assert.equal(small.gatewayFee, 0.575); // 23 * 2.5%
  assert.equal(large.gatewayFee, 1.0);   // 40 * 2.5%
});

test("varied order totals compute correctly (K-Net + credit)", () => {
  // Small K-Net order: fixed fee dwarfs the commission -> negative net (a real
  // small loss, left un-clamped for honest books).
  const tiny = calculateNetCommission(1, 1, 15, "1");
  assert.equal(tiny.grossCommission, 0.15); // 1 * 15%
  assert.equal(tiny.gatewayFee, 0.15);      // flat
  assert.equal(tiny.netCommission, 0);      // 0.15 - 0.15

  const tinyCredit = calculateNetCommission(1, 1, 15, "2");
  assert.equal(tinyCredit.gatewayFee, 0.025); // 1 * 2.5%
  assert.equal(tinyCredit.netCommission, 0.125);

  // Larger credit order.
  const big = calculateNetCommission(100, 103, 15, "2");
  assert.equal(big.grossCommission, 15);
  assert.equal(big.gatewayFee, 2.575);   // 103 * 2.5%
  assert.equal(big.netCommission, 12.425);
  assert.equal(big.boutiquePayout, 85);
});

test("results are rounded to fils (3 dp)", () => {
  // 7.777 * 15% = 1.16655 -> 1.167 ; charged 7.777 credit fee 0.194425 -> 0.194
  const r = calculateNetCommission(7.777, 7.777, 15, "2");
  assert.equal(r.grossCommission, 1.167);
  assert.equal(r.gatewayFee, 0.194);
  assert.equal(r.netCommission, 0.973); // 1.167 - 0.194
});

test("unknown/absent payment type falls back to the credit-card schedule", () => {
  assert.deepEqual(feeForPaymentType("9"), PAYZAH_FEE_SCHEDULE["2"]);
  assert.deepEqual(feeForPaymentType(undefined), PAYZAH_FEE_SCHEDULE["2"]);
  const r = calculateNetCommission(10, 10, 15, "9");
  assert.equal(r.gatewayFee, 0.25); // 10 * 2.5%
});

test("non-numeric amounts never throw (default to 0)", () => {
  const r = calculateNetCommission(undefined, null, "x", "1");
  assert.equal(r.grossCommission, 0);
  assert.equal(r.gatewayFee, 0.15); // fixed fee still applies
  assert.equal(r.netCommission, -0.15);
  assert.equal(r.boutiquePayout, 0);
});
