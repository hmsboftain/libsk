import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Records a sign-in failure to Crashlytics + the debug log (so the REAL cause
/// is never swallowed by a generic "something went wrong"), and returns a
/// user-facing message that prefers the provider's real message over [fallback].
///
/// [context] is a short tag ("google_sign_in", "apple_sign_in", …) used as the
/// Crashlytics reason so failures are grep-able in the dashboard.
///
/// Common real causes this now surfaces instead of hiding:
///   • Google `PlatformException(sign_in_failed, ..., 10, ...)` (DEVELOPER_ERROR)
///     — the Android app's SHA-1/SHA-256 fingerprint for the current signing
///     config is not registered in Firebase (no client_type:1 OAuth client in
///     google-services.json).
///   • Apple authorization errors — the "Sign In with Apple" capability/App ID
///     is not configured, or the provider is disabled in Firebase Auth.
String reportSignInError(
  Object error,
  StackTrace stack,
  String context,
  String fallback,
) {
  debugPrint('[$context] sign-in failed: $error');
  FirebaseCrashlytics.instance.recordError(error, stack, reason: context);
  if (error is FirebaseAuthException) {
    return error.message ?? fallback;
  }
  if (error is PlatformException) {
    final msg = error.message;
    return (msg != null && msg.isNotEmpty) ? msg : fallback;
  }
  return fallback;
}
