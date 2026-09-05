#!/usr/bin/env node
/**
 * Enforcement tests for the single-super_admin tier in firestore.rules.
 *
 * Same approach as verify_rules.js / verify_promo_analytics_rules.js: runs
 * against the real Firebase Rules evaluator over the REST API, so it needs no
 * emulator and no Java — just a gcloud login. Compiling only proves the rules
 * parse; these cases prove the properties the admin-tier tightening depends on:
 *
 *   1. The sole super_admin (isApproved && role == 'super_admin') can still
 *      perform every privileged action (S1 must not lock the founder out).
 *   2. An approved-but-NOT-super admin_users doc (role == 'admin') is now
 *      DENIED everywhere — the former role-agnostic isAdmin() tier is gone.
 *   3. An UNAPPROVED super_admin is denied — isApproved is still required.
 *   4. Normal users / owners / customers keep exactly their own access and
 *      nothing more.
 *   5. S2: the superadmin may edit a user's role (boutique onboarding) but is
 *      blocked from the four verification flags (no signup-gate bypass).
 *   6. U3/U4: pending_invites is gone and manual_notifications is server-only —
 *      even the superadmin cannot read them from a client.
 *
 * Usage:
 *   TOK=$(gcloud auth print-access-token) node scripts/verify_superadmin_rules.js
 *
 * Exits non-zero if any case regresses.
 */
const fs = require("fs");

const source = fs.readFileSync("firestore.rules", "utf8");
const TIME = "2026-09-05T12:00:00Z";
const DOC = (p) => `/databases/(default)/documents/${p}`;

// ── Principals ──────────────────────────────────────────────────────────────
const SUPER = { uid: "super1" }; // admin_users/super1 → approved super_admin
const LOOSE = { uid: "admin1" }; // admin_users/admin1 → approved, role 'admin'
const UNAPPROVED = { uid: "super0" }; // admin_users/super0 → super_admin, NOT approved
const NORMAL = { uid: "user9" }; // no admin_users doc
const OWNER = { uid: "owner1" }; // boutique_owners/owner1 → boutique b1
const CUSTOMER = { uid: "customer1" };

// ── get()/exists() mocks the evaluator can't resolve on its own ─────────────
const adminGet = (uid, data) => [{
  function: "get",
  args: [{ exactValue: DOC(`admin_users/${uid}`) }],
  result: data === undefined ? { undefined: {} } : { value: { data } },
}];
const superMock = (uid) => adminGet(uid, { isApproved: true, role: "super_admin" });
const looseMock = (uid) => adminGet(uid, { isApproved: true, role: "admin" });
const unapprovedMock = (uid) => adminGet(uid, { isApproved: false, role: "super_admin" });
const noAdmin = (uid) => adminGet(uid, undefined); // get() of a missing doc → undefined

const noOwner = (uid) => [{
  function: "exists",
  args: [{ exactValue: DOC(`boutique_owners/${uid}`) }],
  result: { value: false },
}];
const ownerMock = (uid, boutiqueId, isApproved = true) => [
  { function: "exists", args: [{ exactValue: DOC(`boutique_owners/${uid}`) }], result: { value: true } },
  { function: "get", args: [{ exactValue: DOC(`boutique_owners/${uid}`) }], result: { value: { data: { boutiqueId, isApproved } } } },
];

// The API rejects unknown fields on testCase, so names are kept alongside.
const names = [];
function testCase(name, expectation, req, resource, functionMocks) {
  names.push(`[${expectation.padEnd(5)}] ${name}`);
  const tc = { expectation, request: { ...req, time: TIME } };
  if (resource) tc.resource = resource;
  if (functionMocks) tc.functionMocks = functionMocks;
  return tc;
}

// ── Sample documents ────────────────────────────────────────────────────────
const product = { title: "Tee", description: "A tee", price: 10, stock: 5 };
const productFeatured = { ...product, isFeaturedOnHome: true };
const boutique = { name: "Boutique B" };
const boutiqueWasal = { ...boutique, wasalBranchCode: "BR1" };
const userDoc = {
  firstName: "A", lastName: "B", email: "a@b.com", phone: "12345678",
  role: "user", isActive: true, emailVerified: false, phoneVerified: false,
};
const dispute = { customerUid: "customer1", status: "open" };
const gOrder = { customerUid: "customer1", status: "paid", total: 20 };
const slotPayment = { boutiqueId: "b1", amountFils: 21000 };
const banner = { imageUrl: "https://x/y.jpg", isActive: true };
const code = {
  code: "SAVE10", type: "percentage", value: 10, isActive: true,
  usageCount: 0, usageLimit: null, boutiqueId: "b1",
};

const cases = [
  // ══ 1. Read all users ══════════════════════════════════════════════════
  testCase("super reads another user's doc", "ALLOW",
    { auth: SUPER, path: DOC("users/u2"), method: "get" }, { data: userDoc }, superMock("super1")),
  testCase("LOOSE admin reads another user's doc", "DENY",
    { auth: LOOSE, path: DOC("users/u2"), method: "get" }, { data: userDoc }, looseMock("admin1")),
  testCase("unapproved super reads another user's doc", "DENY",
    { auth: UNAPPROVED, path: DOC("users/u2"), method: "get" }, { data: userDoc }, unapprovedMock("super0")),
  testCase("normal user reads another user's doc", "DENY",
    { auth: NORMAL, path: DOC("users/u2"), method: "get" }, { data: userDoc }, noAdmin("user9")),
  testCase("user reads their OWN doc (unchanged)", "ALLOW",
    { auth: { uid: "u2" }, path: DOC("users/u2"), method: "get" }, { data: userDoc }, noAdmin("u2")),

  // ══ 2. Product edit / delete ═══════════════════════════════════════════
  testCase("super updates a product", "ALLOW",
    { auth: SUPER, path: DOC("boutiques/b1/products/p1"), method: "update", resource: { data: product } },
    { data: product }, [...noOwner("super1"), ...superMock("super1")]),
  testCase("LOOSE admin updates a product", "DENY",
    { auth: LOOSE, path: DOC("boutiques/b1/products/p1"), method: "update", resource: { data: product } },
    { data: product }, [...noOwner("admin1"), ...looseMock("admin1")]),
  testCase("owner updates their OWN product (unchanged)", "ALLOW",
    { auth: OWNER, path: DOC("boutiques/b1/products/p1"), method: "update", resource: { data: product } },
    { data: product }, ownerMock("owner1", "b1")),
  testCase("super deletes a product", "ALLOW",
    { auth: SUPER, path: DOC("boutiques/b1/products/p1"), method: "delete" },
    { data: product }, [...noOwner("super1"), ...superMock("super1")]),
  testCase("LOOSE admin deletes a product", "DENY",
    { auth: LOOSE, path: DOC("boutiques/b1/products/p1"), method: "delete" },
    { data: product }, [...noOwner("admin1"), ...looseMock("admin1")]),

  // ══ 3. Paid "featured on home" placement ═══════════════════════════════
  testCase("super sets isFeaturedOnHome", "ALLOW",
    { auth: SUPER, path: DOC("boutiques/b1/products/p1"), method: "update", resource: { data: productFeatured } },
    { data: product }, [...noOwner("super1"), ...superMock("super1")]),
  testCase("owner sets isFeaturedOnHome (paid field, still blocked)", "DENY",
    { auth: OWNER, path: DOC("boutiques/b1/products/p1"), method: "update", resource: { data: productFeatured } },
    { data: product }, ownerMock("owner1", "b1")),

  // ══ 4. wasalBranchCode routing ═════════════════════════════════════════
  testCase("super sets wasalBranchCode", "ALLOW",
    { auth: SUPER, path: DOC("boutiques/b1"), method: "update", resource: { data: boutiqueWasal } },
    { data: boutique }, [...noOwner("super1"), ...superMock("super1")]),
  testCase("owner sets wasalBranchCode (still blocked)", "DENY",
    { auth: OWNER, path: DOC("boutiques/b1"), method: "update", resource: { data: boutiqueWasal } },
    { data: boutique }, ownerMock("owner1", "b1")),

  // ══ 5. Resolve dispute ═════════════════════════════════════════════════
  testCase("super resolves a dispute", "ALLOW",
    { auth: SUPER, path: DOC("disputes/d1"), method: "update", resource: { data: { ...dispute, status: "resolved" } } },
    { data: dispute }, superMock("super1")),
  testCase("LOOSE admin resolves a dispute", "DENY",
    { auth: LOOSE, path: DOC("disputes/d1"), method: "update", resource: { data: { ...dispute, status: "resolved" } } },
    { data: dispute }, looseMock("admin1")),
  testCase("customer edits their own dispute (never allowed)", "DENY",
    { auth: CUSTOMER, path: DOC("disputes/d1"), method: "update", resource: { data: { ...dispute, status: "resolved" } } },
    { data: dispute }, noAdmin("customer1")),
  testCase("customer reads their OWN dispute (unchanged)", "ALLOW",
    { auth: CUSTOMER, path: DOC("disputes/d1"), method: "get" }, { data: dispute }, noAdmin("customer1")),

  // ══ 6. Change order status (global_orders) ═════════════════════════════
  testCase("super updates a global order", "ALLOW",
    { auth: SUPER, path: DOC("global_orders/o1"), method: "update", resource: { data: { ...gOrder, status: "shipped" } } },
    { data: gOrder }, superMock("super1")),
  testCase("LOOSE admin updates a global order", "DENY",
    { auth: LOOSE, path: DOC("global_orders/o1"), method: "update", resource: { data: { ...gOrder, status: "shipped" } } },
    { data: gOrder }, looseMock("admin1")),
  testCase("customer reads their OWN global order (unchanged)", "ALLOW",
    { auth: CUSTOMER, path: DOC("global_orders/o1"), method: "get" }, { data: gOrder }, noAdmin("customer1")),

  // ══ collection-group orders read (dashboard/analytics) ═════════════════
  testCase("super reads a boutique order", "ALLOW",
    { auth: SUPER, path: DOC("boutiques/b1/orders/o1"), method: "get" },
    { data: gOrder }, [...noOwner("super1"), ...superMock("super1")]),
  testCase("LOOSE admin reads a boutique order", "DENY",
    { auth: LOOSE, path: DOC("boutiques/b1/orders/o1"), method: "get" },
    { data: gOrder }, [...noOwner("admin1"), ...looseMock("admin1")]),

  // ══ 7. Revenue read (promo_slot_payments) ══════════════════════════════
  testCase("super reads promo slot payments", "ALLOW",
    { auth: SUPER, path: DOC("promo_slot_payments/pp1"), method: "get" }, { data: slotPayment }, superMock("super1")),
  testCase("LOOSE admin reads promo slot payments", "DENY",
    { auth: LOOSE, path: DOC("promo_slot_payments/pp1"), method: "get" }, { data: slotPayment }, looseMock("admin1")),
  testCase("normal user reads promo slot payments", "DENY",
    { auth: NORMAL, path: DOC("promo_slot_payments/pp1"), method: "get" }, { data: slotPayment }, noAdmin("user9")),

  // ══ 8. Hero banners ════════════════════════════════════════════════════
  testCase("super creates a hero banner", "ALLOW",
    { auth: SUPER, path: DOC("hero_banners/hb1"), method: "create", resource: { data: banner } }, null, superMock("super1")),
  testCase("LOOSE admin creates a hero banner", "DENY",
    { auth: LOOSE, path: DOC("hero_banners/hb1"), method: "create", resource: { data: banner } }, null, looseMock("admin1")),
  testCase("anyone reads hero banners (public, unchanged)", "ALLOW",
    { auth: null, path: DOC("hero_banners/hb1"), method: "get" }, { data: banner }),

  // ══ 9. Discount codes ══════════════════════════════════════════════════
  testCase("super creates a discount code", "ALLOW",
    { auth: SUPER, path: DOC("discount_codes/dc1"), method: "create", resource: { data: code } },
    null, [...noOwner("super1"), ...superMock("super1")]),
  testCase("LOOSE admin creates a discount code", "DENY",
    { auth: LOOSE, path: DOC("discount_codes/dc1"), method: "create", resource: { data: code } },
    null, [...noOwner("admin1"), ...looseMock("admin1")]),

  // ══ 5(bis). S2 — superadmin user-update field scoping ══════════════════
  testCase("super sets a user's role = boutique_owner (onboarding, allowed)", "ALLOW",
    { auth: SUPER, path: DOC("users/u2"), method: "update", resource: { data: { ...userDoc, role: "boutique_owner" } } },
    { data: userDoc }, superMock("super1")),
  testCase("super grants verificationExempt (signup-gate bypass, blocked)", "DENY",
    { auth: SUPER, path: DOC("users/u2"), method: "update", resource: { data: { ...userDoc, verificationExempt: true } } },
    { data: userDoc }, superMock("super1")),
  testCase("super flips emailVerified (blocked)", "DENY",
    { auth: SUPER, path: DOC("users/u2"), method: "update", resource: { data: { ...userDoc, emailVerified: true } } },
    { data: userDoc }, superMock("super1")),
  testCase("super flips phoneVerified (blocked)", "DENY",
    { auth: SUPER, path: DOC("users/u2"), method: "update", resource: { data: { ...userDoc, phoneVerified: true } } },
    { data: userDoc }, superMock("super1")),

  // ══ 6(bis). U3/U4 — removed / server-only collections ══════════════════
  testCase("super reads manual_notifications (server-only now)", "DENY",
    { auth: SUPER, path: DOC("manual_notifications/mn1"), method: "get" }, { data: { title: "x" } }, superMock("super1")),
  testCase("super writes manual_notifications (server-only now)", "DENY",
    { auth: SUPER, path: DOC("manual_notifications/mn1"), method: "create", resource: { data: { title: "x" } } }, null, superMock("super1")),
  testCase("super reads pending_invites (removed → catch-all deny)", "DENY",
    { auth: SUPER, path: DOC("pending_invites/pi1"), method: "get" }, { data: { email: "x@y.com" } }, superMock("super1")),
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
