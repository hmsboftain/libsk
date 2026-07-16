import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';

import 'theme.dart';

/// Confirmation shown after an item is successfully added to the cart, giving
/// the customer an explicit choice between heading to the cart and staying to
/// keep browsing. Replaces the old fire-and-forget "Item added" snackbar.
///
/// Resolves via [Navigator.pop] to `true` when the customer chose "Go to Cart"
/// and `false`/`null` when they chose to continue shopping (or dismissed it).
/// Navigation is left to the caller so this widget stays context-agnostic.
class AddedToCartSheet extends StatelessWidget {
  const AddedToCartSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.zero),
      ),
      builder: (_) => const AddedToCartSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: const BoxDecoration(color: AppColors.border),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 20,
                  color: AppColors.deepAccent,
                ),
                const SizedBox(width: 8),
                Text(l10n.addedToCartTitle, style: AppTextStyles.headingSmall),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepAccent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: Text(l10n.goToCart, style: AppTextStyles.button),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 54,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryText,
                  side: const BorderSide(color: AppColors.border, width: 0.5),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: Text(
                  l10n.continueShopping,
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.primaryText,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
