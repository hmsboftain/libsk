#!/usr/bin/env node
/**
 * Enforcement tests for the signup-verification rules in firestore.rules.
 *
 * Runs against the real Firebase Rules evaluator over the REST API, so it needs
 * no emulator and no Java — just a gcloud login. Compiling rules only proves
 * they parse; these cases prove they actually deny the attack they exist to
 * stop (a client granting itself emailVerified) while still allowing the writes
 * the app makes on every login.
 *
 * Usage:
 *   TOK=$(gcloud auth print-access-token) node scripts/verify_rules.js
 *
 * Exits non-zero if any case regresses.
 */
const fs = require("fs");

const source = fs.readFileSync("firestore.rules", "utf8");
const TIME = "2026-07-16T12:00:00Z";
const P = "/databases/(default)/documents/users/u1";

// An existing, unverified profile — what a new signup's doc looks like.
const existing = {
  firstName: "A", lastName: "B", email: "a@b.com", phone: "12345678",
  role: "user", isActive: true, emailVerified: false, phoneVerified: false,
};

// The API rejects unknown fields on testCase, so names are kept alongside.
const names = [];
function testCase(name, expectation, req, resource) {
  names.push(`[${expectation.padEnd(5)}] ${name}`);
  const tc = { expectation, request: { ...req, time: TIME } };
  if (resource) tc.resource = resource;
  return tc;
}

const cases = [
  // ── The attack this whole design hinges on ──────────────────────────────
  testCase("self-grant emailVerified", "DENY", {
    auth: { uid: "u1" }, path: P, method: "update",
    resource: { data: { ...existing, emailVerified: true } },
  }, { data: existing }),

  testCase("self-grant phoneVerified", "DENY", {
    auth: { uid: "u1" }, path: P, method: "update",
    resource: { data: { ...existing, phoneVerified: true } },
  }, { data: existing }),

  testCase("self-grant verificationExempt", "DENY", {
    auth: { uid: "u1" }, path: P, method: "update",
    resource: { data: { ...existing, verificationExempt: true } },
  }, { data: existing }),

  // ── Create-time bypass ──────────────────────────────────────────────────
  testCase("create already-verified", "DENY", {
    auth: { uid: "u1" }, path: P, method: "create",
    resource: { data: { ...existing, emailVerified: true } },
  }),

  testCase("create exempt", "DENY", {
    auth: { uid: "u1" }, path: P, method: "create",
    resource: { data: { ...existing, verificationExempt: true } },
  }),

  // ── Legitimate traffic must still pass ──────────────────────────────────
  testCase("create unverified profile", "ALLOW", {
    auth: { uid: "u1" }, path: P, method: "create",
    resource: { data: existing },
  }),

  testCase("edit own name", "ALLOW", {
    auth: { uid: "u1" }, path: P, method: "update",
    resource: { data: { ...existing, firstName: "Changed" } },
  }, { data: existing }),

  // setCurrentUserOnline / updateCurrentUserLastLogin run on every login.
  testCase("login sets isOnline", "ALLOW", {
    auth: { uid: "u1" }, path: P, method: "update",
    resource: { data: { ...existing, isOnline: true } },
  }, { data: existing }),

  // ── Role protection must not have regressed ─────────────────────────────
  testCase("self-promote role", "DENY", {
    auth: { uid: "u1" }, path: P, method: "update",
    resource: { data: { ...existing, role: "boutique_owner" } },
  }, { data: existing }),
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
