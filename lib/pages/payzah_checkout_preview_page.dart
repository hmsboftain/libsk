import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../navigation/app_header.dart';
import '../widgets/payzah_checkout_states.dart';
import '../widgets/theme.dart';

/// Debug-only walkthrough of the Payzah checkout states.
///
/// Not routed anywhere in the app. To preview, push it from any debug build,
/// e.g. temporarily:
///
///   Navigator.push(context, MaterialPageRoute(
///     builder: (_) => const PayzahCheckoutPreviewPage()));
///
/// Renders nothing in release builds so it can never leak to customers even
/// if a navigation call slips through.
class PayzahCheckoutPreviewPage extends StatefulWidget {
  const PayzahCheckoutPreviewPage({super.key});

  @override
  State<PayzahCheckoutPreviewPage> createState() =>
      _PayzahCheckoutPreviewPageState();
}

class _PayzahCheckoutPreviewPageState extends State<PayzahCheckoutPreviewPage> {
  PayzahCheckoutState _state = PayzahCheckoutState.loading;

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: PayzahCheckoutState.values.map((s) {
                  final selected = s == _state;
                  return ChoiceChip(
                    label: Text(
                      s.name,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: selected
                            ? Colors.white
                            : AppColors.secondaryText,
                      ),
                    ),
                    selected: selected,
                    selectedColor: AppColors.deepAccent,
                    backgroundColor: AppColors.field,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _state = s),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 18),
            const Divider(
              color: AppColors.border,
              thickness: 0.5,
              height: 0.5,
            ),
            Expanded(
              child: PayzahCheckoutStateView(
                state: _state,
                onRetry: () =>
                    setState(() => _state = PayzahCheckoutState.loading),
                onContinue: () {
                  // Real flow: push OrderConfirmationPage, same destination
                  // as the Stripe success path. Preview just resets.
                  setState(() => _state = PayzahCheckoutState.loading);
                },
                onReturnToCart: () =>
                    setState(() => _state = PayzahCheckoutState.loading),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
