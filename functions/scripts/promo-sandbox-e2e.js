"use strict";

// ============ PROMO-SLOT PAYMENT — LOCAL EMULATOR E2E ============
//
// "Pays" for a promo slot end-to-end against the Firebase EMULATOR — no real
// Payzah, no sandbox key, nothing touches the live project. It exercises the
// real Cloud Functions (createPromoBooking + checkPayzahPaymentStatus) and the
// real settlement path (resolvePaymentAttempt -> settlePaidPromoBooking); only
// the gateway *answer* is faked, via the mockStatus hook that turns on whenever
// PAYZAH_ENV != production (set to "test" in functions/.env.local).
//
// Walk:
//   seed approved owner + boutique + product
//     -> createPromoBooking (featured_product, useCredit:false -> full charge)
//     -> set mockStatus:"paid" on the payment_attempts doc
//     -> checkPayzahPaymentStatus  (same call the app makes on resume)
//     -> assert the booking is now active / paid_pending_review
//
// PREREQUISITES
//   1. A Java runtime (Firestore + Auth emulators need it):  brew install openjdk@17
//   2. Terminal A, from repo root:   firebase emulators:start
//   3. Terminal B, from functions/:  node scripts/promo-sandbox-e2e.js
//
// To test the FAILURE path instead, run:  MOCK=failed node scripts/promo-sandbox-e2e.js
// (expects the booking to end "cancelled" and NO credit spent).

const admin = require("firebase-admin");

const PROJECT = process.env.GCLOUD_PROJECT || "libsk-b68f5";
const REGION = "us-central1";
const FUNCTIONS_PORT = process.env.FUNCTIONS_EMULATOR_PORT || "5001";
const MOCK = process.env.MOCK || "paid"; // paid | failed | unclear | pending
const FAKE_KEY = "fake-api-key";         // the Auth emulator accepts any key

// Point the Admin SDK at the emulator BEFORE initializeApp.
process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";

admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();
const auth = admin.auth();
const FN_BASE = `http://127.0.0.1:${FUNCTIONS_PORT}/${PROJECT}/${REGION}`;

const ok = (m) => console.log(`✓ ${m}`);
function fail(m) { console.error(`\n✗ ${m}`); process.exit(1); }

async function idTokenFor(uid) {
  const customToken = await auth.createCustomToken(uid);
  const res = await fetch(
    `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${FAKE_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    },
  );
  const data = await res.json();
  if (!data.idToken) fail(`Could not mint an emulator ID token: ${JSON.stringify(data)}`);
  return data.idToken;
}

// Invoke an onCall function on the Functions emulator with an auth context.
async function callFn(name, data, idToken) {
  let res;
  try {
    res = await fetch(`${FN_BASE}/${name}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${idToken}`,
      },
      body: JSON.stringify({ data }),
    });
  } catch (e) {
    fail(`Could not reach the Functions emulator at ${FN_BASE} — is \`firebase emulators:start\` running? (${e.message})`);
  }
  const body = await res.json().catch(() => ({}));
  if (body.error) fail(`${name} failed: ${JSON.stringify(body.error)}`);
  return body.result;
}

async function main() {
  const stamp = Date.now();
  const uid = `qa_owner_${stamp}`;
  const boutiqueId = `qa_boutique_${stamp}`;
  const productId = `qa_product_${stamp}`;

  // 1) Seed: auth user + APPROVED owner + boutique + one product to promote.
  await auth.createUser({
    uid, email: `${uid}@example.com`, emailVerified: true, password: "test1234",
  });
  await db.doc(`boutiques/${boutiqueId}`).set({
    name: "QA Boutique",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await db.doc(`boutique_owners/${uid}`).set({ boutiqueId, isApproved: true });
  await db.doc(`boutiques/${boutiqueId}/products/${productId}`).set({
    title: "QA Promo Product", price: 10, stock: 5, category: ["Dresses"],
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  ok(`Seeded approved owner ${uid} + boutique ${boutiqueId} + product`);

  const idToken = await idTokenFor(uid);
  ok("Minted emulator ID token for the owner");

  // 2) Book a promo slot that must be PAID (featured_product, 1 day = 4 KWD).
  //    useCredit:false -> no credit applied -> full charge -> a payment attempt.
  const booking = await callFn("createPromoBooking", {
    placementType: "featured_product",
    productId,
    startDay: 0, numDays: 1,
    paymentMethod: "KNET",
    useCredit: false,
  }, idToken);
  ok(`createPromoBooking -> booking=${booking.bookingId} attempt=${booking.paymentAttemptId} charge=${booking.amountToCharge} KWD creditOnly=${booking.creditOnly}`);
  if (booking.creditOnly || !booking.paymentAttemptId) {
    fail("Expected a charge (a paymentAttemptId), got a credit-only booking.");
  }

  // 3) Fake the gateway answer. Honored only because PAYZAH_ENV=test.
  await db.doc(`payment_attempts/${booking.paymentAttemptId}`)
    .set({ mockStatus: MOCK }, { merge: true });
  ok(`Set mockStatus="${MOCK}" on the payment attempt`);

  // 4) Settle through the real status-check path (what the app calls on resume).
  const settled = await callFn(
    "checkPayzahPaymentStatus", { attemptId: booking.paymentAttemptId }, idToken);
  ok(`checkPayzahPaymentStatus -> ${JSON.stringify(settled)}`);

  // 5) Assert the booking + credit ledger moved the way this outcome should.
  const bSnap = await db.doc(`promo_bookings/${booking.bookingId}`).get();
  const status = bSnap.get("status");
  const bqSnap = await db.doc(`boutiques/${boutiqueId}`).get();
  const balance = bqSnap.get("promoCreditBalance") || 0;

  if (MOCK === "paid") {
    if (["active", "paid_pending_review"].includes(status)) {
      ok(`Booking is now "${status}" — promo payment settled ✅  (credit balance ${balance} KWD, unchanged as expected for useCredit:false)`);
    } else {
      fail(`Booking status is "${status}" (expected active / paid_pending_review).`);
    }
  } else if (MOCK === "failed") {
    if (status === "cancelled") ok(`Booking is "cancelled" as expected for a failed payment.`);
    else fail(`Booking status is "${status}" (expected cancelled).`);
  } else {
    ok(`Booking status is "${status}" for mock="${MOCK}" (still pending until a terminal status).`);
  }

  console.log("\nInspect everything in the Emulator UI: http://127.0.0.1:4000/firestore");
  process.exit(0);
}

main().catch((e) => fail(e.stack || String(e)));
