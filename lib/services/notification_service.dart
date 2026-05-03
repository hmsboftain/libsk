import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
        print('FCM Token: $token');

        await FirestoreService.saveCurrentUserFcmToken();
      } catch (e) {
        print('FCM token error: $e');
      }

      // Token refresh listener
      _messaging.onTokenRefresh.listen((newToken) async {
        try {
          await FirestoreService.saveCurrentUserFcmToken();
        } catch (e) {
          print('FCM refresh save error: $e');
        }
      });

      // Foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        // Handle foreground message if needed
      });

      // App opened by tapping notification from background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        // Handle notification tap if needed
      });

      // App opened by tapping notification from terminated state
      final RemoteMessage? initialMessage =
          await _messaging.getInitialMessage();

      if (initialMessage != null) {
        // Handle initial message if needed
      }
    } catch (e) {
      print('Notification service error: $e');
    }
  }
}
