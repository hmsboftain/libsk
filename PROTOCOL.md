# LIBSK Performance Baseline Protocol

How to capture a **repeatable** performance baseline so that "after" numbers are
directly comparable to "before". Every fix from the audit is validated by
re-running this exact protocol and filling the `AFTER` column in `BASELINE.md`.

> Golden rule: change **one** variable (the fix). Keep device, build mode, data
> fixture, and action script identical between BEFORE and AFTER runs.

---

## 1. Build & device (must be identical every run)

| Requirement | Why |
|---|---|
| **Same physical device** — record make / model / RAM / OS in `BASELINE.md`. | Emulators and different phones have wildly different CPU/GPU/refresh; numbers aren't comparable. |
| **Profile build:** `flutter run --profile` | Debug is unoptimised (JIT, asserts, no tree-shaking) and over-reports jank; release strips the counters we need. Profile keeps all instrumentation (gated on `!kReleaseMode`) **and** runs AOT-optimised code — so one profile run captures the whole baseline. |
| **NOT an emulator, NOT debug, NOT release.** | See above. |
| Device on mains power, screen brightness fixed, no other heavy apps, airplane-mode OFF (we measure real network). | Thermal throttling and background load skew frame timing. |
| Kill the app fully between cold-start runs (swipe from recents). | Cold start must be cold — no warm process, no warm Firestore cache. |

> ✅ All instrumentation is gated on `!kReleaseMode`, so **a single
> `flutter run --profile` run captures everything** — the `FirestoreMetrics`
> read/listener table, the Firebase Performance traces (`cold_start_tti`,
> `storefront_open`, `feed_page_load`), `FrameMetrics`, and the image-cache
> bytes. Nothing populates in release. Run BEFORE and AFTER in the same profile
> mode so they stay comparable.

---

## 2. Data fixture (must be identical every run)

Record these in `BASELINE.md` and use the **same accounts/data** for every run.

| Fixture | How to pin it |
|---|---|
| **Test user** — a dedicated login, not a fresh guest. | Reads depend on follows/saves; a known account keeps them stable. |
| **# boutiques followed** by the test user. | Drives the feed query shape (followed vs. discovery) and `feed.followBtn` listener count. Pick a realistic number (e.g. 8–15) and keep it fixed. |
| **# saved items** for the test user. | Affects `feed.savedGet` hits and saved-items screens. Keep fixed. |
| **Large test boutique** — the one with the most SKUs. Record its **name + exact product count**. | This is the `storefront.query` / `storefront_open` subject. To find the largest: open the app's admin/boutique oversight, or in Firestore console sort a boutique's `products` subcollection. Use the **same** boutique each run. |

> Do not add/remove products, follows, or saves between BEFORE and AFTER. If the
> catalog must change, re-capture BEFORE too.

---

## 3. Action script (perform identically every run)

Run each numbered step the same way, same pacing. Use the two debug FAB buttons
on the Home screen (visible in debug/profile only):
**▶/⏹** = start/stop the feed-scroll frame window; **▤ (list)** = dump the
Firestore read/listener table + image-cache snapshot to the console.

1. **Cold launch** the app (from fully killed). Wait on the splash → Home.
2. **Wait for the feed** to render its first cards. → this stops `cold_start_tti`
   automatically and prints `cold_start_tti: NNN ms` to the console.
3. Press **▶** (start feed-scroll window).
4. **Scroll the feed to the bottom of the first 3 pages** — scroll until two
   load-more spinners have fired (page 2, page 3), at a steady, natural speed.
   Each page load prints a `feed_page_load` trace.
5. At the bottom, press **⏹** (stop window). The console prints the frame summary
   (`frames / jank% / worst frame ms`) and the `imageCache:` line (bytes + count)
   — read the image-cache numbers **here**, at the heaviest moment.
6. Press **▤** to dump the Firestore read/listener table (`feed.query`,
   `feed.followBtn`, `feed.savedGet`, `feed.logoLoad`, peak listeners) and reset.
7. **Open the large test boutique** storefront (tap its card). Wait for the grid
   to paint → prints `storefront_open: sku_count=N`.
8. **Scroll the storefront to the bottom.**
9. Press **▤** again to dump `storefront.query` reads.

Do the run **3 times** and record the **median** of each number (cold start and
jank are noisy; median rejects the worst outlier).

---

## 4. Where each number is read from

| Metric | Source |
|---|---|
| `cold_start_tti` (ms) | Console line `cold_start_tti: NNN ms` (debug/profile). Also visible in Firebase console → Performance → custom trace `cold_start_tti` (metric `tti_ms_from_main`). |
| `storefront_open` (ms) + `sku_count` | Console `storefront_open: sku_count=N`; duration in Firebase Performance → `storefront_open` (attribute `sku_count`). |
| `feed_page_load` (ms) + `feed_query_docs` | Firebase Performance → `feed_page_load` (metric `feed_query_docs`). |
| Firestore reads per tag, peak listeners | Console table from the **▤** dump (`FirestoreMetrics`). Debug build. |
| Feed scroll: frames / jank % / worst frame ms | Console line from the **⏹** stop (`FrameMetrics`). |
| Image cache bytes / count | Console `imageCache: C images, M MB (B bytes)` printed on **⏹** and **▤**. Sourced from `PaintingBinding.instance.imageCache`. |
| (Optional) DevTools cross-check | `flutter run --profile` → DevTools → Performance tab for a frame-by-frame view; Memory tab for image cache. Use to sanity-check the console numbers. |

---

## 5. Metric → finding map

| Metric(s) | Validates |
|---|---|
| `feed.followBtn` reads + **peak active listeners** | Finding 4.1 (per-card follow listeners) |
| `feed.savedGet` reads | Finding 4.2 (per-card saved get) |
| image cache bytes + feed-scroll **jank %** / worst frame | Finding 2.1 (full-res decode, scroll jank) |
| `feed.logoLoad` reads | Finding 2.2 (uncached `Image.network` logo churn) |
| `storefront.query` reads + `storefront_open` ms | Findings 3.1 / 7 (unbounded storefront, over-fetch) |
| `cold_start_tti` ms | Finding 4.4 (pre-`runApp` network block) |
| `feed.query` reads + `feed_page_load` ms | §3 baseline (already cursor-paginated — expected to stay flat; it's the control) |

---

## 6. Instrumentation index (where the code lives)

> **Status (2026-07-02):** only `performance_service.dart` (the Firebase
> Performance traces) exists today. The read/listener counter, frame aggregator,
> on-screen debug controls, and their call-site hooks listed below are
> **planned but not yet created** — this section describes the intended layout,
> not the current tree.

- `lib/core/services/firestore_metrics.dart` *(planned — not yet created)* — read/listener counter + `trackListener` + `dumpAndReset`.
- `lib/core/services/frame_metrics.dart` *(planned — not yet created)* — feed-scroll frame aggregator + image-cache snapshot.
- `lib/core/services/performance_service.dart` — `cold_start_tti`, `storefront_open`, `feed_page_load` traces.
- `lib/widgets/debug_metrics_button.dart` *(planned — not yet created)* — the on-screen ▶/⏹/▤ controls (Home screen, debug/profile only).
- Call sites *(planned, wired in alongside the counter above)*: `feed_service.dart` (feed.query), `follow_service.dart` (feed.followBtn), `feed_card.dart` (feed.savedGet), `boutique_storefront_page.dart` (storefront.query + storefront_open), `boutique_logo_avatar.dart` (feed.logoLoad), `main.dart` + `home_page.dart` (cold_start_tti).

All instrumentation is inert in release builds (guards: `kDebugMode` / `!kReleaseMode`).
