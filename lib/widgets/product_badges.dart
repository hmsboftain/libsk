import 'package:flutter/material.dart';

import '../core/constants/countries.dart';
import '../services/currency_service.dart';
import 'theme.dart';

String _fmtPrice(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

/// "Out of Stock" overlay — bottom-left, dark semi-transparent, small caps.
/// Must be placed as a direct child of a [Stack].
class OutOfStockOverlay extends StatelessWidget {
  final String label;
  const OutOfStockOverlay({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 10,
      left: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65)),
        child: Text(
          label.toUpperCase(),
          style: AppTextStyles.capsLabel.copyWith(
            color: Colors.white,
            fontSize: 9,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// Renders a product price. When [salePrice] is set and below [price], shows
/// the original struck-through in grey next to the sale price, with an optional
/// small "SALE" badge. Wraps gracefully in tight layouts.
class ProductPriceText extends StatelessWidget {
  final double price;
  final double? salePrice;
  final String saleBadgeLabel;
  final TextStyle? style;
  final bool showBadge;

  const ProductPriceText({
    super.key,
    required this.price,
    required this.salePrice,
    required this.saleBadgeLabel,
    this.style,
    this.showBadge = true,
  });

  bool get _onSale =>
      salePrice != null && salePrice! > 0 && salePrice! < price;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? AppTextStyles.labelLarge;

    if (!_onSale) {
      return Text(_fmtPrice(price), style: baseStyle);
    }

    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          _fmtPrice(price),
          style: baseStyle.copyWith(
            color: AppColors.secondaryText,
            decoration: TextDecoration.lineThrough,
            decorationColor: AppColors.secondaryText,
          ),
        ),
        Text(_fmtPrice(salePrice!), style: baseStyle),
        if (showBadge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: const BoxDecoration(color: AppColors.deepAccent),
            child: Text(
              saleBadgeLabel,
              style: AppTextStyles.capsLabel.copyWith(
                color: Colors.white,
                fontSize: 8,
                letterSpacing: 0.5,
              ),
            ),
          ),
      ],
    );
  }
}
