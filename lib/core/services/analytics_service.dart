import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Central, typed wrapper around [FirebaseAnalytics] for LIBSK.
///
/// Every method is fire-and-forget and self-contained: analytics must never
/// break a user flow, so failures are swallowed (logged in debug only). Use the
/// singleton via [AnalyticsService.instance].
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Underlying instance, exposed for a [FirebaseAnalyticsObserver] if needed.
  FirebaseAnalytics get analytics => _analytics;

  Future<void> _log(String name, [Map<String, Object>? parameters]) async {
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
    } catch (e) {
      if (kDebugMode) debugPrint('Analytics event "$name" failed: $e');
    }
  }

  // ── Cart ───────────────────────────────────────────────────────────────────

  Future<void> logAddToCart(
    String productId,
    String productName,
    String boutiqueId,
    double price,
  ) {
    return _log('add_to_cart', {
      'product_id': productId,
      'product_name': productName,
      'boutique_id': boutiqueId,
      'price': price,
    });
  }

  Future<void> logRemoveFromCart(String productId) {
    return _log('remove_from_cart', {'product_id': productId});
  }

  // ── Checkout / purchase ─────────────────────────────────────────────────────

  Future<void> logBeginCheckout(double cartTotal, int itemCount) {
    return _log('begin_checkout', {
      'cart_total': cartTotal,
      'item_count': itemCount,
    });
  }

  Future<void> logPurchase(String orderId, double total, String boutiqueId) {
    return _log('purchase', {
      'order_id': orderId,
      'total': total,
      'boutique_id': boutiqueId,
    });
  }

  // ── Boutique follow ──────────────────────────────────────────────────────────

  Future<void> logBoutiqueFollow(String boutiqueId, String boutiqueName) {
    return _log('boutique_follow', {
      'boutique_id': boutiqueId,
      'boutique_name': boutiqueName,
    });
  }

  Future<void> logBoutiqueUnfollow(String boutiqueId) {
    return _log('boutique_unfollow', {'boutique_id': boutiqueId});
  }

  // ── Promo slots ──────────────────────────────────────────────────────────────

  Future<void> logPromoSlotView(String boutiqueId, int slotPosition) {
    return _log('promo_slot_view', {
      'boutique_id': boutiqueId,
      'slot_position': slotPosition,
    });
  }

  Future<void> logPromoSlotTap(String boutiqueId, int slotPosition) {
    return _log('promo_slot_tap', {
      'boutique_id': boutiqueId,
      'slot_position': slotPosition,
    });
  }

  // ── Search ───────────────────────────────────────────────────────────────────

  Future<void> logSearchQuery(String query, int resultCount) {
    return _log('search', {
      'search_term': query,
      'result_count': resultCount,
    });
  }

  // ── Screen views ─────────────────────────────────────────────────────────────

  Future<void> logScreenView(String screenName) async {
    try {
      await _analytics.logScreenView(screenName: screenName);
    } catch (e) {
      if (kDebugMode) debugPrint('Analytics screen view "$screenName" failed: $e');
    }
  }
}
