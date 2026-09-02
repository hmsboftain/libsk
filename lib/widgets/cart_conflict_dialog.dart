import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../services/firestore_service.dart';
import 'theme.dart';

/// Enforces the "one boutique at a time" cart rule at the add-to-cart
/// chokepoint. Every add path calls [ensureSingleBoutiqueCart] right before
/// [FirestoreService.addToCart]; the cart is limited to a single boutique
/// because each boutique ships as its own Wasal delivery with its own fee.
class CartConflictGuard {
  const CartConflictGuard._();

  /// Returns true when it's OK to add an item from [boutiqueId].
  ///
  /// If the cart already holds a *different* boutique, shows the one-boutique
  /// dialog: on "Clear cart & add" it empties the other boutique carts and
  /// returns true; on cancel (or dismiss) it returns false. When there's no
  /// conflict it returns true without showing anything.
  static Future<bool> ensureSingleBoutiqueCart(
    BuildContext context,
    String boutiqueId,
  ) async {
    final otherBoutique =
        await FirestoreService.conflictingCartBoutiqueName(boutiqueId);
    if (otherBoutique == null) return true;
    if (!context.mounted) return false;

    final l10n = AppLocalizations.of(context)!;
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: const RoundedRectangleBorder(),
        title: Text(
          l10n.cartOneBoutiqueTitle,
          style: AppTextStyles.headingSmall,
        ),
        content: Text(
          l10n.cartOneBoutiqueMessage,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.secondaryText,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.cancel,
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: Text(l10n.cartClearAndAdd, style: AppTextStyles.button),
          ),
        ],
      ),
    );

    if (shouldClear != true) return false;

    await FirestoreService.clearOtherBoutiqueCarts(boutiqueId);
    return true;
  }
}
