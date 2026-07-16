/// Runtime configuration sourced from build-time `--dart-define` flags.
///
/// Secrets live here so they never end up in version control as string
/// literals. Pass values when building / running the app, e.g.:
///
///   flutter run --dart-define=SOME_KEY=value
///
/// Missing defines resolve to the empty string at compile time; callers that
/// rely on a value must validate it before use.
///
/// Payment note: the Payzah private key is a Cloud Functions secret and the
/// checkout cutover is controlled server-side by the PAYZAH_DIRECT_ENABLED
/// Cloud Functions param — neither belongs in the client, so there is no
/// payment configuration here.
class AppConfig {
  const AppConfig._();
}
