# Pre-Order System — Technical Migration Plan

> **Status:** Planning only. Do **not** execute until **after** the MyFatoorah/Tap
> payment migration is complete (deposit mode and "charge remainder on dispatch"
> depend on the gateway's tokenization/partial-capture capabilities).
>
> This document is the execution-ready spec for upgrading the current
> **made-to-order (MTO)** toggle into a full **pre-order** system, as described
> under *Planned Features (Post-Launch) → Pre-Order System* in `CLAUDE.md`.

---

## 1. Current Made-to-Order Implementation (as-built audit)

### 1.1 Complete reference inventory

| Area | File | What it does |
|---|---|---|
| Product model | `lib/models/product.dart:21-22, 41-42, 68-69` | `bool madeToOrder`, `String? deliveryTimeframe` fields + parse |
| Add product | `lib/pages/add_product_page.dart:77,82,99,273-276,327-329,687-724,902` | `_madeToOrder` toggle + `deliveryTimeframeController`; validates timeframe required when MTO; saves via `FirestoreService.addProduct` |
| Edit product | `lib/pages/edit_product_page.dart:109,114,165-167,240,431-434,492-494,1037-1074,1236` | Same toggle/controller; `updateData` writes `madeToOrder` + `deliveryTimeframe` (null when off) |
| Product page | `lib/pages/product_page.dart:641-642,689,705-751,732,737-740` | Reads `madeToOrder`/`deliveryTimeframe`; hides stock indicator when MTO (`if (!isMTO)`); renders MTO banner (clock icon + label + timeframe) |
| Checkout | `lib/pages/checkout_page.dart:45-46,86-136,344,560-614,831-832` | `_autoDetectMto`: if any cart item is MTO → forces `deliveryMethod='Made to Order'`, `deliveryCost=0`; `_fetchLongestTimeframe` picks the longest timeframe **by string length**; renders banner; sends `estimatedDays: null` |
| Cart write | `lib/services/firestore_service.dart:279-280` | `addToCart` copies `madeToOrder: true` onto the cart item when the product has it |
| Add product write | `lib/services/firestore_service.dart:731-732,760-761` | `addProduct` writes `madeToOrder` + `deliveryTimeframe` (null when off) |
| Client createOrder | `lib/services/firestore_service.dart:438,450,466-467` | Passes `estimatedDays` only when `deliveryMethod == 'Made to Order'` |
| Cart item model/widget | `lib/widgets/cart_item.dart:24,37,52,68,82,140-161` | `madeToOrder` field; renders "Made to Order" chip in cart |
| Cloud Function createOrder | `functions/index.js:301,305,314,501-503,522` | `'Made to Order'` is an allowed delivery method; `deliveryCost=0`; stores `estimatedDays` on order doc when present; **still decrements stock** |
| Algolia sync | `functions/index.js:1201,1219,1298` | Indexes `madeToOrder` (3 mapping sites) |
| Firestore rules | `firestore.rules:78,90` | `madeToOrder` is in the **cart-item** `hasOnly` whitelist + bool type check. **No** product-level MTO validation |
| l10n | `app_en.arb` / `app_ar.arb:213-214,303-305,309` | `madeToOrder`, `madeToOrderSubtitle`, `deliveryTimeframe`, `deliveryTimeframeHint`, `deliveryTimeframeRequired`, `estimatedDays` |

### 1.2 How it works end-to-end (narrative)

1. **Owner sets it** (`add_/edit_product_page`): toggles "Made to Order" and types
   a free-text `deliveryTimeframe` (e.g. "7–10 business days"). Timeframe is
   required when the toggle is on. Saved on the product doc as
   `madeToOrder: bool` + `deliveryTimeframe: string|null`.

2. **Customer sees it** (`product_page`): if `madeToOrder == true`, the live
   stock indicator is hidden and a neutral banner shows the label + timeframe.
   The Add-to-Cart flow is otherwise identical to a normal product.

3. **Cart** (`firestore_service.addToCart` + `cart_item`): the `madeToOrder` flag
   is denormalised onto the cart item so checkout can detect it without re-reading
   the product. A "Made to Order" chip renders on the cart line.

4. **Checkout** (`checkout_page._autoDetectMto`): if **any** cart item is MTO, the
   entire order is forced to `deliveryMethod='Made to Order'` with **free
   delivery**, and the dropdown is replaced by a banner. The "longest" timeframe
   is chosen by **string length** (crude/buggy — "9 days" > "10 days" by length).

5. **Order creation** (`functions/index.js createOrder`): `'Made to Order'`
   passes delivery-method validation, sets `deliveryCost = 0`, and stores
   `estimatedDays` on the order doc **only if the client sent it** — but the
   client always sends `null` (`checkout_page:344`), so **`estimatedDays` is
   effectively dead today**. Crucially, **stock is still decremented** for MTO
   items (`functions/index.js:556-563`) and the order is rejected if
   `stock < qty` — so **MTO products must currently carry real stock**.

6. **Delivery time calc:** there is none. `deliveryTimeframe` is a free-text
   string shown verbatim; `estimatedDays` (numeric) is plumbed but unused.

7. **Order confirmation / owner dashboard:** orders carry
   `deliveryMethod: "Made to Order"` and nothing else MTO-specific. The
   `AppOrder` model (`lib/models/order.dart`) does **not** model MTO or
   `estimatedDays`. Owner order management (`owner_orders_page`) uses a single
   status flow for all orders: **Placed → Confirmed → On the Way → Delivered**
   (+ Cancelled), updated via a client-side batch across the boutique/user/global
   order copies. There is no separate MTO/pre-order view.

### 1.3 Data shapes today

**Product doc** (`boutiques/{bid}/products/{pid}`): `title, description, price,
salePrice?, isOutOfStock?, stock, imageUrl, imageUrls[], sizes[], sizeEntries[],
category[], colors[], madeToOrder, deliveryTimeframe?, sizeGuideUrl?,
boutiqueName, boutiqueId, postedToFeed, feedPostedAt, createdAt, updatedAt`.

**Order doc** (written to `users/{uid}/orders`, `global_orders`, and
`boutiques/{bid}/orders`): `orderNumber, date, itemCount, total, status,
customerUid, customerName, customerEmail, deliveryMethod, paymentMethod,
paymentIntentId, address, items[], createdAt, discountCodeId?, discountAmount?,
estimatedDays?` (estimatedDays only on the user + global copies, never populated
in practice).

**Cart item doc**: `productId, boutiqueId, imageUrl, title, description, size,
color?, price, quantity, madeToOrder?, createdAt, updatedAt`.

### 1.4 Key constraints / quirks to respect during migration

- **MTO currently consumes physical stock.** Pre-orders must decouple
  purchasable quantity from `stock` (use a separate `preOrderLimit` /
  `preOrderCount`), or oversell protection will block legitimate pre-orders.
- **Whole-order MTO coupling.** Today one MTO item forces the *entire* order to
  free "Made to Order" delivery. Mixed carts (in-stock + pre-order) are not
  modelled. Decide whether to keep whole-order coupling or split fulfilment.
- **`estimatedDays` is dead plumbing** — safe to repurpose/replace.
- **Timeframe is unstructured free text**, chosen by string length. The
  pre-order system replaces it with a real `dispatchDate` (Timestamp).
- **Order status updates are client-side batches** across 3 collections
  (`owner_orders_page:145-188`). Any new pre-order status must update all 3.
- **`isValidProduct()` does not validate `madeToOrder`** today — products write
  it freely. New pre-order fields should be validated (see §6).

---

## 2. Product Document Field Changes

Replace the MTO pair with a structured pre-order block. Keep `madeToOrder`
readable during a transition window for backward compat (see §5).

| Field | Type | Notes |
|---|---|---|
| `isPreOrder` | `bool` | Replaces `madeToOrder`. |
| `preOrderDispatchDate` | `Timestamp` | Expected dispatch/ship date (replaces free-text `deliveryTimeframe`). |
| `preOrderLimit` | `int?` | Max units the owner will commit to (null = unlimited). |
| `preOrderCount` | `int` | Server-incremented count of committed pre-orders (atomic, like `salesCount`). Starts at 0. |
| `preOrderMessage` | `string?` | Custom customer message, e.g. "Ships after Eid". Max ~280 chars. |
| `preOrderDepositMode` | `string` | `'full'` or `'deposit'`. Default `'full'`. |
| `preOrderDepositPercent` | `int?` | 1–100, required when mode = `'deposit'`. |
| *(retain)* `deliveryTimeframe` | `string?` | Keep temporarily for migration display fallback; remove after backfill. |

`deliveryTimeframe` and `madeToOrder` are **deprecated** post-migration and
removed once all docs are backfilled (§5).

---

## 3. Order Document Field Changes

Pre-order context must be captured **per line item** (a cart can mix in-stock and
pre-order items) and summarised at the order level.

**Per line item** (`items[]`): add
- `isPreOrder: bool`
- `preOrderDispatchDate: Timestamp` (snapshot at purchase time)
- `depositPaid: number` (amount charged now)
- `balanceDue: number` (remainder due on dispatch; 0 when full payment)

**Order level:** add
- `hasPreOrderItems: bool` — for cheap querying/filtering.
- `preOrderStatus: string?` — separate status track for pre-order fulfilment
  (see §4.3). Null/absent for pure in-stock orders.
- `latestDispatchDate: Timestamp?` — max dispatch date across items (drives the
  "ships by" messaging + dispatch notification scheduling).
- `balanceDueTotal: number` — sum of `balanceDue` across items (for deposit mode).

Remove dependence on the dead `estimatedDays` field; replace with the structured
dates above.

---

## 4. createOrder Changes (`functions/index.js`)

### 4.1 Pricing & charge logic
- For **full** deposit mode: charge full `effectivePrice` now (unchanged).
- For **deposit** mode: `depositPaid = round(effectivePrice * depositPercent/100)`,
  `balanceDue = effectivePrice - depositPaid`. Charge only `depositPaid` now via
  the gateway; **store a payment token/mandate** to capture `balanceDue` on
  dispatch. (Requires MyFatoorah/Tap tokenization — hence the post-payment-
  migration dependency.) Continue to compute everything **server-side**; never
  trust client deposit math.

### 4.2 Stock vs. pre-order commitment
- **Do not decrement `stock`** for pre-order line items. Instead:
  - Read `preOrderLimit` / `preOrderCount` in the same transaction.
  - Reject if `preOrderCount + qty > preOrderLimit` (when limit set) — message
    "Pre-order limit reached for this item."
  - `tx.update(productRef, { preOrderCount: increment(qty) })`.
- In-stock items keep the existing aggregated stock check + decrement path
  untouched. The aggregation map must branch per line on `isPreOrder`.

### 4.3 Status / delivery
- Stop forcing whole-order `deliveryMethod='Made to Order'`. Pre-order items get
  per-line `isPreOrder`; the order's physical delivery method applies to in-stock
  items as normal. (If you keep "free delivery on pre-order-only carts," gate it
  on *all* items being pre-order.)
- Initialise `preOrderStatus = 'Pre-Ordered'` when `hasPreOrderItems`.
- Pre-order status flow (distinct from the regular Placed→Delivered flow):
  **Pre-Ordered → Ready to Ship → (then joins regular) On the Way → Delivered**,
  + Cancelled/Refunded.
- Add `"Pre-Ordered"` etc. to the allowed status set the owner can transition to.

### 4.4 Validation
- Add `'Pre-Order'`-related delivery handling to `allowedDeliveryMethods` only if
  you keep a dedicated method; otherwise drop `'Made to Order'` from the list
  after migration.
- Validate per-line `isPreOrder` against the product's `isPreOrder` (don't trust
  the client) and recompute dispatch date from the product doc.

---

## 5. Migration Path for Existing MTO Products

1. **Additive deploy first.** Ship the new fields + code that reads *either*
   `isPreOrder` *or* legacy `madeToOrder` (treat `madeToOrder == true` as
   `isPreOrder == true`). No reads break.
2. **Backfill script** (one-off callable or `tool/` script using Admin SDK):
   for every product where `madeToOrder == true`:
   - `isPreOrder = true`
   - `preOrderDispatchDate` = `now + N days` parsed from `deliveryTimeframe`
     where possible, else a safe default (e.g. now + 14 days) flagged for owner
     review.
   - `preOrderDepositMode = 'full'`, `preOrderCount = 0`,
     `preOrderLimit = null`, `preOrderMessage = deliveryTimeframe` (carry the old
     text as the custom message).
   - Leave `madeToOrder`/`deliveryTimeframe` in place for one release.
3. **Cutover:** flip UI (`add_/edit_product_page`, `product_page`, `cart_item`,
   `checkout_page`) to the new fields; stop writing `madeToOrder`.
4. **Cleanup release:** remove `madeToOrder`/`deliveryTimeframe`/`estimatedDays`
   reads and the legacy fallback; drop the fields from new writes; remove
   `madeToOrder` from the cart-item rules whitelist and Algolia mappings (or
   replace with `isPreOrder`).
5. **Re-index Algolia** (existing full-reindex callable, `functions/index.js`
   ~line 1280) so pre-order fields are searchable/filterable.

Backward-compat shim lives only for steps 1–3; keep the window short.

---

## 6. Firestore Rules Changes (`firestore.rules`)

- **Products** — extend `isValidProduct()` (currently `:59-68`) to validate the
  new optional fields when present:
  - `isPreOrder` is bool
  - `preOrderDispatchDate` is timestamp
  - `preOrderLimit` is int && >= 0 (or null)
  - `preOrderMessage` is string && size() <= 280 (or null)
  - `preOrderDepositMode` in `['full','deposit']`
  - `preOrderDepositPercent` is int && > 0 && <= 100 (required iff mode=='deposit')
  - **`preOrderCount` must NOT be client-writable** — add it to the product
    update **denylist** (`firestore.rules:162-165`) alongside `salesCount`/
    `weeklyOrders` so only Cloud Functions can change it.
- **Cart items** — add `isPreOrder` to the `isValidCartItem()` `hasOnly`
  whitelist (`firestore.rules:76-90`) + bool type check; remove `madeToOrder`
  after cutover.
- **Orders** — unchanged ownership rules; pre-order status transitions ride the
  existing owner/admin update permissions. Verify owners can write the new
  `preOrderStatus` on `boutiques/{bid}/orders` (they can — `:171`).

---

## 7. New Firestore Indexes (`firestore.indexes.json`)

- **Owner Pre-Orders tab:** composite on `boutiques/{bid}/orders` —
  `hasPreOrderItems == true` ordered by `latestDispatchDate ASC` (and/or
  `preOrderStatus` + `latestDispatchDate`).
- **Dispatch-due scheduler:** collection-group index on `orders` for
  `preOrderStatus == 'Pre-Ordered'` + `latestDispatchDate <=` (range) so the
  scheduled function can find orders whose dispatch date has arrived.
- **Optional product filter:** `isPreOrder == true` + `createdAt` if you add a
  storefront "Pre-order" filter.

---

## 8. New l10n Keys (en + ar)

Owner side: `preOrder`, `preOrderSubtitle`, `expectedDispatchDate`,
`selectDispatchDate`, `preOrderLimit`, `preOrderLimitHint`,
`preOrderMessageLabel`, `preOrderMessageHint`, `depositMode`, `fullPayment`,
`depositPercent`, `depositPercentHint`, `preOrderLimitReached`,
`dispatchDateRequired`, `depositPercentRequired`.

Customer side: `preOrderBadge` ("PRE-ORDER"), `shipsOn` ("Ships {date}"),
`chargedNowShipsLater` ("You'll be charged now — ships {date}"),
`depositDueNote` ("{amount} now, {balance} on dispatch"),
`preOrderConfirmationSubject` / body strings for the email.

Owner orders / status: `statusPreOrdered`, `statusReadyToShip`, `preOrdersTab`,
`markReadyToShip`, `balanceDue`, `dispatchDate`.

Deprecate (remove after cutover): `madeToOrder`, `madeToOrderSubtitle`,
`deliveryTimeframe`, `deliveryTimeframeHint`, `deliveryTimeframeRequired`,
`estimatedDays`.

---

## 9. New Cloud Function Logic

1. **`capturePreOrderBalance` (callable or triggered):** when an owner marks a
   pre-order "Ready to Ship" (or on dispatch date for deposit orders), capture
   the stored `balanceDue` via the gateway token, then update order totals.
   Depends on MyFatoorah/Tap partial-capture/tokenization.
2. **`scheduledDispatchReminders` (Cloud Scheduler / `onSchedule` daily):**
   query pre-orders whose `latestDispatchDate` is within N days (index §7) and:
   - notify the **customer** ("Your pre-order ships soon") via FCM + email.
   - notify the **owner** ("Pre-orders due for dispatch this week").
3. **`onPreOrderStatusChanged` (`onDocumentUpdated`):** when `preOrderStatus`
   transitions to "Ready to Ship", send the customer a dispatch email (extend
   the existing `sendOrderStatusEmail` pattern at `functions/index.js:835`).
4. **Pre-order confirmation email:** extend `sendOrderConfirmationEmail`
   (`functions/index.js:806`) to include the dispatch date + deposit/balance
   breakdown when `hasPreOrderItems`.
5. **Backfill callable** (§5.2), admin-only.

---

## 10. UI Work Summary

- **`edit_product_page` / `add_product_page`:** replace `_buildMadeToOrderSection`
  with a pre-order section: toggle, **date picker** (dispatch date), limit field,
  message field, deposit-mode selector + percent field. Replace the
  `deliveryTimeframeRequired` validation with `dispatchDateRequired` +
  `depositPercentRequired`.
- **`product_page`:** replace the MTO banner (`:705-751`) with: "PRE-ORDER" badge
  on the sticky button (replacing Add to Cart wording), dispatch date below
  price, custom message, and "You'll be charged now, ships {date}" (or deposit
  note). Reuse the sold-out/opacity plumbing from Item 7 only for genuine OOS —
  pre-order items are **not** sold out even at `stock == 0`.
- **`cart_item`:** replace "Made to Order" chip with a "PRE-ORDER · ships {date}"
  chip; show deposit/balance if applicable.
- **`checkout_page`:** drop the whole-order MTO coupling; show per-line pre-order
  notes + an order-level "Ships by {date}" + deposit summary.
- **`owner_orders_page`:** add a **Pre-Orders tab** (filter
  `hasPreOrderItems == true`), show dispatch date + balance, and a "Mark Ready to
  Ship" action driving the new pre-order status flow (which must update all 3
  order copies, like the existing `_updateOrderStatus` batch).
- **`AppOrder` model (`lib/models/order.dart`):** add `hasPreOrderItems`,
  `preOrderStatus`, `latestDispatchDate`, `balanceDueTotal`.

---

## 11. Edge Cases & Risks

1. **Stock decoupling regression (highest risk).** Today MTO decrements stock and
   requires `stock >= qty`. If migration sets `isPreOrder` but leaves the
   transaction decrementing stock, pre-orders for `stock == 0` items will be
   rejected. The createOrder branch in §4.2 must land **with** the field change.
2. **Item 7 interaction.** `isSoldOut = isOutOfStock || stock <= 0` will mark
   pre-order items (which legitimately have `stock == 0`) as sold out. Pre-order
   state must take precedence over the sold-out overlay/disable everywhere
   (product_page, all 6 cards, cart).
3. **Mixed carts.** In-stock + pre-order in one cart: decide split vs. single
   fulfilment. Plan assumes per-line handling + order-level summary; checkout and
   owner views must both render mixed orders coherently.
4. **Deposit capture failure.** Gateway balance capture on dispatch can fail
   (expired card/token). Need a retry + owner/customer notification + a clear
   "balance unpaid" state; don't ship until captured (or per boutique policy).
5. **Dispatch date in the past / owner never updates.** Scheduler must handle
   overdue pre-orders (escalate to owner, surface to admin).
6. **Refunds/cancellations of deposits.** `processRefund`
   (`functions/index.js:255`) must handle partial (deposit-only) refunds and
   restore `preOrderCount` (decrement) rather than `stock`.
7. **Timezone of dispatch date.** Store as UTC Timestamp; render in the user's
   locale. Free-text "7–10 days" backfill is imprecise — flag those for owner
   review rather than guessing a hard date.
8. **`preOrderCount` integrity.** Must be Functions-only (rules denylist) and
   adjusted atomically on order create / cancel / refund to avoid drift vs.
   `preOrderLimit`.
9. **Algolia staleness.** `isPreOrder`/dispatch fields only refresh on the next
   product write or full reindex — run reindex at cutover (§5.5).
10. **Backward-compat window.** While both `madeToOrder` and `isPreOrder` exist,
    every reader must check both; keep the window short to avoid divergent state.
11. **Discount + deposit interaction.** Decide whether discounts apply to the
    deposit, the balance, or the full price — compute server-side consistently.
12. **Rate limit / abuse.** Pre-order limit enforcement is the only oversell
    guard (no stock backstop) — ensure it's inside the transaction.

---

## 12. Suggested Execution Order (post-payment-migration)

1. Add fields + `isValidProduct()` validation + `preOrderCount` denylist (rules).
2. Product model + add/edit UI (date picker, limit, message, deposit).
3. createOrder: per-line pre-order branch, `preOrderCount`, deposit math, status.
4. product_page / cards / cart / checkout UI (with Item 7 precedence fix).
5. Owner Pre-Orders tab + status flow + order model fields.
6. Cloud Functions: confirmation email, dispatch scheduler, balance capture.
7. Indexes + Algolia reindex.
8. Backfill existing MTO products; verify; then cleanup release (remove legacy).
