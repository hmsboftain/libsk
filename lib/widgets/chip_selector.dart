import 'package:flutter/material.dart';

import 'theme.dart';

// Shared 0.5px hairline used by every bordered container here.
const BorderSide _hairline = BorderSide(color: AppColors.border, width: 0.5);

/// Alphabetical sizes shown in the first size grid.
const List<String> kLetterSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'One Size'];

/// Numeric sizes shown in the second size grid.
const List<String> kNumericSizes = [
  '6', '8', '10', '12', '14', '16',
  '28', '30', '32', '34', '36', '38', '40',
];

/// Clean multi-select category list — full-width tappable rows with a trailing
/// checkmark, selected rows tinted [AppColors.selectedSoft]. The parent owns the
/// [selected] list and is notified of taps via [onToggle]. Square aesthetic.
class CategoryListSelector extends StatelessWidget {
  final List<String> options;
  final List<String> selected;
  final ValueChanged<String> onToggle;

  const CategoryListSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border.fromBorderSide(_hairline),
      ),
      child: Column(
        children: List.generate(options.length, (i) {
          final option = options[i];
          final isSelected = selected.contains(option);
          final isLast = i == options.length - 1;
          return Material(
            color: isSelected ? AppColors.selectedSoft : AppColors.background,
            child: InkWell(
              onTap: () => onToggle(option),
              child: Container(
                decoration: BoxDecoration(
                  border: isLast ? null : const Border(bottom: _hairline),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: isSelected
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check,
                        size: 18,
                        color: AppColors.deepAccent,
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Shopify-style size + per-size stock editor. Step 1: pick sizes from the
/// grouped letter / numeric grids. Step 2: a bordered stock table animates in
/// with one quantity field per selected size. Preserves the existing per-size
/// stock data structure: emits a list of `{'name': String, 'stock': int}` maps
/// via [onChanged] whenever the selection or a stock value changes.
class SizeStockSelector extends StatefulWidget {
  final List<Map<String, dynamic>> initialEntries;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final String letterSizesLabel;
  final String numericSizesLabel;
  final String sizeColumnLabel;
  final String stockColumnLabel;

  const SizeStockSelector({
    super.key,
    required this.initialEntries,
    required this.onChanged,
    required this.letterSizesLabel,
    required this.numericSizesLabel,
    required this.sizeColumnLabel,
    required this.stockColumnLabel,
  });

  @override
  State<SizeStockSelector> createState() => _SizeStockSelectorState();
}

class _SizeStockSelectorState extends State<SizeStockSelector> {
  // Selected size names (insertion order). Display order is normalised to the
  // grids via [_orderedSelected] so the stock table stays stable.
  final List<String> _selected = [];
  // One stock controller per selected size, kept alive across rebuilds so the
  // cursor doesn't jump while typing.
  final Map<String, TextEditingController> _stock = {};

  @override
  void initState() {
    super.initState();
    for (final entry in widget.initialEntries) {
      final name = entry['name']?.toString() ?? '';
      if (name.isEmpty || _selected.contains(name)) continue;
      final stockValue = entry['stock'];
      final stock = stockValue is int
          ? stockValue
          : int.tryParse(stockValue?.toString() ?? '') ?? 0;
      _selected.add(name);
      _stock[name] = _controller(stock > 0 ? stock.toString() : '');
    }
  }

  TextEditingController _controller(String text) {
    return TextEditingController(text: text)..addListener(_emit);
  }

  @override
  void dispose() {
    for (final c in _stock.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final entries = _orderedSelected()
        .map(
          (name) => <String, dynamic>{
            'name': name,
            'stock': int.tryParse(_stock[name]?.text.trim() ?? '') ?? 0,
          },
        )
        .toList();
    widget.onChanged(entries);
  }

  void _toggle(String size) {
    setState(() {
      if (_selected.contains(size)) {
        _selected.remove(size);
        _stock.remove(size)
          ?..removeListener(_emit)
          ..dispose();
      } else {
        _selected.add(size);
        _stock[size] = _controller('');
      }
    });
    _emit();
  }

  // Selected sizes in canonical grid order, with any legacy/custom sizes
  // (not in the standard grids) appended so existing data is never dropped.
  List<String> _orderedSelected() {
    const order = [...kLetterSizes, ...kNumericSizes];
    final known = order.where(_selected.contains);
    final extra = _selected.where((s) => !order.contains(s));
    return [...known, ...extra];
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selected.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.letterSizesLabel, style: AppTextStyles.capsLabel),
        const SizedBox(height: 10),
        _grid(kLetterSizes),
        const SizedBox(height: 18),
        Text(widget.numericSizesLabel, style: AppTextStyles.capsLabel),
        const SizedBox(height: 10),
        _grid(kNumericSizes),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: hasSelection
              ? Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: _stockTable(),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _grid(List<String> sizes) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sizes.map((size) {
        final isSelected = _selected.contains(size);
        return GestureDetector(
          onTap: () => _toggle(size),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            constraints: const BoxConstraints(minWidth: 52),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? AppColors.deepAccent : AppColors.background,
              border: isSelected ? null : const Border.fromBorderSide(_hairline),
            ),
            child: Text(
              size,
              style: AppTextStyles.labelLarge.copyWith(
                color: isSelected ? Colors.white : AppColors.primaryText,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _stockTable() {
    final rows = _orderedSelected();
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border.fromBorderSide(_hairline),
      ),
      child: Column(
        children: [
          // Header row: SIZE | STOCK
          Container(
            decoration: const BoxDecoration(border: Border(bottom: _hairline)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.sizeColumnLabel.toUpperCase(),
                    style: AppTextStyles.capsLabel,
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    widget.stockColumnLabel.toUpperCase(),
                    style: AppTextStyles.capsLabel,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          ...List.generate(rows.length, (i) {
            final size = rows[i];
            final isLast = i == rows.length - 1;
            return Container(
              decoration: BoxDecoration(
                border: isLast ? null : const Border(bottom: _hairline),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(size, style: AppTextStyles.bodyMedium),
                  ),
                  SizedBox(
                    width: 80,
                    height: 40,
                    child: TextField(
                      controller: _stock[size],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '0',
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                        filled: true,
                        fillColor: AppColors.field,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: _hairline,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: _hairline,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide(
                            color: AppColors.deepAccent,
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
