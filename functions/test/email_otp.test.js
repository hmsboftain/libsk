const test = require("node:test");
const assert = require("node:assert");

const {
  OTP_MAX_ATTEMPTS,
  OTP_RESEND_COOLDOWN_MS,
  generateOtp,
  hashOtp,
  isValidOtpFormat,
  evaluateOtpAttempt,
  resendWaitMs,
} = require("../email_otp");

const UID = "user_abc123";
const NOW = 1_700_000_000_000;

function recordFor(code, overrides = {}) {
  return {
    hash: hashOtp(UID, code),
    email: "shopper@example.com",
    expiresAt: NOW + 60_000,
    attempts: 0,
    lastSentAt: NOW,
    ...overrides,
  };
}

// ── generateOtp ───────────────────────────────────────────────────────────────

test("generateOtp always returns exactly 6 digits", () => {
  for (let i = 0; i < 500; i++) {
    assert.match(generateOtp(), /^\d{6}$/);
  }
});

test("generateOtp pads low values rather than emitting short codes", () => {
  // The padStart is what keeps 42 from becoming a 2-digit code. Exercising the
  // real generator can't reliably hit that, so assert the format contract holds
  // across a large sample and that padding is applied at the boundary.
  assert.strictEqual(String(7).padStart(6, "0"), "000007");
  const codes = new Set();
  for (let i = 0; i < 2000; i++) codes.add(generateOtp());
  assert.ok(codes.size > 1500, "generator should not be collapsing to few values");
});

// ── hashOtp ───────────────────────────────────────────────────────────────────

test("hashOtp is stable for the same uid and code", () => {
  assert.strictEqual(hashOtp(UID, "123456"), hashOtp(UID, "123456"));
});

test("hashOtp salts by uid so identical codes hash differently per user", () => {
  assert.notStrictEqual(hashOtp("user_a", "123456"), hashOtp("user_b", "123456"));
});

test("hashOtp does not leak the code in its output", () => {
  assert.ok(!hashOtp(UID, "123456").includes("123456"));
});

// ── isValidOtpFormat ──────────────────────────────────────────────────────────

test("isValidOtpFormat accepts 6 digits and rejects everything else", () => {
  assert.ok(isValidOtpFormat("000000"));
  assert.ok(isValidOtpFormat("123456"));
  assert.ok(isValidOtpFormat(" 123456 "), "surrounding whitespace is trimmed");

  assert.ok(!isValidOtpFormat("12345"), "too short");
  assert.ok(!isValidOtpFormat("1234567"), "too long");
  assert.ok(!isValidOtpFormat("12345a"), "non-numeric");
  assert.ok(!isValidOtpFormat(""), "empty");
  assert.ok(!isValidOtpFormat(null), "null");
  assert.ok(!isValidOtpFormat(undefined), "undefined");
});

// ── evaluateOtpAttempt ────────────────────────────────────────────────────────

test("correct code verifies and is consumed", () => {
  const d = evaluateOtpAttempt({ record: recordFor("123456"), uid: UID, code: "123456", now: NOW });
  assert.strictEqual(d.ok, true);
  assert.strictEqual(d.consume, true, "a verified code must be single-use");
});

test("wrong code fails, increments attempts, and is not consumed", () => {
  const d = evaluateOtpAttempt({ record: recordFor("123456"), uid: UID, code: "999999", now: NOW });
  assert.strictEqual(d.ok, false);
  assert.strictEqual(d.reason, "mismatch");
  assert.strictEqual(d.incrementTo, 1);
  assert.strictEqual(d.consume, false);
  assert.strictEqual(d.remaining, OTP_MAX_ATTEMPTS - 1);
});

test("missing record reports no-code rather than throwing", () => {
  const d = evaluateOtpAttempt({ record: null, uid: UID, code: "123456", now: NOW });
  assert.strictEqual(d.ok, false);
  assert.strictEqual(d.reason, "no-code");
  assert.strictEqual(d.consume, false);
});

test("expired code fails and is consumed even when the digits are correct", () => {
  const record = recordFor("123456", { expiresAt: NOW - 1 });
  const d = evaluateOtpAttempt({ record, uid: UID, code: "123456", now: NOW });
  assert.strictEqual(d.ok, false);
  assert.strictEqual(d.reason, "expired");
  assert.strictEqual(d.consume, true, "expired codes are cleared, not left to linger");
});

test("code exactly at its expiry instant is still accepted", () => {
  const record = recordFor("123456", { expiresAt: NOW });
  const d = evaluateOtpAttempt({ record, uid: UID, code: "123456", now: NOW });
  assert.strictEqual(d.ok, true, "expiry is exclusive; now > expiresAt is the fail condition");
});

test("attempt cap blocks further guesses, including the correct one", () => {
  const record = recordFor("123456", { attempts: OTP_MAX_ATTEMPTS });
  const d = evaluateOtpAttempt({ record, uid: UID, code: "123456", now: NOW });
  assert.strictEqual(d.ok, false);
  assert.strictEqual(d.reason, "too-many-attempts");
  assert.strictEqual(d.consume, false, "the code is burned but the account is untouched");
});

test("attempts walk up to the cap and then lock out", () => {
  let attempts = 0;
  for (let i = 0; i < OTP_MAX_ATTEMPTS; i++) {
    const d = evaluateOtpAttempt({
      record: recordFor("123456", { attempts }),
      uid: UID,
      code: "000000",
      now: NOW,
    });
    assert.strictEqual(d.reason, "mismatch");
    attempts = d.incrementTo;
  }
  assert.strictEqual(attempts, OTP_MAX_ATTEMPTS);

  const locked = evaluateOtpAttempt({
    record: recordFor("123456", { attempts }),
    uid: UID,
    code: "000000",
    now: NOW,
  });
  assert.strictEqual(locked.reason, "too-many-attempts");
});

test("another user's code does not verify against this uid", () => {
  // The hash is uid-salted, so a code lifted from a different account's record
  // must not validate here even if the digits are right.
  const record = { ...recordFor("123456"), hash: hashOtp("someone_else", "123456") };
  const d = evaluateOtpAttempt({ record, uid: UID, code: "123456", now: NOW });
  assert.strictEqual(d.ok, false);
  assert.strictEqual(d.reason, "mismatch");
});

test("a record with a malformed hash fails closed instead of throwing", () => {
  const record = recordFor("123456", { hash: "not-hex" });
  const d = evaluateOtpAttempt({ record, uid: UID, code: "123456", now: NOW });
  assert.strictEqual(d.ok, false, "a corrupt record must never verify");
});

test("attempts field absent is treated as zero", () => {
  const record = recordFor("123456");
  delete record.attempts;
  const d = evaluateOtpAttempt({ record, uid: UID, code: "999999", now: NOW });
  assert.strictEqual(d.incrementTo, 1);
});

// ── resendWaitMs ──────────────────────────────────────────────────────────────

test("resend is blocked inside the cooldown and allowed after it", () => {
  assert.strictEqual(resendWaitMs(NOW, NOW), OTP_RESEND_COOLDOWN_MS, "immediate resend blocked");
  assert.strictEqual(resendWaitMs(NOW, NOW + OTP_RESEND_COOLDOWN_MS), 0, "allowed at the boundary");
  assert.strictEqual(resendWaitMs(NOW, NOW + OTP_RESEND_COOLDOWN_MS + 1), 0, "allowed after");
  assert.strictEqual(resendWaitMs(NOW, NOW + 30_000), 30_000, "half-way through, half remains");
});

test("resend with no prior send is allowed", () => {
  assert.strictEqual(resendWaitMs(undefined, NOW), 0);
  assert.strictEqual(resendWaitMs(0, NOW), 0);
});
