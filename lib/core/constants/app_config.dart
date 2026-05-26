/// Runtime configuration sourced from build-time `--dart-define` flags.
///
/// Secrets live here so they never end up in version control as string
/// literals. Pass values when building / running the app, e.g.:
///
///   flutter run --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_xxx
///   flutter build ipa --dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_xxx
///
/// Missing defines resolve to the empty string at compile time; callers that
/// rely on a value must validate it before use.
class AppConfig {
  const AppConfig._();

  static const String stripePublishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
  );
}
