// Unit tests for the pure founding-partner credit math in ../promo_credit.js.
// Run with `npm test` (functions/) — uses the Node built-in test runner, no deps.
// These exercise the REAL source module the Cloud Functions call, so a green run
// means the fils/FIFO logic index.js relies on is correct.

const { test } = require("node:test");
const assert = require("node:assert/strict");

const {
  kwdToFils,
  filsToKwd,
  applyFilsDelta,
  isGrantSpendable,
  spendableBalanceFils,
  allocateCreditFifo,
  splitCreditCharge,
} = require("../promo_credit");

const DAY = 24 * 60 * 60 * 1000;
const NOW = 1_700_000_000_000; // fixed clock for determinism

// ─────────────────────────── fils conversion ───────────────────────────

test("kwdToFils rounds to the nearest fil", () => {
  assert.equal(kwdToFils(6), 6000);
  assert.equal(kwdToFils(3), 3000);
  assert.equal(kwdToFils(1.5), 1500);
  assert.equal(kwdToFils(0), 0);
  assert.equal(kwdToFils(0.001), 1);
  // A float that isn't exactly representable must still land on the right fil.
  assert.equal(kwdToFils(1.499999999), 1500);
  assert.equal(kwdToFils(12.345), 12345);
});

test("filsToKwd is the exact inverse for whole fils", () => {
  assert.equal(filsToKwd(6000), 6);
  assert.equal(filsToKwd(1), 0.001);
  assert.equal(filsToKwd(12345), 12.345);
  assert.equal(filsToKwd(0), 0);
});

test("applyFilsDelta moves a KWD balance without float drift", () => {
  // The classic float trap: 6 - 5.001 in KWD would be 0.9990000000000001.
  assert.equal(applyFilsDelta(6, -kwdToFils(5.001)), 0.999);
  // Grant then partial spend then expiry, all exact.
  let bal = 0;
  bal = applyFilsDelta(bal, +6000); // grant 6
  assert.equal(bal, 6);
  bal = applyFilsDelta(bal, -4000); // spend 4
  assert.equal(bal, 2);
  bal = applyFilsDelta(bal, -2000); // expire remaining 2
  assert.equal(bal, 0);

  // Many tiny alternating moves must not accumulate error.
  let b = 10;
  for (let i = 0; i < 1000; i++) b = applyFilsDelta(b, i % 2 === 0 ? -1 : +1);
  assert.equal(b, 10); // 500 down, 500 up
});

// ─────────────────────────── spendability ───────────────────────────

test("isGrantSpendable respects remaining and expiry", () => {
  assert.equal(isGrantSpendable({ remainingFils: 100, expiresAtMs: NOW + DAY }, NOW), true);
  assert.equal(isGrantSpendable({ remainingFils: 0, expiresAtMs: NOW + DAY }, NOW), false);
  assert.equal(isGrantSpendable({ remainingFils: 100, expiresAtMs: NOW - 1 }, NOW), false);
  assert.equal(isGrantSpendable({ remainingFils: 100, expiresAtMs: NOW }, NOW), false); // exact expiry = lapsed
  assert.equal(isGrantSpendable({ remainingFils: 100, expiresAtMs: null }, NOW), true); // never expires
});

test("spendableBalanceFils sums only live grants", () => {
  const grants = [
    { id: "a", remainingFils: 6000, expiresAtMs: NOW + DAY },
    { id: "b", remainingFils: 3000, expiresAtMs: NOW - DAY }, // expired
    { id: "c", remainingFils: 0, expiresAtMs: NOW + DAY }, // consumed
    { id: "d", remainingFils: 1500, expiresAtMs: null }, // never expires
  ];
  assert.equal(spendableBalanceFils(grants, NOW), 7500);
});

// ─────────────────────────── FIFO allocation ───────────────────────────

test("allocateCreditFifo spends soonest-expiring first", () => {
  const grants = [
    { id: "late", remainingFils: 6000, expiresAtMs: NOW + 10 * DAY },
    { id: "soon", remainingFils: 3000, expiresAtMs: NOW + 1 * DAY },
  ];
  const r = allocateCreditFifo(grants, 4000, NOW);
  assert.deepEqual(r.allocations, [
    { creditId: "soon", fils: 3000 },
    { creditId: "late", fils: 1000 },
  ]);
  assert.equal(r.allocatedFils, 4000);
  assert.equal(r.shortfallFils, 0);
});

test("allocateCreditFifo never over-draws a single grant or the request", () => {
  const grants = [{ id: "g", remainingFils: 2500, expiresAtMs: NOW + DAY }];
  const exact = allocateCreditFifo(grants, 2500, NOW);
  assert.deepEqual(exact.allocations, [{ creditId: "g", fils: 2500 }]);
  assert.equal(exact.shortfallFils, 0);

  const over = allocateCreditFifo(grants, 4000, NOW);
  assert.deepEqual(over.allocations, [{ creditId: "g", fils: 2500 }]);
  assert.equal(over.allocatedFils, 2500);
  assert.equal(over.shortfallFils, 1500); // asked 4.000, only 2.500 available
});

test("allocateCreditFifo skips expired grants and reports the shortfall", () => {
  const grants = [
    { id: "dead", remainingFils: 5000, expiresAtMs: NOW - DAY },
    { id: "live", remainingFils: 1000, expiresAtMs: NOW + DAY },
  ];
  const r = allocateCreditFifo(grants, 3000, NOW);
  assert.deepEqual(r.allocations, [{ creditId: "live", fils: 1000 }]);
  assert.equal(r.allocatedFils, 1000);
  assert.equal(r.shortfallFils, 2000);
});

test("allocateCreditFifo orders never-expiring grants last", () => {
  const grants = [
    { id: "forever", remainingFils: 5000, expiresAtMs: null },
    { id: "dated", remainingFils: 2000, expiresAtMs: NOW + 5 * DAY },
  ];
  const r = allocateCreditFifo(grants, 3000, NOW);
  assert.deepEqual(r.allocations, [
    { creditId: "dated", fils: 2000 },
    { creditId: "forever", fils: 1000 },
  ]);
});

test("allocateCreditFifo breaks expiry ties by createdAt then id", () => {
  const exp = NOW + DAY;
  const grants = [
    { id: "z", remainingFils: 1000, expiresAtMs: exp, createdAtMs: 200 },
    { id: "a", remainingFils: 1000, expiresAtMs: exp, createdAtMs: 100 },
  ];
  const r = allocateCreditFifo(grants, 1500, NOW);
  // Older (createdAtMs 100) first, regardless of array/id order.
  assert.deepEqual(r.allocations, [
    { creditId: "a", fils: 1000 },
    { creditId: "z", fils: 500 },
  ]);
});

test("allocateCreditFifo handles zero / negative requests", () => {
  const grants = [{ id: "g", remainingFils: 6000, expiresAtMs: NOW + DAY }];
  for (const amt of [0, -1, -5000]) {
    const r = allocateCreditFifo(grants, amt, NOW);
    assert.deepEqual(r.allocations, []);
    assert.equal(r.allocatedFils, 0);
    assert.equal(r.shortfallFils, 0);
  }
});

test("allocateCreditFifo with no grants is a full shortfall", () => {
  const r = allocateCreditFifo([], 3000, NOW);
  assert.deepEqual(r.allocations, []);
  assert.equal(r.allocatedFils, 0);
  assert.equal(r.shortfallFils, 3000);
});

// ─────────────────── realistic founding-partner scenario ───────────────────

test("founding week1 then a 4 KWD partial spend leaves 2 KWD", () => {
  // Week-1 grant of 6 KWD, expiring in 7 days.
  const grants = [
    { id: "w1", remainingFils: kwdToFils(6), expiresAtMs: NOW + 7 * DAY, createdAtMs: NOW },
  ];
  const price = kwdToFils(4); // a featured_product-style booking
  const balance = spendableBalanceFils(grants, NOW);
  assert.equal(balance, 6000);

  const credit = Math.min(balance, price); // fully covered → case A
  assert.equal(credit, 4000);
  const charge = price - credit;
  assert.equal(charge, 0);

  const alloc = allocateCreditFifo(grants, credit, NOW);
  assert.deepEqual(alloc.allocations, [{ creditId: "w1", fils: 4000 }]);

  // Remaining after the spend, and the new display balance.
  const newBalanceKwd = applyFilsDelta(filsToKwd(balance), -alloc.allocatedFils);
  assert.equal(newBalanceKwd, 2);
});

test("overlapping week1 + week2 grants spend week1 first (nearer expiry)", () => {
  const grants = [
    { id: "w1", remainingFils: kwdToFils(6), expiresAtMs: NOW + 2 * DAY, createdAtMs: NOW - 5 * DAY },
    { id: "w2", remainingFils: kwdToFils(3), expiresAtMs: NOW + 9 * DAY, createdAtMs: NOW },
  ];
  // A 7 KWD banner booking: 6 from week1, 1 from week2.
  const r = allocateCreditFifo(grants, kwdToFils(7), NOW);
  assert.deepEqual(r.allocations, [
    { creditId: "w1", fils: 6000 },
    { creditId: "w2", fils: 1000 },
  ]);
  assert.equal(r.shortfallFils, 0);
});

// ─────────────────── credit / charge split (checkout branch) ───────────────────

test("splitCreditCharge: full coverage is credit-only (skips the gateway)", () => {
  // 6 KWD balance vs a 4 KWD booking → all credit, nothing to charge.
  const r = splitCreditCharge(kwdToFils(6), kwdToFils(4), true);
  assert.deepEqual(r, { creditFils: 4000, chargeFils: 0, creditOnly: true });
});

test("splitCreditCharge: exact coverage is credit-only", () => {
  const r = splitCreditCharge(kwdToFils(4), kwdToFils(4), true);
  assert.deepEqual(r, { creditFils: 4000, chargeFils: 0, creditOnly: true });
});

test("splitCreditCharge: partial coverage drains balance, charges remainder", () => {
  // 3 KWD balance vs a 7 KWD banner → spend all 3, charge 4 via Payzah.
  const r = splitCreditCharge(kwdToFils(3), kwdToFils(7), true);
  assert.deepEqual(r, { creditFils: 3000, chargeFils: 4000, creditOnly: false });
});

test("splitCreditCharge: fractional balance leaves an exact (non-float) charge", () => {
  // The classic trap: a 1.500 KWD balance against a 4.000 booking.
  const r = splitCreditCharge(kwdToFils(1.5), kwdToFils(4), true);
  assert.deepEqual(r, { creditFils: 1500, chargeFils: 2500, creditOnly: false });
  assert.equal(filsToKwd(r.chargeFils), 2.5); // exact, no 2.4999999
});

test("splitCreditCharge: opting out charges the full price, credit untouched", () => {
  const r = splitCreditCharge(kwdToFils(6), kwdToFils(4), false);
  assert.deepEqual(r, { creditFils: 0, chargeFils: 4000, creditOnly: false });
});

test("splitCreditCharge: opted in but zero balance is a full charge", () => {
  const r = splitCreditCharge(0, kwdToFils(4), true);
  assert.deepEqual(r, { creditFils: 0, chargeFils: 4000, creditOnly: false });
});

// End-to-end money identity: for a partial booking, the deferred settlement spend
// (capped at the intended credit AND the live balance) plus the Payzah charge
// must always reconstruct exactly the booked price — no fils lost or created.
test("split + deferred settlement spend reconstructs the price exactly", () => {
  const price = kwdToFils(7);
  const grantsAtBooking = [
    { id: "w1", remainingFils: kwdToFils(3), expiresAtMs: NOW + 2 * DAY, createdAtMs: NOW },
  ];
  const split = splitCreditCharge(spendableBalanceFils(grantsAtBooking, NOW), price, true);
  assert.equal(split.chargeFils, 4000); // charged now via Payzah
  assert.equal(split.creditOnly, false);

  // Settlement: intended credit was 3000; live balance still 3000 → fully applied.
  const settle = allocateCreditFifo(grantsAtBooking, split.creditFils, NOW);
  assert.equal(settle.allocatedFils, 3000);
  assert.equal(split.chargeFils + settle.allocatedFils, price);
});

test("settlement shortfall: balance spent elsewhere caps the credit, charge stands", () => {
  const price = kwdToFils(7);
  const balanceAtBooking = kwdToFils(3);
  const split = splitCreditCharge(balanceAtBooking, price, true);
  assert.equal(split.creditFils, 3000);
  assert.equal(split.chargeFils, 4000);

  // By settlement, another booking drained the grant to 1 KWD.
  const grantsAtSettle = [
    { id: "w1", remainingFils: kwdToFils(1), expiresAtMs: NOW + 2 * DAY, createdAtMs: NOW },
  ];
  const settle = allocateCreditFifo(grantsAtSettle, split.creditFils, NOW);
  assert.equal(settle.allocatedFils, 1000); // only what's left
  assert.equal(settle.shortfallFils, 2000); // logged for manual reconciliation
});
