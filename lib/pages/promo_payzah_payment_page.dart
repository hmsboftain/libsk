import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/services/analytics_service.dart';
import '../services/deep_link_service.dart';
import '../services/payzah_service.dart';
import '../widgets/payzah_checkout_states.dart';
import '../widgets/theme.dart';

/// Drives a Payzah payment for a promo booking `createPromoBooking` just made.
///
/// EXPERIMENT (deliberate, promo-only): unlike the customer checkout
/// [PayzahPaymentPage] — which uses an in-app WebView for KNET/Card and
/// SFSafariViewController only for Apple Pay — this page presents ALL THREE
/// methods (KNET, Card, Apple Pay) in SFSafariViewController via
/// `LaunchMode.inAppBrowserView`. Promo booking is newer and lower-stakes than
/// checkout, so it's the safe place to validate the all-Safari approach before
/// porting checkout. Checkout is intentionally left untouched.
///
/// The page never decides the outcome itself: it initializes the payment,
/// opens the gateway in Safari, and treats the `payment_attempts/{attemptId}`
/// doc (written only by Cloud Functions after a verified get-payment-details
/// response) as the single source of truth. The libsk:// deep link and the
/// app-resume hook merely trigger an extra server-side re-check.
class PromoPayzahPaymentPage extends StatefulWidget {
  final String attemptId;
  final String bookingId;

  /// Human-readable placement, e.g. "Featured Boutique" — shown on success.
  final String placementLabel;
  final double priceKwd;
  final bool isArabic;

  /// "KNET" | "Card" | "Apple Pay". All three open in SFSafariViewController
  /// here (the experiment) — so, unlike checkout, there is no WebView path and
  /// completion for every method arrives via the deep link or app-resume check.
  final String paymentMethod;

  const PromoPayzahPaymentPage({
    super.key,
    required this.attemptId,
    required this.bookingId,
    required this.placementLabel,
    required this.priceKwd,
    this.isArabic = false,
    this.paymentMethod = 'KNET',
  });

  @override
  State<PromoPayzahPaymentPage> createState() => _PromoPayzahPaymentPageState();
}

class _PromoPayzahPaymentPageState extends State<PromoPayzahPaymentPage>
    with WidgetsBindingObserver {
  final PayzahService _payzah = PayzahService();

  PayzahCheckoutState _state = PayzahCheckoutState.loading;

  /// True when the failure came from a resolved (cancelled) attempt — retry must
  /// return to the launcher for a fresh booking, not re-init this one.
  bool _attemptResolved = false;
  bool _successHandled = false;

  /// True once a `libsk://payment-result` deep link has been seen for this
  /// attempt. Discriminates a genuinely in-flight payment (keep verifying) from
  /// an abandon (Safari dismissed with no deep link → offer retry). Reset on
  /// every (re)start.
  bool _redirectSeen = false;

  /// Guards overlapping post-return verifications (repeated resume events).
  bool _verifyingReturn = false;

  /// Debounce for the payment run — blocks a rapid second "Try Again".
  bool _isStartingPayment = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _attemptSub;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AnalyticsService.instance.logScreenView('promo_payzah_payment');

    _attemptSub = FirebaseFirestore.instance
        .collection('payment_attempts')
        .doc(widget.attemptId)
        .snapshots()
        .listen(
          _onAttemptUpdate,
          onError: (Object e) {
            debugPrint('promo payment_attempts listener error: $e');
            _refreshStatus();
          },
        );

    _linkSub = DeepLinkService.instance.paymentResults.listen((_) {
      // A redirect means a terminal gateway page was reached: a real
      // verification, never an abandon. Latch it so a later resume doesn't
      // misread the Safari sheet closing as "owner left".
      _redirectSeen = true;
      // All three methods run in SFSafariViewController here, so the deep link
      // foregrounds the app while the Safari sheet is still presented on top —
      // dismiss it for every method (checkout does this for Apple Pay only).
      closeInAppWebView();
      _refreshStatus();
    });

    _startPayment();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _attemptSub?.cancel();
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Every method leaves the app for Safari here, so resume is a return signal
    // for all three (checkout gates this on Apple Pay only).
    if (_redirectSeen) return; // a redirect already fired — verification underway
    if (_state == PayzahCheckoutState.verifying) {
      // Back from Safari with no libsk:// deep link: the owner tapped Done
      // without paying, or the OS dropped the link. Verify once; if still
      // pending, show the honest not-completed state rather than spinning.
      _verifyAfterReturn();
    }
  }

  Future<void> _startPayment() async {
    if (_isStartingPayment) return;
    _isStartingPayment = true;
    setState(() {
      _state = PayzahCheckoutState.loading;
      _attemptResolved = false;
      _redirectSeen = false;
    });
    try {
      final paymentUrl = await _payzah.initializePayment(
        attemptId: widget.attemptId,
        language: widget.isArabic ? 'ARA' : 'ENG',
      );
      if (!mounted) return;
      setState(() => _state = PayzahCheckoutState.redirecting);

      // The experiment: SFSafariViewController for KNET, Card AND Apple Pay.
      // There is no pop-with-result; completion arrives via the libsk:// deep
      // link (_linkSub) or the app-resume status check — both re-verify
      // server-side.
      final launched = await launchUrl(
        Uri.parse(paymentUrl),
        mode: LaunchMode.inAppBrowserView,
      );
      if (!mounted) return;
      if (!launched) {
        setState(() => _state = PayzahCheckoutState.failure);
        return;
      }
      setState(() => _state = PayzahCheckoutState.verifying);
    } on PayzahException {
      if (!mounted) return;
      // Init failed before any charge — safe to retry in place.
      setState(() => _state = PayzahCheckoutState.failure);
    } finally {
      _isStartingPayment = false;
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await _payzah.checkStatus(widget.attemptId);
      if (!mounted) return;
      _applyStatus(status);
    } on PayzahException {
      // Verification unavailable; reconciliation will settle the attempt.
    }
  }

  /// Return from Safari with no payment-result deep link. A single status check
  /// separates a last-second payment from a genuine abandon — a still-`pending`
  /// attempt gets the honest "not completed" screen. Server-side resolution is
  /// untouched: the attempt stays pending and a real outcome landing later on
  /// the attempt listener still overrides whatever we show.
  Future<void> _verifyAfterReturn() async {
    if (!mounted || _verifyingReturn) return;
    _verifyingReturn = true;
    setState(() => _state = PayzahCheckoutState.verifying);
    String? status;
    try {
      status = await _payzah.checkStatus(widget.attemptId);
    } on PayzahException {
      status = null;
    } finally {
      _verifyingReturn = false;
    }
    if (!mounted) return;
    // A terminal outcome may have arrived on the listener while we checked.
    if (_state != PayzahCheckoutState.verifying) return;
    if (status == null || status == 'pending') {
      setState(() => _state = PayzahCheckoutState.abandoned);
    } else {
      _applyStatus(status);
    }
  }

  void _onAttemptUpdate(DocumentSnapshot<Map<String, dynamic>> snap) {
    final status = snap.data()?['status'] as String?;
    if (!mounted || status == null) return;
    _applyStatus(status);
  }

  void _applyStatus(String status) {
    switch (status) {
      case 'paid':
        _handleSuccess();
      case 'failed':
      case 'expired':
        setState(() {
          _attemptResolved = true;
          _state = PayzahCheckoutState.failure;
        });
      case 'under_review':
        setState(() => _state = PayzahCheckoutState.underReview);
      default:
        break; // pending — keep the transient state
    }
  }

  void _handleSuccess() {
    if (!_successHandled) {
      _successHandled = true;
      AnalyticsService.instance.logScreenView('promo_payzah_paid');
    }
    setState(() => _state = PayzahCheckoutState.success);
  }

  void _onRetry() {
    if (_attemptResolved) {
      // Booking was cancelled server-side and the held slot released — back to
      // the launcher for a fresh booking.
      Navigator.of(context).pop();
    } else {
      // Abandoned or init-failed: the attempt is still pending, so re-run it in
      // place (initializePayzahPayment is re-callable for a pending attempt).
      _startPayment();
    }
  }

  void _onBackToDashboard() {
    // Abandoned attempt: still pending (slot held, retryable) — reconciliation
    // expires it if unused. Leave the payment page.
    Navigator.of(context).pop();
  }

  void _onContinue() {
    // Success or under-review — leave the payment page; the launcher/dashboard
    // is where the owner sees their booking. Return true on success so the
    // caller can refresh.
    Navigator.of(context).pop(_state == PayzahCheckoutState.success);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // No back affordance while pending — leaving mid-verification is handled by
    // reconciliation, but an accidental swipe-back invites a double payment. Only
    // the resolved/abandoned states (done, or pending-but-retryable) are exitable.
    return PopScope(
      canPop: _state == PayzahCheckoutState.failure ||
          _state == PayzahCheckoutState.abandoned,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: PayzahCheckoutStateView(
            state: _state,
            onRetry: _onRetry,
            onContinue: _onContinue,
            onReturnToCart: _onBackToDashboard,
            successBody: l10n.promoPaymentBookedBody,
            abandonedBody: l10n.promoPaymentNotCompletedBody,
            secondaryLabel: l10n.promoReturnToDashboard,
          ),
        ),
      ),
    );
  }
}
