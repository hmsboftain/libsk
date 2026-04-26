import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String get _uid {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception("User not logged in");
    }
    return user.uid;
  }

  // ---------- Saved Items ----------
  static CollectionReference<Map<String, dynamic>> get _savedItemsRef =>
      _firestore.collection('users').doc(_uid).collection('saved_items');

  static Future<void> saveItem({
    required String productId,
    required String boutiqueId,
    required String imageUrl,
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
    final user = _auth.currentUser;
    final uid = user?.uid ?? 'guest';
    return _firestore.collection('users').doc(uid).collection('cart_items');
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
    final user = _auth.currentUser;
    // Use uid if logged in, otherwise use a guest placeholder
    final uid = user?.uid ?? 'guest';

    final cartRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('cart_items');

    final docId = '${productId}_$size';
    final docRef = cartRef.doc(docId);
    final doc = await docRef.get();

    if (doc.exists) {
      final currentQuantity = (doc.data()?['quantity'] ?? 1) as int;
      await docRef.update({
        'quantity': currentQuantity + 1,
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
    await _cartItemsRef.doc(docId).update({
      'quantity': quantity,
    });
  }

  static Future<void> deleteCartItem(String docId) async {
    await _cartItemsRef.doc(docId).delete();
  }
  static Future<void> mergeGuestCartToUser() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final guestCartRef = _firestore
        .collection('users')
        .doc('guest')
        .collection('cart_items');

    final guestItems = await guestCartRef.get();
    if (guestItems.docs.isEmpty) return;

    final userCartRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('cart_items');

    for (final doc in guestItems.docs) {
      final data = doc.data();
      final existingDoc = await userCartRef.doc(doc.id).get();

      if (existingDoc.exists) {
        final currentQuantity = (existingDoc.data()?['quantity'] ?? 1) as int;
        final guestQuantity = (data['quantity'] ?? 1) as int;
        await userCartRef.doc(doc.id).update({
          'quantity': currentQuantity + guestQuantity,
        });
      } else {
        await userCartRef.doc(doc.id).set(data);
      }

      await guestCartRef.doc(doc.id).delete();
    }
  }

  // ---------- Orders ----------
  static CollectionReference<Map<String, dynamic>> get _ordersRef =>
      _firestore.collection('users').doc(_uid).collection('orders');

  static Future<String> generateOrderNumber() async {
    final counterRef = _firestore.collection('metadata').doc('order_counter');

    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(counterRef);

      int lastOrderNumber = 100000;

      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null && data['lastOrderNumber'] is int) {
          lastOrderNumber = data['lastOrderNumber'] as int;
        }
      }

      final newOrderNumber = lastOrderNumber + 1;

      transaction.set(
        counterRef,
        {
          'lastOrderNumber': newOrderNumber,
        },
        SetOptions(merge: true),
      );

      return newOrderNumber.toString();
    });
  }

  static Future<String> createOrder({
    required List<Map<String, dynamic>> items,
    required int itemCount,
    required double total,
    String? deliveryMethod,
    String? paymentMethod,
    String? paymentIntentId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception("User not logged in");
    }

    final orderNumber = await generateOrderNumber();

    final latestAddressSnapshot = await _savedAddressesRef
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    Map<String, dynamic>? addressData;
    if (latestAddressSnapshot.docs.isNotEmpty) {
      addressData = latestAddressSnapshot.docs.first.data();
    }

    final batch = _firestore.batch();

    final userOrderRef = _ordersRef.doc();
    final globalOrderRef =
    _firestore.collection('global_orders').doc(userOrderRef.id);

    final userOrderData = {
      'orderNumber': orderNumber,
      'date':
      "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}",
      'itemCount': itemCount,
      'total': total,
      'status': 'Placed',
      'customerUid': user.uid,
      'customerName': user.displayName ?? 'User',
      'customerEmail': user.email ?? '',
      'deliveryMethod': deliveryMethod ?? '',
      'paymentMethod': paymentMethod ?? '',
      'paymentIntentId': paymentIntentId ?? '',
      'address': addressData,
      'items': items,
      'createdAt': FieldValue.serverTimestamp(),
    };

    batch.set(userOrderRef, userOrderData);

    batch.set(globalOrderRef, {
      ...userOrderData,
      'sourceUserOrderId': userOrderRef.id,
    });

    final Map<String, List<Map<String, dynamic>>> boutiqueItemsMap = {};

    for (final item in items) {
      final boutiqueId = item['boutiqueId']?.toString();

      if (boutiqueId == null || boutiqueId.isEmpty) {
        continue;
      }

      if (!boutiqueItemsMap.containsKey(boutiqueId)) {
        boutiqueItemsMap[boutiqueId] = [];
      }

      boutiqueItemsMap[boutiqueId]!.add(item);
    }

    for (final entry in boutiqueItemsMap.entries) {
      final boutiqueId = entry.key;
      final boutiqueItems = entry.value;

      int boutiqueItemCount = 0;
      double boutiqueTotal = 0;

      for (final item in boutiqueItems) {
        final quantityValue = item['quantity'] ?? 0;
        final priceValue = item['price'] ?? 0;

        final int quantity = quantityValue is int
            ? quantityValue
            : int.tryParse(quantityValue.toString()) ?? 0;

        final double price = priceValue is num
            ? priceValue.toDouble()
            : double.tryParse(priceValue.toString()) ?? 0;

        boutiqueItemCount += quantity;
        boutiqueTotal += price * quantity;
      }

      final boutiqueOrderRef = _firestore
          .collection('boutiques')
          .doc(boutiqueId)
          .collection('orders')
          .doc();

      batch.set(boutiqueOrderRef, {
        'orderNumber': orderNumber,
        'sourceUserOrderId': userOrderRef.id,
        'date':
        "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}",
        'itemCount': boutiqueItemCount,
        'total': boutiqueTotal,
        'status': 'Placed',
        'customerUid': user.uid,
        'customerName': user.displayName ?? 'User',
        'customerEmail': user.email ?? '',
        'deliveryMethod': deliveryMethod ?? '',
        'paymentMethod': paymentMethod ?? '',
        'address': addressData,
        'items': boutiqueItems,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

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