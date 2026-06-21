import 'package:flutter/material.dart';

import 'theme.dart';

// Square outline used by the per-size stock fields.
const _fieldBorder = OutlineInputBorder(
  borderRadius: BorderRadius.zero,
  borderSide: BorderSide(color: AppColors.border, width: 0.5),
);

/// A single square selectable chip. Selected chips fill with
/// [AppColors.deepAccent] and white text; unselected use [AppColors.field] with
/// ink (primary) text. Shared by [ChipSelector] and [SizeChipSelector] so the
/// selected / unselected styling stays identical. Square aesthetic
/// (BorderRadius.zero), matching the LIBSK design system.
class SelectableChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const SelectableChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.deepAccent : AppColors.field,
          border: Border.all(
            color: selected ? AppColors.deepAccent : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelLarge.copyWith(
            color: selected ? Colors.white : AppColors.primaryText,
          ),
        ),
      ),
    );
  }
}

/// Reusable multi-select chip grid. The parent owns the [selected] list and is
/// notified of taps via [onToggle].
class ChipSelector extends StatelessWidget {
  final List<String> options;
  final List<String> selected;
  final ValueChanged<String> onToggle;

  const ChipSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options
          .map(
            (option) => SelectableChip(
              label: option,
              selected: selected.contains(option),
              onTap: () => onToggle(option),
            ),
          )
          .toList(),
    );
  }
}

/// Standard size options offered by [SizeChipSelector] — alpha sizes, common
/// numeric sizes, and "One Size".
const List<String> kStandardSizes = [
  'XS', 'S', 'M', 'L', 'XL', 'XXL',
  '6', '8', '10', '12', '14', '16',
  '28', '30', '32', '34', '36', '38', '40',
  'One Size',
];

/// Multi-select size chips with a per-size stock quantity input. Preserves the
/// existing per-size stock data structure: emits a list of
/// `{'name': String, 'stock': int}` maps via [onChanged] whenever the selection
/// or a stock value changes.
class SizeChipSelector extends StatefulWidget {
  final List<Map<String, dynamic>> initialEntries;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final String stockLabel;
  final List<String> sizes;

  const SizeChipSelector({
    super.key,
    required this.initialEntries,
    required this.onChanged,
    required this.stockLabel,
    this.sizes = kStandardSizes,
  });

  @override
  State<SizeChipSelector> createState() => _SizeChipSelectorState();
}

class _SizeChipSelectorState extends State<SizeChipSelector> {
  // Ordered list of currently-selected size names.
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
    final entries = _selected
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.sizes
              .map(
                (size) => SelectableChip(
                  label: size,
                  selected: _selected.contains(size),
                  onTap: () => _toggle(size),
                ),
              )
              .toList(),
        ),
        if (_selected.isNotEmpty) ...[
          const SizedBox(height: 16),
          ..._selected.map(_buildStockRow),
        ],
      ],
    );
  }

  Widget _buildStockRow(String size) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.selectedSoft,
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Text(size, style: AppTextStyles.labelLarge),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _stock[size],
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: widget.stockLabel,
                filled: true,
                fillColor: AppColors.field,
                hintStyle: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.secondaryText,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: _fieldBorder,
                enabledBorder: _fieldBorder,
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppColors.deepAccent, width: 1),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _toggle(size),
            child: const Icon(
              Icons.close,
              size: 18,
              color: AppColors.deepAccent,
            ),
          ),
        ],
      ),
    );
  }
}
