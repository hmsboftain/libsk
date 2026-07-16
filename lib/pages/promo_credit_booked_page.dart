import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';

import '../core/services/analytics_service.dart';
import '../widgets/payzah_checkout_states.dart';
import '../widgets/theme.dart';

/// Terminal confirmation for a promo booking paid ENTIRELY from promo credit.
///
/// The credit-only path never touches Payzah — `createPromoBooking` spends the
/// credit and writes the booking as already paid in one transaction, so there is
/// no payment attempt to drive and nothing to verify. But a real credit spend
/// did just happen, so it gets the same full-screen confirmation the paid flow
/// gets rather than a toast: it reuses [PayzahCheckoutStateView]'s success state
/// with no-charge wording (the title override exists precisely for this — there
/// was no payment to confirm).
class PromoCreditBookedPage extends StatelessWidget {
  /// Promo credit actually spent, in KWD — surfaced so the owner sees exactly
  /// what came off their balance.
  final double amountFromCredit;

  const PromoCreditBookedPage({super.key, required this.amountFromCredit});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    AnalyticsService.instance.logScreenView('promo_credit_booked');

    // Nothing to retry or abandon — the booking is already committed, so the
    // only way out is Continue (back to the dashboard, which refreshes).
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: PayzahCheckoutStateView(
            state: PayzahCheckoutState.success,
            successTitle: l10n.promoCreditBookedTitle,
            successBody: l10n.promoCreditBookedBody(
              amountFromCredit.toStringAsFixed(3),
            ),
            onContinue: () => Navigator.of(context).pop(true),
          ),
        ),
      ),
    );
  }
}
