"use strict";

// Integer-fils money helpers — the same ones the promo credits ledger uses, so
// the vendor split never does float math on KWD.
const { kwdToFils, filsToKwd } = require("./promo_credit");

// ================= PAYZAH MULTIVENDOR COMMISSION =================
//
// Everything that decides how a marketplace payment is split between a boutique
// and LIBSK on Payzah's Initialize Payment request
// (POST /ws/paymentgateway/index). Kept free of firebase-functions so it is
// unit-tested directly (test/payzah_commission.test.js) — the
// initializePayzahPayment onCall handler in index.js can't be unit-tested as-is.
// The one Firestore read (the vendor key lookup) takes `db` as a parameter so
// tests pass a fake.
//
// There are TWO flows, selected in index.js by PAYZAH_VENDOR_SPLIT_ENABLED:
//
//   1. FEE-ABSORBED VENDOR SPLIT (default). The request is authenticated AS THE
//      BOUTIQUE'S VENDOR ACCOUNT, which is what routes the settlement to the
//      boutique, and LIBSK's cut is sent as a fixed commission. See the
//      "FEE-ABSORBED VENDOR SPLIT" section below.
//
//   2. LEGACY SINGLE MERCHANT KEY (rollback only). Authenticated with LIBSK's
//      merchant key, so LIBSK receives 100% and disburses boutiques manually.
//      The commission_* fields it sends (buildPayzahCommissionFields, next
//      section) are METADATA on the payment record — Payzah has no vendor to
//      split with under the merchant key.

// ================= LEGACY FLOW: COMMISSION METADATA =================
//
// Rollback path only (PAYZAH_VENDOR_SPLIT_ENABLED=false). Maps a boutique's
// Firestore commission config onto the three commission_* fields:
//
//   Firestore field (camelCase)  ->  Payzah request field (snake_case)
//   commissionType               ->  commission_type    (1 = fixed | 2 = percentage | 3 = mixed)
//   commissionPercent            ->  commission_percent (used when type is 2 or 3)
//   commissionFixed              ->  commission_fixed   (used when type is 1 or 3)
//
// We always send all three fields (type + percent + fixed); an unused field for
// the chosen type (e.g. commission_fixed: 0 when type is 2) is harmless.

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
// The default is the STANDARD 15%. The Founding Partner 12% rate is only ever
// set by hand, per boutique, from All Boutiques — it is never auto-applied.
//
// The fee-absorbed vendor split does NOT use this default: a boutique with no
// valid commissionPercent is refused a payment (see readCommissionPercent)
// rather than charged a rate nobody chose for it.
const DEFAULT_COMMISSION = Object.freeze({
  commissionType: 2, // percentage
  commissionPercent: 15,
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

// ================= FEE-ABSORBED VENDOR SPLIT (DEFAULT FLOW) =================
//
// How Payzah routes a payment to a boutique: there is NO vendor identifier in
// the request body. The Initialize Payment request is authenticated AS THE
// VENDOR — Authorization: Base64(vendor private key) — with the boutique's own
// key from the Payzah dashboard (stored server-side in
// boutiqueSecrets/{boutiqueId}.payzahVendorKey). Payzah then settles:
//
//     vendor_net = amount - payzah_fee - merchant_commission
//
// where merchant_commission is LIBSK's cut, sent as commission_fixed.
// Confirmed in the Payzah sandbox across multiple amounts and rates: vendor-key
// auth with no body identifier routes the settlement to that vendor, and
// commission_fixed becomes the settled Merchant Commission exactly.
//
// THE SPLIT. The customer is charged amount = (subtotal - discount) + delivery.
// Commission is on (subtotal - discount) ONLY — never on delivery:
//
//     base          = subtotal - discount
//     boutique_net  = base * (1 - rate)
//     LIBSK's cut   = base * rate - gateway_fee + delivery   -> commission_fixed
//     Payzah's cut  = gateway_fee
//
// Delivery routes ENTIRELY to LIBSK, which pays Wasal directly — the boutique
// never receives any part of it. A discount comes off the subtotal before
// either cut is taken, so it shrinks the pie both cuts come from. The gateway
// fee comes out of LIBSK's cut ("fee-absorbed"), never the boutique's. Payzah's
// vendor_net = amount - fee - commission_fixed then works out to exactly
// base * (1 - rate).
//
// THE FLOOR AT ZERO IS DELIBERATE, NOT A BUG. When base * rate + delivery is
// at or below the gateway fee — in practice a small Made to Order (no delivery)
// order — LIBSK takes ZERO rather than send Payzah a negative commission.
// LIBSK nets nothing on those orders — accepted behaviour. Note what zero does
// NOT do: Payzah deducts its fee from the vendor's settlement, and a zero
// commission can't refund any of it, so the boutique still bears
// (fee - base * rate - delivery). E.g. a 0.500 KWD Made to Order order at 15%
// by K-Net: LIBSK takes 0, the boutique nets 0.350 instead of its 0.425 share.
//
// All money here is INTEGER FILS (1 KWD = 1000 fils), converted to a 3-dp KWD
// string only at the Payzah boundary.

// Payzah's gateway fee for this payment, in integer fils, from the per-method
// PAYZAH_FEE_SCHEDULE below (the same table the order bookkeeping uses):
//   "1" K-Net     -> 150 fils flat
//   "3" Apple Pay -> 150 fils flat (configured debit-only)
//   "2" Card      -> 2.5% of the charged amount
// `amountFils` is the full amount charged — Payzah levies its % fee on that.
function gatewayFeeFils(paymentType, amountFils) {
  const fee = feeForPaymentType(paymentType);
  return kwdToFils(fee.fixedFee) + Math.round((amountFils * fee.percentFee) / 100);
}

// Firestore collection holding each boutique's Payzah vendor private key.
// Deny-all in firestore.rules: read only by Cloud Functions (admin SDK), never
// by any client — see the rule for why it is not on boutiques/{boutiqueId}.
const BOUTIQUE_SECRETS_COLLECTION = "boutiqueSecrets";

// A boutique isn't set up for the vendor split (no vendor key, no valid
// commission rate, or a payment that can't be pinned to one boutique).
// initializePayzahPayment turns this into a loud failure — it must NEVER fall
// back to the merchant key, which would silently settle 100% to LIBSK.
class PayzahVendorSplitConfigError extends Error {
  constructor(message) {
    super(message);
    this.name = "PayzahVendorSplitConfigError";
  }
}

// LIBSK's cut in fils (sent as commission_fixed):
//   max(0, round(baseFils * percent / 100) - feeFils + deliveryFils)
// baseFils = subtotal - discount; commissionPercent is the boutique's rate
// (e.g. 15, 12). See the split above for why delivery is added in full.
function computeVendorSplitCommissionFils({ baseFils, deliveryFils, feeFils, commissionPercent }) {
  const grossFils = Math.round((baseFils * commissionPercent) / 100);
  return Math.max(0, grossFils - feeFils + deliveryFils);
}

// The exact commission fields the vendor split sends — fixed type, LIBSK's cut
// as a 3-dp KWD string (formatted like `amount`), percent zeroed. Nothing else.
function buildVendorSplitCommissionFields(commissionFils) {
  return {
    commission_type: "1", // 1 = fixed
    commission_fixed: filsToKwd(commissionFils).toFixed(3),
    commission_percent: "0",
  };
}

// The boutique's commission rate for the vendor split, or null if it isn't a
// number in 0–100. NO default: the rate is a per-boutique business decision set
// by the superadmin, so a missing one blocks the payment instead of guessing.
function readCommissionPercent(boutiqueData) {
  const raw = boutiqueData ? boutiqueData.commissionPercent : undefined;
  if (raw === undefined || raw === null || raw === "") return null;
  const pct = Number(raw);
  return Number.isFinite(pct) && pct >= 0 && pct <= 100 ? pct : null;
}

// Read a boutique's Payzah vendor private key (admin SDK). Throws
// PayzahVendorSplitConfigError when it is missing or blank — callers must not
// substitute the merchant key.
async function getPayzahVendorKey(db, boutiqueId) {
  if (!boutiqueId) {
    throw new PayzahVendorSplitConfigError("No boutiqueId to look up a Payzah vendor key for.");
  }
  const snap = await db.collection(BOUTIQUE_SECRETS_COLLECTION).doc(boutiqueId).get();
  const key = snap.exists ? snap.data().payzahVendorKey : undefined;
  if (typeof key !== "string" || key.trim() === "") {
    throw new PayzahVendorSplitConfigError(
      `Boutique ${boutiqueId} has no Payzah vendor key (${BOUTIQUE_SECRETS_COLLECTION}/${boutiqueId}.payzahVendorKey).`,
    );
  }
  return key.trim();
}

// A non-negative KWD amount from the payment attempt, as integer fils — or
// null if the field is missing or not a number.
function attemptFils(value) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) return null;
  return kwdToFils(value);
}

// The one boutique whose vendor account a vendor-split payment belongs to.
// Used by BOTH initialization and the status check, so the vendor key is
// always looked up the same way. One payment settles to ONE vendor account:
// checkout is single-boutique (CartConflictGuard), and if a multi-boutique
// attempt ever appears, routing it all to the first boutique would pay one
// boutique for another's items — so anything but exactly one is refused.
function vendorSplitBoutiqueId(attempt) {
  const boutiqueIds = Array.isArray(attempt.boutiqueIds) ? attempt.boutiqueIds : [];
  if (boutiqueIds.length !== 1) {
    throw new PayzahVendorSplitConfigError(
      `Vendor split needs exactly one boutique per payment; attempt has ${boutiqueIds.length}.`,
    );
  }
  return boutiqueIds[0];
}

// Everything initializePayzahPayment needs to send an order payment through the
// vendor split: which key signs it and which commission fields go in the body.
// `paymentType` is the payment_type being sent ("1" | "2" | "3"), which picks
// the gateway fee. Throws PayzahVendorSplitConfigError if the boutique isn't
// fully set up or the attempt can't be split.
async function resolveVendorSplit(db, attempt, paymentType) {
  const boutiqueId = vendorSplitBoutiqueId(attempt);

  const amountFils = kwdToFils(attempt.amount);
  if (!Number.isInteger(amountFils) || amountFils <= 0) {
    throw new PayzahVendorSplitConfigError(`Attempt amount ${attempt.amount} is not a positive KWD amount.`);
  }

  // The breakdown createOrder records alongside `amount`. Without it the split
  // can't keep delivery out of the commission base, so refuse rather than guess
  // (only an attempt created before this breakdown existed can lack it).
  const subtotalFils = attemptFils(attempt.subtotal);
  const discountFils = attemptFils(attempt.discountAmount);
  const deliveryFils = attemptFils(attempt.deliveryCost);
  if (subtotalFils === null || discountFils === null || deliveryFils === null) {
    throw new PayzahVendorSplitConfigError(
      "Attempt has no subtotal/discountAmount/deliveryCost breakdown to split on.",
    );
  }
  const baseFils = subtotalFils - discountFils;
  if (baseFils < 0 || baseFils + deliveryFils !== amountFils) {
    throw new PayzahVendorSplitConfigError(
      `Attempt breakdown doesn't match the charged amount: subtotal ${attempt.subtotal} ` +
      `- discount ${attempt.discountAmount} + delivery ${attempt.deliveryCost} != ${attempt.amount}.`,
    );
  }

  const [privateKey, boutiqueSnap] = await Promise.all([
    getPayzahVendorKey(db, boutiqueId),
    db.collection("boutiques").doc(boutiqueId).get(),
  ]);
  const commissionPercent = readCommissionPercent(boutiqueSnap.exists ? boutiqueSnap.data() : null);
  if (commissionPercent === null) {
    throw new PayzahVendorSplitConfigError(
      `Boutique ${boutiqueId} has no valid commissionPercent (0–100) — set it in All Boutiques.`,
    );
  }

  const feeFils = gatewayFeeFils(paymentType, amountFils);
  const commissionFils = computeVendorSplitCommissionFils({
    baseFils, deliveryFils, feeFils, commissionPercent,
  });
  return {
    boutiqueId,
    privateKey,
    commissionPercent,
    baseFils,
    deliveryFils,
    feeFils,
    commissionFils,
    fields: buildVendorSplitCommissionFields(commissionFils),
  };
}

// ================= WHICH PAYZAH ACCOUNT SIGNS A CALL =================
//
// Payzah keeps LIBSK's merchant account and each boutique's vendor account as
// SEPARATE credential scopes. A payment exists only under the key that created
// it: confirmed in the sandbox (2026-09-11), a vendor-initialized CAPTURED
// payment answers get-payment-details signed with that vendor's key (HTTP 200,
// paymentStatus CAPTURED), while the merchant key gets code 10012 "No Record
// found for the provided details". The merchant key is NOT a universal
// fallback — and a 10012 reads as "not paid yet", so signing a status check
// with the wrong key would quietly expire a payment that was actually captured.
//
// So the account is decided ONCE, at initialization, recorded on the payment
// attempt as payzahAuthMode (before the gateway is called), and every status
// check signs with exactly that account.

const PAYZAH_AUTH_VENDOR = "vendor";
const PAYZAH_AUTH_MERCHANT = "merchant";

// Which account initializes this attempt's payment:
//   * promo booking → merchant. The boutique is the PAYER and LIBSK the payee;
//     signing as the boutique would pay it back its own promo fee.
//   * order, vendor split on (the default) → the boutique's vendor account.
//   * order, vendor split off (rollback) → merchant.
function payzahAuthModeForInit(attempt, vendorSplitEnabled) {
  if (attempt.kind === "promo_booking") return PAYZAH_AUTH_MERCHANT;
  return vendorSplitEnabled ? PAYZAH_AUTH_VENDOR : PAYZAH_AUTH_MERCHANT;
}

// The key a status check (get-payment-details) must be signed with: the SAME
// account that initialized the payment, per the attempt's payzahAuthMode.
//   * "vendor"   → that boutique's vendor key, looked up exactly as
//     initialization does (vendorSplitBoutiqueId + getPayzahVendorKey). If it's
//     gone, this THROWS — never the merchant key, which can't see the payment.
//   * "merchant" → LIBSK's merchant key.
//   * absent     → merchant. Only attempts initialized before payzahAuthMode
//     existed lack it, and every one of those used the merchant key.
//   * anything else → throws rather than guess.
async function payzahStatusSigningKey(db, attempt, merchantKey) {
  const mode = attempt.payzahAuthMode;
  if (mode === PAYZAH_AUTH_VENDOR) {
    return getPayzahVendorKey(db, vendorSplitBoutiqueId(attempt));
  }
  if (mode === PAYZAH_AUTH_MERCHANT || mode === undefined || mode === null) {
    return merchantKey;
  }
  throw new PayzahVendorSplitConfigError(`Unknown payzahAuthMode "${mode}" on payment attempt.`);
}

// ================= INITIALIZE PAYMENT REQUEST BODY =================
//
// The full Initialize Payment body, shared by every flow. Only
// `commissionFields` differs: the vendor split's three fields, the legacy
// metadata, or none (promo bookings). There is deliberately no vendor
// identifier field — vendor routing is the Authorization header, not the body.
function buildPayzahInitPayload({
  trackid, amount, currency, paymentType, language, redirectUrl,
  customerName, customerEmail, customerPhone, commissionFields,
}) {
  return {
    trackid: String(trackid),
    // Plain decimal string, 3 dp, e.g. "11.250" — no symbols or commas.
    amount: Number(amount).toFixed(3),
    currency,
    payment_type: paymentType, // "1" K-Net | "2" card | "3" Transit (Apple Pay)
    language: language === "ARA" ? "ARA" : "ENG",
    // Both URLs point at the same handler — it re-verifies via
    // get-payment-details either way and never trusts which one was hit.
    success_url: redirectUrl,
    error_url: redirectUrl,
    customer_name: customerName,
    customer_email: customerEmail,
    customer_phone: customerPhone,
    ...(commissionFields || {}),
    // kfast_id (Numeric, max 8) appears in the docs' request field table but
    // is never explained anywhere — deliberately omitted until Payzah
    // support confirms its purpose.
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
//   "3" Apple Pay (Transit): 0.150 KD fixed, 0% — debit-only (see below)
const PAYZAH_FEE_SCHEDULE = Object.freeze({
  "1": Object.freeze({ fixedFee: 0.150, percentFee: 0 }),   // K-Net (debit)
  "2": Object.freeze({ fixedFee: 0.000, percentFee: 2.5 }), // Credit card
  // Apple Pay is configured DEBIT-ONLY on the Payzah account, so it always
  // carries the flat K-Net-style 0.150 fee (confirmed by Hussain 2026-09-10).
  "3": Object.freeze({ fixedFee: 0.150, percentFee: 0 }),   // Apple Pay (debit-only)
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
  BOUTIQUE_SECRETS_COLLECTION,
  PayzahVendorSplitConfigError,
  gatewayFeeFils,
  computeVendorSplitCommissionFils,
  buildVendorSplitCommissionFields,
  readCommissionPercent,
  getPayzahVendorKey,
  vendorSplitBoutiqueId,
  resolveVendorSplit,
  PAYZAH_AUTH_VENDOR,
  PAYZAH_AUTH_MERCHANT,
  payzahAuthModeForInit,
  payzahStatusSigningKey,
  buildPayzahInitPayload,
  PAYZAH_FEE_SCHEDULE,
  feeForPaymentType,
  calculateNetCommission,
};
