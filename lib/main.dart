import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:libsk/l10n/app_localizations.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'services/firestore_service.dart';
import 'services/currency_service.dart';
import 'pages/splash_page.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'widgets/theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  await FirestoreService.prepareGuestCartId();

  // Initialise currency service — loads saved country and fetches live rates
  await CurrencyService.instance.init();

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

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
  bool _isDeviceCompromised = false;

  @override
  void initState() {
    super.initState();
    _checkDeviceSecurity();
    // Rebuild UI if currency/country changes while app is running
    CurrencyService.instance.addListener(_onCurrencyChanged);
  }

  @override
  void dispose() {
    CurrencyService.instance.removeListener(_onCurrencyChanged);
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (mounted) setState(() {});
  }

  void changeLanguage(Locale locale) {
    setState(() => _locale = locale);
  }

  Future<void> _checkDeviceSecurity() async {
    try {
      final jailbroken = await FlutterJailbreakDetection.jailbroken;
      if (jailbroken && mounted) {
        setState(() => _isDeviceCompromised = true);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.light,
      locale: _locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      title: 'LIBSK',
      home: _isDeviceCompromised
          ? _SecurityWarningPage(
              onContinue: () => setState(() => _isDeviceCompromised = false),
            )
          : StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  FirestoreService.saveCurrentUserFcmToken();
                }
                return SplashPage(onLanguageChange: changeLanguage);
              },
            ),
    );
  }
}

class _SecurityWarningPage extends StatelessWidget {
  final VoidCallback onContinue;

  const _SecurityWarningPage({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 60),
              Image.asset(
                'assets/libsk_logo.png',
                height: 56,
                fit: BoxFit.contain,
              ),
              const Spacer(),
              Text(
                'Security Warning',
                style: AppTextStyles.headingLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'This device appears to be modified. For your security, '
                'payments and sensitive features are unavailable.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.secondaryText,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.deepAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  child: const Text('Continue', style: AppTextStyles.button),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
