import 'package:flutter/material.dart';

import 'theme.dart';

// Shared 0.5px hairline used by every bordered surface here.
const BorderSide _hairline = BorderSide(color: AppColors.border, width: 0.5);

/// Alphabetical sizes, shown first in the size picker.
const List<String> kLetterSizes = [
  'One Size',
  'XS',
  'S',
  'M',
  'L',
  'XL',
  'XXL',
];

/// Numeric sizes, shown after the "Numeric Sizes" divider.
const List<String> kNumericSizes = [
  '6',
  '8',
  '10',
  '12',
  '14',
  '16',
  '28',
  '30',
  '32',
  '34',
  '36',
  '38',
  '40',
];

/// One entry in a multi-select sheet: a non-selectable section [header] or a
/// selectable [value].
class MultiSelectEntry {
  final String? header;
  final String? value;
  const MultiSelectEntry.header(this.header) : value = null;
  const MultiSelectEntry.value(this.value) : header = null;
}

/// Tappable field styled like a regular input (square border, same fill) that
/// shows the placeholder or the current selection and opens a picker on tap.
class _PickerField extends StatelessWidget {
  final String text;
  final bool isPlaceholder;
  final VoidCallback onTap;

  const _PickerField({
    required this.text,
    required this.isPlaceholder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: const BoxDecoration(
          color: AppColors.field,
          border: Border.fromBorderSide(_hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: isPlaceholder
                      ? AppColors.secondaryText
                      : AppColors.primaryText,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 22,
              color: AppColors.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared multi-select bottom sheet — ~4 rows visible, scrollable for more, a
/// trailing checkmark on selected rows, and a Done button. Toggling mutates the
/// caller's [selected] list via [onToggle] and rebuilds the sheet's checkmarks
/// live. Square aesthetic throughout.
Future<void> _showMultiSelectSheet({
  required BuildContext context,
  required List<MultiSelectEntry> entries,
  required List<String> selected,
  required ValueChanged<String> onToggle,
  required String doneLabel,
}) {
  const rowHeight = 56.0;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(width: 36, height: 4, color: AppColors.border),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: rowHeight * 4),
                  child: ListView.builder(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      if (entry.value == null) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          decoration: const BoxDecoration(
                            border: Border(top: _hairline),
                          ),
                          child: Text(
                            entry.header!,
                            style: AppTextStyles.capsLabel,
                          ),
                        );
                      }
                      final value = entry.value!;
                      final isSelected = selected.contains(value);
                      return InkWell(
                        onTap: () {
                          onToggle(value);
                          setSheetState(() {});
                        },
                        child: Container(
                          height: rowHeight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: const BoxDecoration(
                            border: Border(bottom: _hairline),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  value,
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w500
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check,
                                  size: 20,
                                  color: AppColors.deepAccent,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.deepAccent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                      child: Text(doneLabel, style: AppTextStyles.button),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Dropdown-style multi-select field for a flat list of [options]. The parent
/// owns the [selected] list and is notified of toggles via [onToggle].
class MultiSelectField extends StatelessWidget {
  final String placeholder;
  final List<String> selected;
  final List<String> options;
  final ValueChanged<String> onToggle;
  final String doneLabel;

  const MultiSelectField({
    super.key,
    required this.placeholder,
    required this.selected,
    required this.options,
    required this.onToggle,
    required this.doneLabel,
  });

  @override
  Widget build(BuildContext context) {
    final hasSelection = selected.isNotEmpty;
    return _PickerField(
      text: hasSelection ? selected.join(', ') : placeholder,
      isPlaceholder: !hasSelection,
      onTap: () => _showMultiSelectSheet(
        context: context,
        entries: options
            .map((o) => MultiSelectEntry.value(o))
            .toList(growable: false),
        selected: selected,
        onToggle: onToggle,
        doneLabel: doneLabel,
      ),
    );
  }
}

/// Dropdown-style size picker with a per-size stock table that animates in once
/// a size is selected. Preserves the existing per-size stock data structure:
/// emits a list of `{'name': String, 'stock': int}` maps via [onChanged].
class SizeStockField extends StatefulWidget {
  final List<Map<String, dynamic>> initialEntries;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final String placeholder;
  final String doneLabel;
  final String numericGroupLabel;
  final String sizeColumnLabel;
  final String stockColumnLabel;

  const SizeStockField({
    super.key,
    required this.initialEntries,
    required this.onChanged,
    required this.placeholder,
    required this.doneLabel,
    required this.numericGroupLabel,
    required this.sizeColumnLabel,
    required this.stockColumnLabel,
  });

  @override
  State<SizeStockField> createState() => _SizeStockFieldState();
}

class _SizeStockFieldState extends State<SizeStockField> {
  // Selected size names (insertion order). Display/emit order is normalised to
  // the canonical grids via [_orderedSelected].
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

  List<MultiSelectEntry> _sheetEntries() => [
    ...kLetterSizes.map((s) => MultiSelectEntry.value(s)),
    MultiSelectEntry.header(widget.numericGroupLabel),
    ...kNumericSizes.map((s) => MultiSelectEntry.value(s)),
  ];

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selected.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PickerField(
          text: hasSelection
              ? _orderedSelected().join(', ')
              : widget.placeholder,
          isPlaceholder: !hasSelection,
          onTap: () => _showMultiSelectSheet(
            context: context,
            entries: _sheetEntries(),
            selected: _selected,
            onToggle: _toggle,
            doneLabel: widget.doneLabel,
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: hasSelection
              ? Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _stockTable(),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
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
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          ...List.generate(rows.length, (i) {
            final size = rows[i];
            final isLast = i == rows.length - 1;
            // Swipe a row left to remove that size (and its stock field).
            return Dismissible(
              key: ValueKey('size_$size'),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => _toggle(size),
              background: Container(
                color: AppColors.deepAccent,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: const Icon(
                  Icons.delete_outline,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  border: isLast ? null : const Border(bottom: _hairline),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
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
                        textInputAction: TextInputAction.done,
                        onEditingComplete: () =>
                            FocusScope.of(context).unfocus(),
                        textAlign: TextAlign.right,
                        style: AppTextStyles.bodyMedium,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '0',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
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
              ),
            );
          }),
        ],
      ),
    );
  }
}
