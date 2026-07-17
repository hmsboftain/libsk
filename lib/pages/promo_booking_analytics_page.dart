import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:libsk/l10n/app_localizations.dart';

import '../navigation/app_header.dart';
import '../widgets/theme.dart';

/// What a boutique owner sees about ONE booking they paid for: did anyone tap
/// it, and did those taps turn into sales?
///
/// Everything on this page comes from the `stats` rollup already on the booking
/// document plus its `attributed_sales` subcollection — the raw click log is
/// server-only and is never read here. Opening this page therefore costs one
/// document the dashboard already had, plus a small subcollection read.
///
/// Deliberately NOT shown: impressions, and therefore no click-through rate.
/// Views aren't tracked (see the analytics section header in functions/index.js),
/// so "conversion" here means orders per click and the UI says so rather than
/// letting an owner read it as CTR.

// ── Pure presentation logic (unit-tested in test/promo_analytics_page_test.dart) ──

/// Fils → KWD. The server stores attributed revenue in fils to keep the
/// arithmetic integral, exactly like the credit ledger.
double filsToKwd(int fils) => fils / 1000.0;

/// Orders per click. Null when there are no clicks — a rate with a zero
/// denominator is undefined, and showing "0%" would read as "this ad converts
/// terribly" when the truth is "nobody has clicked it yet".
double? conversionRate({required int clicks, required int orders}) {
  if (clicks <= 0) return null;
  return orders / clicks;
}

/// Net position of the booking: attributed revenue minus what the ad cost.
double netKwd({required int attributedRevenueFils, required double adSpendKwd}) =>
    filsToKwd(attributedRevenueFils) - adSpendKwd;

/// One bar of the sparkline.
@immutable
class DayCount {
  final String day; // "YYYY-MM-DD", Kuwait calendar
  final int clicks;
  const DayCount(this.day, this.clicks);
}

/// Expand `stats.clicksByDay` into one entry per booked day, in order.
///
/// Days the booking ran but nobody clicked MUST still appear, as zeroes: a gap
/// in the row is information ("Thursday did nothing"), whereas silently omitting
/// it would misrepresent a quiet day as a day that never ran.
///
/// [dayStart] is inclusive and [dayEnd] exclusive, matching the booking.
List<DayCount> clicksByDaySeries({
  required Map<String, dynamic>? clicksByDay,
  required DateTime dayStart,
  required DateTime dayEnd,
}) {
  const kuwaitOffset = Duration(hours: 3);
  // Walk the window on Kuwait's calendar, since that is how the days were sold
  // and how the server bucketed the counts.
  var cursor = dayStart.toUtc().add(kuwaitOffset);
  final end = dayEnd.toUtc().add(kuwaitOffset);
  final out = <DayCount>[];
  // A booking spans at most 7 days; the guard is belt-and-braces against a
  // malformed window rather than a real bound.
  while (cursor.isBefore(end) && out.length < 31) {
    final key = DateFormat('yyyy-MM-dd').format(cursor);
    final raw = clicksByDay?[key];
    out.add(DayCount(key, raw is num ? raw.toInt() : 0));
    cursor = cursor.add(const Duration(days: 1));
  }
  return out;
}

/// Can this booking have performance to show at all?
///
/// A booking that never rendered has no clicks by construction, and showing it
/// an empty dashboard would read as "your ad failed" rather than "your ad never
/// ran". `renderingApplied` is the server's own record of having put it on
/// screen, so it is the honest gate.
bool bookingHasRun(Map<String, dynamic> booking) =>
    booking['renderingApplied'] == true;

/// Live now, versus finished.
bool bookingIsRunning(Map<String, dynamic> booking, DateTime now) {
  final end = booking['dayEnd'] ?? booking['weekEnd'];
  if (end is! Timestamp) return false;
  return bookingHasRun(booking) && end.toDate().isAfter(now);
}

// ── Page ──────────────────────────────────────────────────────────────────────

class PromoBookingAnalyticsPage extends StatelessWidget {
  final String bookingId;
  final String boutiqueId;

  const PromoBookingAnalyticsPage({
    super.key,
    required this.bookingId,
    required this.boutiqueId,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              // Live: a click landing while the owner watches updates in place.
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('promo_bookings')
                    .doc(bookingId)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                        strokeWidth: 1.5,
                      ),
                    );
                  }
                  final data = snap.data?.data();
                  if (data == null) {
                    return _note(l10n.promoAnalyticsNeverRan);
                  }
                  return _body(context, l10n, data);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    Map<String, dynamic> booking,
  ) {
    final locale = Localizations.localeOf(context).toLanguageTag();

    if (!bookingHasRun(booking)) {
      // Distinguish "not yet" from "never" — an owner reading an empty page
      // deserves to know which.
      final status = booking['status']?.toString() ?? '';
      const deadStatuses = {'cancelled', 'expired', 'rejected'};
      return _note(deadStatuses.contains(status)
          ? l10n.promoAnalyticsNeverRan
          : l10n.promoAnalyticsNotRunYet);
    }

    final stats = booking['stats'];
    final statsMap = stats is Map ? Map<String, dynamic>.from(stats) : const {};
    final clicks = (statsMap['clicks'] as num?)?.toInt() ?? 0;
    final orders = (statsMap['attributedOrders'] as num?)?.toInt() ?? 0;
    final revenueFils =
        (statsMap['attributedRevenueFils'] as num?)?.toInt() ?? 0;
    final adSpend = (booking['priceKwd'] as num?)?.toDouble() ?? 0;
    final conversion = conversionRate(clicks: clicks, orders: orders);
    final net = netKwd(attributedRevenueFils: revenueFils, adSpendKwd: adSpend);

    final rawByDay = statsMap['clicksByDay'];
    final series = clicksByDaySeries(
      clicksByDay: rawByDay is Map ? Map<String, dynamic>.from(rawByDay) : null,
      dayStart: (booking['dayStart'] as Timestamp?)?.toDate() ??
          DateTime.now().toUtc(),
      dayEnd: (booking['dayEnd'] as Timestamp?)?.toDate() ??
          DateTime.now().toUtc(),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Text(l10n.promoAnalyticsTitle, style: AppTextStyles.displayMedium),
        const SizedBox(height: 4),
        Text(
          _window(booking, locale),
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.secondaryText,
          ),
        ),
        const SizedBox(height: 18),

        Row(
          children: [
            Expanded(
              child: _Metric(
                label: l10n.promoAnalyticsClicks,
                value: '$clicks',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Metric(
                label: l10n.promoAnalyticsOrders,
                value: '$orders',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: l10n.promoAnalyticsRevenue,
                value: filsToKwd(revenueFils).toStringAsFixed(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Metric(
                label: l10n.promoAnalyticsAdSpend,
                value: adSpend.toStringAsFixed(3),
              ),
            ),
          ],
        ),

        // The bottom line an owner actually came for: did this ad pay for
        // itself? Only meaningful once something has been attributed.
        if (orders > 0) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            color: AppColors.card,
            child: Text(
              net >= 0
                  ? l10n.promoAnalyticsNetPositive(net.toStringAsFixed(3))
                  : l10n.promoAnalyticsNetNegative((-net).toStringAsFixed(3)),
              style: AppTextStyles.bodyMedium.copyWith(
                color: net >= 0 ? AppColors.deepAccent : AppColors.secondaryText,
              ),
            ),
          ),
        ],

        const SizedBox(height: 10),
        _Metric(
          label: l10n.promoAnalyticsConversion,
          value: conversion == null
              ? '—'
              : '${(conversion * 100).toStringAsFixed(0)}%',
          hint: l10n.promoAnalyticsNoImpressionsNote,
        ),

        const SizedBox(height: 22),
        Text(l10n.promoAnalyticsClicksByDay, style: AppTextStyles.headingSmall),
        const SizedBox(height: 10),
        if (clicks == 0)
          _muted(l10n.promoAnalyticsNoClicksYet)
        else
          _Sparkline(series: series, locale: locale),
        const SizedBox(height: 8),
        _muted(l10n.promoAnalyticsClickNote),

        const SizedBox(height: 22),
        Text(
          l10n.promoAnalyticsAttributedOrders,
          style: AppTextStyles.headingSmall,
        ),
        const SizedBox(height: 10),
        _AttributedSales(bookingId: bookingId, locale: locale),
        const SizedBox(height: 8),
        _muted(l10n.promoAnalyticsAttributionNote),
      ],
    );
  }

  String _window(Map<String, dynamic> booking, String locale) {
    final start = booking['dayStart'];
    final end = booking['dayEnd'];
    if (start is! Timestamp || end is! Timestamp) return '';
    final lastDay = end.toDate().subtract(const Duration(days: 1));
    return '${DateFormat('EEE d', locale).format(start.toDate())} – '
        '${DateFormat('EEE d MMM', locale).format(lastDay)}';
  }

  Widget _note(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.secondaryText,
            ),
          ),
        ),
      );

  static Widget _muted(String text) => Text(
        text,
        style: AppTextStyles.labelSmall.copyWith(color: AppColors.secondaryText),
      );
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;

  const _Metric({required this.label, required this.value, this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: AppTextStyles.capsLabel),
          const SizedBox(height: 6),
          Text(value, style: AppTextStyles.displayMedium.copyWith(fontSize: 24)),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bar-per-day clicks. Bars are proportional to the busiest day; a zero day
/// renders as a visible baseline rather than nothing, so "ran but quiet" reads
/// differently from "didn't run".
class _Sparkline extends StatelessWidget {
  final List<DayCount> series;
  final String locale;

  const _Sparkline({required this.series, required this.locale});

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) return const SizedBox.shrink();
    final max = series.map((d) => d.clicks).reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in series)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${d.clicks}', style: AppTextStyles.labelSmall),
                    const SizedBox(height: 4),
                    Container(
                      height: max == 0 ? 2 : (d.clicks / max) * 56 + 2,
                      decoration: BoxDecoration(
                        color: d.clicks == 0
                            ? AppColors.border
                            : AppColors.deepAccent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _dayLabel(d.day),
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _dayLabel(String isoDay) {
    final parsed = DateTime.tryParse(isoDay);
    if (parsed == null) return '';
    return DateFormat('E', locale).format(parsed);
  }
}

/// The orders this ad actually drove. Reads the booking's attributed_sales
/// subcollection, which the security rules expose to this boutique's owner only.
class _AttributedSales extends StatelessWidget {
  final String bookingId;
  final String locale;

  const _AttributedSales({required this.bookingId, required this.locale});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('promo_bookings')
          .doc(bookingId)
          .collection('attributed_sales')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 40,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: AppColors.deepAccent,
                  strokeWidth: 1.5,
                ),
              ),
            ),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return PromoBookingAnalyticsPage._muted(l10n.promoAnalyticsNoOrdersYet);
        }
        // Newest first.
        final sorted = docs.toList()
          ..sort((a, b) {
            final ta = a.data()['attributedAt'];
            final tb = b.data()['attributedAt'];
            final ma = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
            final mb = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
            return mb.compareTo(ma);
          });

        return Column(
          children: [
            for (final d in sorted) _saleRow(context, l10n, d.data()),
          ],
        );
      },
    );
  }

  Widget _saleRow(
    BuildContext context,
    AppLocalizations l10n,
    Map<String, dynamic> sale,
  ) {
    // A reversed sale stays listed rather than vanishing: an owner who saw an
    // order yesterday deserves to see it was refunded, not silently lose it.
    final reversed = sale['reversed'] == true;
    final revenue = (sale['revenueFils'] as num?)?.toInt() ?? 0;
    final at = sale['attributedAt'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.promoAnalyticsOrderNumber(
                    sale['orderNumber']?.toString() ?? '—',
                  ),
                  style: AppTextStyles.bodyMedium,
                ),
                if (at is Timestamp) ...[
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('d MMM, HH:mm', locale).format(at.toDate()),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                filsToKwd(revenue).toStringAsFixed(3),
                style: AppTextStyles.bodyMedium.copyWith(
                  color: reversed
                      ? AppColors.secondaryText
                      : AppColors.primaryText,
                  decoration: reversed ? TextDecoration.lineThrough : null,
                ),
              ),
              if (reversed) ...[
                const SizedBox(height: 2),
                Text(
                  l10n.promoAnalyticsReturnedOrder,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
