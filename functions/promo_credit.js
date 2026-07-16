// ================= FOUNDING-PARTNER PROMO CREDIT: PURE MATH =================
//
// All money-critical credit arithmetic lives here as PURE functions (no I/O, no
// Firestore, no clock) so it can be unit-tested directly against source — see
// test/promo_credit.test.js. index.js requires this module; the Cloud Functions
// there do the reads/writes and delegate every calculation to these helpers.
//
// WHY FILS: KWD has 3 decimal places (1 KWD = 1000 fils). Doing credit math in
// floating-point KWD invites dust like `6 - 5.001 === 0.9990000000000001`, which
// would break the "fully covered" (charge === 0) branch at checkout. So every
// internal calculation is in INTEGER fils; we convert to a 3-dp KWD number only
// at the Firestore boundary (the denormalized display balance) and to a 3-dp
// string only at the Payzah boundary.

// Free promo credit granted to founding-partner boutiques, relative to launch.
const FOUNDING_WEEK1_KWD = 6; // granted by the one-time launch recharge
const FOUNDING_WEEK2_KWD = 3; // granted 7 days later by the daily scheduler
const CREDIT_EXPIRY_DAYS = 7; // every grant expires this many days after it lands

// KWD (number) → integer fils. Rounds to the nearest fil so a 3-dp input is
// exact and a stray float (e.g. 1.4999999) can't truncate the wrong way.
function kwdToFils(kwd) {
  return Math.round(Number(kwd) * 1000);
}

// Integer fils → KWD (number), exact to 3 dp. Rounds the input first so callers
// can't accidentally persist a fractional-fil balance.
function filsToKwd(fils) {
  return Math.round(Number(fils)) / 1000;
}

// Apply a fils delta to a KWD balance WITHOUT float drift: convert the existing
// balance to integer fils, add the (integer) delta, convert back. Used by every
// mutation that moves the denormalized promoCreditBalance, so repeated
// grant/spend/expiry writes never accumulate rounding error.
function applyFilsDelta(balanceKwd, deltaFils) {
  return filsToKwd(kwdToFils(balanceKwd || 0) + Math.round(Number(deltaFils)));
}

// Is a grant spendable at nowMs? It must have credit left and not have expired.
// A null/absent expiry means "never expires" (a deliberate admin top-up option).
function isGrantSpendable(grant, nowMs) {
  const remaining = Math.floor(Number(grant.remainingFils) || 0);
  if (remaining <= 0) return false;
  const exp = grant.expiresAtMs;
  return exp == null || exp > nowMs;
}

// Sum of spendable credit at nowMs, in fils. This is the AUTHORITATIVE balance
// used for allocation decisions — it excludes expired-but-not-yet-swept grants,
// so we never spend credit that has lapsed even if the daily sweep hasn't run
// and the denormalized display balance is briefly stale-high.
function spendableBalanceFils(grants, nowMs) {
  let sum = 0;
  for (const g of grants) {
    if (isGrantSpendable(g, nowMs)) sum += Math.floor(Number(g.remainingFils) || 0);
  }
  return sum;
}

// FIFO order for spending: soonest-expiring grant first (so credit about to
// lapse is used before credit that lasts longer), never-expiring grants last.
// Ties break by grant age then id, so allocation is fully deterministic.
function compareGrantsForSpend(a, b) {
  const ax = a.expiresAtMs == null ? Infinity : a.expiresAtMs;
  const bx = b.expiresAtMs == null ? Infinity : b.expiresAtMs;
  if (ax !== bx) return ax - bx;
  const ac = a.createdAtMs == null ? 0 : a.createdAtMs;
  const bc = b.createdAtMs == null ? 0 : b.createdAtMs;
  if (ac !== bc) return ac - bc;
  return String(a.id).localeCompare(String(b.id));
}

// Allocate `spendFils` across the given grants, FIFO by expiry, spending only
// what each grant has left and only from grants still spendable at nowMs. Pure:
// it returns the allocation trail and totals but mutates nothing.
//
//   grants: [{ id, remainingFils, expiresAtMs|null, createdAtMs|null }]
//   → { allocations: [{ creditId, fils }],  // grants drawn from, in spend order
//       allocatedFils,                       // total actually taken (<= spendFils)
//       shortfallFils }                      // spendFils not covered (0 if fully met)
//
// A non-zero shortfall means the caller asked to spend more than is available;
// callers decide whether that's a clamp (clawback) or a logged anomaly
// (settlement race). This function never over-allocates a grant or the request.
function allocateCreditFifo(grants, spendFils, nowMs) {
  const want = Math.max(0, Math.floor(Number(spendFils) || 0));
  const order = grants
    .filter((g) => isGrantSpendable(g, nowMs))
    .sort(compareGrantsForSpend);

  const allocations = [];
  let remaining = want;
  for (const g of order) {
    if (remaining <= 0) break;
    const avail = Math.floor(Number(g.remainingFils) || 0);
    const take = Math.min(avail, remaining);
    if (take > 0) {
      allocations.push({ creditId: g.id, fils: take });
      remaining -= take;
    }
  }
  return { allocations, allocatedFils: want - remaining, shortfallFils: remaining };
}

// Decide how a booking's price splits between promo credit and a Payzah charge,
// given the boutique's live spendable balance (in fils). Pure — the caller reads
// the balance and passes it in.
//   creditFils  — what credit covers (0 when not opted in, or no balance)
//   chargeFils  — the remainder to charge through the gateway
//   creditOnly  — true iff credit covers the WHOLE price, so the gateway is
//                 skipped and the booking is written as already paid
// The split always drains the smaller of (balance, price): a partial credit
// therefore spends the entire balance and charges the rest; full coverage
// charges nothing. All integer fils, so the creditOnly (chargeFils === 0) test
// is exact.
function splitCreditCharge(balanceFils, priceFils, useCredit) {
  const price = Math.max(0, Math.floor(Number(priceFils) || 0));
  const bal = Math.max(0, Math.floor(Number(balanceFils) || 0));
  const creditFils = useCredit ? Math.min(bal, price) : 0;
  const chargeFils = price - creditFils;
  return { creditFils, chargeFils, creditOnly: chargeFils === 0 };
}

module.exports = {
  FOUNDING_WEEK1_KWD,
  FOUNDING_WEEK2_KWD,
  CREDIT_EXPIRY_DAYS,
  kwdToFils,
  filsToKwd,
  applyFilsDelta,
  isGrantSpendable,
  spendableBalanceFils,
  compareGrantsForSpend,
  allocateCreditFifo,
  splitCreditCharge,
};
