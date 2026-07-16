import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../services/verification_service.dart';
import '../widgets/theme.dart';

/// Email OTP step for new signups.
///
/// Reached straight after account creation: the Auth user and Firestore profile
/// already exist at this point but are gated until the code round-trips, so the
/// page must assume a signed-in-but-unusable session.
class EmailVerificationPage extends StatefulWidget {
  /// Shown in the "we sent a code to…" line. Falls back to the Auth email.
  final String? email;

  const EmailVerificationPage({super.key, this.email});

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  final _codeController = TextEditingController();

  bool _isVerifying = false;
  bool _isSending = false;
  String? _error;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  String get _email =>
      widget.email ?? FirebaseAuth.instance.currentUser?.email ?? '';

  @override
  void initState() {
    super.initState();
    // Send on arrival so the common path is: land here, code is already coming.
    WidgetsBinding.instance.addPostFrameCallback((_) => _send(initial: true));
    _codeController.addListener(() {
      // Clear a stale error as soon as the user starts correcting the code.
      if (_error != null) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startResendCooldown(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendSeconds--);
      if (_resendSeconds <= 0) t.cancel();
    });
  }

  Future<void> _send({bool initial = false}) async {
    if (_isSending) return;
    setState(() {
      _isSending = true;
      if (!initial) _error = null;
    });

    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;

    try {
      final result = await VerificationService.sendEmailOtp(locale: locale);
      if (!mounted) return;

      if (result.alreadyVerified) {
        // Verified out from under us — a second device, or a resumed session.
        _finish();
        return;
      }
      _startResendCooldown(60);
      if (!initial) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.codeSentCheckInbox)),
        );
      }
    } on OtpException catch (e) {
      if (!mounted) return;
      if (e.retryAfterSeconds != null) {
        // Server-side cooldown is authoritative — mirror it rather than guess.
        _startResendCooldown(e.retryAfterSeconds!);
        setState(() => _error = null);
      } else {
        setState(() => _error = e.code == 'resource-exhausted'
            ? l10n.tooManyCodeRequests
            : l10n.couldNotSendCode);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = l10n.couldNotSendCode);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) return;

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    final l10n = AppLocalizations.of(context)!;

    try {
      await VerificationService.verifyEmailOtp(code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.emailVerifiedSuccess)),
      );
      _finish();
    } on OtpException catch (e) {
      if (!mounted) return;
      setState(() {
        _codeController.clear();
        switch (e.code) {
          case 'deadline-exceeded':
            _error = l10n.codeExpiredRequestNew;
          case 'not-found':
            _error = l10n.codeExpiredRequestNew;
          case 'resource-exhausted':
            _error = l10n.tooManyAttemptsRequestNew;
          default:
            _error = e.remainingAttempts != null && e.remainingAttempts! > 0
                ? l10n.incorrectCodeAttemptsLeft(e.remainingAttempts!)
                : l10n.incorrectCode;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = l10n.incorrectCode);
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _finish() => Navigator.pop(context, true);

  /// A typo'd address creates an account nobody can reach. Rather than stranding
  /// the user until the cleanup job reaps it, let them abandon it deliberately.
  Future<void> _startOver() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: const RoundedRectangleBorder(),
        title: Text(l10n.startOverConfirmTitle, style: AppTextStyles.headingSmall),
        content: Text(l10n.startOverConfirmBody, style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel, style: AppTextStyles.labelLarge),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            child: Text(l10n.startOverConfirm, style: AppTextStyles.button),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Sign out only — the account is left for the cleanup job rather than
    // deleted from the client. Client-side deletion needs a recent login and
    // would leave the Firestore profile and its subcollections orphaned.
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canResend = _resendSeconds <= 0 && !_isSending;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const SizedBox(height: 30),
                Image.asset('assets/libsk_logo.png', height: 90, fit: BoxFit.contain),
                const SizedBox(height: 60),
                Text(l10n.verifyYourEmail, style: AppTextStyles.headingLarge),
                const SizedBox(height: 12),
                Text(
                  l10n.verificationCodeSentTo(_email),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 36),

                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.enterSixDigitCode,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  maxLength: 6,
                  // The code is always Western digits even in Arabic — the email
                  // renders them that way, so accepting only these avoids a
                  // mismatch when an Arabic keyboard emits ٦.
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                  ],
                  style: AppTextStyles.headingLarge.copyWith(letterSpacing: 12),
                  decoration: const InputDecoration(counterText: ''),
                  onChanged: (v) {
                    if (v.length == 6 && !_isVerifying) _verify();
                  },
                ),

                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.error_outline, size: 15, color: AppColors.deepAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.deepAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton(
                    onPressed: _isVerifying ? null : _verify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.deepAccent,
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    child: _isVerifying
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(l10n.verifyCode, style: AppTextStyles.button),
                  ),
                ),
                const SizedBox(height: 22),

                GestureDetector(
                  onTap: canResend ? () => _send() : null,
                  child: Text(
                    canResend ? l10n.resendCode : l10n.resendCodeIn(_resendSeconds),
                    style: AppTextStyles.labelLarge.copyWith(
                      color: canResend
                          ? AppColors.primaryText
                          : AppColors.secondaryText,
                      decoration: canResend ? TextDecoration.underline : null,
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                GestureDetector(
                  onTap: _startOver,
                  child: Text(
                    l10n.wrongEmailStartOver,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.secondaryText,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
