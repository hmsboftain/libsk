# LIBSK Performance Baseline

Captured per [PROTOCOL.md](PROTOCOL.md). Fill the `BEFORE` column from one full
protocol run (median of 3) **before** any audit fix lands; fill each `AFTER`
cell as the corresponding fix is merged.

> **Status: BEFORE captured (physical iPhone, profile build, LTE).**
> Read/listener table, frame timing, and image-cache bytes are filled from the
> on-screen dump after one protocol run (cold start → feed scroll → storefront
> open). `cold_start_tti`, `storefront_open` ms, and `feed_page_load` are still
> `pending` — they come from the Firebase Performance console / DevTools, not the
> on-screen dump. `AFTER` stays empty until each fix lands.
>
> **Honesty note on jank (2.1):** on this device with the small test fixture,
> jank was only **0.4 %** — the scroll is smooth *today*. The memory finding
> still holds: **8 cached images = 73.4 MB ≈ 9.2 MB/image**, confirming full-res
> decode with no `memCacheWidth`. The jank impact of that is **latent, not
> active** at this data size — it will bite on lower-RAM devices and larger
> feeds (more concurrent images → cache eviction churn / GC). Record the win
> after 2.1 as the **memory drop**, not a jank drop, unless a larger fixture
> reproduces active jank.

---

## Run metadata (fill in)

| Field | Value |
|---|---|
| Date captured | 2026-06-28 |
| Device make / model | physical iPhone (exact model _pending_) |
| Device RAM | _pending_ |
| OS version | _pending_ |
| Network | LTE |
| Flutter version (`flutter --version`) | _pending_ |
| Build mode | profile (`flutter run --profile`) — captures everything in one run |
| App git SHA | _pending_ (`git rev-parse --short HEAD`) |

## Data fixture (fill in, keep identical across runs)

| Field | Value |
|---|---|
| Test user (uid / email) | _pending_ |
| # boutiques followed | _pending_ |
| # saved items | _pending_ |
| Large test boutique (name) | _pending_ |
| Large test boutique SKU count | _pending_ |

---

## Metrics

### A. Firestore reads & listeners (profile run; ▤ dumps)

| Tag / metric | BEFORE | AFTER | Validates |
|---|---|---|---|
| `feed.query` reads | **12** | | §3 baseline / control |
| `feed.followBtn` reads | **25** | | 4.1 |
| `feed.followBtn` **peak active listeners** | **3** | | **4.1 (headline)** |
| `feed.savedGet` reads | **24** | | 4.2 |
| `feed.logoLoad` reads | **25** | | 2.2 |
| `storefront.query` reads (open + scroll) | **17** | | 3.1 / 7 |
| `storefront.query` **peak active listeners** | **1** | | 3.1 |

### B. Latency traces (profile run; Firebase Performance + console)

| Trace / metric | BEFORE | AFTER | Validates |
|---|---|---|---|
| `cold_start_tti` — `tti_ms_from_main` (ms) | _pending (DevTools)_ | | 4.4 |
| `storefront_open` (ms) @ `sku_count`≈17 | _pending (DevTools)_ | | 3.1 / 7 |
| `feed_page_load` p50 (ms) | _pending (DevTools)_ | | §3 control |
| `feed_page_load` `feed_query_docs` per page | _pending (DevTools)_ | | §3 control |

### C. Feed-scroll frame timing (profile run; ⏹ summary)

| Metric | BEFORE | AFTER | Validates |
|---|---|---|---|
| Total frames in window | **2733** | | 2.1 |
| Jank frames | **10** | | 2.1 |
| **Jank %** | **0.4 %** (latent — see note) | | **2.1 (headline)** |
| Worst frame — total span (ms) | _not captured_ | | 2.1 |
| Worst frame — build (ms) | _not captured_ | | 2.1 |
| Worst frame — raster (ms) | **16.8** | | 2.1 |
| Frame budget used | ~16.7 ms (**60 Hz** — worstRaster 16.8 ms ≈ one missed 60 Hz frame) | | context |

### D. Image cache (profile run; at bottom of feed scroll)

| Metric | BEFORE | AFTER | Validates |
|---|---|---|---|
| Image cache size (MB) | **73.4** (76,985,644 bytes) | | **2.1 (headline)** |
| Image cache image count | **8** | | 2.1 |
| Derived: MB per image | **≈ 9.2 MB** (full-res decode, no `memCacheWidth`) | | **2.1 (headline)** |

---

## What to expect from the code (derived, NOT measured — use to sanity-check the capture)

These are predictions from reading the code, provided only so an obviously-wrong
capture is easy to spot. They are **not** the baseline; the measured numbers
above are. Confirm against them, don't substitute them.

- **`feed.followBtn` peak listeners (4.1):** roughly one live Firestore doc
  listener per feed card currently mounted (viewport + `SliverList` cache
  extent). Expect **high-single / low-double digits** during a 3-page scroll;
  `FollowButton` opens a fresh listener on every build. Target after 4.1: **~0–1**.
- **`feed.savedGet` reads (4.2):** ≈ one get per feed card rendered over the
  session → on the order of the total cards scrolled past (24+ across 3 pages).
  Target after 4.2: **~1** (single batched load of the saved set).
- **`feed.logoLoad` reads (2.2):** ≥ number of logo widgets built; because
  `BoutiqueLogoAvatar` uses uncached `Image.network`, expect **more** load
  counts than distinct boutiques (re-builds on scroll re-instantiate the
  provider). Target after 2.2: ≈ distinct boutiques, once each.
- **`storefront.query` reads (3.1/7):** ≈ **full SKU count of the large boutique
  on open** (unbounded `.snapshots()` with no `limit`), plus the whole set again
  on any write while open. Target after pagination: **first page size (~12)**.
- **`feed.query` reads (control):** `pageSize` (8) × pages loaded ≈ **24** for 3
  pages. Should stay flat across all fixes — it's the cursor-paginated control.
- **`cold_start_tti` (4.4):** includes the awaited `CurrencyService.fetchRates()`
  HTTP round-trip + `Stripe.applySettings()` before `runApp`. Expect this to
  drop by roughly the FX-request time once that work moves off the startup path.
- **Image cache MB / jank % (2.1):** with no `memCacheWidth` anywhere, 1080px
  images decode at full res (~5–6 MB each in memory). Expect a **large** cache
  footprint and non-trivial jank %; both should fall sharply after the decode
  fix.

---

## Change log

| Date | Fix landed | Findings | Notes |
|---|---|---|---|
| 2026-06-28 | Instrumentation only | — | Baseline scaffolding added; no audit perf fix applied. |
| 2026-06-28 | BEFORE captured | all | Physical iPhone, profile, LTE. See tables above. |
| 2026-06-28 | Bug fixes (not perf) | C/D index, Browse All swallow, order-detail closures | Added missing `products.createdAt`/`price` collection-group single-field indexes + §1 composites; Browse All now shows an error state instead of silent-empty; order-detail label functions now invoked. **No audit perf fix (2.1/4.1/4.2/3.1/2.2) applied yet.** |
| 2026-06-29 | **Fix #1 (2.1)** | 2.1 | `memCacheWidth` + `maxWidthDiskCache:1080` on all 21 `CachedNetworkImage` sites via `image_sizing.dart` (full-bleed = screenW×DPR cap 3, tiles 600, logos 150). **Compare: imageCache MB 73.4 → ~15 expected.** |
| 2026-06-29 | **Fix #4 (2.2)** | 2.2 | `BoutiqueLogoAvatar` + `rotating_hero_banner` switched `Image.network` → `CachedNetworkImage` (logos 150, banner screenW×DPR). Win shows in imageCache MB + eliminated network re-fetches (DevTools network), not in `feed.logoLoad` (that counter still tallies build instantiations). |
| 2026-06-29 | **Fix #3 (4.4)** | 4.4 | `fetchRates()` + `Stripe.applySettings()` moved off the pre-`runApp` path (`unawaited` after `runApp`); `loadSavedCountry()` (prefs-only) stays synchronous. **Compare: `cold_start_tti`.** |
| 2026-06-29 | **Index file mirror (§1)** | §1 | `firestore.indexes.json` reconciled to exactly match live (`firebase firestore:indexes`) — added 2-field `boutiques(isVisibleOnHome,homeOrder)`, 2-field `products(isFeaturedOnHome,featuredOrder)`, `products(boutiqueId,postedToFeed,feedPostedAt)`, and `products.title` override. No future delete prompts. Not deployed. |

### Reconciliation vs. code-derived predictions

- **4.1 `feed.followBtn`:** predicted "high-single/low-double" peak listeners; **measured peak 3** — only ~3 cards are mounted concurrently (viewport + cache extent), so 3 live listeners at once. The **25 reads** still confirm the re-subscribe churn (a fresh listener per `FollowButton.build`). Headline for 4.1 stays: reads 25 → ~1, peak 3 → ~0–1.
- **4.2 `feed.savedGet` = 24:** matches "≈ one get per card scrolled past." Target ~1.
- **2.2 `feed.logoLoad` = 25:** exceeds the handful of distinct boutiques in the fixture → confirms uncached `Image.network` re-instantiation on scroll.
- **3.1/7 `storefront.query` = 17, peak 1:** the unbounded `.snapshots()` returned the boutique's full ~17-SKU set on open (so `sku_count` ≈ 17). Target after pagination: ~12 (first page).
- **§3 `feed.query` = 12:** cursor-paginated control; should stay ~flat across all fixes.
