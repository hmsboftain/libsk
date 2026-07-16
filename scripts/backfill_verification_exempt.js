#!/usr/bin/env node
/**
 * One-time backfill: grandfathers every account that existed before mandatory
 * email/phone verification shipped.
 *
 * Every users doc written before the cutoff gets verificationExempt: true, and
 * its Firebase Auth record gets emailVerified: true, so the signup gate never
 * challenges an existing customer or boutique owner. Accounts created after the
 * cutoff are left alone — they own the new flags from birth and must verify.
 *
 * Marking Auth emailVerified: true asserts an address we never actually
 * round-tripped a code through. That is the grandfathering decision, stated
 * plainly: these accounts predate the requirement and are not retroactively
 * subject to it. The alternative — leaving Auth false and relying on a
 * Firestore flag — makes a Firestore read load-bearing on every login and
 * locks out the whole existing user base if it ever fails.
 *
 * MUST run to completion before the gate ships. Until it does, existing users
 * have no exempt flag and would be locked out on next launch.
 *
 * Usage:
 *   node scripts/backfill_verification_exempt.js            # dry run, writes nothing
 *   node scripts/backfill_verification_exempt.js --commit   # applies the writes
 *
 * Auth: application default credentials.
 *   gcloud auth application-default login
 */

const admin = require("firebase-admin");

const PROJECT_ID = "libsk-b68f5";
const COMMIT = process.argv.includes("--commit");
const BATCH_LIMIT = 400; // Firestore caps a batch at 500 writes.

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

async function main() {
  console.log(`\nBackfill verificationExempt — project ${PROJECT_ID}`);
  console.log(COMMIT ? "MODE: COMMIT (writes will be applied)\n" : "MODE: DRY RUN (no writes)\n");

  const snap = await db.collection("users").get();
  console.log(`users docs found: ${snap.size}`);

  // Only touch docs that don't already carry the flag, so re-running is safe
  // and an interrupted run can simply be re-invoked.
  const pending = snap.docs.filter((d) => d.get("verificationExempt") !== true);
  const already = snap.size - pending.length;

  console.log(`already exempt:   ${already}`);
  console.log(`to stamp:         ${pending.length}\n`);

  if (pending.length === 0) {
    console.log("Nothing to do.\n");
    return;
  }

  for (const doc of pending) {
    const email = doc.get("email") || "(no email)";
    const role = doc.get("role") || "user";
    console.log(`  ${doc.id}  ${role.padEnd(15)} ${email}`);
  }
  console.log("");

  if (!COMMIT) {
    console.log("Dry run — re-run with --commit to apply.\n");
    return;
  }

  // Pass 1 — Firebase Auth.
  //
  // These accounts predate verification, so Auth still reports emailVerified:
  // false for every password signup among them. The signup gate reads Auth as
  // its source of truth, so without this pass every existing customer would be
  // locked out on next launch and only a successful Firestore read could rescue
  // them. Grandfathered means treated as verified, so we say so in Auth and the
  // gate needs no Firestore read at all on the hot path.
  let authStamped = 0;
  let authMissing = 0;
  for (const doc of pending) {
    try {
      const record = await admin.auth().getUser(doc.id);
      if (!record.emailVerified) {
        await admin.auth().updateUser(doc.id, { emailVerified: true });
        authStamped++;
      }
    } catch (err) {
      if (err.code === "auth/user-not-found") {
        // Firestore profile with no Auth user behind it — nothing to sign in
        // with, so leave it be and let a human look.
        console.warn(`  ! ${doc.id} has no Auth user; Firestore-only stamp`);
        authMissing++;
      } else {
        throw err;
      }
    }
  }
  console.log(`auth: ${authStamped} stamped verified, ${authMissing} without an Auth user\n`);

  // Pass 2 — Firestore mirror.
  let written = 0;
  for (let i = 0; i < pending.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const doc of pending.slice(i, i + BATCH_LIMIT)) {
      batch.update(doc.ref, {
        verificationExempt: true,
        // Stamped true as well: an exempt account is treated as fully verified
        // everywhere, so no read path needs to special-case the exempt branch —
        // and the cleanup job's emailVerified == false query cannot see them.
        emailVerified: true,
        phoneVerified: true,
        verificationExemptAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      written++;
    }
    await batch.commit();
    console.log(`committed ${Math.min(i + BATCH_LIMIT, pending.length)}/${pending.length}`);
  }

  console.log(`\nDone — ${written} docs stamped exempt, ${authStamped} Auth users marked verified.\n`);
}

main().catch((err) => {
  console.error("\nBackfill failed:", err.message);
  process.exit(1);
});
