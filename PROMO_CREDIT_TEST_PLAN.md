# Founding Partner Promo Credit — End-to-End Test Plan

Manual E2E script for the founding-partner promo credit system. The pure money
math (fils conversion, FIFO allocation, credit/charge split) is already covered
by `functions/test/promo_credit.test.js` (`cd functions && npm test`); this plan
covers what unit tests can't — the live Firestore transactions, the Payzah
settlement path, and the scheduled jobs.

**Project:** `libsk-b68f5` · **Region:** `us-central1`
**Firestore console:** https://console.firebase.google.com/project/libsk-b68f5/firestore

---

## Prerequisites

- [ ] Signed in as a **super admin** (`admin_users/{uid}.role == 'super_admin'`).
- [ ] `PAYZAH_DIRECT_ENABLED = "true"` (needed for the partial-payment tests; the
      credit-only test deliberately works even when it's `"false"`).
- [ ] Payzah **sandbox** credentials active; KNET is the verified sandbox method.
- [ ] A disposable test boutique + its approved owner account (you'll need to log
      in as the owner to book).
- [ ] The `promoCredits` collection-group index is **READY** (see
      [Index readiness](#index-readiness) — required for Test 7 only).

### Reference values (from `functions/index.js` / `promo_credit.js`)

| | |
|---|---|
| Founding Week 1 / Week 2 | **6.000** / **3.000** KWD |
| Grant expiry | **7 days** |
| `home_banner` | 12.000/day · 63.000/week |
| `featured_product` | 4.000/day · 21.000/week |
| `top_of_category` | 3.000/day · 17.000/week |
| Pending-payment hold | 5 minutes |

> **Note:** `PROMO_TEST_BOOK_CURRENT_WEEK` is `false`, so bookings land in **next**
> Sun–Sat and won't render immediately. That's expected — this plan tests the
> credit/payment lifecycle, not rendering.

**Ledger path:** `boutiques/{boutiqueId}/promoCredits/{creditId}`
**Balance field:** `boutiques/{boutiqueId}.promoCreditBalance`

---

## Test 0 — Founding-partner flag at signup

1. Super admin → **Boutique Onboarding** → onboard the test boutique with
   **Founding partner** checked.

**Expect** on `boutiques/{id}`:
- `foundingPartner: true`, `promoCreditPending: true`
- **No** `promoCreditBalance` field, **no** `promoCredits` entries — nothing is
  granted at signup (that's the whole point: launch date is unknown here).

> If `promoCreditBalance` appears, the create-rule guard has regressed.

---

## Test 1 — Launch recharge

1. Super admin dashboard → **Promo Credits**. Card shows **"1 pending"**.
2. Tap **Run recharge** → confirm.

**Expect** — snackbar `Recharged 1, skipped 0`; the boutique row balance updates
live to **6.000**:
- `promoCreditBalance: 6`, `promoCreditPending: false`
- `promoCreditWeek2Pending: true`, `promoCreditWeek2DueAt: now + 7d`
- New `promoCredits` entry: `type: "grant"`, `reason: "founding_week1"`,
  `amount: 6`, `amountFils: 6000`, `remainingFils: 6000`,
  `expiresAt: now + 7d`, `grantedBy: <your uid>`

3. **Idempotency:** tap **Run recharge** again → `Recharged 0, skipped 0`
   (pending count is 0, button hidden — verify no second grant appears).

---

## Test 2 — Credit-only booking (fully covered, no gateway)

Balance **6.000**; book `featured_product` for **1 day = 4.000** → fully covered.

1. Log in as the **boutique owner** → Promotions → **Featured Product**.
2. Pick 1 day + a product. Checkbox reads **"Use promo credit · 6.000 KWD available"**.
3. Check it.

**Expect (before booking):** breakdown shows `Promo credit −4.000` / `To pay 0.000`;
the **payment-method picker disappears**; button reads **"Confirm booking"**.

4. Tap **Confirm booking**.

**Expect:** full-screen **"Booking confirmed"** — *"4.000 KWD of promo credit was
used — nothing to pay."* (not a toast), then back to the dashboard.

**Verify in Firestore:**
- `promo_bookings/{id}`: `status: "active"`, `creditOnly: true`,
  `paymentMethod: "credit"`, `amountFromCredit: 4`, `amountToCharge: 0`,
  `creditSpentFils: 4000`, `paidAt` set, **no `paymentAttemptId`**
- **No new `payment_attempts` doc** ← the gateway was skipped entirely
- New ledger entry: `type: "spend"`, `amount: -4`, `reason: "promo_booking:{id}"`,
  `allocations: [{ creditId: <week1 grant>, fils: 4000 }]`
- Week-1 grant `remainingFils: 2000`; `promoCreditBalance: 2`

> **Bonus check:** set `PAYZAH_DIRECT_ENABLED="false"` and repeat — a credit-only
> booking must still succeed (the gate only applies when there's a remainder).

---

## Test 3 — Partial booking + deferred settlement

Balance **2.000**; book `home_banner` for **1 day = 12.000** → 2 credit + 10 charge.

1. As owner → **Home Banner** → 1 day, upload a creative, check **Use promo credit**.

**Expect:** `Promo credit −2.000` / `To pay 10.000`; payment picker **visible**;
button reads **"Book & pay · 10.000 KWD"**.

2. Tap it, and **stop at the Payzah gateway page** (don't pay yet).

**Verify the deferral — this is the core of the design:**
- `promo_bookings/{id}`: `status: "pending_payment"`, `amountFromCredit: 2`,
  `amountFromCreditFils: 2000`, `amountToCharge: 10`
- `payment_attempts/{id}`: `amount: **10**` ← the **remainder only**, never 12
- `promoCreditBalance` is **still 2.000**, week-1 grant `remainingFils` still
  **2000**, and **no spend entry exists** ← credit is NOT taken at booking time

3. Complete payment with KNET sandbox.

**Expect** — success screen; then in Firestore:
- `promo_bookings/{id}`: `status: "paid_pending_review"` (banners await review),
  `creditSpentFils: 2000`, `paidAt` set
- New ledger entry: `type: "spend"`, `amount: -2`, `reason: "promo_booking:{id}"`
- Week-1 grant `remainingFils: 0`; `promoCreditBalance: 0`
- **Money identity:** `10.000 charged + 2.000 credit = 12.000 booked` ✅

---

## Test 4 — Abandoned partial costs no credit

The payoff of deferring: an abandoned checkout needs no refund logic.

1. Super admin → **Promo Credits** → tap the boutique → adjust **+3**, reason
   `test top-up` → Apply. (Also exercises `adjustPromoCredit`.)

**Expect:** `Applied 3.000 KWD. New balance 3.000 KWD.` · ledger entry
`type: "admin_adjustment"`, `remainingFils: 3000`, `expiresAt: now + 7d`,
`grantedBy: <your uid>`.

2. As owner, book `top_of_category` **2 days = 6.000** with credit checked
   (3 credit + 3 charge). At the gateway, **dismiss without paying**.

**Expect:** "Payment not completed" state.

**Verify:**
- `promoCreditBalance` **still 3.000**, top-up grant `remainingFils` still **3000**
- **No spend entry, no refund entry** — credit was never touched
- After the 5-min hold + reconcile (~3 min): booking → `status: "cancelled"`,
  slot released, credit still 3.000

---

## Test 5 — Banner reject refunds the credit

The Test-3 banner is sitting at `paid_pending_review` with `creditSpentFils: 2000`.

1. Super admin → **Promo Banner Approvals** → **Reject** it (any reason).

**Expect** on `promo_bookings/{id}`: `status: "rejected"`, `creditRefunded: true`.

**Verify the refund:**
- New ledger entry: `type: "admin_adjustment"`, `amount: +2`,
  `reason: "promo_booking_refund:{bookingId}"`, `remainingFils: 2000`,
  **fresh** `expiresAt: now + 7d` (by design — we re-credit rather than restore
  possibly-lapsed source grants)
- `promoCreditBalance: 5.000` (3 from Test 4 + 2 refunded)

2. **Idempotency:** the booking is now `rejected`, so a repeat reject must fail
   with `Booking is rejected.` — no double refund.

> Cash refunds remain manual (Payzah dashboard) — only *credit* auto-refunds.

---

## Test 6 — Clawback clamps to the live balance

1. Adjust the boutique by **−99**, reason `clawback test`.

**Expect:** `Applied -5.000 KWD. New balance 0.000 KWD.` — it removes only what
exists, never going negative. Ledger: `type: "admin_adjustment"`, `amount: -5`,
with an `allocations` trail across both live grants. All `remainingFils: 0`.

---

## Test 7 — Expiry sweep

> ⚠️ Requires the `promoCredits` collection-group index to be **READY** — the
> sweep's query (`remainingFils > 0 && expiresAt <= now`) fails without it.
> Confirm via [Index readiness](#index-readiness) first.

Grants can't be issued already-expired (`expiresInDays` is 1–3650), so back-date
one directly — the console writes as admin and bypasses rules.

1. Adjust the boutique **+4**, reason `expiry test` → balance **4.000**.
2. In the Firestore console, open that new `promoCredits` entry and edit
   `expiresAt` to **yesterday**.

**Sanity check first — expired credit must be unspendable immediately, before the
sweep runs:** as owner, open any placement. The checkbox should show
**0.000 available** (or be hidden). This proves the authoritative live-balance
path ignores expired-but-unswept credit even while `promoCreditBalance` still
reads 4.000.

3. Force-run the sweep (don't wait 24h):

```bash
gcloud scheduler jobs run firebase-schedule-sweepExpiredPromoCredits-us-central1 \
  --location=us-central1 --project=libsk-b68f5
```

4. Check logs:

```bash
firebase functions:log --only sweepExpiredPromoCredits
```

**Expect:**
- New ledger entry: `type: "expiry"`, `amount: -4`, `reason: "expiry"`,
  `allocations: [{ creditId: <back-dated grant>, fils: 4000 }]`, `expiresAt: null`
- Back-dated grant: `remainingFils: 0` (its `amount` still reads `4` — the audit
  trail is never rewritten)
- `promoCreditBalance: 0.000`

5. **Idempotency:** force-run again → no second expiry entry (`remainingFils` is
   already 0, so the query no longer matches it).

---

## Test 8 — Week-2 grant (optional)

1. Console-edit `boutiques/{id}.promoCreditWeek2DueAt` to **yesterday**
   (`promoCreditWeek2Pending` should still be `true`).
2. Force-run:

```bash
gcloud scheduler jobs run firebase-schedule-grantFoundingWeek2Credits-us-central1 \
  --location=us-central1 --project=libsk-b68f5
```

**Expect:** ledger entry `type: "grant"`, `reason: "founding_week2_launch_recharge"`,
`amount: 3`, `expiresAt: now + 7d`, `grantedBy: null`;
`promoCreditWeek2Pending: false`; balance **+3.000**.
Re-running grants nothing further (flag is cleared).

---

## Test 9 — Security rules (client can't touch the ledger)

As the **boutique owner** (not admin), attempt:

1. Write `promoCreditBalance` on your own boutique doc → **must be denied**.
2. Write to `boutiques/{id}/promoCredits/{anything}` → **must be denied**.
3. Read `boutiques/{id}/promoCredits` for **your own** boutique → **allowed**.
4. Read another boutique's `promoCredits` → **must be denied**.

> Quickest path: the Rules Playground in the Firestore console.

---

## Index readiness

The sweep (Test 7) needs the `promoCredits` **collection-group** index built.

```bash
gcloud firestore indexes composite list --project=libsk-b68f5 \
  --format="table(name.basename(),state,queryScope,fields)"
```

Look for the `promoCredits` / `COLLECTION_GROUP` entry with
**`expiresAt` then `remainingFils`**. **`state: READY`** = safe to run Test 7.
`state: CREATING` = wait (usually minutes on a small collection).

> ⚠️ **Field order matters — this bit us once.** The sweep filters on TWO
> inequalities (`remainingFils > 0 && expiresAt <= now`). Firestore requires the
> composite index fields in a specific order for multi-inequality queries, and
> the index was first defined as `[remainingFils, expiresAt]` — which built
> `READY` and *looked* correct, but the sweep still failed at runtime with
> `FAILED_PRECONDITION: The query requires an index`. The working order is
> **`[expiresAt, remainingFils]`**. A `READY` index does not prove the query is
> served — the only real check is running the function (below).
> Verified working 2026-07-16.

**Status:** index is deployed and READY, and the sweep has been smoke-tested
against it (force-run → clean execution, no errors).

Everything else in this plan (Tests 0–6, 8, 9) is index-independent and safe to
run immediately after deploy.

---

## Cleanup

- Delete the test `promo_bookings` docs and the boutique's `promoCredits` entries.
- Reset `boutiques/{id}.promoCreditBalance` to `0` (console — clients can't).
- To re-run the whole plan: set `promoCreditPending: true` and clear
  `promoCreditWeek2Pending` / `promoCreditWeek2DueAt`.
- Deactivate any `hero_banners` doc a banner test published.
