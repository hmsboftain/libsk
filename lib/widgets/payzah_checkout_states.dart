import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';

import 'theme.dart';

/// Checkout states for the Payzah direct (redirect-based) payment flow.
///
/// Payzah hands the customer off to KNET / card in the browser and the app
/// only learns the outcome when the `payzahRedirect` /
/// `reconcilePayzahPayments` Cloud Functions resolve the corresponding
/// `payment_attempts` doc. That asynchronous gap is why [redirecting] and
/// [verifying] exist as first-class states here. Driven live by
/// `PayzahPaymentPage`; preview every state via `PayzahCheckoutPreviewPage`
/// in debug builds.
enum PayzahCheckoutState {
  /// The payment attempt is being created server-side.
  loading,

  /// About to hand off to KNET / Apple Pay. Brief transitional state — the
  /// actual redirect is triggered by the (currently stubbed) Payzah init call.
  redirecting,

  /// Back from the redirect, waiting for reconciliation to confirm the
  /// payment. The customer must not assume success or failure yet.
  verifying,

  /// Payment confirmed — the real flow continues to [OrderConfirmationPage],
  /// same destination as the Stripe success path.
  success,

  /// Payment failed or expired. Distinct from a network error: the charge did
  /// not go through and the customer may retry.
  failure,

  /// The customer left the gateway without completing payment — the WebView was
  /// closed, or the Safari sheet dismissed, before any `libsk://` redirect fired
  /// and a follow-up status check still reads pending. NOT a failure: nothing
  /// was charged and the SAME attempt is still valid, so retry resumes it in
  /// place rather than creating a new order. Distinct from [verifying], which is
  /// a genuinely in-flight payment (a redirect was seen) we're still awaiting.
  abandoned,

  /// The gateway reported an uncertain outcome (HOST TIMEOUT / NOT CAPTURED)
  /// and the retry window elapsed. NOT a failure — funds may have moved, so
  /// the order is parked as "Payment Under Review" for manual resolution and
  /// the customer must not be told to pay again.
  underReview,
}

class PayzahCheckoutStateView extends StatelessWidget {
  final PayzahCheckoutState state;

  /// Shown on [PayzahCheckoutState.failure] — retries the payment attempt.
  final VoidCallback? onRetry;

  /// Shown on [PayzahCheckoutState.success] — continues to order confirmation.
  final VoidCallback? onContinue;

  /// Shown on [PayzahCheckoutState.abandoned] — the secondary "return to cart"
  /// action offered alongside retry.
  final VoidCallback? onReturnToCart;

  /// Optional copy overrides so a non-checkout flow (e.g. promo booking) can
  /// reuse this exact view with context-appropriate wording. Null = the default
  /// order-checkout strings, so the customer checkout flow is unchanged.
  ///
  /// [successTitle] exists for flows that confirm something other than a payment
  /// — a promo booking paid entirely from promo credit is confirmed, but nothing
  /// was charged, so "Payment confirmed" would be wrong.
  final String? successTitle;
  final String? successBody;
  final String? abandonedBody;
  final String? secondaryLabel;

  const PayzahCheckoutStateView({
    super.key,
    required this.state,
    this.onRetry,
    this.onContinue,
    this.onReturnToCart,
    this.successTitle,
    this.successBody,
    this.abandonedBody,
    this.secondaryLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Center(
        child: switch (state) {
          PayzahCheckoutState.loading => _pendingState(
            title: l10n.paymentPreparingTitle,
            body: l10n.paymentPreparingBody,
          ),
          PayzahCheckoutState.redirecting => _pendingState(
            title: l10n.paymentRedirectingTitle,
            body: l10n.paymentRedirectingBody,
          ),
          PayzahCheckoutState.verifying => _pendingState(
            title: l10n.paymentVerifyingTitle,
            body: l10n.paymentVerifyingBody,
            showSecureNote: true,
            l10n: l10n,
          ),
          PayzahCheckoutState.success => _resolvedState(
            icon: Icons.check,
            title: successTitle ?? l10n.paymentConfirmedTitle,
            body: successBody ?? l10n.paymentConfirmedBody,
            buttonLabel: l10n.continueAction,
            onPressed: onContinue,
          ),
          PayzahCheckoutState.failure => _resolvedState(
            icon: Icons.close,
            title: l10n.paymentFailedTitle,
            body: l10n.paymentFailedBody,
            buttonLabel: l10n.tryAgain,
            onPressed: onRetry,
          ),
          PayzahCheckoutState.abandoned => _resolvedState(
            // Neutral, not the failure X — nothing was charged, the customer
            // simply didn't finish.
            icon: Icons.info_outline,
            title: l10n.paymentNotCompletedTitle,
            body: abandonedBody ?? l10n.paymentNotCompletedBody,
            buttonLabel: l10n.tryAgain,
            onPressed: onRetry,
            secondaryLabel: secondaryLabel ?? l10n.returnToCart,
            onSecondary: onReturnToCart,
          ),
          PayzahCheckoutState.underReview => _resolvedState(
            icon: Icons.hourglass_empty,
            title: l10n.paymentUnderReviewTitle,
            body: l10n.paymentUnderReviewBody,
            buttonLabel: l10n.continueAction,
            onPressed: onContinue,
          ),
        },
      ),
    );
  }

  // Spinner states — loading / redirecting / verifying.
  Widget _pendingState({
    required String title,
    required String body,
    bool showSecureNote = false,
    AppLocalizations? l10n,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            color: AppColors.deepAccent,
            strokeWidth: 1.5,
          ),
        ),
        const SizedBox(height: 26),
        Text(
          title,
          style: AppTextStyles.headingMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          body,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.secondaryText,
          ),
          textAlign: TextAlign.center,
        ),
        if (showSecureNote && l10n != null) ...[
          const SizedBox(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 13,
                color: AppColors.secondaryText,
              ),
              const SizedBox(width: 6),
              Text(l10n.secureCheckout, style: AppTextStyles.labelSmall),
            ],
          ),
        ],
      ],
    );
  }

  // Terminal / resolved states — success / failure / abandoned / under review.
  // [secondaryLabel] adds a low-emphasis text action beneath the primary
  // button (used by [PayzahCheckoutState.abandoned] for "return to cart").
  Widget _resolvedState({
    required IconData icon,
    required String title,
    required String body,
    required String buttonLabel,
    VoidCallback? onPressed,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            border: Border.fromBorderSide(
              BorderSide(color: AppColors.deepAccent, width: 1),
            ),
          ),
          child: Icon(icon, size: 26, color: AppColors.deepAccent),
        ),
        const SizedBox(height: 26),
        Text(
          title,
          style: AppTextStyles.headingMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          body,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.secondaryText,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 34),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepAccent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.softAccent,
              disabledForegroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: Text(buttonLabel, style: AppTextStyles.button),
          ),
        ),
        if (secondaryLabel != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: onSecondary,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.secondaryText,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              child: Text(
                secondaryLabel,
                style: AppTextStyles.button.copyWith(
                  color: AppColors.secondaryText,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
