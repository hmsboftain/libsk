import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/services/analytics_service.dart';
import '../services/deep_link_service.dart';
import '../services/firestore_service.dart';
import '../services/payzah_service.dart';
import '../widgets/payzah_checkout_states.dart';
import '../widgets/theme.dart';
import 'order_confirmation_page.dart';
import 'payzah_webview_page.dart';

/// Drives a Payzah direct payment for an order `createOrder` just created.
///
/// The page never decides the outcome itself: it initializes the payment,
/// presents the gateway in an in-app WebView (PayzahWebViewPage), and then
/// treats the customer's `payment_attempts/{attemptId}` doc as the single
/// source of truth — that doc is only ever written by Cloud Functions after a
/// verified get-payment-details response. The intercepted redirect link, the
/// OS deep link, and the app-resume hook merely trigger an extra server-side
/// check; their payloads are never trusted.
class PayzahPaymentPage extends StatefulWidget {
  final String attemptId;
  final String orderNumber;
  final String boutiqueId;
  final String boutiqueName;
  final double total;
  final bool isArabic;

  /// "KNET" | "Card" | "Apple Pay". KNET/Card present the gateway in the
  /// in-app WebView; Apple Pay must use SFSafariViewController
  /// (LaunchMode.inAppBrowserView) because Apple Pay JS cannot run inside
  /// WKWebView — a current WebKit restriction.
  final String paymentMethod;

  const PayzahPaymentPage({
    super.key,
    required this.attemptId,
    required this.orderNumber,
    required this.boutiqueId,
    required this.boutiqueName,
    required this.total,
    this.isArabic = false,
    this.paymentMethod = 'KNET',
  });

  @override
  State<PayzahPaymentPage> createState() => _PayzahPaymentPageState();
}

class _PayzahPaymentPageState extends State<PayzahPaymentPage>
    with WidgetsBindingObserver {
  final PayzahService _payzah = PayzahService();

  PayzahCheckoutState _state = PayzahCheckoutState.loading;

  /// True when the failure state came from a resolved (cancelled) attempt, in
  /// which case retry must return to checkout for a fresh order instead of
  /// re-initializing this one.
  bool _attemptResolved = false;
  bool _successHandled = false;

  /// True once a `libsk://payment-result` redirect has been observed for this
  /// attempt (WebView intercept or OS deep link). It's the discriminator
  /// between a genuinely in-flight payment (redirect seen → keep verifying) and
  /// an abandon (browser closed / sheet dismissed with no redirect → offer
  /// retry). Reset on every (re)start of the payment.
  bool _redirectSeen = false;

  /// Guards against overlapping post-return verifications (e.g. repeated
  /// app-resume events while the one check is still in flight).
  bool _verifyingReturn = false;

  /// Debounce guard for the payment run — blocks a rapid second "Try Again" tap
  /// from kicking off a second payment initialization before the button rebuilt.
  bool _isStartingPayment = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _attemptSub;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AnalyticsService.instance.logScreenView('payzah_payment');

    _attemptSub = FirebaseFirestore.instance
        .collection('payment_attempts')
        .doc(widget.attemptId)
        .snapshots()
        .listen(
          _onAttemptUpdate,
          // A failed listener (rules, offline) must not strand the customer
          // on the verifying spinner — the callable below both re-verifies
          // server-side and returns the status for a direct UI update.
          onError: (Object e) {
            debugPrint('payment_attempts listener error: $e');
            _refreshStatus();
          },
        );

    // Redirect arrived (app was foregrounded via libsk://payment-result) —
    // ask the server to re-verify; the attempt listener shows the result.
    _linkSub = DeepLinkService.instance.paymentResults.listen((_) {
      // A redirect means the customer reached a terminal gateway page: this is
      // a real verification, never an abandon. Latch it so a subsequent
      // app-resume doesn't misread the sheet closing as "customer left".
      _redirectSeen = true;
      if (widget.paymentMethod == 'Apple Pay') {
        // The deep link foregrounds the app but leaves the
        // SFSafariViewController sheet presented — dismiss it so the
        // customer lands on the verifying/result screen, not the sheet.
        closeInAppWebView();
      }
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
    // Only the Apple Pay path actually leaves the app (SFSafariViewController);
    // KNET/Card run in an in-app WebView route and report their outcome through
    // the pop result instead. So resume is a return signal for Apple Pay only.
    if (widget.paymentMethod != 'Apple Pay') return;
    // A redirect already fired — a normal verification is underway and this
    // resume is just the sheet closing; nothing to decide here.
    if (_redirectSeen) return;
    if (_state == PayzahCheckoutState.verifying) {
      // Back from the Safari sheet with no libsk:// deep link: the customer
      // tapped Done without paying, or the OS dropped the link. Verify once and,
      // if still pending, show the honest not-completed state instead of
      // spinning until reconciliation expires the attempt.
      _verifyAfterReturn();
    }
  }

  Future<void> _startPayment() async {
    // Re-entrancy guard: drop a rapid second tap that lands before the retry
    // button rebuilt, so we never start two payment initializations at once.
    if (_isStartingPayment) return;
    _isStartingPayment = true;
    setState(() {
      _state = PayzahCheckoutState.loading;
      _attemptResolved = false;
      // Fresh attempt run — no redirect seen yet, so a return without one reads
      // as an abandon.
      _redirectSeen = false;
    });
    try {
      final paymentUrl = await _payzah.initializePayment(
        attemptId: widget.attemptId,
        language: widget.isArabic ? 'ARA' : 'ENG',
      );
      if (!mounted) return;
      setState(() => _state = PayzahCheckoutState.redirecting);

      if (widget.paymentMethod == 'Apple Pay') {
        // Transit page in SFSafariViewController — Apple Pay JS is
        // unavailable inside WKWebView, so this flow cannot use
        // PayzahWebViewPage. There is no pop-with-result here: completion
        // arrives solely via the libsk:// deep link (_linkSub) or the
        // app-resume status check; both re-verify server-side.
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
        return;
      }

      // KNET / Card: in-app WebView; resolves with the intercepted
      // libsk://payment-result link, or null if the customer closed it
      // before the redirect.
      final Uri? redirectLink = await Navigator.of(context).push<Uri>(
        MaterialPageRoute(
          builder: (context) => PayzahWebViewPage(directUrl: paymentUrl),
          fullscreenDialog: true,
        ),
      );
      if (!mounted) return;

      if (redirectLink != null) {
        // Redirect fired — a genuine, in-flight completion. Same pipeline as an
        // OS-delivered deep link: _linkSub hears it (latching _redirectSeen)
        // and triggers the server-side re-verification.
        setState(() => _state = PayzahCheckoutState.verifying);
        DeepLinkService.instance.emitPaymentResult(redirectLink);
      } else {
        // Closed before any redirect — likely abandoned. Verify once (they may
        // have paid just before closing); if still pending, say so plainly
        // rather than spinning until reconciliation settles the attempt. The
        // attempt stays pending (stock held, order retryable) throughout.
        _verifyAfterReturn();
      }
    } on PayzahException {
      if (!mounted) return;
      // Init failed before any charge could happen — safe to retry in place.
      setState(() => _state = PayzahCheckoutState.failure);
    } finally {
      // Cleared once setup + the browser/WebView handoff returns; by then the
      // retry button is gone, and a later abandon/failure can retry freshly.
      _isStartingPayment = false;
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await _payzah.checkStatus(widget.attemptId);
      if (!mounted) return;
      // Apply the callable's answer directly — normally the attempt doc
      // listener delivers the same update, but this keeps the flow moving
      // even if that listener is dead or slow.
      _applyStatus(status);
    } on PayzahException {
      // Verification unavailable; reconciliation will settle the attempt.
    }
  }

  /// Handle a return from the gateway that did NOT carry a payment-result
  /// redirect: the WebView popped with null, or the Safari sheet was dismissed
  /// with no `libsk://` deep link. A single status check separates a last-second
  /// payment from a genuine abandon — a still-`pending` attempt gets the honest
  /// "not completed" screen instead of an indefinite spinner. Server-side
  /// resolution is untouched: the attempt stays pending, and a real outcome
  /// landing later on the attempt listener still overrides whatever we show.
  Future<void> _verifyAfterReturn() async {
    if (!mounted || _verifyingReturn) return;
    _verifyingReturn = true;
    setState(() => _state = PayzahCheckoutState.verifying);
    String? status;
    try {
      status = await _payzah.checkStatus(widget.attemptId);
    } on PayzahException {
      // Couldn't reach the gateway — treat as not-completed for now;
      // reconciliation / the attempt listener corrects it if a payment landed.
      status = null;
    } finally {
      _verifyingReturn = false;
    }
    if (!mounted) return;
    // A terminal outcome (paid / failed / under review) may have arrived on the
    // attempt listener while we were checking — don't clobber it.
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
        // pending — keep whatever transient state we're in.
        break;
    }
  }

  void _handleSuccess() {
    if (!_successHandled) {
      _successHandled = true;
      AnalyticsService.instance.logPurchase(
        widget.orderNumber,
        widget.total,
        widget.boutiqueId,
      );
      // Single-boutique checkout — clear only this boutique's cart. Deferred
      // until the payment is confirmed so a failed payment keeps the cart.
      FirestoreService.clearBoutiqueCart(widget.boutiqueId);
    }
    setState(() => _state = PayzahCheckoutState.success);
  }

  void _onRetry() {
    if (_attemptResolved) {
      // Order was cancelled server-side and stock released — back to checkout
      // (the cart is untouched) for a fresh attempt.
      Navigator.of(context).pop();
    } else {
      // Abandoned or init-failed: the attempt is still pending, so re-run it in
      // place — initializePayzahPayment is re-callable for a pending attempt and
      // no new order is created.
      _startPayment();
    }
  }

  void _onReturnToCart() {
    // Abandoned attempt: still pending (stock held, retryable) — reconciliation
    // expires it if it goes unused. Back to checkout; the cart is untouched.
    Navigator.of(context).pop();
  }

  void _onContinue() {
    if (_state == PayzahCheckoutState.success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => OrderConfirmationPage(
            orderNumber: widget.orderNumber,
            boutiqueName: widget.boutiqueName,
          ),
        ),
      );
    } else {
      // Under review — the order is parked for support; leave checkout
      // entirely so the customer can't accidentally pay twice.
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    // No back affordance while pending: leaving mid-verification is handled
    // by reconciliation, but an accidental swipe-back into checkout invites a
    // double payment, so only the resolved/abandoned states are exitable — and
    // in those the attempt is either done or pending-but-retryable, so a
    // swipe-back to checkout is safe.
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
            onReturnToCart: _onReturnToCart,
          ),
        ),
      ),
    );
  }
}
