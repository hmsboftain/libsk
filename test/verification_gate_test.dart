import 'package:flutter_test/flutter_test.dart';
import 'package:libsk/services/verification_service.dart';

/// Decision-table tests for the signup gate.
///
/// These exist because of a live regression: the exempt check sat inside the
/// phone-enforcement branch, so with phone enforcement off (its shipping state)
/// it never ran, and every pre-existing account was prompted for an OTP it
/// could not receive. The gate had no test, so nothing caught it until a human
/// tried to log in.
void main() {
  final beforeCutoff = kVerificationCutoff.subtract(const Duration(days: 30));
  final afterCutoff = kVerificationCutoff.add(const Duration(minutes: 1));

  group('grandfathering', () {
    test('account created before the cutoff is never gated', () {
      final s = VerificationService.resolveStatus(
        createdAt: beforeCutoff,
        emailVerified: false, // the exact state of the 32 existing accounts
        phoneEnforced: false,
      );
      expect(s.isVerified, isTrue);
      expect(s.needsEmail, isFalse);
    });

    test('grandfathering survives phone enforcement being switched on', () {
      // The regression in miniature: this branch is where exempt used to live,
      // and the other branch is where it was actually needed.
      final s = VerificationService.resolveStatus(
        createdAt: beforeCutoff,
        emailVerified: false,
        phoneEnforced: true,
        phoneVerified: false,
      );
      expect(s.isVerified, isTrue, reason: 'existing users owe nothing, ever');
    });

    test('verificationExempt alone grandfathers, even without a creation time', () {
      final s = VerificationService.resolveStatus(
        createdAt: null,
        emailVerified: false,
        phoneEnforced: true,
        exempt: true,
      );
      expect(s.isVerified, isTrue);
    });

    test('creationTime alone grandfathers, even when the exempt flag never landed', () {
      // Precisely the production state: backfill never ran, so exempt is false.
      final s = VerificationService.resolveStatus(
        createdAt: beforeCutoff,
        emailVerified: false,
        phoneEnforced: false,
        exempt: false,
      );
      expect(s.isVerified, isTrue,
          reason: 'the two signals are independent; either one is sufficient');
    });

    test('account created after the cutoff is NOT grandfathered', () {
      final s = VerificationService.resolveStatus(
        createdAt: afterCutoff,
        emailVerified: false,
        phoneEnforced: false,
      );
      expect(s.needsEmail, isTrue, reason: 'new signups must verify');
    });

    test('an account created exactly at the cutoff must verify', () {
      // isBefore is exclusive; the cutoff instant belongs to the new regime.
      final s = VerificationService.resolveStatus(
        createdAt: kVerificationCutoff,
        emailVerified: false,
        phoneEnforced: false,
      );
      expect(s.needsEmail, isTrue);
    });

    test('a null creation time does not grandfather by accident', () {
      final s = VerificationService.resolveStatus(
        createdAt: null,
        emailVerified: false,
        phoneEnforced: false,
      );
      expect(s.needsEmail, isTrue, reason: 'absence of evidence is not exemption');
    });

    test('isGrandfathered is a pure boundary check', () {
      expect(VerificationService.isGrandfathered(createdAt: beforeCutoff), isTrue);
      expect(VerificationService.isGrandfathered(createdAt: afterCutoff), isFalse);
      expect(VerificationService.isGrandfathered(createdAt: kVerificationCutoff), isFalse);
      expect(VerificationService.isGrandfathered(createdAt: null), isFalse);
    });
  });

  group('new accounts', () {
    test('unverified email is gated', () {
      final s = VerificationService.resolveStatus(
        createdAt: afterCutoff,
        emailVerified: false,
        phoneEnforced: false,
      );
      expect(s.needsEmail, isTrue);
      expect(s.isVerified, isFalse);
    });

    test('verified email passes while phone is unenforced', () {
      // The Google/Apple path: provider-verified email, no phone, must pass.
      final s = VerificationService.resolveStatus(
        createdAt: afterCutoff,
        emailVerified: true,
        phoneEnforced: false,
        phoneVerified: false,
      );
      expect(s.isVerified, isTrue);
    });

    test('verified email is gated once phone enforcement switches on', () {
      // The interim social signups. They were never marked exempt precisely so
      // that flipping the flag catches them rather than grandfathering a bypass.
      final s = VerificationService.resolveStatus(
        createdAt: afterCutoff,
        emailVerified: true,
        phoneEnforced: true,
        phoneVerified: false,
      );
      expect(s.needsEmail, isFalse);
      expect(s.needsPhone, isTrue);
      expect(s.isVerified, isFalse);
    });

    test('both verified passes under full enforcement', () {
      final s = VerificationService.resolveStatus(
        createdAt: afterCutoff,
        emailVerified: true,
        phoneEnforced: true,
        phoneVerified: true,
      );
      expect(s.isVerified, isTrue);
    });

    test('phone is never demanded while enforcement is off', () {
      final s = VerificationService.resolveStatus(
        createdAt: afterCutoff,
        emailVerified: true,
        phoneEnforced: false,
        phoneVerified: false,
      );
      expect(s.needsPhone, isFalse);
    });
  });
}
