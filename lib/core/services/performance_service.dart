import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// Central, typed factory for Firebase Performance Monitoring traces and HTTP
/// metrics used across LIBSK.
///
/// Each method returns an *unstarted* [Trace] / [HttpMetric] — the caller is
/// responsible for calling `start()` before the measured work and `stop()`
/// after (ideally in a `finally` so it stops on errors too). Use the singleton
/// via [PerformanceService.instance].
class PerformanceService {
  PerformanceService._();
  static final PerformanceService instance = PerformanceService._();

  // Resolved lazily on each use rather than as a construction-time field, so
  // that merely constructing this singleton (e.g. `markAppStart()` at the very
  // top of main()) does NOT touch FirebasePerformance.instance before
  // Firebase.initializeApp() has run. markAppStart only sets a DateTime.
  FirebasePerformance get _performance => FirebasePerformance.instance;

  /// Custom-trace names must be ≤ 100 chars; attribute values must too.
  static String _clip(String value) =>
      value.length <= 100 ? value : value.substring(0, 100);

  /// Trace around the `createOrder` Cloud Function call.
  /// start() before the call, stop() after.
  Trace traceCreateOrder() => _performance.newTrace('create_order');

  /// Trace spanning the full checkout flow duration.
  Trace traceCheckoutFlow() => _performance.newTrace('checkout_flow');

  /// Trace around a search query's latency. The query text is attached as an
  /// attribute (clipped to the 100-char limit) rather than baked into the trace
  /// name, which must stay low-cardinality.
  Trace traceSearchQuery(String query) {
    final trace = _performance.newTrace('search_query');
    trace.putAttribute('query', _clip(query));
    return trace;
  }

  /// Trace around an image load. [context] (e.g. 'product_page', 'feed') is
  /// attached as an attribute to distinguish call sites.
  Trace traceImageLoad(String context) {
    final trace = _performance.newTrace('image_load');
    trace.putAttribute('context', _clip(context));
    return trace;
  }

  /// HTTP metric for an outbound network call. start() before the request,
  /// stop() after the response (set responseCode/payload sizes if available).
  HttpMetric httpMetric(String url, HttpMethod method) =>
      _performance.newHttpMetric(url, method);

  /// Trace around one [FeedService.fetchMainPage] call (initial or load-more).
  /// Caller attaches a `feed_query_docs` metric and stops it in a finally.
  Trace traceFeedPageLoad() => _performance.newTrace('feed_page_load');

  /// Trace from boutique storefront route build to products-grid first paint.
  /// Caller attaches a `sku_count` metric and stops it in a post-frame callback.
  Trace traceStorefrontOpen() => _performance.newTrace('storefront_open');

  // ── Cold-start TTI (finding 4.4) ───────────────────────────────────────────
  // Measures main() start → first feed frame painted. This deliberately spans
  // the pre-runApp network block (CurrencyService.fetchRates + Stripe) so we
  // capture it BEFORE that work is moved off the startup path.

  DateTime? _appStartedAt;
  Trace? _coldStartTrace;
  bool _coldStartCaptured = false;

  /// Call as the very first statement of `main()`. Records the wall-clock
  /// origin; no Firebase dependency, safe before `ensureInitialized()`.
  void markAppStart() => _appStartedAt = DateTime.now();

  /// Call once Firebase is initialised (traces need the plugin up). Begins the
  /// release-surviving `cold_start_tti` trace.
  Future<void> startColdStartTrace() async {
    _coldStartTrace = _performance.newTrace('cold_start_tti');
    await _coldStartTrace?.start();
  }

  /// Call from a post-frame callback the first time the feed has painted with
  /// data. Records `tti_ms_from_main` on the trace (the true main→feed figure,
  /// since the trace itself can only start post-Firebase-init) and stops it.
  Future<void> markFeedFirstFrame() async {
    if (_coldStartCaptured) return;
    _coldStartCaptured = true;
    final ms = _appStartedAt == null
        ? null
        : DateTime.now().difference(_appStartedAt!).inMilliseconds;
    if (ms != null) _coldStartTrace?.setMetric('tti_ms_from_main', ms);
    await _coldStartTrace?.stop();
    if (kDebugMode) {
      debugPrint('cold_start_tti: ${ms ?? '?'} ms (main → first feed frame)');
    }
  }
}
