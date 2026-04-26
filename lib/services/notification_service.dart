import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../firebase_options.dart';
import 'firestore_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  print('Background message received: ${message.messageId}');
  print('Background title: ${message.notification?.title}');
  print('Background body: ${message.notification?.body}');
  print('Background data: ${message.data}');
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> initialize() async {
    // iOS foreground presentation
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Ask user for permission
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    print('Notification permission status: ${settings.authorizationStatus}');

    // Get device token
    final String? token = await _messaging.getToken();
    print('FCM token: $token');

    // Token refresh listener
    _messaging.onTokenRefresh.listen((newToken) async {
      print('FCM token refreshed: $newToken');
      await FirestoreService.saveCurrentUserFcmToken();
    });

    // Foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Foreground message received: ${message.messageId}');
      print('Foreground title: ${message.notification?.title}');
      print('Foreground body: ${message.notification?.body}');
      print('Foreground data: ${message.data}');
    });

    // App opened by tapping notification from background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification tap opened app from background');
      print('Tap data: ${message.data}');
    });

    // App opened by tapping notification from terminated state
    final RemoteMessage? initialMessage =
    await _messaging.getInitialMessage();

    if (initialMessage != null) {
      print('Notification tap opened app from terminated state');
      print('Initial data: ${initialMessage.data}');
    }
  }
}