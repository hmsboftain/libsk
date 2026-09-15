"use strict";

// ============ ONE-TIME BACKFILL: BOUTIQUE COMMISSION FIELDS ============
//
// Stamps the Payzah multivendor commission config onto EXISTING boutique docs
// that don't have it yet:
//
//   commissionType:    2   (percentage)
//   commissionPercent: 12
//   commissionFixed:   0
//
// Matches DEFAULT_COMMISSION in ../payzah_commission.js — keep them in sync. If
// you change the default rate, change it there first, then re-read it here.
//
// SAFETY:
//   * DRY RUN by default — prints what WOULD change and writes nothing.
//     Re-run with APPLY=1 to actually write.
//   * NON-DESTRUCTIVE — only sets a field that is missing on a given doc; a
//     field already present (any value) is left untouched. A doc that already
//     has all three fields is skipped entirely.
//   * Runs against LIVE Firestore via Application Default Credentials. Make
//     sure you're pointed at the right project first:
//       gcloud auth application-default login
//       gcloud config set project libsk-b68f5
//
// USAGE (from functions/):
//   node scripts/backfill-boutique-commission.js            # dry run
//   APPLY=1 node scripts/backfill-boutique-commission.js    # write
//
// This script is intentionally NOT wired into deploy and is not a Cloud
// Function — it's run by hand, once, after the default rate is finalized.

const admin = require("firebase-admin");
const { DEFAULT_COMMISSION } = require("../payzah_commission");

const PROJECT = process.env.GCLOUD_PROJECT || "libsk-b68f5";
const APPLY = process.env.APPLY === "1";

// Guard: never silently run against the emulator for a "real" backfill, and
// never let APPLY run against the emulator by accident either.
if (process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    `Refusing to run: FIRESTORE_EMULATOR_HOST is set (${process.env.FIRESTORE_EMULATOR_HOST}).\n` +
    "This backfill targets live Firestore. Unset it and retry.",
  );
  process.exit(1);
}

admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();

async function main() {
  console.log(
    `\nBoutique commission backfill — project ${PROJECT} — ${APPLY ? "APPLY (writing)" : "DRY RUN (no writes)"}\n`,
  );
  console.log(
    `Defaults: commissionType=${DEFAULT_COMMISSION.commissionType}, ` +
    `commissionPercent=${DEFAULT_COMMISSION.commissionPercent}, ` +
    `commissionFixed=${DEFAULT_COMMISSION.commissionFixed}\n`,
  );

  const snap = await db.collection("boutiques").get();
  let scanned = 0;
  let toUpdate = 0;
  let skipped = 0;
  const writes = [];

  snap.forEach((doc) => {
    scanned += 1;
    const data = doc.data() || {};
    const patch = {};

    // Only set a field that is entirely absent — never overwrite an existing
    // value (hasOwnProperty so a legitimate 0 is treated as present).
    if (!Object.prototype.hasOwnProperty.call(data, "commissionType")) {
      patch.commissionType = DEFAULT_COMMISSION.commissionType;
    }
    if (!Object.prototype.hasOwnProperty.call(data, "commissionPercent")) {
      patch.commissionPercent = DEFAULT_COMMISSION.commissionPercent;
    }
    if (!Object.prototype.hasOwnProperty.call(data, "commissionFixed")) {
      patch.commissionFixed = DEFAULT_COMMISSION.commissionFixed;
    }

    if (Object.keys(patch).length === 0) {
      skipped += 1;
      return;
    }
    toUpdate += 1;
    const name = data.name || "(unnamed)";
    console.log(`  ${doc.id}  ${name}  -> set ${JSON.stringify(patch)}`);
    writes.push({ ref: doc.ref, patch });
  });

  console.log(
    `\nScanned ${scanned} boutique(s): ${toUpdate} need defaults, ${skipped} already complete.`,
  );

  if (!APPLY) {
    console.log("\nDRY RUN — nothing written. Re-run with APPLY=1 to commit.\n");
    return;
  }
  if (writes.length === 0) {
    console.log("\nNothing to write.\n");
    return;
  }

  // Firestore batches cap at 500 writes; chunk to stay under it.
  const CHUNK = 400;
  for (let i = 0; i < writes.length; i += CHUNK) {
    const batch = db.batch();
    for (const { ref, patch } of writes.slice(i, i + CHUNK)) {
      batch.set(ref, patch, { merge: true });
    }
    await batch.commit();
  }
  console.log(`\nDone — updated ${writes.length} boutique(s).\n`);
}

main().catch((err) => {
  console.error("\nBackfill failed:", err);
  process.exit(1);
});
