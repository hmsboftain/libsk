import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:libsk/l10n/app_localizations.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'services/firestore_service.dart';
import 'services/currency_service.dart';
import 'core/services/performance_service.dart';
import 'pages/splash_page.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'widgets/theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  runZonedGuarded<Future<void>>(() async {
    // Wall-clock origin for the cold-start TTI baseline (finding 4.4). Must be
    // the very first thing so it spans the pre-runApp network block below.
    // Only stores a DateTime — touches no Firebase service (the Performance
    // handle is resolved lazily), so it is safe before Firebase.initializeApp().
    PerformanceService.instance.markAppStart();

    WidgetsFlutterBinding.ensureInitialized();

    // Bound the global image cache so a long feed scroll evicts old bitmaps
    // instead of growing without limit (finding 2.1). memCacheWidth caps the
    // decode size of each image; this caps how many decoded images are retained
    // in total — observed climbing 31→65→99MB and still rising before this.
    PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20; // ~100 MB

    // Firebase MUST be initialised before any Firebase service (App Check,
    // Crashlytics, Performance, Firestore, Messaging) is touched below.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // App Check — must run before any other Firebase service. Uses platform
    // attestation in release (DeviceCheck on iOS, Play Integrity on Android)
    // and the debug provider in debug builds so emulators/dev builds work.
    await FirebaseAppCheck.instance.activate(
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleDeviceCheckProvider(),
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );

    // Crashlytics — only collect crash reports in release builds.
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      !kDebugMode,
    );

    // Route Flutter framework errors to Crashlytics.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterError;

    // Route uncaught asynchronous (platform) errors to Crashlytics.
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    await FirestoreService.prepareGuestCartId();

    // Load the saved/detected country from local prefs only (no network) so the
    // first frame renders the right currency. Live FX rates fetch in the
    // background after runApp — finding 4.4. Fallback rates are active until
    // they arrive, and CurrencyService is a ChangeNotifier so prices refresh.
    await CurrencyService.instance.loadSavedCountry();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Begin the release-surviving cold_start_tti trace (stopped at the feed's
    // first painted frame in HomePage).
    await PerformanceService.instance.startColdStartTrace();

    runApp(const LibskApp());

    // Deferred off the cold-start critical path (finding 4.4): the FX HTTP
    // round-trip and Stripe.applySettings no longer block the first feed frame.
    // Neither is needed to render the feed; Stripe is only required at checkout.
    unawaited(CurrencyService.instance.fetchRates());
    unawaited(_initStripe());

    Future.delayed(const Duration(seconds: 2), () async {
      try {
        await NotificationService.instance.initialize();
      } catch (e) {
        debugPrint('Notification initialization failed: $e');
      }
    });
  }, (error, stack) {
    // If an error is thrown before Firebase.initializeApp() completes, touching
    // FirebaseCrashlytics.instance here would itself throw [core/no-app] and
    // mask the real cause — so only report to Crashlytics once Firebase is up.
    if (Firebase.apps.isNotEmpty) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } else {
      debugPrint('Startup error before Firebase init: $error\n$stack');
    }
  });
}

/// Stripe init, deferred off the cold-start path (finding 4.4). Only needed at
/// checkout, so it must not block the first feed frame.
Future<void> _initStripe() async {
  Stripe.publishableKey =
      'pk_test_51TOOjvCTdAUQnhiZ4ArRKUYtg2TIuKEc3j0LeMDk036JhqGoPlsVV6ZdO4resgC8XJg5C8fZBhkhMROon5Go9Flf00SX2GiCmu';
  await Stripe.instance.applySettings();
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
