"use strict";

// Unit tests for ../payzah_commission.js. Run with `npm test` (functions/) —
// Node's built-in runner, no deps. These exercise the REAL module
// initializePayzahPayment calls, so a green run means: the fee-absorbed vendor
// split (formula, vendor-key lookup, no-fallback failures, exact request body),
// the switched-off merchant-key flow sending exactly the pre-split request, and
// the internal gateway-fee bookkeeping all hold.

const { test } = require("node:test");
const assert = require("node:assert/strict");

const {
  DEFAULT_COMMISSION,
  BOUTIQUE_SECRETS_COLLECTION,
  PayzahVendorSplitConfigError,
  gatewayFeeFils,
  computeVendorSplitCommissionFils,
  buildVendorSplitCommissionFields,
  readCommissionPercent,
  getPayzahVendorKey,
  resolveVendorSplit,
  PAYZAH_AUTH_VENDOR,
  PAYZAH_AUTH_MERCHANT,
  resolvePayzahInitAuth,
  payzahStatusSigningKey,
  buildPayzahInitPayload,
  PAYZAH_FEE_SCHEDULE,
  feeForPaymentType,
  calculateNetCommission,
} = require("../payzah_commission");

// ── gateway fee / net commission (internal bookkeeping) ───────────────────────
//
// These exercise calculateNetCommission, which index.js persists on every order
// as gatewayFee + netCommission. Boutique payout must NEVER move with the
// payment method; only netCommission absorbs the gateway fee.

test("fee schedule matches Payzah's published rates per payment_type", () => {
  assert.deepEqual(PAYZAH_FEE_SCHEDULE["1"], { fixedFee: 0.150, percentFee: 0 });   // K-Net
  assert.deepEqual(PAYZAH_FEE_SCHEDULE["2"], { fixedFee: 0.000, percentFee: 2.5 }); // Credit
  assert.deepEqual(PAYZAH_FEE_SCHEDULE["3"], { fixedFee: 0.150, percentFee: 0 });   // Apple Pay (debit-only)
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

test("Apple Pay (payment_type 3): debit-only — 0.150 fixed, no percentage", () => {
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

// ══════════════════════════════════════════════════════════════════════════════
// FEE-ABSORBED VENDOR SPLIT
// ══════════════════════════════════════════════════════════════════════════════

// Minimal stand-in for the admin SDK: collection(name).doc(id).get() over a
// map of "collection/id" -> data. Records every path read.
function fakeDb(docs) {
  const reads = [];
  return {
    reads,
    collection(name) {
      return {
        doc(id) {
          return {
            async get() {
              reads.push(`${name}/${id}`);
              const data = docs[`${name}/${id}`];
              return { exists: data !== undefined, data: () => data };
            },
          };
        },
      };
    },
  };
}

const VENDOR_KEY = "vk_test_boutique_b1_secret";
const MERCHANT_KEY = "pk_test_libsk_merchant";
// An order attempt as createOrder writes it: amount = subtotal - discount + delivery.
const orderAttempt = (overrides = {}) => ({
  trackid: "LIBSK123", boutiqueIds: ["b1"], payzahPaymentType: "1",
  subtotal: 10, discountAmount: 0, deliveryCost: 2, amount: 12,
  ...overrides,
});
const configuredDb = (overrides = {}) => fakeDb({
  "boutiqueSecrets/b1": { payzahVendorKey: VENDOR_KEY },
  "boutiques/b1": { name: "B1", commissionPercent: 15 },
  ...overrides,
});

// Payzah's settlement of one payment, all in fils, given what we send.
function settle({ subtotalFils, discountFils, deliveryFils, pct, paymentType }) {
  const baseFils = subtotalFils - discountFils;
  const amountFils = baseFils + deliveryFils;
  const feeFils = gatewayFeeFils(paymentType, amountFils);
  const commissionFils = computeVendorSplitCommissionFils({ baseFils, deliveryFils, feeFils, commissionPercent: pct });
  return { baseFils, amountFils, feeFils, commissionFils, vendorNetFils: amountFils - feeFils - commissionFils };
}

// ── gateway fee: per method, not a flat constant ──────────────────────────────

test("gateway fee: K-Net and Apple Pay 150 fils flat, whatever the amount", () => {
  for (const amountFils of [500, 10000, 12000, 250000]) {
    assert.equal(gatewayFeeFils("1", amountFils), 150);
    assert.equal(gatewayFeeFils("3", amountFils), 150);
  }
});

test("gateway fee: card ('2', what checkout's 'Card' maps to) is 2.5% of the charged amount", () => {
  assert.equal(gatewayFeeFils("2", 10000), 250);
  assert.equal(gatewayFeeFils("2", 12000), 300);
  assert.equal(gatewayFeeFils("2", 7650), 191);   // 191.25 -> 191
  assert.equal(gatewayFeeFils("2", 500), 13);     // 12.5 -> 13
});

test("gateway fee is read from PAYZAH_FEE_SCHEDULE (one table for split + bookkeeping)", () => {
  for (const type of ["1", "2", "3"]) {
    const f = PAYZAH_FEE_SCHEDULE[type];
    assert.equal(gatewayFeeFils(type, 12000), Math.round(f.fixedFee * 1000) + Math.round(12000 * f.percentFee / 100));
  }
  assert.equal(gatewayFeeFils(undefined, 12000), 300); // unknown -> card schedule, as feeForPaymentType
});

// ── the split: commission on (subtotal - discount), delivery to LIBSK ─────────

test("K-Net, 10.000 + 2.000 delivery at 15%: LIBSK 3.350, boutique 8.500, Payzah 0.150", () => {
  const r = settle({ subtotalFils: 10000, discountFils: 0, deliveryFils: 2000, pct: 15, paymentType: "1" });
  assert.equal(r.commissionFils, 3350); // 1.500 - 0.150 + 2.000
  assert.equal(r.vendorNetFils, 8500);  // 10.000 x 0.85 — none of the delivery
  assert.equal(r.feeFils, 150);
  assert.equal(r.commissionFils - 2000, 1350); // what LIBSK keeps after paying Wasal
});

test("delivery never reaches the boutique: its payout is identical at any delivery fee", () => {
  for (const deliveryFils of [0, 1000, 2000, 3500, 6000]) {
    const r = settle({ subtotalFils: 10000, discountFils: 0, deliveryFils, pct: 15, paymentType: "1" });
    assert.equal(r.vendorNetFils, 8500, `delivery ${deliveryFils}`);
  }
});

test("a discount comes off the subtotal before EITHER cut", () => {
  // 10.000 - 1.000 discount + 2.000 delivery at 15%: base 9.000
  const r = settle({ subtotalFils: 10000, discountFils: 1000, deliveryFils: 2000, pct: 15, paymentType: "1" });
  assert.equal(r.vendorNetFils, 7650);  // 9.000 x 0.85 (not 10.000 x 0.85 - 1.000)
  assert.equal(r.commissionFils, 3200); // 9.000 x 0.15 - 0.150 + 2.000
  // Both sides shrink by their share of the discount: boutique 0.850, LIBSK 0.150.
  const none = settle({ subtotalFils: 10000, discountFils: 0, deliveryFils: 2000, pct: 15, paymentType: "1" });
  assert.equal(none.vendorNetFils - r.vendorNetFils, 850);
  assert.equal(none.commissionFils - r.commissionFils, 150);
});

test("card: the 2.5% fee comes out of LIBSK's cut, not the boutique's payout", () => {
  const r = settle({ subtotalFils: 10000, discountFils: 0, deliveryFils: 2000, pct: 15, paymentType: "2" });
  assert.equal(r.feeFils, 300);          // 2.5% of the 12.000 charged
  assert.equal(r.commissionFils, 3200);  // 1.500 - 0.300 + 2.000
  assert.equal(r.vendorNetFils, 8500);   // unchanged vs K-Net
});

test("Apple Pay settles exactly like K-Net", () => {
  const knet = settle({ subtotalFils: 13000, discountFils: 500, deliveryFils: 2000, pct: 12, paymentType: "1" });
  const apple = settle({ subtotalFils: 13000, discountFils: 500, deliveryFils: 2000, pct: 12, paymentType: "3" });
  assert.deepEqual(apple, knet);
});

test("identity across a grid: boutique nets base x (1 - rate); amount = boutique + LIBSK + Payzah", () => {
  for (const subtotalFils of [1000, 7500, 10000, 13000, 45250]) {
    for (const discountFils of [0, 500, 1000]) {
      for (const deliveryFils of [0, 1500, 3000]) {
        for (const pct of [12, 15]) {
          for (const paymentType of ["1", "2", "3"]) {
            const r = settle({ subtotalFils, discountFils, deliveryFils, pct, paymentType });
            const label = JSON.stringify({ subtotalFils, discountFils, deliveryFils, pct, paymentType });
            assert.equal(r.vendorNetFils + r.commissionFils + r.feeFils, r.amountFils, label);
            if (r.commissionFils > 0) {
              assert.equal(r.vendorNetFils, r.baseFils - Math.round((r.baseFils * pct) / 100), label);
            }
            assert.ok(Number.isInteger(r.commissionFils) && r.commissionFils >= 0, label);
          }
        }
      }
    }
  }
});

test("floor at zero: base x rate + delivery at or below the fee sends 0, never a negative", () => {
  // Made to Order (no delivery) small orders are the only realistic case.
  assert.equal(computeVendorSplitCommissionFils({ baseFils: 1000, deliveryFils: 0, feeFils: 150, commissionPercent: 15 }), 0); // exactly the fee
  assert.equal(computeVendorSplitCommissionFils({ baseFils: 1250, deliveryFils: 0, feeFils: 150, commissionPercent: 12 }), 0); // exactly the fee
  assert.equal(computeVendorSplitCommissionFils({ baseFils: 500, deliveryFils: 0, feeFils: 150, commissionPercent: 15 }), 0);
  assert.equal(computeVendorSplitCommissionFils({ baseFils: 1255, deliveryFils: 0, feeFils: 150, commissionPercent: 12 }), 1);
});

test("floor at zero: the boutique still bears the fee LIBSK's zero cut can't cover", () => {
  // 0.500 KWD Made to Order at 15% by K-Net: fair share 0.425, boutique nets 0.350.
  const r = settle({ subtotalFils: 500, discountFils: 0, deliveryFils: 0, pct: 15, paymentType: "1" });
  assert.equal(r.commissionFils, 0);
  assert.equal(r.vendorNetFils, 350);
});

test("delivery keeps a small order off the floor — the boutique still nets its exact share", () => {
  const r = settle({ subtotalFils: 500, discountFils: 0, deliveryFils: 2000, pct: 15, paymentType: "1" });
  assert.equal(r.commissionFils, 1925); // 0.075 - 0.150 + 2.000
  assert.equal(r.vendorNetFils, 425);   // 0.500 x 0.85
});

test("commission fields: fixed type, 3-dp KWD string, percent zeroed — nothing else", () => {
  assert.deepEqual(buildVendorSplitCommissionFields(3350), {
    commission_type: "1", commission_fixed: "3.350", commission_percent: "0",
  });
  assert.equal(buildVendorSplitCommissionFields(0).commission_fixed, "0.000");
  assert.equal(buildVendorSplitCommissionFields(1).commission_fixed, "0.001");
});

test("readCommissionPercent: numbers 0-100 only, and NO default", () => {
  assert.equal(readCommissionPercent({ commissionPercent: 15 }), 15);
  assert.equal(readCommissionPercent({ commissionPercent: 12 }), 12);
  assert.equal(readCommissionPercent({ commissionPercent: "12" }), 12);
  assert.equal(readCommissionPercent({ commissionPercent: 0 }), 0);
  for (const bad of [undefined, null, "", "abc", -1, 101, NaN, Infinity]) {
    assert.equal(readCommissionPercent({ commissionPercent: bad }), null, `commissionPercent: ${bad}`);
  }
  assert.equal(readCommissionPercent({}), null);
  assert.equal(readCommissionPercent(null), null);
});

test("the default commission is the STANDARD 15% (Founding Partner 12% is manual only)", () => {
  assert.equal(DEFAULT_COMMISSION.commissionPercent, 15);
});

// ── vendor key lookup ────────────────────────────────────────────────────────

test("vendor key lookup: reads boutiqueSecrets/{id} and returns the trimmed key", async () => {
  const db = fakeDb({ "boutiqueSecrets/b1": { payzahVendorKey: `  ${VENDOR_KEY}\n` } });
  assert.equal(await getPayzahVendorKey(db, "b1"), VENDOR_KEY);
  assert.equal(BOUTIQUE_SECRETS_COLLECTION, "boutiqueSecrets");
  assert.deepEqual(db.reads, ["boutiqueSecrets/b1"]);
});

test("vendor key lookup: missing doc, blank key, wrong type or no boutiqueId all throw", async () => {
  const cases = [
    [fakeDb({}), "b1"],
    [fakeDb({ "boutiqueSecrets/b1": {} }), "b1"],
    [fakeDb({ "boutiqueSecrets/b1": { payzahVendorKey: "   " } }), "b1"],
    [fakeDb({ "boutiqueSecrets/b1": { payzahVendorKey: 12345 } }), "b1"],
    [fakeDb({}), undefined],
  ];
  for (const [db, boutiqueId] of cases) {
    await assert.rejects(getPayzahVendorKey(db, boutiqueId), PayzahVendorSplitConfigError);
  }
});

// ── resolveVendorSplit: the whole decision for one order payment ─────────────

test("resolveVendorSplit: signs with the VENDOR key and routes delivery to LIBSK", async () => {
  const split = await resolveVendorSplit(configuredDb(), orderAttempt(), "1");
  assert.equal(split.privateKey, VENDOR_KEY);
  assert.notEqual(split.privateKey, MERCHANT_KEY);
  assert.equal(split.boutiqueId, "b1");
  assert.equal(split.baseFils, 10000);
  assert.equal(split.deliveryFils, 2000);
  assert.equal(split.feeFils, 150);
  assert.equal(split.commissionFils, 3350);
  assert.deepEqual(split.fields, { commission_type: "1", commission_fixed: "3.350", commission_percent: "0" });
});

test("resolveVendorSplit: card payment_type picks the 2.5% fee", async () => {
  const split = await resolveVendorSplit(configuredDb(), orderAttempt({ payzahPaymentType: "2" }), "2");
  assert.equal(split.feeFils, 300);
  assert.equal(split.fields.commission_fixed, "3.200");
});

test("resolveVendorSplit: discount and the boutique's own 12% rate", async () => {
  const db = configuredDb({ "boutiques/b1": { commissionPercent: 12 } });
  const attempt = orderAttempt({ subtotal: 13, discountAmount: 1.3, deliveryCost: 2, amount: 13.7 });
  const split = await resolveVendorSplit(db, attempt, "1");
  assert.equal(split.baseFils, 11700);
  assert.equal(split.commissionFils, 1404 - 150 + 2000); // round(11700 x 0.12) = 1404
  assert.equal(split.fields.commission_fixed, "3.254");
});

test("resolveVendorSplit: Made to Order floor case still resolves, commission_fixed 0.000", async () => {
  const attempt = orderAttempt({ subtotal: 0.5, deliveryCost: 0, amount: 0.5 });
  const split = await resolveVendorSplit(configuredDb(), attempt, "1");
  assert.equal(split.commissionFils, 0);
  assert.equal(split.fields.commission_fixed, "0.000");
});

test("resolveVendorSplit: an attempt without the subtotal/discount/delivery breakdown FAILS", async () => {
  for (const missing of ["subtotal", "discountAmount", "deliveryCost"]) {
    const attempt = orderAttempt();
    delete attempt[missing];
    await assert.rejects(resolveVendorSplit(configuredDb(), attempt, "1"), PayzahVendorSplitConfigError, missing);
  }
  await assert.rejects(resolveVendorSplit(configuredDb(), orderAttempt({ deliveryCost: "2" }), "1"), PayzahVendorSplitConfigError);
});

test("resolveVendorSplit: a breakdown that doesn't add up to the charged amount FAILS", async () => {
  // e.g. amount includes something the breakdown doesn't explain
  await assert.rejects(resolveVendorSplit(configuredDb(), orderAttempt({ amount: 12.5 }), "1"), PayzahVendorSplitConfigError);
  // discount larger than the subtotal
  await assert.rejects(resolveVendorSplit(configuredDb(),
    orderAttempt({ subtotal: 1, discountAmount: 2, deliveryCost: 2, amount: 1 }), "1"), PayzahVendorSplitConfigError);
});

test("resolveVendorSplit: a missing vendor key FAILS — it never falls back to another key", async () => {
  const db = fakeDb({ "boutiques/b1": { commissionPercent: 15 } });
  await assert.rejects(resolveVendorSplit(db, orderAttempt(), "1"), (err) => {
    assert.ok(err instanceof PayzahVendorSplitConfigError);
    assert.match(err.message, /no Payzah vendor key/);
    return true;
  });
});

test("resolveVendorSplit: a missing or invalid commission rate FAILS (no default rate)", async () => {
  for (const boutique of [{ name: "no rate" }, { commissionPercent: "abc" }, { commissionPercent: 150 }, undefined]) {
    await assert.rejects(resolveVendorSplit(configuredDb({ "boutiques/b1": boutique }), orderAttempt(), "1"),
      PayzahVendorSplitConfigError);
  }
});

test("resolveVendorSplit: a payment must map to exactly one boutique", async () => {
  for (const boutiqueIds of [[], ["b1", "b2"], undefined]) {
    await assert.rejects(resolveVendorSplit(configuredDb(), orderAttempt({ boutiqueIds }), "1"), PayzahVendorSplitConfigError);
  }
});

test("resolveVendorSplit: a non-positive or non-numeric amount FAILS", async () => {
  for (const amount of [0, -5, "abc", undefined]) {
    await assert.rejects(resolveVendorSplit(configuredDb(), orderAttempt({ amount }), "1"), PayzahVendorSplitConfigError);
  }
});

// ── the request body Payzah receives ─────────────────────────────────────────

const payloadArgs = (commissionFields) => ({
  trackid: "LIBSK123", amount: 12, currency: "414", paymentType: "1", language: "ENG",
  redirectUrl: "https://example.test/payzahRedirect",
  customerName: "Customer", customerEmail: "c@example.com", customerPhone: "",
  commissionFields,
});

test("vendor-split body has EXACTLY the expected fields — no vendor identifier", async () => {
  const split = await resolveVendorSplit(configuredDb(), orderAttempt(), "1");
  const body = buildPayzahInitPayload(payloadArgs(split.fields));
  assert.deepEqual(Object.keys(body).sort(), [
    "amount", "commission_fixed", "commission_percent", "commission_type", "currency",
    "customer_email", "customer_name", "customer_phone", "error_url", "language",
    "payment_type", "success_url", "trackid",
  ]);
  assert.equal(body.amount, "12.000");          // the full charge, delivery included
  assert.equal(body.commission_type, "1");
  assert.equal(body.commission_fixed, "3.350"); // LIBSK's cut incl. the delivery pass-through
  assert.equal(body.commission_percent, "0");   // never a non-zero percent alongside the fixed cut
  for (const key of Object.keys(body)) {
    assert.doesNotMatch(key, /vendor|merchant|beneficiary|delivery|subtotal|discount/i, `unexpected field "${key}"`);
  }
  assert.ok(!JSON.stringify(body).includes(VENDOR_KEY)); // routing is the Authorization header
});

test("body formats amount to 3 dp and normalises language", () => {
  const body = buildPayzahInitPayload({ ...payloadArgs(null), amount: 11.25, language: "fr" });
  assert.equal(body.amount, "11.250");
  assert.equal(body.language, "ENG");
  assert.equal(buildPayzahInitPayload({ ...payloadArgs(null), language: "ARA" }).language, "ARA");
});

test("promo-booking body (no commission fields) carries no commission_* keys at all", () => {
  const body = buildPayzahInitPayload(payloadArgs(null));
  assert.equal(Object.keys(body).filter((k) => k.startsWith("commission_")).length, 0);
});

// ── status checks sign with the account that initialized the payment ─────────
//
// Payzah's merchant and vendor accounts are separate scopes: a vendor payment is
// visible ONLY to that vendor's key (the merchant key gets 10012 "No Record
// found"). So the key a status check uses must equal the key init used, on
// every path.

// initializePayzahPayment's key choice (the real resolvePayzahInitAuth).
// Returns the mode, the key init signs with, and `stored`: the attempt as it is
// stored afterwards, i.e. with whatever init writes before the gateway call.
// Status checks run against `stored`, as they do in production.
async function initSigning(db, attempt, vendorSplitEnabled) {
  const auth = await resolvePayzahInitAuth(db, attempt, {
    vendorSplitEnabled, merchantKey: MERCHANT_KEY, paymentType: "1",
  });
  return { mode: auth.mode, key: auth.privateKey, stored: { ...attempt, ...(auth.attemptFields || {}) } };
}
const promoAttempt = (overrides = {}) => ({
  kind: "promo_booking", boutiqueId: "b1", trackid: "LIBSKP1", amount: 21, payzahPaymentType: "1",
  ...overrides,
});

test("vendor-split order: the status check signs with the SAME vendor key that initialized it", async () => {
  const db = configuredDb();
  const init = await initSigning(db, orderAttempt(), true);
  assert.equal(init.mode, PAYZAH_AUTH_VENDOR);
  assert.equal(init.key, VENDOR_KEY);
  assert.equal(init.stored.payzahAuthMode, PAYZAH_AUTH_VENDOR); // recorded before the gateway call
  const statusKey = await payzahStatusSigningKey(db, init.stored, MERCHANT_KEY);
  assert.equal(statusKey, init.key);
  assert.notEqual(statusKey, MERCHANT_KEY); // the merchant key can't see a vendor payment
});

test("vendor-split order: status looks the key up exactly as init does (same boutique, same doc)", async () => {
  const initDb = configuredDb();
  await initSigning(initDb, orderAttempt(), true);
  const statusDb = configuredDb();
  await payzahStatusSigningKey(statusDb, { ...orderAttempt(), payzahAuthMode: PAYZAH_AUTH_VENDOR }, MERCHANT_KEY);
  assert.ok(initDb.reads.includes("boutiqueSecrets/b1"));
  assert.deepEqual(statusDb.reads, ["boutiqueSecrets/b1"]);
});

test("promo booking: merchant key at init AND at status — even with the split on and a vendor key on file", async () => {
  const db = configuredDb(); // boutique b1 HAS a vendor key; the promo must still ignore it
  for (const splitOn of [true, false]) {
    const init = await initSigning(db, promoAttempt(), splitOn);
    assert.equal(init.mode, PAYZAH_AUTH_MERCHANT);
    assert.equal(init.key, MERCHANT_KEY);
    assert.deepEqual(init.stored, promoAttempt()); // nothing written on the attempt
    const statusKey = await payzahStatusSigningKey(db, init.stored, MERCHANT_KEY);
    assert.equal(statusKey, init.key);
  }
  assert.deepEqual(db.reads, []); // the boutique's vendor key is never even read
});

test("split-off order: merchant key at init AND at status, nothing read or written", async () => {
  const db = configuredDb();
  const init = await initSigning(db, orderAttempt(), false);
  assert.equal(init.mode, PAYZAH_AUTH_MERCHANT);
  assert.deepEqual(init.stored, orderAttempt()); // the attempt doc is left exactly as createOrder wrote it
  const statusKey = await payzahStatusSigningKey(db, init.stored, MERCHANT_KEY);
  assert.equal(statusKey, MERCHANT_KEY);
  assert.equal(statusKey, init.key);
  assert.deepEqual(db.reads, []); // no boutique or vendor-key lookup at all
});

test("every path: status key === init key (table)", async () => {
  const cases = [
    { label: "order, split on", attempt: orderAttempt(), splitOn: true, want: VENDOR_KEY },
    { label: "order, split off", attempt: orderAttempt(), splitOn: false, want: MERCHANT_KEY },
    { label: "promo, split on", attempt: promoAttempt(), splitOn: true, want: MERCHANT_KEY },
    { label: "promo, split off", attempt: promoAttempt(), splitOn: false, want: MERCHANT_KEY },
  ];
  for (const c of cases) {
    const db = configuredDb();
    const init = await initSigning(db, c.attempt, c.splitOn);
    const statusKey = await payzahStatusSigningKey(db, init.stored, MERCHANT_KEY);
    assert.equal(init.key, c.want, c.label);
    assert.equal(statusKey, init.key, c.label);
  }
});

test("attempt with no payzahAuthMode (pre-split, or merchant-signed): merchant", async () => {
  const db = configuredDb();
  for (const mode of [undefined, null]) {
    assert.equal(await payzahStatusSigningKey(db, { ...orderAttempt(), payzahAuthMode: mode }, MERCHANT_KEY), MERCHANT_KEY);
  }
});

test("vendor payment whose vendor key is gone: the status check FAILS — never the merchant key", async () => {
  const db = fakeDb({ "boutiques/b1": { commissionPercent: 15 } }); // no boutiqueSecrets/b1
  await assert.rejects(
    payzahStatusSigningKey(db, { ...orderAttempt(), payzahAuthMode: PAYZAH_AUTH_VENDOR }, MERCHANT_KEY),
    PayzahVendorSplitConfigError,
  );
});

test("vendor payment on a multi-boutique attempt: status refuses, exactly like init", async () => {
  const attempt = { ...orderAttempt({ boutiqueIds: ["b1", "b2"] }), payzahAuthMode: PAYZAH_AUTH_VENDOR };
  await assert.rejects(payzahStatusSigningKey(configuredDb(), attempt, MERCHANT_KEY), PayzahVendorSplitConfigError);
  await assert.rejects(resolveVendorSplit(configuredDb(), attempt, "1"), PayzahVendorSplitConfigError);
});

test("unknown payzahAuthMode: the status check refuses to guess", async () => {
  await assert.rejects(
    payzahStatusSigningKey(configuredDb(), { ...orderAttempt(), payzahAuthMode: "Vendor" }, MERCHANT_KEY),
    PayzahVendorSplitConfigError,
  );
});

test("split switched OFF between retries of a vendor attempt: rewritten to merchant, status follows", async () => {
  const db = configuredDb();
  const first = await initSigning(db, orderAttempt(), true);
  assert.equal(first.stored.payzahAuthMode, PAYZAH_AUTH_VENDOR);
  const retry = await initSigning(db, first.stored, false); // the customer retries the same pending attempt
  assert.equal(retry.key, MERCHANT_KEY);
  assert.equal(retry.stored.payzahAuthMode, PAYZAH_AUTH_MERCHANT); // not left saying "vendor"
  assert.equal(await payzahStatusSigningKey(db, retry.stored, MERCHANT_KEY), MERCHANT_KEY);
});

test("split switched ON between retries of a merchant attempt: recorded as vendor, status follows", async () => {
  const db = configuredDb();
  const first = await initSigning(db, orderAttempt(), false);
  assert.equal(first.stored.payzahAuthMode, undefined);
  const retry = await initSigning(db, first.stored, true);
  assert.equal(retry.stored.payzahAuthMode, PAYZAH_AUTH_VENDOR);
  assert.equal(await payzahStatusSigningKey(db, retry.stored, MERCHANT_KEY), VENDOR_KEY);
});

// ══════════════════════════════════════════════════════════════════════════════
// SPLIT SWITCHED OFF = EXACTLY THE PRE-SPLIT REQUEST
// ══════════════════════════════════════════════════════════════════════════════
//
// With PAYZAH_VENDOR_SPLIT_ENABLED=false, initializePayzahPayment must send
// Payzah exactly what it sent before the vendor split existed.
//
// PRE_SPLIT_BODY pins that body: what initializePayzahPayment sent as deployed
// on 2026-09-06 (functions/index.js at 63eebf1), for payloadArgs' inputs,
// serialised the way callPayzah sends it (JSON.stringify). JSON.stringify keeps
// insertion order, so key order is pinned too.
const PRE_SPLIT_BODY =
  "{\"trackid\":\"LIBSK123\",\"amount\":\"12.000\",\"currency\":\"414\",\"payment_type\":\"1\"," +
  "\"language\":\"ENG\",\"success_url\":\"https://example.test/payzahRedirect\"," +
  "\"error_url\":\"https://example.test/payzahRedirect\",\"customer_name\":\"Customer\"," +
  "\"customer_email\":\"c@example.com\",\"customer_phone\":\"\"}";

// The pre-split body for any inputs, built field for field the way that code
// built it.
function preSplitBody(a) {
  return {
    trackid: String(a.trackid),
    amount: Number(a.amount).toFixed(3),
    currency: a.currency,
    payment_type: a.paymentType,
    language: a.language === "ARA" ? "ARA" : "ENG",
    success_url: a.redirectUrl,
    error_url: a.redirectUrl,
    customer_name: a.customerName,
    customer_email: a.customerEmail,
    customer_phone: a.customerPhone,
  };
}

// initializePayzahPayment's body: resolvePayzahInitAuth, then
// buildPayzahInitPayload with its commission fields, chained as index.js does.
async function initBody(db, attempt, vendorSplitEnabled, args = payloadArgs(null)) {
  const auth = await resolvePayzahInitAuth(db, attempt, {
    vendorSplitEnabled, merchantKey: MERCHANT_KEY, paymentType: args.paymentType,
  });
  return { auth, body: buildPayzahInitPayload({ ...args, commissionFields: auth.commissionFields }) };
}

test("split OFF: an order's body is byte-identical to the pre-split body", async () => {
  const { auth, body } = await initBody(configuredDb(), orderAttempt(), false);
  assert.equal(JSON.stringify(body), PRE_SPLIT_BODY);
  assert.equal(JSON.stringify(preSplitBody(payloadArgs(null))), PRE_SPLIT_BODY); // the builder matches the pin
  assert.equal(auth.privateKey, MERCHANT_KEY);
  assert.equal(auth.commissionFields, null);
  assert.equal(auth.attemptFields, null);
});

test("split OFF: pre-split body for every payment type, language, amount, trackid and customer", async () => {
  let checked = 0;
  for (const paymentType of ["1", "2", "3"]) {
    for (const language of ["ENG", "ARA", undefined, "fr"]) {
      for (const [trackid, amount] of [["LIBSK123", 12], [100057, 11.25], ["LIBSK9", 0.5], ["LIBSK10", 1234.5678]]) {
        for (const [customerName, customerEmail, customerPhone] of [
          ["Customer", "c@example.com", ""],
          ["نورة", "", "50000000"],
        ]) {
          const args = {
            ...payloadArgs(null), paymentType, language, trackid, amount, customerName, customerEmail, customerPhone,
          };
          const attempt = orderAttempt({ payzahPaymentType: paymentType, trackid, amount });
          const { body } = await initBody(configuredDb(), attempt, false, args);
          assert.equal(JSON.stringify(body), JSON.stringify(preSplitBody(args)), JSON.stringify(args));
          checked++;
        }
      }
    }
  }
  assert.equal(checked, 96);
});

test("split OFF: no commission fields, whatever the boutique's commission config says", async () => {
  const boutiques = [
    {}, // no commission fields at all (BasicsByGlamour on 2026-09-16)
    { commissionPercent: 12 },
    { commissionType: 2, commissionPercent: 15, commissionFixed: 0 },
    { commissionType: 1, commissionPercent: 0, commissionFixed: 1.5 },
  ];
  for (const boutique of boutiques) {
    const { body } = await initBody(configuredDb({ "boutiques/b1": boutique }), orderAttempt(), false);
    assert.deepEqual(Object.keys(body).filter((k) => k.startsWith("commission")), [], JSON.stringify(boutique));
    assert.equal(JSON.stringify(body), PRE_SPLIT_BODY);
  }
});

test("split OFF: a boutique that isn't set up at all still pays, and nothing is read from Firestore", async () => {
  const db = fakeDb({}); // no boutique doc and no vendor key
  const { auth, body } = await initBody(db, orderAttempt(), false);
  assert.equal(JSON.stringify(body), PRE_SPLIT_BODY);
  assert.deepEqual(db.reads, []);
  assert.equal(auth.attemptFields, null);
});

test("split OFF: attempts the split would refuse still go through, as they did pre-split", async () => {
  const attempts = [
    orderAttempt({ boutiqueIds: ["b1", "b2"] }), // multi-boutique
    orderAttempt({ subtotal: undefined, discountAmount: undefined, deliveryCost: undefined }), // no breakdown
    orderAttempt({ subtotal: 99 }), // breakdown doesn't add up
    orderAttempt({ boutiqueIds: undefined }), // no boutique at all
  ];
  for (const attempt of attempts) {
    const { auth, body } = await initBody(fakeDb({}), attempt, false);
    assert.equal(auth.privateKey, MERCHANT_KEY);
    assert.equal(JSON.stringify(body), PRE_SPLIT_BODY);
  }
});

test("promo booking: the pre-split body with the split on or off", async () => {
  for (const splitOn of [true, false]) {
    const db = configuredDb();
    const { auth, body } = await initBody(db, promoAttempt(), splitOn);
    assert.equal(JSON.stringify(body), PRE_SPLIT_BODY);
    assert.equal(auth.privateKey, MERCHANT_KEY);
    assert.equal(auth.attemptFields, null);
    assert.deepEqual(db.reads, []);
  }
});

test("split ON differs from the pre-split body only by the three commission fields", async () => {
  const { body } = await initBody(configuredDb(), orderAttempt(), true);
  const { commission_type: t, commission_fixed: f, commission_percent: p, ...rest } = body;
  assert.deepEqual([t, f, p], ["1", "3.350", "0"]);
  assert.equal(JSON.stringify(rest), PRE_SPLIT_BODY);
});

