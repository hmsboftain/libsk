# LIBSK — Launch QA

Pre-launch QA record. Code-level verification of the backend (Cloud Functions,
Firestore/Storage rules) plus the fixes that came out of it and Hussain's manual
device pass. Kept in-repo so the remaining items stay tracked.

- **Verified:** 2026-09-05
- **How:** local Firebase emulator suite (Firestore/Auth/Functions) + rules-unit
  tests. Cloud Functions were invoked **in-process** (real `firebase-admin`,
  data in the emulator) so real transaction logic ran; payments simulated via
  the `mockStatus` hook. No live project, no real Payzah/Wasal/Resend creds.
- **Test harness:** the emulator test suites live outside the repo (scratchpad).
  Pattern: start `firebase emulators:start --only firestore,auth,functions`,
  then run rules tests via `@firebase/rules-unit-testing` and callables via the
  v2 `.run()` method. ~390 assertions + the in-repo `functions/test/*` unit
  tests (96) all green.

> Emulator caveat (not a product bug): the firebase-tools **functions emulator
> proxies `firebase-admin` and drops `admin.firestore.FieldValue` statics**, so
> write-path functions 500 *in the emulator*. The deployed `firebase-admin@13`
> has the statics; tests invoke functions in-process to bypass the proxy.

---

## Fixes on branch `qa/launch-fixes`

| # | Area | Fix | Verified |
|---|------|-----|----------|
| 1 | **Wasal aggregation (bug)** | `applyWasalDeliveryStatus` + `markReadyForPickup` fan-out wrote `wasalStatuses` with a **dotted key in `set({merge:true})`** — a literal field name in the admin SDK, so the nested map stayed `{}`. Multi-boutique orders were marked **Delivered after only the first delivery**, and the double-push suppression broke. Now written as a nested object → deep-merges correctly. | 25/25 Wasal assertions (multi-boutique: one delivered → On the Way; all → Delivered) |
| 2 | **Status email fee (bug)** | `sendOrderStatusEmail` recomputed a flat 3/5 delivery fee instead of reading `after.deliveryCost` (Wasal orders showed the wrong fee). Now mirrors the confirmation email. | code + re-read |
| 3 | **Status email coverage** | Emails now sent for **Confirmed / On the Way / Delivered / Cancelled** (was only Delivered/Cancelled, keyed off non-existent `Picked Up`/`Out for Delivery` statuses), each a full **receipt** via `orderEmailHtml`. | code + re-read |
| 4 | **Google/Apple sign-in** | Root causes found: (a) **iOS Apple** — missing `com.apple.developer.applesignin` entitlement (added to `Runner.entitlements`); (b) **Android Google** — `google-services.json` has no `client_type:1` (Android/SHA) OAuth client → `ApiException 10` (**needs SHA registration, see below**); (c) error handling swallowed the real error (`catch (_)`) — now records to Crashlytics + surfaces the real message via `lib/services/auth_error.dart` (login + sign-up). | config inspected; error path code-reviewed |
| 5 | **OTP email logo** | Header wordmark "LIBSK" replaced with the logo image, embedded as a Resend **inline `cid:` attachment** (`functions/email_assets.js`, base64) so it renders in Gmail/Apple Mail (data: URIs get stripped). | code |
| 6 | **Branded password reset** | Re-added `sendBrandedPasswordReset` callable (generates the reset link via Admin SDK + sends a branded email through Resend). Client `forgot_password_page.dart` now calls it. Rate-limited per email; **never reveals whether an account exists** (returns `{sent:true}` always) — closes the old user-not-found enumeration leak. | 6/6 assertions (validation + enumeration guard) |
| 7 | **Dead code** | Deleted `PayzahCheckoutPreviewPage`, `AppUser`, `AppOrder` (+ `Order` typedef), `CartItemModel` (0 external refs). **Kept `PromoCategoryUsage`** — it's used internally by the live `PromoAvailability`. | `flutter analyze` clean |
| 8 | **Boutique visibility toggle (feature)** | New owner-writable `isVisible` boolean. Boutiques onboard **hidden** (`isVisible:false`); owner flips it visible from *My Boutique* once setup is done. Rules updated (owner-writable + bool-guarded, scoped). Storefront browse (`boutiques_page`) hides `isVisible === false`. | 104/104 rules assertions |

### ⚠️ Visibility toggle — migration-safety (read before deploy)
The 2026-08-24 outage was caused by a boutique-visibility gating whose **backfill
flaw hid existing boutiques**. This implementation is deliberately
**migration-safe**: the storefront hides a boutique **only** when
`isVisible === false` (explicit). Missing field or `true` both read as visible,
so **existing boutiques are unaffected and NO backfill is required**. Do not
switch the storefront to a `where isVisible == true` query — that would hide
every existing boutique (the field is absent on them) and re-trigger the outage.

**Scope note:** hiding is applied at the customer **boutique-browse** surface.
Deeper hiding of a hidden boutique's **products** in the home feed, Algolia
search, and category pages is a scoped follow-up (reuse the same
`isVisible !== false` rule; no backfill).

---

## Backend verified green (emulator)

- **Rules (B):** role model, order-doc create/delete denial, verification/role
  fields server-only, promo/ranking + `promoCreditBalance`/`wasalBranchCode`
  owner-locked, product validation, guest-cart shape, deny-all collections,
  `payment_attempts`/disputes/admin_users/boutique_owners scoping, Storage
  (public read, owner/admin write, >5MB & non-image & cross-boutique rejected).
- **createOrder (C/G):** server price re-read, oversell/aggregation,
  `isOutOfStock`, caps (50/100/5000), 15% commission (global + per boutique),
  discount validation + single-use race, monotonic order number, newest address,
  Pending-Payment-first, atomic 3-way split, 5/hr rate limit.
- **Payments (C):** `resolvePaymentAttempt` CAS (side-effects once), redirect
  re-verifies via get-payment-details (ignores query status), reconcile grace +
  10-check cap, `checkPayzahPaymentStatus` owner-only, no double stock release.
- **Promo credit (D):** server pricing, credit-only vs deferred partial-credit,
  no-double-spend, idempotent recharge/week-2/sweep, adjust caps, reject-once,
  expired-credit-never-spent.
- **Auth/OTP (E):** verify flow, send gates (cooldown + 5/hr), profile mirror.
- **Fulfillment (G/H):** `updateOrderStatus` (owner-derived boutique, fans to 3
  docs), disputes (own delivered order, 7-day, one-per-order, 3/day, allowlist),
  low-stock crossing, `sendManualNotification` honest `no_push_dispatched`.
- **Search/feed (I):** click validate + 30-min dedup, 48h attribution +
  reversal, follow counts, trending reset, feed expiry, rendering flags
  non-destructive to admin editorial featuring.
- **Public forms (J):** CORS allowlist (prod-accurate), field allowlist, per-IP
  5/hr, HTML-escaped email bodies.
- **Wasal (F):** webhook signature, dispatch preconditions (reject before any
  API call), stale-claim frees, aggregation, never overrides Cancelled.

### Known imprecision (not fixed — flagged for a decision)
- `updateOrderStatus` validates the target status is one of the 5 valid values
  but does **not** enforce a transition graph (e.g. `Delivered → Placed` is
  allowed). Not a security issue; decide if a state machine is wanted.

---

## Still open (needs live creds / console — not fixed here)

- **Android Google sign-in:** register the app's **SHA-1 + SHA-256** for the
  current signing config (debug + release/upload key) in Firebase Console →
  Project Settings → Android app, then **re-download `google-services.json`**
  (adds the missing `client_type:1` OAuth client). Get the SHAs with
  `cd android && ./gradlew signingReport`. Also confirm Google + Apple providers
  are **enabled** in Firebase Auth, and the Apple **Service ID + redirect URI**
  (Team ID `S28HXJ48JF`) for the App ID / Sign In with Apple capability.
- **Orphaned prod function:** `firebase functions:list` — confirm whether
  `sendBrandedPasswordReset` already exists in prod (this branch re-adds it) and
  that `sendWelcomeEmail` (PR #41) is on master before any functions deploy, or a
  `--force` deploy prunes it again.
- **Scheduled jobs:** confirm all are deployed and error-free in Cloud Scheduler
  / Functions logs (`reconcilePayzahPayments`, `reconcileWasalDeliveries`,
  `activate/expirePromoBookings`, `grantFoundingWeek2Credits`,
  `sweepExpiredPromoCredits`, `cleanupUnverifiedAccounts`, `resetWeeklyTrending`,
  `expireFeedSponsored`, `cleanupRateLimits`, `cleanupGuestCarts`).
- **Wasal wallet-charge partial-failure / orphan-ID path** — narrow failure
  window, code-reviewed as correct (claim held, orphan logged), not exercised live.
- **OTP / password-reset / order emails** — actual Resend send + reset-link
  validity need the live key (logic verified; send is live-only).
- **Language switcher (EN/AR + RTL)** — deferred by Hussain.

## Confirmed working live (manual device pass, 2026-09-05)
Payzah card/KNET/Apple Pay + refund; Wasal live dispatch, double-tap protection,
cancel-with-live-delivery, branch codes; prod webhook delivery; OTP + password
reset received; App Check + jailbreak warning; login role routing + verification
gate; full admin panel; search/feed/follow/filters/cart-conflict; addresses +
guest-cart merge; currency switcher; courier phone never shown; push lands.
