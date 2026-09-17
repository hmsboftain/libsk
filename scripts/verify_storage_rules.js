#!/usr/bin/env node
/**
 * Enforcement tests for storage.rules.
 *
 * Same approach as verify_superadmin_rules.js: runs against the real Firebase
 * Rules evaluator over the REST API (no emulator), with the cross-service
 * firestore.exists()/firestore.get() calls mocked. Cases cover:
 *
 *   1. Public reads for every image folder the app serves.
 *   2. Boutique owners (boutique_owners/{uid}: boutiqueId + isApproved) may
 *      write only their OWN boutique's folders, images only, < 5 MB.
 *   3. Only the super_admin (admin_users/{uid}: isApproved AND
 *      role == 'super_admin') writes hero_banners — an approved admin_users
 *      doc with any other role, or an unapproved super_admin, is denied.
 *   4. Everything outside the known folders is closed to everyone.
 *
 * Usage:
 *   TOK=$(gcloud auth print-access-token) node scripts/verify_storage_rules.js
 *   # test the DEPLOYED ruleset instead of the local file:
 *   TOK=$(gcloud auth print-access-token) RULESET=<ruleset-id> node scripts/verify_storage_rules.js
 *
 * Exits non-zero if any case regresses.
 */
const fs = require("fs");

const PROJECT = "libsk-b68f5";
const BUCKET = `${PROJECT}.firebasestorage.app`;
const RULESET = process.env.RULESET || "";
const TIME = "2026-09-17T12:00:00Z";
const DOC = (p) => `/databases/(default)/documents/${p}`;
const OBJ = (p) => `/b/${BUCKET}/o/${p}`;

// ── Principals ──────────────────────────────────────────────────────────────
const SUPER = { uid: "super1" }; // admin_users/super1 → approved super_admin
const LOOSE = { uid: "admin1" }; // admin_users/admin1 → approved, role 'admin'
const UNAPPROVED = { uid: "super0" }; // admin_users/super0 → super_admin, NOT approved
const OWNER = { uid: "owner1" }; // boutique_owners/owner1 → b1, approved
const PENDING_OWNER = { uid: "owner2" }; // boutique_owners/owner2 → b1, NOT approved
const NORMAL = { uid: "user9" }; // no admin_users / boutique_owners doc

// ── firestore.exists()/get() mocks ──────────────────────────────────────────
const docMock = (p, data) => data === undefined
  ? [{ function: "firestore.exists", args: [{ exactValue: DOC(p) }], result: { value: false } }]
  : [
    { function: "firestore.exists", args: [{ exactValue: DOC(p) }], result: { value: true } },
    { function: "firestore.get", args: [{ exactValue: DOC(p) }], result: { value: { data } } },
  ];
const admin = (uid, data) => docMock(`admin_users/${uid}`, data);
const owner = (uid, data) => docMock(`boutique_owners/${uid}`, data);

const mocks = {
  super1: [...owner("super1"), ...admin("super1", { isApproved: true, role: "super_admin" })],
  admin1: [...owner("admin1"), ...admin("admin1", { isApproved: true, role: "admin" })],
  super0: [...owner("super0"), ...admin("super0", { isApproved: false, role: "super_admin" })],
  owner1: [...owner("owner1", { boutiqueId: "b1", isApproved: true }), ...admin("owner1")],
  owner2: [...owner("owner2", { boutiqueId: "b1", isApproved: false }), ...admin("owner2")],
  user9: [...owner("user9"), ...admin("user9")],
};

const IMG = { size: 1024 * 1024, contentType: "image/jpeg" };
const BIG_IMG = { size: 6 * 1024 * 1024, contentType: "image/jpeg" };
const PDF = { size: 1024, contentType: "application/pdf" };
const EXISTING = { size: 1024, contentType: "image/jpeg", name: "x.jpg", bucket: BUCKET };

// The API rejects unknown fields on testCase, so names are kept alongside.
const names = [];
function testCase(name, expectation, auth, method, objectPath, newResource) {
  names.push(`[${expectation.padEnd(5)}] ${name}`);
  const request = { path: OBJ(objectPath), method, time: TIME };
  if (auth) request.auth = auth;
  if (newResource) request.resource = { ...newResource, name: objectPath, bucket: BUCKET };
  const tc = { expectation, request };
  if (method !== "create") tc.resource = { ...EXISTING, name: objectPath };
  if (auth) tc.functionMocks = mocks[auth.uid];
  return tc;
}

const OWNER_FOLDERS = ["product_images", "size_guides", "boutique_logos", "boutique_banners", "promo_banners"];

const cases = [
  // ══ 1. Public reads ════════════════════════════════════════════════════
  ...[...OWNER_FOLDERS.map((f) => `${f}/b1/1.jpg`), "hero_banners/1.jpg"].map((p) =>
    testCase(`anonymous reads ${p}`, "ALLOW", null, "get", p)),

  // ══ 2. Owner writes ════════════════════════════════════════════════════
  ...OWNER_FOLDERS.map((f) =>
    testCase(`owner uploads to own ${f}/b1`, "ALLOW", OWNER, "create", `${f}/b1/1.jpg`, IMG)),
  ...OWNER_FOLDERS.map((f) =>
    testCase(`owner uploads to OTHER boutique ${f}/b2`, "DENY", OWNER, "create", `${f}/b2/1.jpg`, IMG)),
  testCase("owner deletes own product image", "ALLOW", OWNER, "delete", "product_images/b1/1.jpg"),
  testCase("owner deletes OTHER boutique's product image", "DENY", OWNER, "delete", "product_images/b2/1.jpg"),
  testCase("owner uploads a non-image", "DENY", OWNER, "create", "product_images/b1/1.pdf", PDF),
  testCase("owner uploads a 6 MB image", "DENY", OWNER, "create", "product_images/b1/1.jpg", BIG_IMG),
  testCase("UNAPPROVED owner uploads to own boutique", "DENY", PENDING_OWNER, "create", "product_images/b1/1.jpg", IMG),
  testCase("owner uploads a hero banner", "DENY", OWNER, "create", "hero_banners/1.jpg", IMG),
  testCase("normal user uploads a product image", "DENY", NORMAL, "create", "product_images/b1/1.jpg", IMG),
  testCase("anonymous uploads a product image", "DENY", null, "create", "product_images/b1/1.jpg", IMG),

  // ══ 3. Super admin ═════════════════════════════════════════════════════
  testCase("super uploads a hero banner", "ALLOW", SUPER, "create", "hero_banners/1.jpg", IMG),
  testCase("super deletes a hero banner", "ALLOW", SUPER, "delete", "hero_banners/1.jpg"),
  testCase("super uploads to any boutique's product_images", "ALLOW", SUPER, "create", "product_images/b2/1.jpg", IMG),
  testCase("super deletes any boutique's logo", "ALLOW", SUPER, "delete", "boutique_logos/b2/1.jpg"),
  testCase("super uploads a non-image hero banner", "DENY", SUPER, "create", "hero_banners/1.pdf", PDF),
  testCase("LOOSE admin (role 'admin') uploads a hero banner", "DENY", LOOSE, "create", "hero_banners/1.jpg", IMG),
  testCase("LOOSE admin deletes a hero banner", "DENY", LOOSE, "delete", "hero_banners/1.jpg"),
  testCase("LOOSE admin uploads to a boutique's product_images", "DENY", LOOSE, "create", "product_images/b1/1.jpg", IMG),
  testCase("UNAPPROVED super uploads a hero banner", "DENY", UNAPPROVED, "create", "hero_banners/1.jpg", IMG),
  testCase("normal user uploads a hero banner", "DENY", NORMAL, "create", "hero_banners/1.jpg", IMG),

  // ══ 4. Unknown paths ═══════════════════════════════════════════════════
  testCase("anonymous reads an unknown path", "DENY", null, "get", "private/1.jpg"),
  testCase("super uploads to an unknown path", "DENY", SUPER, "create", "private/1.jpg", IMG),
  testCase("owner uploads to a nested path under own folder", "DENY", OWNER, "create", "product_images/b1/sub/1.jpg", IMG),
];

const body = { testSuite: { testCases: cases } };
if (!RULESET) {
  body.source = { files: [{ name: "storage.rules", content: fs.readFileSync("storage.rules", "utf8") }] };
}
const target = RULESET
  ? `projects/${PROJECT}/rulesets/${RULESET}`
  : `projects/${PROJECT}`;

console.log(`Testing ${RULESET ? `deployed ruleset ${RULESET}` : "local storage.rules"}\n`);

fetch(`https://firebaserules.googleapis.com/v1/${target}:test`, {
  method: "POST",
  headers: {
    Authorization: "Bearer " + process.env.TOK,
    "Content-Type": "application/json",
    "x-goog-user-project": PROJECT,
  },
  body: JSON.stringify(body),
})
  .then((r) => r.json())
  .then((j) => {
    if (j.error) {
      console.log("API ERROR:", JSON.stringify(j.error).slice(0, 600));
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
        console.log("       " + String(r.debugMessages).slice(0, 300));
      }
    });
    console.log(`\n${results.length - failed}/${results.length} storage rules tests passed`);
    if (failed || results.length !== cases.length) process.exit(1);
  });
