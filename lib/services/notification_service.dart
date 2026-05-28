import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../firebase_options.dart';
import '../main.dart' show navigatorKey;
import '../pages/disputes_page.dart';
import '../pages/order_details_page.dart';
import '../pages/owner_dashboard_page.dart';
import '../widgets/order_item.dart';
import '../widgets/theme.dart';
import 'firestore_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> initialize() async {
    try {
      // Delay to prevent iOS crash on startup
      await Future.delayed(const Duration(seconds: 2));

      // Ask user for permission
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      // iOS foreground presentation
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Save device token to Firestore
      try {
        final token = await _messaging.getToken();
        debugPrint('FCM Token: $token');

        await FirestoreService.saveCurrentUserFcmToken();
      } catch (e) {
        debugPrint('FCM token error: $e');
      }

      // Token refresh listener
      _messaging.onTokenRefresh.listen((newToken) async {
        try {
          await FirestoreService.saveCurrentUserFcmToken();
        } catch (e) {
          debugPrint('FCM refresh save error: $e');
        }
      });

      // Foreground messages — show a branded in-app snackbar; do not navigate.
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _showForegroundSnackBar(message);
      });

      // App opened by tapping notification from background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleNotificationTap(message.data);
      });

      // App opened by tapping notification from terminated state
      final RemoteMessage? initialMessage =
          await _messaging.getInitialMessage();

      if (initialMessage != null) {
        _handleNotificationTap(initialMessage.data);
      }
    } catch (e) {
      debugPrint('Notification service error: $e');
    }
  }

  // ── Foreground in-app banner ────────────────────────────────────────────
  void _showForegroundSnackBar(RemoteMessage message) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    if (title.isEmpty && body.isEmpty) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.showSnackBar(
      SnackBar(
        backgroundColor: AppColors.primaryText,
        duration: const Duration(seconds: 4),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(
                title,
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.background,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (title.isNotEmpty && body.isNotEmpty)
              const SizedBox(height: 2),
            if (body.isNotEmpty)
              Text(
                body,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.background),
              ),
          ],
        ),
      ),
    );
  }

  // ── Tap routing ─────────────────────────────────────────────────────────
  //
  // Routes the user to the most relevant page based on the `type` field that
  // every server-sent notification now includes. Missing/unknown types are
  // silently ignored so we just land on the current screen.
  Future<void> _handleNotificationTap(Map<String, dynamic> data) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final type = data['type']?.toString() ?? '';
    switch (type) {
      case 'order_status':
        final orderId = data['orderId']?.toString() ?? '';
        if (orderId.isEmpty) return;
        await _pushOrderDetails(navigator, orderId);
        break;
      case 'dispute_status':
        navigator.push(
          MaterialPageRoute(builder: (_) => const DisputesPage()),
        );
        break;
      case 'low_stock':
        navigator.push(
          MaterialPageRoute(builder: (_) => const OwnerDashboardPage()),
        );
        break;
      case 'manual':
      default:
        // No-op — just opening the app is enough.
        break;
    }
  }

  // OrderDetailsPage requires an OrderItem, so fetch the doc for the signed-in
  // user and build it. If the user is signed out or the doc is gone, bail out
  // quietly rather than crash.
  Future<void> _pushOrderDetails(
    NavigatorState navigator,
    String orderId,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('orders')
          .doc(orderId)
          .get();
      if (!doc.exists) return;
      final order = OrderItem.fromFirestore(doc.id, doc.data() ?? {});
      navigator.push(
        MaterialPageRoute(builder: (_) => OrderDetailsPage(order: order)),
      );
    } catch (e) {
      debugPrint('Notification tap: failed to load order $orderId: $e');
    }
  }
}
