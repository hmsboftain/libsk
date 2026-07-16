#!/usr/bin/env node
/**
 * Enforcement tests for the promo ad-analytics rules in firestore.rules.
 *
 * Same approach as verify_rules.js: runs against the real Firebase Rules
 * evaluator over the REST API, so it needs no emulator and no Java — just a
 * gcloud login. Compiling only proves the rules parse; these cases prove the
 * three properties the design actually depends on:
 *
 *   1. an owner reads their OWN booking stats and attributed sales,
 *   2. an owner CANNOT read a rival boutique's ad performance,
 *   3. nobody — owner or customer — can touch the raw click log or write the
 *      billing-adjacent counters by hand.
 *
 * Usage:
 *   TOK=$(gcloud auth print-access-token) node scripts/verify_promo_analytics_rules.js
 *
 * Exits non-zero if any case regresses.
 */
const fs = require("fs");

const source = fs.readFileSync("firestore.rules", "utf8");
const TIME = "2026-07-16T12:00:00Z";

const BOOKING = "/databases/(default)/documents/promo_bookings/bk1";
const SALE = "/databases/(default)/documents/promo_bookings/bk1/attributed_sales/o1";
const CLICK = "/databases/(default)/documents/promo_click_events/e1";

// A live booking owned by boutique b1, with the analytics rollup attached.
const booking = {
  boutiqueId: "b1", placementType: "featured_product", status: "active",
  priceFils: 21000,
  stats: { clicks: 12, attributedOrders: 3, attributedRevenueFils: 45000 },
};

const sale = {
  orderId: "o1", bookingId: "bk1", boutiqueId: "b1",
  placementType: "featured_product", revenueFils: 12500, reversed: false,
};

const clickEvent = {
  bookingId: "bk1", boutiqueId: "b1", uid: "customer1",
  subjectType: "product", subjectId: "p1",
};

// The API rejects unknown fields on testCase, so names are kept alongside.
const names = [];
function testCase(name, expectation, req, resource, functionMocks) {
  names.push(`[${expectation.padEnd(5)}] ${name}`);
  const tc = { expectation, request: { ...req, time: TIME } };
  if (resource) tc.resource = resource;
  if (functionMocks) tc.functionMocks = functionMocks;
  return tc;
}

// owner1 owns boutique b1; owner2 owns a rival boutique.
const OWNER1 = { uid: "owner1" };
const OWNER2 = { uid: "owner2" };
const CUSTOMER = { uid: "customer1" };

// isBoutiqueOwnerOf() resolves ownership with exists()+get() against
// boutique_owners/{uid}, which the evaluator cannot resolve on its own. Mocking
// those lookups is what makes the ALLOW cases meaningful: without them every
// read denies for want of data, and a rule that denied the rightful owner too
// would sail through a suite of DENY-only cases.
const ownerDoc = (uid, boutiqueId, isApproved = true) => [
  {
    function: "exists",
    args: [{ exactValue: `/databases/(default)/documents/boutique_owners/${uid}` }],
    result: { value: true },
  },
  {
    function: "get",
    args: [{ exactValue: `/databases/(default)/documents/boutique_owners/${uid}` }],
    result: { value: { data: { boutiqueId, isApproved } } },
  },
];

const cases = [
  // ── The whole point: an owner sees their own ad performance ─────────────
  testCase("owner reads their OWN booking stats", "ALLOW", {
    auth: OWNER1, path: BOOKING, method: "get",
  }, { data: booking }, ownerDoc("owner1", "b1")),

  testCase("owner reads their OWN attributed sales", "ALLOW", {
    auth: OWNER1, path: SALE, method: "get",
  }, { data: sale }, ownerDoc("owner1", "b1")),

  // An owner pending approval has no dashboard yet.
  testCase("unapproved owner reads booking stats", "DENY", {
    auth: OWNER1, path: BOOKING, method: "get",
  }, { data: booking }, ownerDoc("owner1", "b1", false)),

  // ── An owner must never read a rival's ad numbers ───────────────────────
  testCase("rival owner reads booking stats (ownership resolved)", "DENY", {
    auth: OWNER2, path: BOOKING, method: "get",
  }, { data: booking }, ownerDoc("owner2", "b2")),

  testCase("rival owner reads attributed sales (ownership resolved)", "DENY", {
    auth: OWNER2, path: SALE, method: "get",
  }, { data: sale }, ownerDoc("owner2", "b2")),

  // ── An owner must never read a rival's ad numbers ───────────────────────
  testCase("rival owner reads another boutique's booking stats", "DENY", {
    auth: OWNER2, path: BOOKING, method: "get",
  }, { data: booking }),

  testCase("rival owner reads another boutique's attributed sales", "DENY", {
    auth: OWNER2, path: SALE, method: "get",
  }, { data: sale }),

  testCase("signed-out read of booking stats", "DENY", {
    auth: null, path: BOOKING, method: "get",
  }, { data: booking }),

  // ── Counters are billing-adjacent: never client-writable ────────────────
  // Ownership is mocked as VALID throughout, so each denial is the write rule
  // doing its job — not a lookup that failed to resolve.
  testCase("owner inflates their own click count", "DENY", {
    auth: OWNER1, path: BOOKING, method: "update",
    resource: { data: { ...booking, stats: { ...booking.stats, clicks: 9999 } } },
  }, { data: booking }, ownerDoc("owner1", "b1")),

  testCase("owner fabricates attributed revenue", "DENY", {
    auth: OWNER1, path: BOOKING, method: "update",
    resource: {
      data: { ...booking, stats: { ...booking.stats, attributedRevenueFils: 999000 } },
    },
  }, { data: booking }, ownerDoc("owner1", "b1")),

  testCase("owner forges an attributed sale", "DENY", {
    auth: OWNER1, path: SALE, method: "create",
    resource: { data: sale },
  }, null, ownerDoc("owner1", "b1")),

  testCase("owner un-reverses a refunded sale", "DENY", {
    auth: OWNER1, path: SALE, method: "update",
    resource: { data: { ...sale, reversed: false } },
  }, { data: { ...sale, reversed: true } }, ownerDoc("owner1", "b1")),

  testCase("owner deletes an attributed sale", "DENY", {
    auth: OWNER1, path: SALE, method: "delete",
  }, { data: sale }, ownerDoc("owner1", "b1")),

  // ── The raw click log is closed to everyone ─────────────────────────────
  // Owners get the rollup, never the per-customer stream: an owner must not be
  // able to mine WHO tapped their ad.
  testCase("owner reads the raw click log", "DENY", {
    auth: OWNER1, path: CLICK, method: "get",
  }, { data: clickEvent }, ownerDoc("owner1", "b1")),

  testCase("customer reads their own click event", "DENY", {
    auth: CUSTOMER, path: CLICK, method: "get",
  }, { data: clickEvent }),

  testCase("client forges a click event", "DENY", {
    auth: CUSTOMER, path: CLICK, method: "create",
    resource: { data: clickEvent },
  }),

  testCase("client deletes a click event", "DENY", {
    auth: OWNER1, path: CLICK, method: "delete",
  }, { data: clickEvent }),
];

const body = {
  source: { files: [{ name: "firestore.rules", content: source }] },
  testSuite: { testCases: cases },
};

fetch("https://firebaserules.googleapis.com/v1/projects/libsk-b68f5:test", {
  method: "POST",
  headers: {
    Authorization: "Bearer " + process.env.TOK,
    "Content-Type": "application/json",
    "x-goog-user-project": "libsk-b68f5",
  },
  body: JSON.stringify(body),
})
  .then((r) => r.json())
  .then((j) => {
    if (j.error) {
      console.log("API ERROR:", JSON.stringify(j.error).slice(0, 400));
      process.exit(1);
    }
    const compileErrors = (j.issues || []).filter((i) => i.severity === "ERROR");
    if (compileErrors.length) {
      compileErrors.forEach((i) => console.log("COMPILE:", i.description));
      process.exit(1);
    }
    const results = j.testResults || [];
    let failed = 0;
    results.forEach((r, i) => {
      const ok = r.state === "SUCCESS";
      if (!ok) failed++;
      console.log(`${ok ? "PASS" : "FAIL"}  ${names[i]}`);
      if (!ok && r.debugMessages) {
        console.log("       " + String(r.debugMessages).slice(0, 200));
      }
    });
    console.log(`\n${results.length - failed}/${results.length} rules tests passed`);
    if (failed) process.exit(1);
  });
