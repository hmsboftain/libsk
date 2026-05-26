import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../firebase_options.dart';
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

      // Foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        // Handle foreground message
      });

      // App opened by tapping notification from background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        // Handle notification tap
      });

      // App opened by tapping notification from terminated state
      final RemoteMessage? initialMessage =
          await _messaging.getInitialMessage();

      if (initialMessage != null) {
        // Handle initial message
      }
    } catch (e) {
      debugPrint('Notification service error: $e');
    }
  }
}
