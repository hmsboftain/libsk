/**
 * Pure email-OTP logic — code generation, hashing, and the verify-attempt state
 * machine. Kept free of Firestore and Auth so the decision table can be unit
 * tested directly (test/email_otp.test.js); index.js owns the transaction and
 * the I/O around it.
 */

const crypto = require("crypto");

const OTP_TTL_MS = 10 * 60 * 1000;        // code lifetime: 10 minutes
const OTP_MAX_ATTEMPTS = 5;               // wrong guesses per issued code
const OTP_RESEND_COOLDOWN_MS = 60 * 1000; // minimum gap between sends

function generateOtp() {
  // randomInt is uniform and unpredictable. Math.random() is neither, and this
  // code is the only thing between a guessed email and a live account.
  return String(crypto.randomInt(0, 1000000)).padStart(6, "0");
}

function hashOtp(uid, code) {
  // Salted per-uid, so the same code issued to two users doesn't collide, and
  // stored hashed so console access or a stray log doesn't expose live codes.
  // Not meaningful against offline brute force — a 6-digit space falls
  // instantly. The real protections are the server-only rule on email_otps,
  // the attempt cap and the TTL.
  return crypto.createHash("sha256").update(`${uid}.${code}`).digest("hex");
}

function isValidOtpFormat(code) {
  return /^\d{6}$/.test(String(code || "").trim());
}

/**
 * Decides what a verify attempt should do, without performing it.
 *
 * @param {object|null} record  the stored email_otps doc data, or null if absent
 * @param {string} uid
 * @param {string} code         the code the user submitted
 * @param {number} now          epoch ms
 * @returns {{ok: boolean, reason?: string, remaining?: number, consume: boolean, incrementTo?: number}}
 *   consume — the caller should delete the record (verified, or expired/spent)
 */
function evaluateOtpAttempt({ record, uid, code, now }) {
  if (!record) {
    return { ok: false, reason: "no-code", consume: false };
  }
  if (now > record.expiresAt) {
    return { ok: false, reason: "expired", consume: true };
  }
  if ((record.attempts || 0) >= OTP_MAX_ATTEMPTS) {
    // The code is burned, not the account — locking the account here would hand
    // anyone a denial-of-service against a known email address.
    return { ok: false, reason: "too-many-attempts", consume: false };
  }

  const expected = Buffer.from(record.hash, "hex");
  const actual = Buffer.from(hashOtp(uid, code), "hex");
  const match =
    expected.length === actual.length && crypto.timingSafeEqual(expected, actual);

  if (!match) {
    const attempts = (record.attempts || 0) + 1;
    return {
      ok: false,
      reason: "mismatch",
      remaining: OTP_MAX_ATTEMPTS - attempts,
      consume: false,
      incrementTo: attempts,
    };
  }

  // Single-use: the caller deletes it so a replayed code can't verify twice.
  return { ok: true, consume: true };
}

/**
 * Milliseconds the caller must still wait before a resend is allowed.
 * Returns 0 when a resend is permitted.
 */
function resendWaitMs(lastSentAt, now) {
  const wait = OTP_RESEND_COOLDOWN_MS - (now - (lastSentAt || 0));
  return wait > 0 ? wait : 0;
}

module.exports = {
  OTP_TTL_MS,
  OTP_MAX_ATTEMPTS,
  OTP_RESEND_COOLDOWN_MS,
  generateOtp,
  hashOtp,
  isValidOtpFormat,
  evaluateOtpAttempt,
  resendWaitMs,
};
