import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'theme.dart';

/// Tap-start / tap-end day-range picker for the one bookable week (Sun–Sat).
///
/// Controlled: the parent owns [startDay] / [numDays] and receives every change
/// through [onChanged]. The picker enforces a CONTIGUOUS run — a second tap that
/// would span a sold-out day instead starts a fresh selection at that day.
///
/// Each day shows its real date and the remaining capacity for this placement;
/// sold-out days (or days that would break this boutique's per-day limits) are
/// disabled. Availability is decided by the caller via [isDayOpen] so the same
/// widget serves the simple placements and the per-category one.
class PromoWeekPicker extends StatefulWidget {
  /// Sunday 00:00 of the bookable week (from getPromoAvailability.weekStart).
  final DateTime weekStart;

  /// Whether day [index] (Sun=0 … Sat=6) can be part of a selection.
  final bool Function(int day) isDayOpen;

  /// Remaining capacity to show inside day [index]; null hides the number.
  final int? Function(int day) remainingFor;

  final int? startDay;
  final int? numDays;
  final void Function(int startDay, int numDays) onChanged;

  const PromoWeekPicker({
    super.key,
    required this.weekStart,
    required this.isDayOpen,
    required this.remainingFor,
    required this.startDay,
    required this.numDays,
    required this.onChanged,
  });

  @override
  State<PromoWeekPicker> createState() => _PromoWeekPickerState();
}

class _PromoWeekPickerState extends State<PromoWeekPicker> {
  /// First tap of an in-progress two-tap sequence; null once a range is settled.
  int? _anchor;

  bool _selected(int day) {
    final s = widget.startDay, n = widget.numDays;
    if (s == null || n == null) return false;
    return day >= s && day < s + n;
  }

  bool _rangeOpen(int a, int b) {
    for (var d = a; d <= b; d++) {
      if (!widget.isDayOpen(d)) return false;
    }
    return true;
  }

  void _tap(int day) {
    if (!widget.isDayOpen(day)) return;
    final anchor = _anchor;
    if (anchor == null) {
      // Start a new selection at this day.
      setState(() => _anchor = day);
      widget.onChanged(day, 1);
      return;
    }
    final lo = day < anchor ? day : anchor;
    final hi = day < anchor ? anchor : day;
    if (_rangeOpen(lo, hi)) {
      setState(() => _anchor = null); // settled
      widget.onChanged(lo, hi - lo + 1);
    } else {
      // Would span a closed day — restart from here instead.
      setState(() => _anchor = day);
      widget.onChanged(day, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dow = DateFormat.E(locale);
    final dnum = DateFormat.d(locale);
    return Row(
      children: [
        for (var d = 0; d < 7; d++) ...[
          Expanded(child: _cell(d, dow, dnum)),
          if (d < 6) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _cell(int day, DateFormat dow, DateFormat dnum) {
    final date = widget.weekStart.add(Duration(days: day));
    final open = widget.isDayOpen(day);
    final selected = _selected(day);
    final remaining = widget.remainingFor(day);

    final Color bg;
    final Color fg;
    final Color border;
    if (selected) {
      bg = AppColors.deepAccent;
      fg = Colors.white;
      border = AppColors.deepAccent;
    } else if (!open) {
      bg = AppColors.disabledField;
      fg = AppColors.softAccent;
      border = AppColors.disabledField;
    } else {
      bg = AppColors.card;
      fg = AppColors.primaryText;
      border = AppColors.border;
    }

    return GestureDetector(
      onTap: open ? () => _tap(day) : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(color: bg, border: Border.all(color: border)),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(
              dow.format(date),
              style: AppTextStyles.labelSmall.copyWith(
                color: selected ? Colors.white70 : AppColors.secondaryText,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              dnum.format(date),
              style: AppTextStyles.bodyMedium.copyWith(
                color: fg,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 12,
              child: !open
                  ? Icon(Icons.remove, size: 11, color: fg)
                  : (remaining == null
                        ? const SizedBox.shrink()
                        : Text(
                            '$remaining',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: selected ? Colors.white70 : AppColors.secondaryText,
                              fontSize: 10,
                            ),
                          )),
            ),
          ],
        ),
      ),
    );
  }
}
