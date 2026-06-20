import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../core/constants/countries.dart';
import '../navigation/app_header.dart';
import '../services/currency_service.dart';
import '../widgets/theme.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

// ── Period enum & helpers ─────────────────────────────────────────────────────

enum _RevenuePeriod { today, thisWeek, thisMonth, thisYear, allTime }

// Returns null for allTime — caller skips the Firestore filter
DateTime? _periodStartDate(_RevenuePeriod period) {
  final now = DateTime.now();
  switch (period) {
    case _RevenuePeriod.today:
      return DateTime(now.year, now.month, now.day);
    case _RevenuePeriod.thisWeek:
      final start = now.subtract(Duration(days: now.weekday - 1));
      return DateTime(start.year, start.month, start.day);
    case _RevenuePeriod.thisMonth:
      return DateTime(now.year, now.month, 1);
    case _RevenuePeriod.thisYear:
      return DateTime(now.year, 1, 1);
    case _RevenuePeriod.allTime:
      return null;
  }
}

String _periodLabel(_RevenuePeriod period, AppLocalizations l10n) {
  switch (period) {
    case _RevenuePeriod.today:
      return l10n.today;
    case _RevenuePeriod.thisWeek:
      return l10n.thisWeek;
    case _RevenuePeriod.thisMonth:
      return l10n.thisMonth;
    case _RevenuePeriod.thisYear:
      return l10n.thisYear;
    case _RevenuePeriod.allTime:
      return l10n.allTime;
  }
}

double _sumField(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  String field,
) {
  return docs.fold(0.0, (total, doc) {
    final v = doc.data()[field] ?? 0;
    return total + (v is num ? v.toDouble() : 0);
  });
}

// Builds a date-filtered query for a flat collection
Query<Map<String, dynamic>> _revenueQuery(
  String collection,
  _RevenuePeriod period,
) {
  Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
    collection,
  );
  final startDate = _periodStartDate(period);
  if (startDate != null) {
    q = q.where(
      'createdAt',
      isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
    );
  }
  return q;
}

// ── Page ──────────────────────────────────────────────────────────────────────

class AdminRevenuePage extends StatefulWidget {
  const AdminRevenuePage({super.key});

  @override
  State<AdminRevenuePage> createState() => _AdminRevenuePageState();
}

class _AdminRevenuePageState extends State<AdminRevenuePage> {
  _RevenuePeriod _selectedPeriod = _RevenuePeriod.thisMonth;

  double _commissionsTotal = 0;
  double _promoSlotsTotal = 0;
  bool _isLoading = true;
  bool _hasError = false;

  double get _grandTotal => _commissionsTotal + _promoSlotsTotal;

  @override
  void initState() {
    super.initState();
    _fetchRevenue();
  }

  // Two reads fire in parallel via Future.wait, each filtered server-side
  // by the selected period — no more full-collection reads on every chip tap
  Future<void> _fetchRevenue() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final results = await Future.wait([
        _revenueQuery('global_orders', _selectedPeriod).get(),
        _revenueQuery('promo_slot_payments', _selectedPeriod).get(),
      ]);

      final commissions = _sumField(
        results[0].docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>(),
        'commissionAmount',
      );
      final promoSlots = _sumField(
        results[1].docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>(),
        'amount',
      );

      if (!mounted) return;
      setState(() {
        _commissionsTotal = commissions;
        _promoSlotsTotal = promoSlots;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _selectPeriod(_RevenuePeriod period) {
    setState(() => _selectedPeriod = period);
    _fetchRevenue();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.deepAccent,
                onRefresh: _fetchRevenue,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.revenueBreakdown,
                        style: AppTextStyles.displayMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.revenueBreakdownDescription,
                        style: AppTextStyles.bodySmall,
                      ),
                      const SizedBox(height: 20),

                      // ── Period selector ───────────────────────────
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _RevenuePeriod.values.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final period = _RevenuePeriod.values[index];
                            final isSelected = _selectedPeriod == period;
                            return GestureDetector(
                              onTap: () => _selectPeriod(period),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.deepAccent
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.deepAccent
                                        : AppColors.border,
                                    width: 0.5,
                                  ),
                                ),
                                child: Text(
                                  _periodLabel(period, l10n),
                                  style: AppTextStyles.capsLabel.copyWith(
                                    fontSize: 10,
                                    color: isSelected
                                        ? Colors.white
                                        : AppColors.secondaryText,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 20),

                      if (_isLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 60),
                            child: CircularProgressIndicator(
                              color: AppColors.deepAccent,
                              strokeWidth: 1.5,
                            ),
                          ),
                        )
                      else if (_hasError)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 60),
                            child: Text(
                              l10n.failedToLoadAnalytics,
                              style: AppTextStyles.bodyMedium,
                            ),
                          ),
                        )
                      else ...[
                        // ── Total card ──────────────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            color: AppColors.deepAccent,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.totalRevenue,
                                style: AppTextStyles.capsLabel.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _fmt(_grandTotal),
                                style: AppTextStyles.displayMedium.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _periodLabel(_selectedPeriod, l10n),
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // ── Breakdown cards ─────────────────────────
                        _RevenueCard(
                          icon: Icons.percent_outlined,
                          label: l10n.commissions,
                          subtitle: l10n.commissionsSubtitle,
                          amount: _commissionsTotal,
                          percentage: _grandTotal > 0
                              ? _commissionsTotal / _grandTotal * 100
                              : 0,
                          l10n: l10n,
                        ),
                        _RevenueCard(
                          icon: Icons.campaign_outlined,
                          label: l10n.promoSlots,
                          subtitle: l10n.promoSlotsSubtitle,
                          amount: _promoSlotsTotal,
                          percentage: _grandTotal > 0
                              ? _promoSlotsTotal / _grandTotal * 100
                              : 0,
                          l10n: l10n,
                        ),

                        const SizedBox(height: 20),

                        // ── Promo slot breakdown ────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            border: Border.all(
                              color: AppColors.border,
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.promoSlotTypes,
                                style: AppTextStyles.capsLabel,
                              ),
                              const SizedBox(height: 14),
                              _PromoRow(
                                type: l10n.homepageBanner,
                                pricing: l10n.promoHomepageBannerPricing,
                              ),
                              _PromoRow(
                                type: l10n.featuredBoutiques,
                                pricing: l10n.promoFeaturedBoutiquesPricing,
                              ),
                              _PromoRow(
                                type: l10n.featuredProducts,
                                pricing: l10n.promoFeaturedProductsPricing,
                              ),
                              _PromoRow(
                                type: l10n.searchPlacement,
                                pricing: l10n.promoSearchPlacementPricing,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
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

// ── Revenue card widget ───────────────────────────────────────────────────────

class _RevenueCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final double amount;
  final double percentage;
  final AppLocalizations l10n;

  const _RevenueCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.amount,
    required this.percentage,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.deepAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTextStyles.labelLarge),
                    Text(subtitle, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              Text(
                _fmt(amount),
                style: AppTextStyles.headingSmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                    width: constraints.maxWidth,
                    height: 4,
                    color: AppColors.field,
                  ),
                  Container(
                    width:
                        constraints.maxWidth *
                        (percentage / 100).clamp(0.0, 1.0),
                    height: 4,
                    color: AppColors.deepAccent,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            l10n.percentOfTotalRevenue(percentage.toStringAsFixed(1)),
            style: AppTextStyles.bodySmall.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ── Promo row widget ──────────────────────────────────────────────────────────

class _PromoRow extends StatelessWidget {
  final String type;
  final String pricing;

  const _PromoRow({required this.type, required this.pricing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(type, style: AppTextStyles.bodyMedium)),
          Text(pricing, style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}
