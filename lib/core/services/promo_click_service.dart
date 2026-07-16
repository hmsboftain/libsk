import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../services/firestore_service.dart';

/// The five paid placements a boutique can book. String values must match
/// PROMO_PLACEMENTS in functions/index.js — the server re-derives everything
/// from them and rejects anything it does not recognise.
class PromoPlacement {
  const PromoPlacement._();

  static const String homeBanner = 'home_banner';
  static const String featuredProduct = 'featured_product';
  static const String featuredBoutique = 'featured_boutique';
  static const String topOfCategory = 'top_of_category';
  static const String feedSponsored = 'feed_sponsored';
}

/// Provenance for one rendered placement: which booking paid to put this thing
/// on screen. Written by applyPromoRendering (see the stamp comment in
/// functions/index.js) onto the target document itself.
@immutable
class PromoStamp {
  final String bookingId;
  final String boutiqueId;
  final String placementType;

  /// Only set for top_of_category, which is bought per category.
  final String? category;

  const PromoStamp({
    required this.bookingId,
    required this.boutiqueId,
    required this.placementType,
    this.category,
  });
}

/// Find the stamp for [placementType] on a document's `promoAttribution` array.
///
/// Returns null when the document is on screen for FREE — an admin editorial
/// pick sets the very same rendering flags (isFeaturedOnHome and friends) but
/// leaves no stamp, and a click on one of those must never be billed to a paid
/// booking. Null is therefore the normal, common case, not an error.
///
/// [category] is required to disambiguate top_of_category: one product can be
/// pinned in two categories by two different bookings, and a click in "Dresses"
/// belongs to whichever booking bought "Dresses".
PromoStamp? promoStampFor(
  List<dynamic>? promoAttribution,
  String placementType, {
  String? category,
}) {
  if (promoAttribution == null) return null;
  for (final entry in promoAttribution) {
    if (entry is! Map) continue;
    if (entry['placementType'] != placementType) continue;
    if (category != null && entry['category'] != category) continue;
    final bookingId = entry['bookingId']?.toString() ?? '';
    final boutiqueId = entry['boutiqueId']?.toString() ?? '';
    if (bookingId.isEmpty) continue;
    return PromoStamp(
      bookingId: bookingId,
      boutiqueId: boutiqueId,
      placementType: placementType,
      category: entry['category']?.toString(),
    );
  }
  return null;
}

/// Reads the promo stamps off a raw Firestore document.
List<dynamic>? promoAttributionOf(Map<String, dynamic>? data) {
  final raw = data?['promoAttribution'];
  return raw is List ? raw : null;
}

/// Records taps on paid promo placements, so a boutique can see whether the
/// placement it bought actually did anything.
///
/// Fire-and-forget by contract: ad measurement must never delay or break a tap.
/// Every method returns immediately, never throws, and is deliberately NOT
/// awaited at its call sites — navigation happens regardless of whether the
/// click was recorded. Same discipline as [AnalyticsService].
///
/// Everything the caller passes is a CLAIM the server re-verifies (booking
/// active, in-window, actually rendering this subject) before it counts, so a
/// tampered client cannot pad its own numbers or poison a rival's.
class PromoClickService {
  PromoClickService._();
  static final PromoClickService instance = PromoClickService._();

  // Resolved lazily (same pattern as FirestoreService._functions): as an eager
  // field this would demand an initialised Firebase merely to touch the
  // singleton, which a unit test has no reason to need.
  //
  // logPromoClick is deployed to us-central1 — the attribution trigger lives in
  // europe-west1 beside the database, but this is a callable.
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Set by tests to observe calls without touching the network.
  @visibleForTesting
  static void Function(Map<String, dynamic> payload)? debugOnClick;

  /// Log a tap on a stamped placement. [subjectId] is the product id for
  /// product-scoped placements and the boutique id for boutique-scoped ones.
  Future<void> logClick({
    required String bookingId,
    required String placementType,
    required String subjectId,
    String? category,
  }) async {
    if (bookingId.isEmpty || subjectId.isEmpty) return;

    final payload = <String, dynamic>{
      'bookingId': bookingId,
      'placementType': placementType,
      'subjectId': subjectId,
      if (category != null) 'category': category,
      // Stable per-device id. Sent even when signed in, so a click made while
      // signed out has something to be matched on later. NOTE: signed-out
      // clicks are recorded but not yet attributable to a purchase — see the
      // note on logPromoClick in functions/index.js.
      'deviceId': FirestoreService.guestCartId ?? '',
    };

    final observer = debugOnClick;
    if (observer != null) {
      observer(payload);
      return;
    }

    try {
      await _functions.httpsCallable('logPromoClick').call(payload);
    } catch (e) {
      // Never surfaced and never rethrown: a failed measurement must not cost
      // the shopper their tap. A rejected click (stale stamp on a cached
      // screen, expired booking) is an ordinary outcome, not an error.
      if (kDebugMode) debugPrint('Promo click log failed: $e');
    }
  }

  /// Convenience for a stamped document — no-ops when [stamp] is null, i.e.
  /// when the placement is editorial rather than paid.
  Future<void> logStamped(PromoStamp? stamp, {required String subjectId}) {
    if (stamp == null) return Future<void>.value();
    return logClick(
      bookingId: stamp.bookingId,
      placementType: stamp.placementType,
      subjectId: subjectId,
      category: stamp.category,
    );
  }

  /// home_banner is the one placement whose provenance is NOT in a
  /// promoAttribution array: applyPromoRendering publishes a dedicated
  /// hero_banners document carrying `promoBookingId` and `boutiqueId` directly.
  /// Editorial banners have neither, so they log nothing.
  Future<void> logBannerClick(Map<String, dynamic> bannerData) {
    final bookingId = bannerData['promoBookingId']?.toString() ?? '';
    final boutiqueId = bannerData['boutiqueId']?.toString() ?? '';
    if (bookingId.isEmpty || boutiqueId.isEmpty) return Future<void>.value();
    return logClick(
      bookingId: bookingId,
      placementType: PromoPlacement.homeBanner,
      subjectId: boutiqueId,
    );
  }
}

/// Convenience for reading a stamp straight off a snapshot.
PromoStamp? promoStampOfDoc(
  DocumentSnapshot<Map<String, dynamic>> doc,
  String placementType, {
  String? category,
}) =>
    promoStampFor(promoAttributionOf(doc.data()), placementType,
        category: category);
