import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String? _guestCartId;

  static String get _uid {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception("User not logged in");
    }
    return user.uid;
  }

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

    if (user != null) {
      return user.uid;
    }

    if (_guestCartId == null) {
      throw Exception('Guest cart ID has not been prepared');
    }

    return _guestCartId!;
  }

  // ---------- Saved Items ----------

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

  // ---------- Saved Boutiques ----------

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

  static Future<bool> isBoutiqueSaved(String boutiqueId) async {
    final doc = await _savedBoutiquesRef.doc(boutiqueId).get();
    return doc.exists;
  }

  // ---------- Saved Addresses ----------

  static CollectionReference<Map<String, dynamic>> get _savedAddressesRef =>
      _firestore.collection('users').doc(_uid).collection('saved_addresses');

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

  static Future<void> deleteAddress(String addressId) async {
    await _savedAddressesRef.doc(addressId).delete();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getSavedAddressesStream() {
    return _savedAddressesRef
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ---------- Cart ----------

  static CollectionReference<Map<String, dynamic>> get _cartItemsRef {
    return _firestore
        .collection('users')
        .doc(_cartOwnerId)
        .collection('cart_items');
  }

  static Future<void> addToCart({
    required String productId,
    required String boutiqueId,
    required String imageUrl,
    required String title,
    required String description,
    required String size,
    required double price,
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

    final cartRef = _firestore
        .collection('users')
        .doc(_cartOwnerId)
        .collection('cart_items');

    final docId = '${productId}_$size';
    final docRef = cartRef.doc(docId);
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
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await docRef.set({
        'productId': productId,
        'boutiqueId': boutiqueId,
        'imageUrl': imageUrl,
        'title': title,
        'description': description,
        'size': size,
        'price': price,
        'quantity': 1,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getCartItemsStream() {
    return _cartItemsRef.orderBy('createdAt', descending: true).snapshots();
  }

  static Future<void> updateCartItemQuantity({
    required String docId,
    required int quantity,
  }) async {
    if (quantity <= 0) {
      await _cartItemsRef.doc(docId).delete();
      return;
    }

    final cartItemDoc = await _cartItemsRef.doc(docId).get();

    if (!cartItemDoc.exists) {
      throw Exception('Cart item not found');
    }

    final cartItemData = cartItemDoc.data();

    final productId = cartItemData?['productId']?.toString() ?? '';
    final boutiqueId = cartItemData?['boutiqueId']?.toString() ?? '';
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

    await _cartItemsRef.doc(docId).update({
      'quantity': quantity,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteCartItem(String docId) async {
    await _cartItemsRef.doc(docId).delete();
  }

  static Future<void> mergeGuestCartToUser() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await prepareGuestCartId();

    final guestId = _guestCartId;
    if (guestId == null || guestId.isEmpty) return;

    final guestCartRef = _firestore
        .collection('users')
        .doc(guestId)
        .collection('cart_items');

    final guestItems = await guestCartRef.get();
    if (guestItems.docs.isEmpty) return;

    final userCartRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('cart_items');

    for (final doc in guestItems.docs) {
      final data = doc.data();

      final productId = data['productId']?.toString() ?? '';
      final boutiqueId = data['boutiqueId']?.toString() ?? '';

      if (productId.isEmpty || boutiqueId.isEmpty) {
        await guestCartRef.doc(doc.id).delete();
        continue;
      }

      final productDoc = await _firestore
          .collection('boutiques')
          .doc(boutiqueId)
          .collection('products')
          .doc(productId)
          .get();

      if (!productDoc.exists) {
        await guestCartRef.doc(doc.id).delete();
        continue;
      }

      final stockValue = productDoc.data()?['stock'] ?? 0;
      final int currentStock = stockValue is int
          ? stockValue
          : int.tryParse(stockValue.toString()) ?? 0;

      if (currentStock <= 0) {
        await guestCartRef.doc(doc.id).delete();
        continue;
      }

      final existingDoc = await userCartRef.doc(doc.id).get();

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

        await userCartRef.doc(doc.id).update({
          'quantity': safeQuantity,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final safeQuantity =
        guestQuantity > currentStock ? currentStock : guestQuantity;

        await userCartRef.doc(doc.id).set({
          ...data,
          'quantity': safeQuantity,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await guestCartRef.doc(doc.id).delete();
    }
  }

  // ---------- Orders ----------

  static CollectionReference<Map<String, dynamic>> get _ordersRef =>
      _firestore.collection('users').doc(_uid).collection('orders');

  static Future<String> createOrder({
    required List<Map<String, dynamic>> items,
    required int itemCount,
    required double total,
    String? deliveryMethod,
    String? paymentMethod,
    String? paymentIntentId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable  = functions.httpsCallable('createOrder');

    final result = await callable.call({
      'items':           items,
      'deliveryMethod':  deliveryMethod  ?? '',
      'paymentMethod':   paymentMethod   ?? '',
      'paymentIntentId': paymentIntentId ?? '',
    });

    final data        = Map<String, dynamic>.from(result.data as Map);
    final orderNumber = data['orderNumber']?.toString();

    if (orderNumber == null || orderNumber.isEmpty) {
      throw Exception('Order number missing from server response');
    }

    return orderNumber;
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

  static Stream<QuerySnapshot<Map<String, dynamic>>> getGlobalOrdersStream() {
    return _firestore
        .collection('global_orders')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ================= OWNER SIDE =================

  static Future<bool> isCurrentUserOwner() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final doc =
    await _firestore.collection('boutique_owners').doc(user.uid).get();

    return doc.exists;
  }

  static Future<bool> isCurrentUserApprovedOwner() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final doc =
    await _firestore.collection('boutique_owners').doc(user.uid).get();

    if (!doc.exists) return false;

    final data = doc.data();
    if (data == null) return false;

    return data['role'] == 'boutique_owner' && data['isApproved'] == true;
  }

  static Future<Map<String, dynamic>?> getCurrentOwnerData() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final doc =
    await _firestore.collection('boutique_owners').doc(user.uid).get();

    if (!doc.exists) return null;

    return doc.data();
  }

  static Future<String?> getCurrentOwnerBoutiqueId() async {
    final ownerData = await getCurrentOwnerData();
    if (ownerData == null) return null;

    return ownerData['boutiqueId'] as String?;
  }

  static Future<Map<String, dynamic>?> getOwnerBoutiqueData() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception("User not logged in");
    }

    final ownerDoc =
    await _firestore.collection('boutique_owners').doc(user.uid).get();

    if (!ownerDoc.exists) {
      throw Exception("Owner document not found");
    }

    final ownerData = ownerDoc.data();

    if (ownerData == null) {
      throw Exception("Owner data is null");
    }

    final boutiqueId = ownerData['boutiqueId'];

    if (boutiqueId == null || boutiqueId.toString().isEmpty) {
      throw Exception("No boutiqueId assigned to this owner");
    }

    final boutiqueDoc =
    await _firestore.collection('boutiques').doc(boutiqueId).get();

    if (!boutiqueDoc.exists) {
      throw Exception("Boutique document not found");
    }

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

  static Future<Stream<QuerySnapshot<Map<String, dynamic>>>?>
  getCurrentOwnerProductsStream() async {
    final boutiqueId = await getCurrentOwnerBoutiqueId();
    if (boutiqueId == null) return null;

    return getOwnerProductsStream(boutiqueId);
  }

  static Future<void> addProductForCurrentOwner({
    required String title,
    required String description,
    required double price,
    required String imageUrl,
    required List<String> imageUrls,
    required int stock,
    required List<String> sizes,
  }) async {
    final boutiqueId = await getCurrentOwnerBoutiqueId();

    if (boutiqueId == null) {
      throw Exception('No boutique found for current owner');
    }

    final boutiqueData = await getOwnerBoutiqueData();
    final boutiqueName = boutiqueData?['name']?.toString() ?? 'Boutique';

    await _firestore
        .collection('boutiques')
        .doc(boutiqueId)
        .collection('products')
        .add({
      'title': title,
      'description': description,
      'price': price,
      'imageUrl': imageUrl,
      'imageUrls': imageUrls,
      'stock': stock,
      'sizes': sizes,
      'boutiqueName': boutiqueName,
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
  }) async {
    final boutiqueRef = await getCurrentOwnerBoutiqueRef();

    if (boutiqueRef == null) {
      throw Exception('No boutique found for current owner');
    }

    final updateData = <String, dynamic>{
      'name': name,
      'description': description,
    };

    if (logoPath != null) {
      updateData['logoPath'] = logoPath;
    }

    if (bannerPath != null) {
      updateData['bannerPath'] = bannerPath;
    }

    await boutiqueRef.update(updateData);
  }

  // ================= USER DOCUMENTS =================

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

  // ================= ADMIN SIDE =================

  static Future<Map<String, dynamic>?> getCurrentAdminData() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final doc = await _firestore.collection('admin_users').doc(user.uid).get();

    if (!doc.exists) return null;
    return doc.data();
  }

  static Future<bool> isCurrentUserAdmin() async {
    final adminData = await getCurrentAdminData();
    if (adminData == null) return false;

    return adminData['isApproved'] == true;
  }

  static Future<bool> isCurrentUserSuperAdmin() async {
    final adminData = await getCurrentAdminData();
    if (adminData == null) return false;

    return adminData['isApproved'] == true &&
        adminData['role'] == 'super_admin';
  }

  static Future<bool> canCurrentUserManageUsers() async {
    final adminData = await getCurrentAdminData();
    if (adminData == null) return false;

    return adminData['isApproved'] == true &&
        adminData['canManageUsers'] == true;
  }

  static Future<bool> canCurrentUserManageBoutiques() async {
    final adminData = await getCurrentAdminData();
    if (adminData == null) return false;

    return adminData['isApproved'] == true &&
        adminData['canManageBoutiques'] == true;
  }

  static Future<bool> canCurrentUserManageOrders() async {
    final adminData = await getCurrentAdminData();
    if (adminData == null) return false;

    return adminData['isApproved'] == true &&
        adminData['canManageOrders'] == true;
  }

  static Future<bool> canCurrentUserManageHomepage() async {
    final adminData = await getCurrentAdminData();
    if (adminData == null) return false;

    return adminData['isApproved'] == true &&
        adminData['canManageHomepage'] == true;
  }

  static Future<bool> canCurrentUserViewAnalytics() async {
    final adminData = await getCurrentAdminData();
    if (adminData == null) return false;

    return adminData['isApproved'] == true &&
        adminData['canViewAnalytics'] == true;
  }

  // ================= ADMIN DASHBOARD STREAMS =================

  static Stream<QuerySnapshot<Map<String, dynamic>>> getAllUsersStream() {
    return _firestore.collection('users').snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getAllBoutiquesStream() {
    return _firestore.collection('boutiques').snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>>
  getAllBoutiqueOwnersStream() {
    return _firestore.collection('boutique_owners').snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getAllAdminsStream() {
    return _firestore.collection('admin_users').snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>>
  getAllBoutiqueOrdersStream() {
    return _firestore.collectionGroup('orders').snapshots();
  }

  // ================= NOTIFICATIONS =================

  static Future<void> saveCurrentUserFcmToken() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final token = await FirebaseMessaging.instance.getToken();

    if (token == null || token.isEmpty) return;

    await _firestore.collection('users').doc(user.uid).set({
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
        .update({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    });
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

  static Future<void> createManualNotificationRequest({
    required String title,
    required String body,
    required String targetType,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not logged in');
    }

    final isAdmin = await isCurrentUserAdmin();
    final isSuperAdmin = await isCurrentUserSuperAdmin();

    if (!isAdmin && !isSuperAdmin) {
      throw Exception('Only admins can send notifications');
    }

    await _firestore.collection('manual_notifications').add({
      'title': title,
      'body': body,
      'targetType': targetType,
      'createdByUid': user.uid,
      'createdByEmail': user.email ?? '',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>>
  getManualNotificationsStream() {
    return _firestore
        .collection('manual_notifications')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}