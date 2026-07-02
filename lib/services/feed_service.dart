import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/services/performance_service.dart';
import '../models/product.dart';
import '../widgets/feed_card.dart' show FeedBadge;
import 'follow_service.dart';

/// One assembled feed item: the product, why it's shown, and its boutique logo.
class FeedEntry {
  final Product product;
  final FeedBadge badge;
  final String boutiqueLogoUrl;

  const FeedEntry({
    required this.product,
    required this.badge,
    required this.boutiqueLogoUrl,
  });
}

/// A page of the main (followed / recent) feed, plus the cursor and a flag for
/// whether more pages exist.
class FeedPage {
  final List<FeedEntry> entries;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;

  const FeedPage({
    required this.entries,
    required this.lastDoc,
    required this.hasMore,
  });
}

/// Builds the home feed by running a few independent queries and combining
/// them: the main paginated stream (products from followed boutiques, or recent
/// posted products when the user follows nobody), plus trending and sponsored
/// injections.
///
/// Trending and sponsored depend on fields written by Cloud Functions /
/// the promo system (`weeklyOrders`, `isFeedSponsored`, `feedSponsoredUntil`).
/// Until those exist their queries simply return empty, so the feed degrades
/// gracefully to followed + recent.
class FeedService {
  FeedService();

  final _db = FirebaseFirestore.instance;
  final _follow = FollowService();

  /// Cache of boutiqueId -> logo URL so a feed full of the same boutique
  /// doesn't re-read its doc per card. Cleared on pull-to-refresh.
  final Map<String, String> _logoCache = {};

  static const int pageSize = 8;
  static const int _whereInLimit = 30; // Firestore cap for whereIn

  void clearCache() => _logoCache.clear();

  Future<String> _logoFor(String boutiqueId) async {
    if (boutiqueId.isEmpty) return '';
    final cached = _logoCache[boutiqueId];
    if (cached != null) return cached;
    try {
      final doc = await _db.collection('boutiques').doc(boutiqueId).get();
      final logo = doc.data()?['logoPath']?.toString() ?? '';
      _logoCache[boutiqueId] = logo;
      return logo;
    } catch (_) {
      return '';
    }
  }

  Future<List<FeedEntry>> _toEntries(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    FeedBadge badge,
  ) async {
    final entries = <FeedEntry>[];
    for (final doc in docs) {
      final product = Product.fromFirestore(doc);
      final logo = await _logoFor(product.boutiqueId);
      entries.add(
        FeedEntry(product: product, badge: badge, boutiqueLogoUrl: logo),
      );
    }
    return entries;
  }

  /// Main paginated feed. Followed boutiques if the user follows any, otherwise
  /// recent posted products as a discovery fallback.
  Future<FeedPage> fetchMainPage({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    final followingIds = await _follow.getFollowingIds();

    Query<Map<String, dynamic>> query;
    FeedBadge badge;

    if (followingIds.isNotEmpty) {
      // whereIn caps at 30; for launch scale the most recent 30 follows is a
      // fine bound. (Step 5 can rotate the window if anyone follows more.)
      final ids = followingIds.length > _whereInLimit
          ? followingIds.sublist(0, _whereInLimit)
          : followingIds;
      query = _db
          .collectionGroup('products')
          .where('postedToFeed', isEqualTo: true)
          .where('boutiqueId', whereIn: ids)
          .orderBy('feedPostedAt', descending: true);
      badge = FeedBadge.followed;
    } else {
      query = _db
          .collectionGroup('products')
          .where('postedToFeed', isEqualTo: true)
          .orderBy('feedPostedAt', descending: true);
      badge = FeedBadge.recommended;
    }

    query = query.limit(pageSize);
    if (startAfter != null) query = query.startAfterDocument(startAfter);

    // Trace one feed page load (initial or load-more) for Firebase Performance.
    final trace = PerformanceService.instance.traceFeedPageLoad();
    await trace.start();
    try {
      final snap = await query.get();
      trace.setMetric('feed_query_docs', snap.docs.length);

      final docs = snap.docs;
      final entries = await _toEntries(docs, badge);

      return FeedPage(
        entries: entries,
        lastDoc: docs.isNotEmpty ? docs.last : null,
        hasMore: docs.length == pageSize,
      );
    } finally {
      await trace.stop();
    }
  }

  /// Trending products by weekly sales velocity. Dormant until `weeklyOrders`
  /// is populated by the order Cloud Function (step 5).
  Future<List<FeedEntry>> fetchTrending({int limit = 6}) async {
    try {
      final snap = await _db
          .collectionGroup('products')
          .where('postedToFeed', isEqualTo: true)
          .where('weeklyOrders', isGreaterThan: 0)
          .orderBy('weeklyOrders', descending: true)
          .limit(limit)
          .get();
      return _toEntries(snap.docs, FeedBadge.hot);
    } catch (e) {
      debugPrint('TRENDING ERROR: $e');
      return [];
    }
  }

  /// Active sponsored products. Dormant until the promo system sets
  /// `isFeedSponsored` / `feedSponsoredUntil` (step 5).
  Future<List<FeedEntry>> fetchSponsored({int limit = 5}) async {
    try {
      final snap = await _db
          .collectionGroup('products')
          .where('isFeedSponsored', isEqualTo: true)
          .where('feedSponsoredUntil', isGreaterThan: Timestamp.now())
          .orderBy('feedSponsoredUntil')
          .limit(limit)
          .get();
      debugPrint('SPONSORED QUERY RETURNED: ${snap.docs.length} docs');
      return _toEntries(snap.docs, FeedBadge.sponsored);
    } catch (e) {
      debugPrint('SPONSORED ERROR: $e');
      return [];
    }
  }

  /// Injects [sponsored] into [main] every [gap] cards, then appends any
  /// leftovers. Returns [main] unchanged when there's nothing sponsored.
  List<FeedEntry> interleave(
    List<FeedEntry> main,
    List<FeedEntry> sponsored, {
    int gap = 4,
  }) {
    if (sponsored.isEmpty) return main;
    final result = <FeedEntry>[];
    var s = 0;
    for (var i = 0; i < main.length; i++) {
      result.add(main[i]);
      if ((i + 1) % gap == 0 && s < sponsored.length) {
        result.add(sponsored[s++]);
      }
    }
    while (s < sponsored.length) {
      result.add(sponsored[s++]);
    }
    return result;
  }
}
