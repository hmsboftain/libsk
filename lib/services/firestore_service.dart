import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/analytics_service.dart';
import '../models/admin_permissions.dart';
import '../models/promo_availability.dart';

/// Result of `createPromoBooking` — enough to drive the Payzah payment, or to
/// know it was fully covered by promo credit and no payment is needed.
class PromoBookingResult {
  final String bookingId;

  /// Null when [creditOnly] — a fully-credit-funded booking has no payment
  /// attempt and skips the Payzah page entirely.
  final String? paymentAttemptId;
  final double priceKwd;

  /// Credit applied to this booking and the remainder charged via Payzah (KWD).
  final double amountFromCredit;
  final double amountToCharge;

  /// True when credit covered the whole price: the booking is already active (or
  /// awaiting banner review) and there is nothing to pay.
  final bool creditOnly;

  const PromoBookingResult({
    required this.bookingId,
    required this.paymentAttemptId,
    required this.priceKwd,
    required this.amountFromCredit,
    required this.amountToCharge,
    required this.creditOnly,
  });
}

class FirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String? _guestCartId;

  static String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in");
    return user.uid;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  // ── Guest cart ─────────────────────────────────────────────────────────────

  static Future<void> prepareGuestCartId() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedGuestId = prefs.getString('guestCartId');

    if (savedGuestId == null || savedGuestId.isEmpty) {
      final rng = Random.secure();
      final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      savedGuestId = 'guest_$hex';
      await prefs.setString('guestCartId', savedGuestId);
    }

    _guestCartId = savedGuestId;
  }

  static String get _cartOwnerId {
    final user = _auth.currentUser;
    if (user != null) return user.uid;
    if (_guestCartId == null) {
      throw Exception('Guest cart ID has not been prepared');
    }
    return _guestCartId!;
  }

  // ── Saved Items ────────────────────────────────────────────────────────────

  static CollectionReference<Map<String, dynamic>> get _savedItemsRef =>
      _firestore.collection('users').doc(_uid).collection('saved_items');

  static Future<void> saveItem({
    required String productId,
    required String boutiqueId,
    required String imageUrl,
    required List<String> imageUrls,
    required String title,
    required String boutiqueName,
    required double price,
    required String description,
    required List<String> sizes,
    required int stock,
  }) async {
    await _savedItemsRef.doc(productId).set({
      'productId': productId,
      'boutiqueId': boutiqueId,
      'imageUrl': imageUrl,
      'imageUrls': imageUrls,
      'title': title,
      'boutiqueName': boutiqueName,
      'price': price,
      'description': description,
      'sizes': sizes,
      'stock': stock,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> removeSavedItem(String productId) async {
    await _savedItemsRef.doc(productId).delete();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getSavedItemsStream() {
    return _savedItemsRef.orderBy('createdAt', descending: true).snapshots();
  }

  static Future<bool> isItemSaved(String productId) async {
    final doc = await _savedItemsRef.doc(productId).get();
    return doc.exists;
  }

  /// One-time fetch of the current user's saved product ids (single get, not a
  /// listener). Backs the shared SavedItemsController so the feed no longer
  /// issues a per-card `isItemSaved` get (finding 4.2).
  static Future<Set<String>> fetchSavedItemIds() async {
    final snap = await _savedItemsRef.get();
    return snap.docs.map((d) => d.id).toSet();
  }

  // ── Saved Boutiques ────────────────────────────────────────────────────────

  static CollectionReference<Map<String, dynamic>> get _savedBoutiquesRef =>
      _firestore.collection('users').doc(_uid).collection('saved_boutiques');

  static Future<void> saveBoutique({
    required String boutiqueId,
    required String imageUrl,
    required String boutiqueName,
  }) async {
    await _savedBoutiquesRef.doc(boutiqueId).set({
      'boutiqueId': boutiqueId,
      'imageUrl': imageUrl,
      'boutiqueName': boutiqueName,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> removeSavedBoutique(String boutiqueId) async {
    await _savedBoutiquesRef.doc(boutiqueId).delete();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getSavedBoutiquesStream() {
    return _savedBoutiquesRef
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ── Saved Addresses ────────────────────────────────────────────────────────

  static CollectionReference<Map<String, dynamic>> get _savedAddressesRef =>
      _firestore.collection('users').doc(_uid).collection('saved_addresses');

  /// Kuwait address — uses block/street/house/governorate structure.
  static Future<void> addAddress({
    required String firstName,
    required String lastName,
    required String governorate,
    required String area,
    required String block,
    required String street,
    required String house,
    required String floor,
    required String apartment,
    required String phone,
  }) async {
    await _savedAddressesRef.add({
      'type': 'kuwait',
      'firstName': firstName,
      'lastName': lastName,
      'governorate': governorate,
      'area': area,
      'block': block,
      'street': street,
      'house': house,
      'floor': floor,
      'apartment': apartment,
      'phone': phone,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// International address — uses address lines / city / zip structure.
  static Future<void> addInternationalAddress({
    required String firstName,
    required String lastName,
    required String addressLine1,
    required String addressLine2,
    required String city,
    required String zipCode,
    required String countryCode,
    required String phone,
  }) async {
    await _savedAddressesRef.add({
      'type': 'international',
      'firstName': firstName,
      'lastName': lastName,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'zipCode': zipCode,
      'countryCode': countryCode,
      'phone': phone,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteAddress(String addressId) async {
    await _savedAddressesRef.doc(addressId).delete();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getSavedAddressesStream() {
    return _savedAddressesRef
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ── Cart ───────────────────────────────────────────────────────────────────

  // Cart is stored per boutique: users/{owner}/carts/{boutiqueId} holds a
  // summary doc (name, logo, itemCount) and an items/{itemId} subcollection.
  static CollectionReference<Map<String, dynamic>> get _cartsRef {
    return _firestore
        .collection('users')
        .doc(_cartOwnerId)
        .collection('carts');
  }

  static CollectionReference<Map<String, dynamic>> _cartItemsRef(
    String boutiqueId,
  ) {
    return _cartsRef.doc(boutiqueId).collection('items');
  }

  /// Streams the user's per-boutique cart summary docs (one per boutique),
  /// most recently updated first. Drives the cart switcher.
  static Stream<QuerySnapshot<Map<String, dynamic>>> getCartsStream() {
    return _cartsRef.orderBy('updatedAt', descending: true).snapshots();
  }

  /// Total line-item count across all of the user's boutique carts, for the
  /// header badge. Sums the maintained `itemCount` on each summary doc so no
  /// collection-group query (and matching index/rule) is required.
  static Stream<int> getCartItemCountStream() {
    return _cartsRef.snapshots().map(
      (snap) => snap.docs.fold<int>(
        0,
        (total, d) => total + ((d.data()['itemCount'] as num?)?.toInt() ?? 0),
      ),
    );
  }

  /// Creates the per-boutique cart summary doc if it doesn't exist yet, pulling
  /// the boutique name/logo so the switcher can render without reading items.
  static Future<void> _ensureCartSummary({
    required DocumentReference<Map<String, dynamic>> cartDocRef,
    required String boutiqueId,
    Map<String, dynamic>? productData,
  }) async {
    final existing = await cartDocRef.get();
    if (existing.exists) return;

    String boutiqueName = (productData?['boutiqueName'] ?? '').toString();
    String boutiqueLogoUrl = '';
    try {
      final bDoc =
          await _firestore.collection('boutiques').doc(boutiqueId).get();
      final b = bDoc.data();
      if (b != null) {
        if (boutiqueName.isEmpty) boutiqueName = (b['name'] ?? '').toString();
        boutiqueLogoUrl = (b['logoPath'] ?? '').toString();
      }
    } catch (_) {}

    await cartDocRef.set({
      'boutiqueId': boutiqueId,
      'boutiqueName': boutiqueName,
      'boutiqueLogoUrl': boutiqueLogoUrl,
      'itemCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> addToCart({
    required String productId,
    required String boutiqueId,
    required String imageUrl,
    required String title,
    required String description,
    required String size,
    String color = '',
    required double price,
    String specialRequest = '',
  }) async {
    final productRef = _firestore
        .collection('boutiques')
        .doc(boutiqueId)
        .collection('products')
        .doc(productId);

    final productDoc = await productRef.get();

    if (!productDoc.exists) {
      throw Exception('$title is no longer available');
    }

    final productData = productDoc.data();
    final stockValue = productData?['stock'] ?? 0;
    final int currentStock = stockValue is int
        ? stockValue
        : int.tryParse(stockValue.toString()) ?? 0;

    if (currentStock <= 0) {
      throw Exception('$title is out of stock');
    }

    final cartDocRef = _cartsRef.doc(boutiqueId);
    final itemsRef = cartDocRef.collection('items');

    final normalizedColor = color.trim();
    final normalizedRequest = specialRequest.trim();
    final docId = normalizedColor.isEmpty
        ? '${productId}_$size'
        : '${productId}_${size}_$normalizedColor';
    final docRef = itemsRef.doc(docId);
    final doc = await docRef.get();

    if (doc.exists) {
      final quantityValue = doc.data()?['quantity'] ?? 1;
      final int currentQuantity = quantityValue is int
          ? quantityValue
          : int.tryParse(quantityValue.toString()) ?? 1;

      if (currentQuantity + 1 > currentStock) {
        throw Exception('Only $currentStock left in stock');
      }

      await docRef.update({
        'quantity': currentQuantity + 1,
        // Same product+size+colour is one cart line; a fresh note replaces the
        // stored one, an empty note leaves the existing note untouched.
        if (normalizedRequest.isNotEmpty) 'specialRequest': normalizedRequest,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Bump the cart to the top of the switcher.
      await cartDocRef.set({
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      // Ensure the boutique cart summary exists before its first item.
      await _ensureCartSummary(
        cartDocRef: cartDocRef,
        boutiqueId: boutiqueId,
        productData: productData,
      );

      await docRef.set({
        'productId': productId,
        'boutiqueId': boutiqueId,
        'imageUrl': imageUrl,
        'title': title,
        'description': description,
        'size': size,
        if (normalizedColor.isNotEmpty) 'color': normalizedColor,
        if (normalizedRequest.isNotEmpty) 'specialRequest': normalizedRequest,
        'price': price,
        'quantity': 1,
        // Store madeToOrder flag so checkout can detect it
        if (productData?['madeToOrder'] == true) 'madeToOrder': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // New line item — maintain the count used by the header badge.
      await cartDocRef.set({
        'itemCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    AnalyticsService.instance.logAddToCart(productId, title, boutiqueId, price);
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getCartItemsStream(
    String boutiqueId,
  ) {
    return _cartItemsRef(boutiqueId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Future<void> updateCartItemQuantity({
    required String boutiqueId,
    required String docId,
    required int quantity,
  }) async {
    if (quantity <= 0) {
      await _removeCartItem(boutiqueId, docId);
      return;
    }

    final itemsRef = _cartItemsRef(boutiqueId);
    final cartItemDoc = await itemsRef.doc(docId).get();
    if (!cartItemDoc.exists) throw Exception('Cart item not found');

    final cartItemData = cartItemDoc.data();
    final productId = cartItemData?['productId']?.toString() ?? '';
    final title = cartItemData?['title']?.toString() ?? 'Product';

    final productDoc = await _firestore
        .collection('boutiques')
        .doc(boutiqueId)
        .collection('products')
        .doc(productId)
        .get();

    if (!productDoc.exists) {
      throw Exception('$title is no longer available');
    }

    final stockValue = productDoc.data()?['stock'] ?? 0;
    final int currentStock = stockValue is int
        ? stockValue
        : int.tryParse(stockValue.toString()) ?? 0;

    if (quantity > currentStock) {
      throw Exception('Only $currentStock left in stock');
    }

    await itemsRef.doc(docId).update({
      'quantity': quantity,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _cartsRef.doc(boutiqueId).set({
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> deleteCartItem({
    required String boutiqueId,
    required String docId,
  }) async {
    await _removeCartItem(boutiqueId, docId);
  }

  /// Deletes a line item and keeps the summary in sync: decrements the
  /// maintained count, and deletes the whole boutique cart once its last item
  /// is gone, so the switcher never shows an empty cart.
  static Future<void> _removeCartItem(String boutiqueId, String docId) async {
    final cartDocRef = _cartsRef.doc(boutiqueId);
    await cartDocRef.collection('items').doc(docId).delete();

    final remaining = await cartDocRef.collection('items').limit(1).get();
    if (remaining.docs.isEmpty) {
      await cartDocRef.delete();
    } else {
      await cartDocRef.set({
        'itemCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Empties a boutique's cart entirely (used after a successful checkout).
  static Future<void> clearBoutiqueCart(String boutiqueId) async {
    final cartDocRef = _cartsRef.doc(boutiqueId);
    final items = await cartDocRef.collection('items').get();
    for (final doc in items.docs) {
      await doc.reference.delete();
    }
    await cartDocRef.delete();
  }

  static Future<void> mergeGuestCartToUser() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await prepareGuestCartId();

    final guestId = _guestCartId;
    if (guestId == null || guestId.isEmpty) return;

    final guestCartsRef =
        _firestore.collection('users').doc(guestId).collection('carts');
    final userCartsRef =
        _firestore.collection('users').doc(user.uid).collection('carts');

    final guestCarts = await guestCartsRef.get();
    if (guestCarts.docs.isEmpty) return;

    for (final guestCart in guestCarts.docs) {
      final boutiqueId = guestCart.id;
      final guestMeta = guestCart.data();
      final guestItemsRef = guestCartsRef.doc(boutiqueId).collection('items');
      final userItemsRef = userCartsRef.doc(boutiqueId).collection('items');

      final guestItems = await guestItemsRef.get();

      for (final doc in guestItems.docs) {
        final data = doc.data();
        final productId = data['productId']?.toString() ?? '';
        final itemBoutiqueId = data['boutiqueId']?.toString() ?? '';

        if (productId.isEmpty || itemBoutiqueId.isEmpty) {
          await guestItemsRef.doc(doc.id).delete();
          continue;
        }

        final productDoc = await _firestore
            .collection('boutiques')
            .doc(itemBoutiqueId)
            .collection('products')
            .doc(productId)
            .get();

        if (!productDoc.exists) {
          await guestItemsRef.doc(doc.id).delete();
          continue;
        }

        final stockValue = productDoc.data()?['stock'] ?? 0;
        final int currentStock = stockValue is int
            ? stockValue
            : int.tryParse(stockValue.toString()) ?? 0;

        if (currentStock <= 0) {
          await guestItemsRef.doc(doc.id).delete();
          continue;
        }

        final existingDoc = await userItemsRef.doc(doc.id).get();
        final guestQuantityValue = data['quantity'] ?? 1;
        final int guestQuantity = guestQuantityValue is int
            ? guestQuantityValue
            : int.tryParse(guestQuantityValue.toString()) ?? 1;

        if (existingDoc.exists) {
          final currentQuantityValue = existingDoc.data()?['quantity'] ?? 1;
          final int currentQuantity = currentQuantityValue is int
              ? currentQuantityValue
              : int.tryParse(currentQuantityValue.toString()) ?? 1;

          final mergedQuantity = currentQuantity + guestQuantity;
          final safeQuantity =
              mergedQuantity > currentStock ? currentStock : mergedQuantity;

          await userItemsRef.doc(doc.id).update({
            'quantity': safeQuantity,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          final safeQuantity =
              guestQuantity > currentStock ? currentStock : guestQuantity;

          await userItemsRef.doc(doc.id).set({
            ...data,
            'quantity': safeQuantity,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        await guestItemsRef.doc(doc.id).delete();
      }

      // Rebuild the user's summary doc for this boutique from the merged
      // items, then drop the guest cart.
      final mergedItems = await userItemsRef.get();
      if (mergedItems.docs.isNotEmpty) {
        final userCartDocRef = userCartsRef.doc(boutiqueId);
        final existingSummary = await userCartDocRef.get();
        await userCartDocRef.set({
          'boutiqueId': boutiqueId,
          'boutiqueName': guestMeta['boutiqueName'] ?? '',
          'boutiqueLogoUrl': guestMeta['boutiqueLogoUrl'] ?? '',
          'itemCount': mergedItems.docs.length,
          if (!existingSummary.exists)
            'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await guestCartsRef.doc(boutiqueId).delete();
    }
  }

  // ── Orders ─────────────────────────────────────────────────────────────────

  static CollectionReference<Map<String, dynamic>> get _ordersRef =>
      _firestore.collection('users').doc(_uid).collection('orders');

  /// Creates an order via the Cloud Function (Payzah redirect flow: the order
  /// starts as "Pending Payment" and the returned [CreateOrderResult.paymentAttemptId]
  /// is handed to `initializePayzahPayment`).
  ///
  /// [discountCodeId] and [discountAmount] are optional — only pass them when
  /// a discount code has been validated on the checkout page.
  ///
  /// [estimatedDays] is only relevant when [deliveryMethod] == "Made to Order".
  static Future<CreateOrderResult> createOrder({
    required List<Map<String, dynamic>> items,
    required int itemCount,
    required double total,
    String? deliveryMethod,
    String? paymentMethod,
    // ── Discount code (feature #8) ──────────────────────────
    String? discountCodeId,
    double? discountAmount,
    // ── Made to order (feature #3) ──────────────────────────
    int? estimatedDays,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    final callable = _functions.httpsCallable('createOrder');

    final payload = <String, dynamic>{
      'items': items,
      'deliveryMethod': deliveryMethod ?? '',
      'paymentMethod': paymentMethod ?? '',
      'paymentProvider': 'payzah',
      if (discountCodeId != null && discountCodeId.isNotEmpty) ...{
        'discountCodeId': discountCodeId,
        'discountAmount': discountAmount ?? 0,
      },
      if (deliveryMethod == 'Made to Order' && estimatedDays != null)
        'estimatedDays': estimatedDays,
    };

    final result = await callable.call(payload);
    final data = Map<String, dynamic>.from(result.data as Map);
    final orderNumber = data['orderNumber']?.toString();
    final orderId = data['orderId']?.toString();
    final paymentAttemptId = data['paymentAttemptId']?.toString();

    if (orderNumber == null || orderNumber.isEmpty) {
      throw Exception('Order number missing from server response');
    }
    if (paymentAttemptId == null || paymentAttemptId.isEmpty) {
      throw Exception('Payment attempt id missing from server response');
    }

    return CreateOrderResult(
      orderNumber: orderNumber,
      orderId: orderId ?? '',
      paymentAttemptId: paymentAttemptId,
    );
  }

  /// Superadmin bookkeeping for the manual refund process: money is refunded
  /// by hand in the Payzah merchant dashboard first, then this records the
  /// outcome — "Refunded" on all three order copies, with who marked it and
  /// when stamped on the global order. No gateway API call is involved.
  /// Firestore rules restrict these order writes to admins.
  static Future<void> markOrderRefundedAsAdmin(String globalOrderId) async {
    final adminUser = _auth.currentUser;
    if (adminUser == null) throw Exception("User not logged in");

    final globalRef = _firestore.collection('global_orders').doc(globalOrderId);
    final snap = await globalRef.get();
    if (!snap.exists) throw Exception('Order not found');
    final data = snap.data()!;

    await globalRef.update({
      'status': 'Refunded',
      'refundedBy': adminUser.uid,
      'refundedByEmail': adminUser.email ?? '',
      'refundedAt': FieldValue.serverTimestamp(),
    });

    final customerUid = data['customerUid']?.toString() ?? '';
    final sourceUserOrderId = data['sourceUserOrderId']?.toString() ?? '';
    if (customerUid.isNotEmpty && sourceUserOrderId.isNotEmpty) {
      await _firestore
          .collection('users')
          .doc(customerUid)
          .collection('orders')
          .doc(sourceUserOrderId)
          .update({'status': 'Refunded'});
    }

    final items = data['items'];
    if (items is List && sourceUserOrderId.isNotEmpty) {
      final boutiqueIds = <String>{};
      for (final item in items) {
        final id = (item is Map ? item['boutiqueId'] : null)?.toString() ?? '';
        if (id.isNotEmpty) boutiqueIds.add(id);
      }
      for (final boutiqueId in boutiqueIds) {
        final boutiqueOrders = await _firestore
            .collection('boutiques')
            .doc(boutiqueId)
            .collection('orders')
            .where('sourceUserOrderId', isEqualTo: sourceUserOrderId)
            .get();
        for (final doc in boutiqueOrders.docs) {
          await doc.reference.update({'status': 'Refunded'});
        }
      }
    }
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getOrdersStream() {
    return _ordersRef.orderBy('createdAt', descending: true).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getOwnerOrdersStream(
    String boutiqueId,
  ) {
    return _firestore
        .collection('boutiques')
        .doc(boutiqueId)
        .collection('orders')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> getGlobalOrdersOnce() {
    return _firestore
        .collection('global_orders')
        .orderBy('createdAt', descending: true)
        .get();
  }

  // ── Discount codes (feature #8) ────────────────────────────────────────────

  /// Calls the [validateDiscountCode] Cloud Function.
  /// Returns a map with keys: codeId, code, type, value, discountAmount,
  /// description, boutiqueId, boutiqueName.
  static Future<Map<String, dynamic>> validateDiscountCode({
    required String code,
    required double subtotal,
    required List<String> boutiqueIds,
  }) async {
    final callable = _functions.httpsCallable('validateDiscountCode');
    final result = await callable.call({
      'code': code.toUpperCase().trim(),
      'subtotal': subtotal,
      'boutiqueIds': boutiqueIds,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  // ── Promo slots (feature #5) ───────────────────────────────────────────────

  /// Available slot types and their display labels.
  static const Map<String, String> promoSlotTypes = {
    'home_banner': 'Home Banner',
    'featured_product': 'Featured Product',
    'category_sponsored': 'Sponsored in Category',
    'feed_sponsored': 'Sponsored in Feed',
    'boutique_featured': 'Featured Boutique',
  };

  /// Fetches active promo slot listings (prices and durations) from Firestore.
  /// The super admin manages these documents in `promo_slot_config/{slotType}`.
  static Future<List<Map<String, dynamic>>> getPromoSlotConfig() async {
    final snap = await _firestore.collection('promo_slot_config').get();
    return snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  /// Returns the stream of promo slot bookings for the current boutique owner.
  static Future<Stream<QuerySnapshot<Map<String, dynamic>>>?>
  getOwnerPromoSlotsStream() async {
    final boutiqueId = await getCurrentOwnerBoutiqueId();
    if (boutiqueId == null) return null;

    return _firestore
        .collection('promo_slots')
        .where('boutiqueId', isEqualTo: boutiqueId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Books a promo slot for the current boutique owner.
  ///
  /// This creates a pending booking document. Payment via MyFatoorah is
  /// initiated separately — call [initiatePromoSlotPayment] after this.
  /// Once payment is confirmed the slot becomes active.
  static Future<String> bookPromoSlot({
    required String slotType,
    required int durationDays,
    required double priceKwd,
  }) async {
    final boutiqueId = await getCurrentOwnerBoutiqueId();
    if (boutiqueId == null) throw Exception('No boutique found');

    final boutiqueData = await getOwnerBoutiqueData(boutiqueId: boutiqueId);
    final boutiqueName = boutiqueData?['name']?.toString() ?? '';

    final docRef = await _firestore.collection('promo_slots').add({
      'boutiqueId': boutiqueId,
      'boutiqueName': boutiqueName,
      'slotType': slotType,
      'slotLabel': promoSlotTypes[slotType] ?? slotType,
      'durationDays': durationDays,
      'priceKwd': priceKwd,
      'status': 'pending_payment', // → 'active' after payment confirmed
      'paymentStatus': 'unpaid',
      'paymentMethod': 'myfatoorah',
      'createdAt': FieldValue.serverTimestamp(),
    });

    return docRef.id;
  }

  /// Initiates a MyFatoorah payment for a promo slot booking.
  ///
  /// Calls the [initiatePromoSlotPayment] Cloud Function which creates a
  /// MyFatoorah invoice and returns the payment URL. The owner is then
  /// redirected to that URL to complete payment.
  ///
  /// NOTE: Wire this up once you have your MyFatoorah API key. The Cloud
  /// Function stub is in index.js — search for initiatePromoSlotPayment.
  static Future<String> initiatePromoSlotPayment({
    required String promoSlotId,
  }) async {
    final callable = _functions.httpsCallable('initiatePromoSlotPayment');
    final result = await callable.call({'promoSlotId': promoSlotId});
    final data = Map<String, dynamic>.from(result.data as Map);
    final paymentUrl = data['paymentUrl']?.toString();
    if (paymentUrl == null || paymentUrl.isEmpty) {
      throw Exception('Payment URL missing from server response');
    }
    return paymentUrl;
  }

  /// Books a weekly promo placement via the `createPromoBooking` Cloud Function.
  ///
  /// The server derives the boutique, verifies targets, enforces availability
  /// and computes the price — the client sends only the placement, its targets
  /// and a payment method (never a price). Returns the ids needed to drive the
  /// Payzah payment: pass [PromoBookingResult.paymentAttemptId] to the promo
  /// payment page, which runs the same Payzah flow as customer checkout.
  /// Day-based placements (all but feed) require [startDay] (0=Sun…6=Sat) and
  /// [numDays] (1–7). Targets are one unit: [productId] for featured_product;
  /// [category] + [productIds] (1–2) for top_of_category; [targetProductIds]
  /// (1–2 posts) for feed; [bannerImageUrl] for home_banner.
  static Future<PromoBookingResult> createPromoBooking({
    required String placementType,
    required String paymentMethod,
    int? startDay,
    int? numDays,
    String? productId,
    List<String>? targetProductIds,
    String? category,
    List<String>? productIds,
    String? bannerImageUrl,
    bool useCredit = false,
  }) async {
    final callable = _functions.httpsCallable('createPromoBooking');
    final result = await callable.call({
      'placementType': placementType,
      'paymentMethod': paymentMethod,
      'useCredit': useCredit,
      if (startDay != null) 'startDay': startDay,
      if (numDays != null) 'numDays': numDays,
      if (productId != null) 'productId': productId,
      if (targetProductIds != null) 'targetProductIds': targetProductIds,
      if (category != null) 'category': category,
      if (productIds != null) 'productIds': productIds,
      if (bannerImageUrl != null) 'bannerImageUrl': bannerImageUrl,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final attemptId = data['paymentAttemptId']?.toString();
    return PromoBookingResult(
      bookingId: data['bookingId']?.toString() ?? '',
      paymentAttemptId: (attemptId == null || attemptId.isEmpty) ? null : attemptId,
      priceKwd: (data['priceKwd'] as num?)?.toDouble() ?? 0,
      amountFromCredit: (data['amountFromCredit'] as num?)?.toDouble() ?? 0,
      amountToCharge: (data['amountToCharge'] as num?)?.toDouble() ?? 0,
      creditOnly: data['creditOnly'] == true,
    );
  }

  /// Live availability + the server-computed price tables for the upcoming
  /// bookable week (next Sun–Sat, Asia/Kuwait). Approved-owner gated server-side.
  /// The returned [PromoAvailability] is the ONLY source of prices the dashboard
  /// displays — see the class docs on price integrity.
  static Future<PromoAvailability> getPromoAvailability() async {
    final callable = _functions.httpsCallable('getPromoAvailability');
    final result = await callable.call();
    return PromoAvailability.fromMap(
      Map<String, dynamic>.from(result.data as Map),
    );
  }

  /// The current owner's promo bookings (new `promo_bookings` collection, not
  /// the legacy `promo_slots`). Equality-only query on the auto-indexed
  /// `boutiqueId`; the dashboard sorts/groups client-side, so no composite index
  /// is required. Returns null when the caller has no boutique.
  static Future<Stream<QuerySnapshot<Map<String, dynamic>>>?>
  getMyPromoBookingsStream() async {
    final boutiqueId = await getCurrentOwnerBoutiqueId();
    if (boutiqueId == null) return null;
    return _firestore
        .collection('promo_bookings')
        .where('boutiqueId', isEqualTo: boutiqueId)
        .snapshots();
  }

  /// Home-banner bookings awaiting super-admin review. Only banners ever reach
  /// `paid_pending_review`, so an equality query on the auto-indexed `status`
  /// returns exactly the review queue with no composite index.
  static Stream<QuerySnapshot<Map<String, dynamic>>>
  getPendingPromoBannersStream() {
    return _firestore
        .collection('promo_bookings')
        .where('status', isEqualTo: 'paid_pending_review')
        .snapshots();
  }

  /// Super-admin: approve a pending banner creative. The scheduled activator
  /// publishes the hero banner when its day-window opens.
  static Future<void> approvePromoBanner(String bookingId) async {
    final callable = _functions.httpsCallable('approvePromoBanner');
    await callable.call({'bookingId': bookingId});
  }

  /// Super-admin: reject a pending banner creative (payment refunded manually;
  /// any promo credit spent on it is refunded automatically server-side).
  static Future<void> rejectPromoBanner(String bookingId, {String? reason}) async {
    final callable = _functions.httpsCallable('rejectPromoBanner');
    await callable.call({
      'bookingId': bookingId,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
  }

  // ── Founding-partner promo credit (super admin) ────────────────────────────

  /// Super-admin: the ONE-TIME launch action. Grants Week-1 founding credit to
  /// every boutique still flagged `promoCreditPending` and schedules their Week-2
  /// grant 7 days out. Idempotent server-side — already-recharged boutiques are
  /// skipped, so a re-run is safe. Returns how many were recharged vs skipped.
  static Future<({int recharged, int skipped})>
  rechargeFoundingPartnerCredits() async {
    final callable = _functions.httpsCallable('rechargeFoundingPartnerCredits');
    final result = await callable.call();
    final data = Map<String, dynamic>.from(result.data as Map);
    return (
      recharged: (data['recharged'] as num?)?.toInt() ?? 0,
      skipped: (data['skipped'] as num?)?.toInt() ?? 0,
    );
  }

  /// Super-admin: manual promo-credit adjustment — goodwill top-up, a boutique
  /// joining mid-cohort, or a dispute clawback. A positive [amount] grants credit
  /// (expiring after [expiresInDays]; pass 0 for never); a negative one claws it
  /// back FIFO, clamped to the live balance. Returns what was actually applied
  /// (a clawback larger than the balance removes only what's there) and the new
  /// balance, both in KWD.
  static Future<({double applied, double newBalance})> adjustPromoCredit({
    required String boutiqueId,
    required double amount,
    required String reason,
    int? expiresInDays,
  }) async {
    final callable = _functions.httpsCallable('adjustPromoCredit');
    final result = await callable.call({
      'boutiqueId': boutiqueId,
      'amount': amount,
      'reason': reason,
      if (expiresInDays != null) 'expiresInDays': expiresInDays,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return (
      applied: (data['applied'] as num?)?.toDouble() ?? 0,
      newBalance: (data['newBalance'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Called by the admin to manually activate a promo slot after payment is
  /// confirmed (fallback before MyFatoorah webhook is wired up).
  static Future<void> activatePromoSlot(String promoSlotId) async {
    final now = DateTime.now();
    final doc = await _firestore
        .collection('promo_slots')
        .doc(promoSlotId)
        .get();
    if (!doc.exists) throw Exception('Promo slot not found');

    final data = doc.data()!;
    final durationDays = (data['durationDays'] as num?)?.toInt() ?? 7;
    final expiresAt = Timestamp.fromDate(now.add(Duration(days: durationDays)));

    await _firestore.collection('promo_slots').doc(promoSlotId).update({
      'status': 'active',
      'paymentStatus': 'paid',
      'activatedAt': FieldValue.serverTimestamp(),
      'expiresAt': expiresAt,
    });
  }

  /// Returns a stream of all promo slots for admin view.
  static Stream<QuerySnapshot<Map<String, dynamic>>> getAllPromoSlotsStream() {
    return _firestore
        .collection('promo_slots')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ── Owner side ─────────────────────────────────────────────────────────────

  static Future<bool> isCurrentUserOwner() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final doc = await _firestore
        .collection('boutique_owners')
        .doc(user.uid)
        .get();
    return doc.exists;
  }

  static Future<bool> isCurrentUserApprovedOwner() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final doc = await _firestore
        .collection('boutique_owners')
        .doc(user.uid)
        .get();
    if (!doc.exists) return false;
    final data = doc.data();
    if (data == null) return false;
    return data['role'] == 'boutique_owner' && data['isApproved'] == true;
  }

  static Future<Map<String, dynamic>?> getCurrentOwnerData() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final doc = await _firestore
        .collection('boutique_owners')
        .doc(user.uid)
        .get();
    if (!doc.exists) return null;
    return doc.data();
  }

  static Future<String?> getCurrentOwnerBoutiqueId() async {
    final ownerData = await getCurrentOwnerData();
    if (ownerData == null) return null;
    return ownerData['boutiqueId'] as String?;
  }

  /// Fetches the current owner's boutique doc.
  ///
  /// Pass [boutiqueId] when it's already known (e.g. from a prior
  /// [getCurrentOwnerData] / [getCurrentOwnerBoutiqueId] read) to skip the
  /// redundant `boutique_owners` lookup (finding F2). Behaviour is otherwise
  /// identical — it still throws when the owner or boutique can't be resolved.
  static Future<Map<String, dynamic>?> getOwnerBoutiqueData({
    String? boutiqueId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    String? resolvedId = boutiqueId;
    if (resolvedId == null) {
      final ownerDoc = await _firestore
          .collection('boutique_owners')
          .doc(user.uid)
          .get();
      if (!ownerDoc.exists) throw Exception("Owner document not found");

      final ownerData = ownerDoc.data();
      if (ownerData == null) throw Exception("Owner data is null");

      resolvedId = ownerData['boutiqueId']?.toString();
    }

    if (resolvedId == null || resolvedId.isEmpty) {
      throw Exception("No boutiqueId assigned to this owner");
    }

    final boutiqueDoc = await _firestore
        .collection('boutiques')
        .doc(resolvedId)
        .get();
    if (!boutiqueDoc.exists) throw Exception("Boutique document not found");

    return boutiqueDoc.data();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getOwnerProductsStream(
    String boutiqueId,
  ) {
    return _firestore
        .collection('boutiques')
        .doc(boutiqueId)
        .collection('products')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Future<void> addProductForCurrentOwner({
    required String title,
    required String description,
    required double price,
    double? salePrice,
    bool isOutOfStock = false,
    required String imageUrl,
    required List<String> imageUrls,
    required int stock,
    required List<String> sizes,
    required List<Map<String, dynamic>> sizeEntries,
    required List<String> category,
    required List<String> colors,
    required bool madeToOrder,
    String? deliveryTimeframe,
    // ── Size guide (feature #4) ──────────────────────────────
    String? sizeGuideUrl,
    bool postToFeed = true,
  }) async {
    final boutiqueId = await getCurrentOwnerBoutiqueId();
    if (boutiqueId == null) {
      throw Exception('No boutique found for current owner');
    }

    final boutiqueData = await getOwnerBoutiqueData(boutiqueId: boutiqueId);
    final boutiqueName = boutiqueData?['name']?.toString() ?? 'Boutique';

    await _firestore
        .collection('boutiques')
        .doc(boutiqueId)
        .collection('products')
        .add({
          'title': title,
          'description': description,
          'price': price,
          'salePrice': salePrice,
          'isOutOfStock': isOutOfStock,
          'imageUrl': imageUrl,
          'imageUrls': imageUrls,
          'stock': stock,
          'sizes': sizes,
          'sizeEntries': sizeEntries,
          'category': category,
          'colors': colors,
          'madeToOrder': madeToOrder,
          'deliveryTimeframe': madeToOrder ? deliveryTimeframe : null,
          if (sizeGuideUrl != null && sizeGuideUrl.isNotEmpty)
            'sizeGuideUrl': sizeGuideUrl,
          'boutiqueName': boutiqueName,
          'boutiqueId': boutiqueId,
          'postedToFeed': postToFeed,
          'feedPostedAt': postToFeed ? FieldValue.serverTimestamp() : null,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  static Future<DocumentReference<Map<String, dynamic>>?>
  getCurrentOwnerBoutiqueRef() async {
    final boutiqueId = await getCurrentOwnerBoutiqueId();
    if (boutiqueId == null) return null;
    return _firestore.collection('boutiques').doc(boutiqueId);
  }

  static Future<void> updateCurrentOwnerBoutique({
    required String name,
    required String description,
    String? logoPath,
    String? bannerPath,
    bool? showStockCount,
  }) async {
    final boutiqueRef = await getCurrentOwnerBoutiqueRef();
    if (boutiqueRef == null) {
      throw Exception('No boutique found for current owner');
    }

    final updateData = <String, dynamic>{
      'name': name,
      'description': description,
    };
    if (logoPath != null) updateData['logoPath'] = logoPath;
    if (bannerPath != null) updateData['bannerPath'] = bannerPath;
    if (showStockCount != null) updateData['showStockCount'] = showStockCount;

    await boutiqueRef.update(updateData);
  }

  // ── User documents ─────────────────────────────────────────────────────────

  static Future<void> createUserProfile({
    required String uid,
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
  }) async {
    await _firestore.collection('users').doc(uid).set({
      'firstName': firstName,
      'lastName': lastName,
      'fullName': '$firstName $lastName',
      'email': email,
      'phone': phone,
      'role': 'user',
      'isActive': true,
      'isOnline': false,
      'createdAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateCurrentUserLastLogin() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).set({
      'email': user.email ?? '',
      'fullName': user.displayName ?? 'User',
      'isActive': true,
      'lastLoginAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> setCurrentUserOnline() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).set({
      'email': user.email ?? '',
      'fullName': user.displayName ?? 'User',
      'isActive': true,
      'isOnline': true,
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> setCurrentUserOffline() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).set({
      'isOnline': false,
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── Admin side ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getCurrentAdminData() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final doc = await _firestore.collection('admin_users').doc(user.uid).get();
    if (!doc.exists) return null;
    return doc.data();
  }

  static Future<AdminPermissions> getCurrentUserPermissions() async {
    final data = await getCurrentAdminData();
    return AdminPermissions.fromMap(data);
  }

  static Future<bool> isCurrentUserAdmin() async {
    final permissions = await getCurrentUserPermissions();
    return permissions.isApproved;
  }

  static Future<bool> isCurrentUserSuperAdmin() async {
    final permissions = await getCurrentUserPermissions();
    return permissions.isSuperAdmin;
  }

  static Future<bool> canCurrentUserManageUsers() async {
    final permissions = await getCurrentUserPermissions();
    return permissions.canManageUsers;
  }

  static Future<bool> canCurrentUserManageBoutiques() async {
    final permissions = await getCurrentUserPermissions();
    return permissions.canManageBoutiques;
  }

  static Future<bool> canCurrentUserManageOrders() async {
    final permissions = await getCurrentUserPermissions();
    return permissions.canManageOrders;
  }

  static Future<bool> canCurrentUserManageHomepage() async {
    final permissions = await getCurrentUserPermissions();
    return permissions.canManageHomepage;
  }

  static Future<bool> canCurrentUserViewAnalytics() async {
    final permissions = await getCurrentUserPermissions();
    return permissions.canViewAnalytics;
  }

  // ── Admin dashboard reads ──────────────────────────────────────────────────
  // One-shot .get() instead of full-collection .snapshots() listeners: these
  // collections grow unbounded, and a live listener re-reads the whole set on
  // every write. Browse lists paginate; aggregation pages read once per open.

  static const int adminPageSize = 50;

  /// One page of users, ordered by document id for stable cursoring.
  static Future<QuerySnapshot<Map<String, dynamic>>> fetchUsersPage({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = adminPageSize,
  }) {
    Query<Map<String, dynamic>> q = _firestore
        .collection('users')
        .orderBy(FieldPath.documentId)
        .limit(limit);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    return q.get();
  }

  /// Total user count via an aggregate query (one cheap read, not a full scan).
  static Future<int> getUsersCount() async {
    final snap = await _firestore.collection('users').count().get();
    return snap.count ?? 0;
  }

  /// Full one-shot read of all users — for dashboards / filtered views that
  /// aggregate totals and role breakdowns across the whole collection.
  static Future<QuerySnapshot<Map<String, dynamic>>> getAllUsersOnce() {
    return _firestore.collection('users').get();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getAllBoutiquesStream() {
    return _firestore.collection('boutiques').snapshots();
  }

  /// Full one-shot read of every boutique order — for platform sales totals.
  static Future<QuerySnapshot<Map<String, dynamic>>>
  getAllBoutiqueOrdersOnce() {
    return _firestore.collectionGroup('orders').get();
  }

  // ── Notifications ──────────────────────────────────────────────────────────

  static Future<void> saveCurrentUserFcmToken() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      await _firestore.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  static Future<void> deleteCurrentUserFcmToken() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).set({
      'fcmToken': FieldValue.delete(),
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>>
  getCurrentUserNotificationsStream() {
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Future<void> markNotificationAsRead(String notificationId) async {
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'isRead': true, 'readAt': FieldValue.serverTimestamp()});
  }

  static Future<void> markAllNotificationsAsRead() async {
    final notifications = await _firestore
        .collection('users')
        .doc(_uid)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (final doc in notifications.docs) {
      batch.update(doc.reference, {
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}

/// Result of the createOrder Cloud Function. [paymentAttemptId] identifies
/// the payment_attempts doc the Payzah flow initializes against and the
/// checkout UI listens to for the verified outcome.
class CreateOrderResult {
  final String orderNumber;
  final String orderId;
  final String paymentAttemptId;

  CreateOrderResult({
    required this.orderNumber,
    required this.orderId,
    required this.paymentAttemptId,
  });
}
