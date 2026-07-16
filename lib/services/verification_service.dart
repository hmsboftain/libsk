import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Accounts created before this instant predate mandatory verification and are
/// never challenged — see requirement: existing users are not retroactively
/// subject to it.
///
/// This is the moment verification went live in production (the Cloud Functions
/// deploy on 16 Jul 2026). It is a fixed point in the past and must never be
/// moved forward: doing so would re-grandfather accounts that were created
/// under the requirement and have already been gated by it.
final DateTime kVerificationCutoff = DateTime.utc(2026, 7, 16, 15, 30);

/// What a signed-in account still owes before it can use the app.
class VerificationStatus {
  final bool needsEmail;
  final bool needsPhone;

  const VerificationStatus({required this.needsEmail, required this.needsPhone});

  const VerificationStatus.clear() : needsEmail = false, needsPhone = false;

  bool get isVerified => !needsEmail && !needsPhone;
}

/// Mandatory signup verification.
///
/// Firebase Auth's own `emailVerified` is the source of truth, not a Firestore
/// field:
///   - Google/Apple sign-ins arrive with it already true, so social signups
///     never see the OTP screen.
///   - The verifyEmailOtp Cloud Function flips it for password signups.
///   - The backfill stamped it true on every pre-existing account, so
///     grandfathered users pass without a Firestore read.
///
/// That last point is why the email gate reads Auth alone: a Firestore hiccup
/// can't lock the existing user base out of the app.
class VerificationService {
  static final _auth = FirebaseAuth.instance;
  static final _firestore = FirebaseFirestore.instance;
  static final _functions = FirebaseFunctions.instance;

  /// Cached so the gate doesn't re-read config on every auth state change.
  static bool? _phoneEnforcementCache;

  /// Phone verification is built but not enforced: Firebase Phone Auth on iOS
  /// needs an APNs key uploaded to Firebase Auth, which needs Apple Developer
  /// enrollment (still pending). Flip `metadata/verification_config`
  /// `.enforcePhoneVerification` to true once that lands and this gate starts
  /// applying to every account created since the feature shipped — interim
  /// social signups included, since they were never marked exempt.
  static Future<bool> isPhoneEnforcementEnabled() async {
    if (_phoneEnforcementCache != null) return _phoneEnforcementCache!;
    try {
      final doc = await _firestore
          .collection('metadata')
          .doc('verification_config')
          .get();
      _phoneEnforcementCache = doc.data()?['enforcePhoneVerification'] == true;
    } catch (_) {
      // Config unreachable — don't enforce. Failing open on phone is the right
      // trade here: the email gate is unaffected (it reads Auth), and locking
      // every customer out over a config read is worse than briefly not
      // enforcing a check that isn't switched on yet anyway.
      _phoneEnforcementCache = false;
    }
    return _phoneEnforcementCache!;
  }

  static void clearCache() => _phoneEnforcementCache = null;

  /// What the signed-in user still owes. Signed-out callers get a clear status —
  /// there's nothing to gate until someone is actually authenticated.
  static Future<VerificationStatus> checkCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return const VerificationStatus.clear();

    // emailVerified is cached in the local token; the Cloud Function flipped it
    // server-side, so reload before trusting it or a just-verified user bounces
    // straight back to the OTP screen.
    try {
      await user.reload();
    } on FirebaseAuthException catch (e) {
      // The account was deleted (cleanup job) or disabled while signed in.
      if (e.code == 'user-not-found' || e.code == 'user-disabled') {
        await _auth.signOut();
        return const VerificationStatus.clear();
      }
      // Offline: fall through and judge on the cached token rather than
      // stranding the user on a spinner.
    }

    final fresh = _auth.currentUser;
    if (fresh == null) return const VerificationStatus.clear();

    final createdAt = fresh.metadata.creationTime;
    final emailVerified = fresh.emailVerified;

    // Grandfathered accounts are resolved without touching Firestore, so an
    // existing user can never be locked out by a failed read.
    if (isGrandfathered(createdAt: createdAt)) {
      return const VerificationStatus.clear();
    }

    if (!await isPhoneEnforcementEnabled()) {
      return resolveStatus(
        createdAt: createdAt,
        emailVerified: emailVerified,
        phoneEnforced: false,
      );
    }

    // Phone is the one check that needs Firestore, because there's no Auth-side
    // equivalent of "this number was verified for this account" until the number
    // is actually linked.
    try {
      final doc = await _firestore.collection('users').doc(fresh.uid).get();
      final data = doc.data();
      return resolveStatus(
        createdAt: createdAt,
        emailVerified: emailVerified,
        phoneEnforced: true,
        exempt: data?['verificationExempt'] == true,
        phoneVerified: data?['phoneVerified'] == true,
      );
    } catch (_) {
      return resolveStatus(
        createdAt: createdAt,
        emailVerified: emailVerified,
        phoneEnforced: false,
      );
    }
  }

  /// Whether an account predates mandatory verification.
  ///
  /// Auth's creationTime is set by Firebase, is immutable, is carried in the
  /// token, and exists for every account — so this holds even when the profile
  /// doc is missing or its verificationExempt flag was never backfilled. It is
  /// the primary grandfather signal precisely because it depends on nothing
  /// having gone right beforehand; verificationExempt is the queryable record
  /// of the same decision, not the mechanism.
  static bool isGrandfathered({required DateTime? createdAt}) {
    if (createdAt == null) return false;
    return createdAt.isBefore(kVerificationCutoff);
  }

  /// The gate's decision table, pure so it can be tested without Firebase.
  ///
  /// Extracted after a live regression: the exempt check previously sat inside
  /// the phone-enforcement branch, so with phone enforcement off it never ran
  /// and every grandfathered account was prompted for a code it could not
  /// receive. Nothing here may read ambient state — that's what let the bug
  /// hide.
  static VerificationStatus resolveStatus({
    required DateTime? createdAt,
    required bool emailVerified,
    required bool phoneEnforced,
    bool exempt = false,
    bool phoneVerified = false,
  }) {
    // Grandfathering wins over everything, by either signal.
    if (exempt || isGrandfathered(createdAt: createdAt)) {
      return const VerificationStatus.clear();
    }
    return VerificationStatus(
      needsEmail: !emailVerified,
      needsPhone: phoneEnforced && !phoneVerified,
    );
  }

  /// Sends a 6-digit code to the signed-in user's email address.
  /// Returns the seconds to wait when the server rejects an early resend.
  static Future<OtpSendResult> sendEmailOtp({required String locale}) async {
    try {
      final result = await _functions
          .httpsCallable('sendEmailOtp')
          .call({'locale': locale});
      final data = Map<String, dynamic>.from(result.data as Map);
      return OtpSendResult(
        sent: data['sent'] == true,
        alreadyVerified: data['alreadyVerified'] == true,
      );
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final retryAfter = details is Map ? details['retryAfterSeconds'] : null;
      throw OtpException(
        code: e.code,
        message: e.message ?? 'Could not send the code.',
        retryAfterSeconds: retryAfter is int ? retryAfter : null,
      );
    }
  }

  /// Verifies the code. On success the Cloud Function flips Auth's
  /// emailVerified, so the local token is refreshed before returning.
  static Future<void> verifyEmailOtp(String code) async {
    try {
      await _functions.httpsCallable('verifyEmailOtp').call({'code': code});
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final remaining = details is Map ? details['remaining'] : null;
      throw OtpException(
        code: e.code,
        message: e.message ?? 'Could not verify the code.',
        remainingAttempts: remaining is int ? remaining : null,
      );
    }
    // Without this the client still holds a token saying emailVerified: false.
    await _auth.currentUser?.reload();
    await _auth.currentUser?.getIdToken(true);
  }
}

class OtpSendResult {
  final bool sent;
  final bool alreadyVerified;
  const OtpSendResult({required this.sent, required this.alreadyVerified});
}

class OtpException implements Exception {
  final String code;
  final String message;
  final int? retryAfterSeconds;
  final int? remainingAttempts;

  const OtpException({
    required this.code,
    required this.message,
    this.retryAfterSeconds,
    this.remainingAttempts,
  });

  @override
  String toString() => 'OtpException($code): $message';
}
