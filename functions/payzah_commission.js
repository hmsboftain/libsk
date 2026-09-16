"use strict";

// ================= PAYZAH MULTIVENDOR COMMISSION FIELDS =================
//
// Pure mapping from a boutique's Firestore commission config to the optional
// multivendor fields on Payzah's Initialize Payment request
// (POST /ws/paymentgateway/index). Kept as a standalone, side-effect-free
// module so the mapping + fallback rules are unit-tested directly (see
// test/payzah_commission.test.js) — the initializePayzahPayment onCall handler
// in index.js reads live Firestore and can't be unit-tested as-is.
//
//   Firestore field (camelCase)  ->  Payzah request field (snake_case)
//   commissionType               ->  commission_type    (1 = fixed | 2 = percentage | 3 = mixed)
//   commissionPercent            ->  commission_percent (used when type is 2 or 3)
//   commissionFixed              ->  commission_fixed   (used when type is 1 or 3)
//
// We always send all three fields (type + percent + fixed); an unused field for
// the chosen type (e.g. commission_fixed: 0 when type is 2) is harmless.
//
// IMPORTANT — UNCONFIRMED WITH PAYZAH (as of 2026-09-07):
//   * Nothing in this app wires boutiques to Payzah SUB-MERCHANT accounts (one
//     merchant private key, no per-boutique settlement account / IBAN), so
//     these fields are currently METADATA on the payment record. They do NOT by
//     themselves produce a real payout split — LIBSK still receives 100% and
//     disburses boutiques manually unless/until Payzah registers sub-merchants.
//   * The DIRECTION of commission_percent (does it mean LIBSK's commission cut,
//     or the vendor's retained share?) must be confirmed with Payzah support
//     before this is relied on for money. Do not deploy as a real split without
//     that confirmation.

// Single source of truth for the default commission config, applied when a
// boutique document is missing (or has an invalid value for) a field.
//
// This is intentionally ONE default — NOT 12-vs-15 business logic baked into
// code. Per-boutique rates are set/edited from the superadmin "All Boutiques"
// screen (admin_boutiques_page.dart), which is how rates are adjusted going
// forward without a code change. Keep this value in sync with the Flutter
// onboarding default (boutique_onboarding_page.dart) and the backfill script
// (scripts/backfill-boutique-commission.js).
//
// NOTE: the placeholder rate below is 12 (the figure in the original request).
// Set it to the rate you actually want before running the backfill or shipping.
const DEFAULT_COMMISSION = Object.freeze({
  commissionType: 2, // percentage
  commissionPercent: 12,
  commissionFixed: 0,
});

// Payzah commission_type enum: 1 fixed, 2 percentage, 3 mixed.
const VALID_COMMISSION_TYPES = [1, 2, 3];

// Build the Payzah commission fields from a boutique document's data.
//
// Returns { fields, usedFallback, missingFields }:
//   fields        - { commission_type, commission_percent, commission_fixed } (numbers)
//   usedFallback  - true if any field fell back to DEFAULT_COMMISSION
//   missingFields - the camelCase field names that were missing/invalid
//
// NEVER throws. A missing or malformed value falls back to the default so a
// commission lookup can never break a checkout. Pass null/undefined to get the
// pure defaults.
function buildPayzahCommissionFields(boutiqueData) {
  const data = boutiqueData || {};
  const missingFields = [];

  let commissionType = Number(data.commissionType);
  if (!Number.isFinite(commissionType) || !VALID_COMMISSION_TYPES.includes(commissionType)) {
    commissionType = DEFAULT_COMMISSION.commissionType;
    missingFields.push("commissionType");
  }

  let commissionPercent = Number(data.commissionPercent);
  if (!Number.isFinite(commissionPercent) || commissionPercent < 0 || commissionPercent > 100) {
    commissionPercent = DEFAULT_COMMISSION.commissionPercent;
    missingFields.push("commissionPercent");
  }

  let commissionFixed = Number(data.commissionFixed);
  if (!Number.isFinite(commissionFixed) || commissionFixed < 0) {
    commissionFixed = DEFAULT_COMMISSION.commissionFixed;
    missingFields.push("commissionFixed");
  }

  return {
    fields: {
      commission_type: commissionType,
      commission_percent: commissionPercent,
      commission_fixed: commissionFixed,
    },
    usedFallback: missingFields.length > 0,
    missingFields,
  };
}

// ================= GATEWAY FEE / NET COMMISSION (INTERNAL BOOKKEEPING) =================
//
// Payzah charges LIBSK a processing fee per transaction. This is OUR OWN
// accounting only — it is NEVER sent to Payzah and never affects the boutique
// payout: a boutique always receives its full share (commission base minus our
// commission), regardless of how the customer paid. The gateway fee comes out
// of LIBSK's own commission.
//
// Fee schedule keyed by Payzah payment_type ("1"/"2"/"3" — the same values
// stored on payment_attempts as payzahPaymentType):
//   "1" K-Net (debit): 0.150 KD fixed, 0%
//   "2" Credit card:   0.000 KD fixed, 2.5%
//   "3" Apple Pay (Transit): card-funded, so it really inherits the underlying
//       card's rate — 0.150 fixed if debit-funded, 2.5% if credit-funded. We
//       cannot tell per transaction which was used (see below), so it carries a
//       conservative debit-mixed placeholder.
const PAYZAH_FEE_SCHEDULE = Object.freeze({
  "1": Object.freeze({ fixedFee: 0.150, percentFee: 0 }),   // K-Net (debit)
  "2": Object.freeze({ fixedFee: 0.000, percentFee: 2.5 }), // Credit card
  // TODO: Payzah doesn't expose underlying card type for Apple Pay — this is an
  // estimate, verify against real transaction fees periodically. Nothing the
  // Cloud Functions capture from the redirect callback or get-payment-details
  // identifies debit- vs credit-funding for a payment_type "3" transaction, and
  // this fee is computed at order creation (before payment) anyway. If Payzah
  // later exposes a funding/card-type field (the redirect body carries an
  // unparsed `paymentMethod`), branch this entry on it and recompute at
  // settlement instead of here.
  "3": Object.freeze({ fixedFee: 0.150, percentFee: 0 }),   // Apple Pay — debit-mixed placeholder
});

// Unknown/absent payment types fall back to the credit-card schedule — a
// percentage fee is the safer (won't under-count on larger orders) default for
// an anomalous value. A real checkout is always one of "1"/"2"/"3".
const DEFAULT_FEE = PAYZAH_FEE_SCHEDULE["2"];

// KWD is a 3-decimal (fils) currency; round money the same way the rest of the
// order math does (parseFloat(x.toFixed(3))) so stored figures reconcile.
function round3(n) {
  return parseFloat(Number(n).toFixed(3));
}

// Look up the gateway fee rates for a Payzah payment_type. Never throws.
function feeForPaymentType(paymentType) {
  return PAYZAH_FEE_SCHEDULE[String(paymentType)] || DEFAULT_FEE;
}

// Compute LIBSK's net commission and the gateway fee for one order.
//
// Two separate amounts, deliberately:
//   commissionBase - the merchandise value (GMV / subtotal) commission and the
//                    boutique payout are computed on. Delivery is NOT part of
//                    this (it passes through to the courier).
//   chargedTotal   - the full amount the customer actually paid (subtotal +
//                    delivery - discount). Payzah's percentage fee is levied on
//                    THIS, so the gateway fee uses it, not commissionBase.
//
// Returns { grossCommission, gatewayFee, netCommission, boutiquePayout }, all
// rounded to fils. netCommission may be negative on tiny orders where the fixed
// fee exceeds the commission — that's a real (if rare) loss, left un-clamped for
// honest books. boutiquePayout is ALWAYS commissionBase - grossCommission: the
// gateway fee never touches it.
function calculateNetCommission(commissionBase, chargedTotal, commissionPercent, paymentType) {
  const base = Number(commissionBase);
  const charged = Number(chargedTotal);
  const pct = Number(commissionPercent);
  const safeBase = Number.isFinite(base) ? base : 0;
  const safeCharged = Number.isFinite(charged) ? charged : 0;
  const safePct = Number.isFinite(pct) ? pct : 0;

  const fee = feeForPaymentType(paymentType);

  const grossCommission = round3(safeBase * (safePct / 100));
  const gatewayFee = round3(fee.fixedFee + (safeCharged * fee.percentFee / 100));
  const netCommission = round3(grossCommission - gatewayFee);
  const boutiquePayout = round3(safeBase - grossCommission);

  return { grossCommission, gatewayFee, netCommission, boutiquePayout };
}

module.exports = {
  DEFAULT_COMMISSION,
  VALID_COMMISSION_TYPES,
  buildPayzahCommissionFields,
  PAYZAH_FEE_SCHEDULE,
  feeForPaymentType,
  calculateNetCommission,
};
