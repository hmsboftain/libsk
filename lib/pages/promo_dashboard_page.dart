import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:libsk/l10n/app_localizations.dart';

import '../models/promo_availability.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';
import 'promo_placement_booking_page.dart';

/// The boutique owner's promotions hub: a "Book" tab (availability browser for
/// the upcoming week across all 5 placements) and a "My bookings" tab
/// (active/upcoming/past bookings). Replaces the interim single-placement
/// launcher.
class PromoDashboardPage extends StatefulWidget {
  const PromoDashboardPage({super.key});

  @override
  State<PromoDashboardPage> createState() => _PromoDashboardPageState();
}

/// Placement order shown in the hub. feed_sponsored last (it's the odd one out —
/// weekly, no dates).
const List<String> _placementOrder = [
  'home_banner',
  'featured_product',
  'featured_boutique',
  'top_of_category',
  'feed_sponsored',
];

String _placementLabel(AppLocalizations l10n, String type) {
  switch (type) {
    case 'home_banner':
      return l10n.promoPlacementHomeBanner;
    case 'featured_product':
      return l10n.promoPlacementFeaturedProduct;
    case 'featured_boutique':
      return l10n.promoPlacementFeaturedBoutique;
    case 'top_of_category':
      return l10n.promoPlacementTopOfCategory;
    case 'feed_sponsored':
      return l10n.promoPlacementFeedSponsored;
    default:
      return type;
  }
}

IconData _placementIcon(String type) {
  switch (type) {
    case 'home_banner':
      return Icons.view_carousel_outlined;
    case 'featured_product':
      return Icons.star_outline;
    case 'featured_boutique':
      return Icons.storefront_outlined;
    case 'top_of_category':
      return Icons.category_outlined;
    case 'feed_sponsored':
      return Icons.dynamic_feed_outlined;
    default:
      return Icons.campaign_outlined;
  }
}

class _PromoDashboardPageState extends State<PromoDashboardPage> {
  String? _boutiqueId;
  PromoAvailability? _availability;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final boutiqueId = await FirestoreService.getCurrentOwnerBoutiqueId();
      final availability = await FirestoreService.getPromoAvailability();
      if (!mounted) return;
      setState(() {
        _boutiqueId = boutiqueId;
        _availability = availability;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          foregroundColor: AppColors.primaryText,
          title: Text(l10n.promotions, style: AppTextStyles.labelLarge),
          bottom: TabBar(
            labelColor: AppColors.primaryText,
            unselectedLabelColor: AppColors.secondaryText,
            indicatorColor: AppColors.deepAccent,
            labelStyle: AppTextStyles.labelLarge,
            tabs: [
              Tab(text: l10n.promoTabBook),
              Tab(text: l10n.promoTabMyBookings),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildBookTab(l10n),
            const _MyBookingsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildBookTab(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _availability == null || _boutiqueId == null) {
      return _ErrorRetry(message: _error ?? l10n.somethingWentWrong, onRetry: _load);
    }
    final a = _availability!;
    // weekEnd is exclusive (the following Sunday), so the last bookable day is
    // the day before — Saturday, in Kuwait's Sun–Sat week.
    final lastDay = a.weekEnd.subtract(const Duration(days: 1));
    final locale = Localizations.localeOf(context).toLanguageTag();
    final range =
        '${DateFormat('EEE d', locale).format(a.weekStart)} – ${DateFormat('EEE d MMM', locale).format(lastDay)}';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Text(l10n.promoUpcomingWeek, style: AppTextStyles.headingSmall),
          const SizedBox(height: 4),
          Text(
            range,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 16),
          for (final type in _placementOrder)
            if (a.placement(type) != null)
              _PlacementCard(
                type: type,
                label: _placementLabel(l10n, type),
                placement: a.placement(type)!,
                globalRemainingPerDay: a.globalRemainingPerDay,
                onBook: () => _openBooking(type, a),
              ),
        ],
      ),
    );
  }

  Future<void> _openBooking(String type, PromoAvailability a) async {
    final l10n = AppLocalizations.of(context)!;
    final booked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PromoPlacementBookingPage(
          boutiqueId: _boutiqueId!,
          placementType: type,
          placementLabel: _placementLabel(l10n, type),
          placement: a.placement(type)!,
          weekStart: a.weekStart,
          globalRemainingPerDay: a.globalRemainingPerDay,
          promoCreditBalance: a.promoCreditBalance,
        ),
      ),
    );
    if (booked == true) _load(); // refresh occupancy after a successful booking
  }
}

class _PlacementCard extends StatelessWidget {
  final String type;
  final String label;
  final PromoPlacement placement;
  final List<int> globalRemainingPerDay;
  final VoidCallback onBook;

  const _PlacementCard({
    required this.type,
    required this.label,
    required this.placement,
    required this.globalRemainingPerDay,
    required this.onBook,
  });

  bool get _soldOut {
    if (!placement.dayBased || placement.perCategory) return false;
    for (var d = 0; d < 7; d++) {
      if (placement.normalDayOpen(d,
          globalRemainingPerDay: globalRemainingPerDay)) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final daily = placement.priceForDays(1);
    final weekly = placement.priceForDays(7);

    final String priceLine;
    if (placement.dayBased && daily != null && weekly != null) {
      priceLine = l10n.promoRateLine(
        daily.toStringAsFixed(3),
        weekly.toStringAsFixed(3),
      );
    } else {
      final p1 = placement.priceForPosts(1);
      final p2 = placement.priceForPosts(2);
      priceLine = (p1 != null && p2 != null)
          ? l10n.promoFeedRateLine(p1.toStringAsFixed(3), p2.toStringAsFixed(3))
          : '';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: InkWell(
        onTap: onBook,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_placementIcon(type),
                      size: 20, color: AppColors.deepAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (type == 'home_banner')
                    _tag(l10n.promoNeedsApproval),
                  const Icon(Icons.chevron_right, color: AppColors.secondaryText),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                priceLine,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: 10),
              _availabilityRow(l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _availabilityRow(AppLocalizations l10n) {
    if (!placement.dayBased) {
      return _note(l10n.promoFeedWeekNote);
    }
    if (placement.perCategory) {
      return _note(l10n.promoByCategoryNote);
    }
    if (_soldOut) {
      return _note(l10n.promoSoldOutWeek, danger: true);
    }
    // Compact remaining strip, Sun–Sat.
    return Row(
      children: [
        for (var d = 0; d < 7; d++) ...[
          Expanded(child: _dayPip(d)),
          if (d < 6) const SizedBox(width: 4),
        ],
      ],
    );
  }

  Widget _dayPip(int day) {
    final open = placement.normalDayOpen(day,
        globalRemainingPerDay: globalRemainingPerDay);
    final remaining =
        day < placement.remainingPerDay.length ? placement.remainingPerDay[day] : 0;
    final low = open && remaining <= 1;
    final Color bg = !open
        ? AppColors.disabledField
        : low
            ? AppColors.selectedSoft
            : AppColors.field;
    return Container(
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Text(
        open ? '$remaining' : '·',
        style: AppTextStyles.labelSmall.copyWith(
          fontSize: 10,
          color: open ? AppColors.secondaryText : AppColors.softAccent,
        ),
      ),
    );
  }

  Widget _note(String text, {bool danger = false}) => Text(
        text,
        style: AppTextStyles.labelSmall.copyWith(
          color: danger ? AppColors.deepAccent : AppColors.secondaryText,
        ),
      );

  Widget _tag(String text) => Container(
        margin: const EdgeInsetsDirectional.only(end: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
        child: Text(
          text,
          style: AppTextStyles.labelSmall.copyWith(
            fontSize: 10,
            color: AppColors.secondaryText,
          ),
        ),
      );
}

class _MyBookingsTab extends StatelessWidget {
  const _MyBookingsTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<Stream<QuerySnapshot<Map<String, dynamic>>>?>(
      future: FirestoreService.getMyPromoBookingsStream(),
      builder: (context, streamSnap) {
        if (streamSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final stream = streamSnap.data;
        if (stream == null) {
          return _empty(l10n.promoNoBookings);
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) return _empty(l10n.promoNoBookings);

            // Current (active/upcoming/awaiting) vs past (expired/rejected/etc).
            const current = {'active', 'paid_pending_review', 'pending_payment'};
            final currentDocs = docs
                .where((d) => current.contains(d.data()['status']))
                .toList()
              ..sort(_byDayStart);
            final pastDocs = docs
                .where((d) => !current.contains(d.data()['status']))
                .toList()
              ..sort((a, b) => _byDayStart(b, a));

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                if (currentDocs.isNotEmpty) ...[
                  _groupHeader(l10n.promoGroupCurrent),
                  for (final d in currentDocs)
                    _BookingRow(data: d.data(), locale: _locale(context)),
                ],
                if (pastDocs.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _groupHeader(l10n.promoGroupPast),
                  for (final d in pastDocs)
                    _BookingRow(data: d.data(), locale: _locale(context)),
                ],
              ],
            );
          },
        );
      },
    );
  }

  String _locale(BuildContext context) =>
      Localizations.localeOf(context).toLanguageTag();

  static int _byDayStart(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final ta = a.data()['dayStart'];
    final tb = b.data()['dayStart'];
    final ma = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
    final mb = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
    return ma.compareTo(mb);
  }

  Widget _groupHeader(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: AppTextStyles.headingSmall),
      );

  Widget _empty(String text) => Center(
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
}

class _BookingRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final String locale;

  const _BookingRow({required this.data, required this.locale});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final type = data['placementType']?.toString() ?? '';
    final status = data['status']?.toString() ?? '';
    final price = (data['priceKwd'] as num?)?.toDouble();

    final dayStart = data['dayStart'];
    final dayEnd = data['dayEnd'];
    String window = '';
    if (dayStart is Timestamp && dayEnd is Timestamp) {
      final start = dayStart.toDate();
      final lastDay = dayEnd.toDate().subtract(const Duration(days: 1));
      window =
          '${DateFormat('EEE d', locale).format(start)} – ${DateFormat('EEE d MMM', locale).format(lastDay)}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_placementIcon(type), size: 18, color: AppColors.deepAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _placementLabel(l10n, type),
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _StatusChip(status: status),
            ],
          ),
          if (window.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              window,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
          ],
          if (price != null) ...[
            const SizedBox(height: 2),
            Text(
              l10n.promoPriceKwd(price.toStringAsFixed(3)),
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
          ],
          if (status == 'rejected' && (data['rejectionReason'] ?? '') != '') ...[
            const SizedBox(height: 6),
            Text(
              data['rejectionReason'].toString(),
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

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final String label;
    switch (status) {
      case 'active':
        label = l10n.promoStatusActive;
      case 'paid_pending_review':
        label = l10n.promoStatusPendingReview;
      case 'pending_payment':
        label = l10n.promoStatusAwaitingPayment;
      case 'rejected':
        label = l10n.promoStatusRejected;
      case 'cancelled':
        label = l10n.promoStatusCancelled;
      case 'expired':
      default:
        label = l10n.promoStatusExpired;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.field,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          fontSize: 10,
          color: AppColors.secondaryText,
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: Text(l10n.tryAgain,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.deepAccent,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
