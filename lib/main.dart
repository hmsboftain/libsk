import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:libsk/l10n/app_localizations.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/firestore_service.dart';
import 'navigation/main_navigation_bar.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await FirestoreService.prepareGuestCartId();

  FirebaseMessaging.onBackgroundMessage(
    firebaseMessagingBackgroundHandler,
  );

  Stripe.publishableKey =
  'pk_test_51TOOjvCTdAUQnhiZ4ArRKUYtg2TIuKEc3j0LeMDk036JhqGoPlsVV6ZdO4resgC8XJg5C8fZBhkhMROon5Go9Flf00SX2GiCmu';
  await Stripe.instance.applySettings();

runApp(const LibskApp());

Future.delayed(const Duration(seconds: 2), () async {
  try {
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint('Notification initialization failed: $e');
  }
});
}

class LibskApp extends StatefulWidget {
  const LibskApp({super.key});

  static void setLocale(BuildContext context, Locale newLocale) {
    final state = context.findAncestorStateOfType<_LibskAppState>();
    state?.changeLanguage(newLocale);
  }

  @override
  State<LibskApp> createState() => _LibskAppState();
}

class _LibskAppState extends State<LibskApp> {
  Locale _locale = const Locale('en');

  void changeLanguage(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: const [
        Locale('en'),
        Locale('ar'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      title: 'LIBSK',
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            FirestoreService.saveCurrentUserFcmToken();
          }

          return PermissionGatePage(onLanguageChange: changeLanguage);
        },
      ),
    );
  }
}

class PermissionGatePage extends StatefulWidget {
  final Function(Locale) onLanguageChange;

  const PermissionGatePage({
    super.key,
    required this.onLanguageChange,
  });

  @override
  State<PermissionGatePage> createState() => _PermissionGatePageState();
}

class _PermissionGatePageState extends State<PermissionGatePage> {
  bool _permissionsHandled = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.photos.request();
    await Permission.location.request();

    if (!mounted) return;

    setState(() {
      _permissionsHandled = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionsHandled) {
      return const Scaffold(
        backgroundColor: Color(0xFFFFFDF8),
        body: Center(
          child: CircularProgressIndicator(color: Colors.black),
        ),
      );
    }

    return MainNavigationPage(
      onLanguageChange: widget.onLanguageChange,
    );
  }
}
