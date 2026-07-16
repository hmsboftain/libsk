import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';

import '../core/constants/countries.dart';
import '../models/product.dart';
import '../services/currency_service.dart';
import '../services/firestore_service.dart';
import 'theme.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

/// Quick-pick bottom sheet for adding a feed product to the cart without
/// leaving the feed. Mirrors the size/colour selection and validation in
/// [ProductPage] exactly, and routes through the same
/// [FirestoreService.addToCart] call so behaviour can't diverge.
///
/// Returns `true` via [Navigator.pop] when an item was added, so the caller
/// can show the confirmation snackbar. Validation messages are shown inside
/// the sheet while it is still open.
class FeedAddToCartSheet extends StatefulWidget {
  final Product product;
  const FeedAddToCartSheet({super.key, required this.product});

  /// Opens the sheet and resolves to `true` if an item was added.
  static Future<bool?> show(BuildContext context, Product product) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.zero),
      ),
      builder: (_) => FeedAddToCartSheet(product: product),
    );
  }

  @override
  State<FeedAddToCartSheet> createState() => _FeedAddToCartSheetState();
}

class _FeedAddToCartSheetState extends State<FeedAddToCartSheet> {
  String _selectedSize = '';
  String _selectedColor = '';
  bool _isAdding = false;
  final _specialRequestController = TextEditingController();

  Product get _product => widget.product;

  @override
  void initState() {
    super.initState();
    if (_product.sizes.isNotEmpty) _selectedSize = _product.sizes.first;
    if (_product.colors.isNotEmpty) _selectedColor = _product.colors.first;
  }

  @override
  void dispose() {
    _specialRequestController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    // Re-entrancy guard: drop a rapid second tap that lands before the disabled
    // button has rebuilt, so the item can't be added twice.
    if (_isAdding) return;

    final l10n = AppLocalizations.of(context)!;
    final hasColors = _product.colors.isNotEmpty;

    if (_product.isSoldOut) {
      _snack(l10n.thisProductIsOutOfStock);
      return;
    }
    if (_selectedSize.isEmpty) {
      _snack(l10n.pleaseSelectASize);
      return;
    }
    if (hasColors &&
        (_selectedColor.isEmpty || !_product.colors.contains(_selectedColor))) {
      _snack(l10n.pleaseSelectAColour);
      return;
    }

    setState(() => _isAdding = true);
    try {
      await FirestoreService.addToCart(
        productId: _product.id,
        boutiqueId: _product.boutiqueId,
        imageUrl: _product.displayImageUrl,
        title: _product.title,
        description: _product.description,
        size: _selectedSize,
        color: hasColors ? _selectedColor : '',
        price: _product.price,
        specialRequest: _specialRequestController.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAdding = false);
      final detail = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : null;
      _snack(
        (detail == null || detail.isEmpty) ? l10n.somethingWentWrong : detail,
      );
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  Widget _chip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.deepAccent : Colors.transparent,
          border: Border.all(
            color: isSelected ? AppColors.deepAccent : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelLarge.copyWith(
            fontSize: 12,
            color: isSelected ? Colors.white : AppColors.primaryText,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sizes = _product.sizes;
    final colors = _product.colors;
    final hasSizes = sizes.isNotEmpty;

    // Tap anywhere off a field (e.g. the Special Request box) to drop the
    // keyboard; child gestures still win, so chips and the button keep working.
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: const BoxDecoration(color: AppColors.border),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _product.title,
                    style: AppTextStyles.headingSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _fmt(_product.price),
                  style: AppTextStyles.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 18),

            Text(l10n.sizeSection, style: AppTextStyles.labelLarge),
            const SizedBox(height: 8),
            if (hasSizes)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: sizes
                    .map(
                      (s) => _chip(
                        label: s,
                        isSelected: _selectedSize == s,
                        onTap: () => setState(() => _selectedSize = s),
                      ),
                    )
                    .toList(),
              )
            else
              Text(l10n.noSizesAvailable, style: AppTextStyles.bodySmall),

            if (colors.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(l10n.colours, style: AppTextStyles.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: colors
                    .map(
                      (c) => _chip(
                        label: c,
                        isSelected: _selectedColor == c,
                        onTap: () => setState(() => _selectedColor = c),
                      ),
                    )
                    .toList(),
              ),
            ],

            const SizedBox(height: 16),
            Text(l10n.specialRequest, style: AppTextStyles.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _specialRequestController,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: AppTextStyles.bodyMedium,
              decoration: InputDecoration(
                hintText: l10n.specialRequestHint,
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.secondaryText,
                ),
                filled: true,
                fillColor: AppColors.field,
                contentPadding: const EdgeInsets.all(14),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppColors.border, width: 0.5),
                ),
                enabledBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppColors.border, width: 0.5),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppColors.deepAccent, width: 1),
                ),
              ),
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isAdding ? null : _add,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepAccent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: _isAdding
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.addToCart, style: AppTextStyles.button),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
