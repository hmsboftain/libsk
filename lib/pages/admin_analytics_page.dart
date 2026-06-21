import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../widgets/error_state_widget.dart';
import '../core/constants/countries.dart';
import '../navigation/app_header.dart';
import '../services/currency_service.dart';
import '../widgets/theme.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

enum AnalyticsFilter { allTime, today, thisWeek, thisMonth }

// ── Pure helpers ──────────────────────────────────────────────────────────────

double _parseTotal(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _countStatus(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  String status,
) {
  return docs
      .where((doc) =>
          doc.data()['status']?.toString().toLowerCase() ==
          status.toLowerCase())
      .length;
}

// Returns null when there are no sales — caller handles display
String? _topBoutiqueName(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final Map<String, double> boutiqueSales = {};
  final Map<String, String> boutiqueNames = {};

  for (final doc in docs) {
    final data = doc.data();
    final total = _parseTotal(data['total']);
    final items = data['items'];
    if (items is! List || items.isEmpty) continue;

    final first = Map<String, dynamic>.from(items.first as Map);
    final boutiqueId = first['boutiqueId']?.toString() ?? '';
    final boutiqueName = first['boutiqueName']?.toString() ?? '';
    if (boutiqueId.isEmpty) continue;

    boutiqueSales[boutiqueId] = (boutiqueSales[boutiqueId] ?? 0) + total;
    boutiqueNames[boutiqueId] = boutiqueName;
  }

  if (boutiqueSales.isEmpty) return null;

  final top =
      boutiqueSales.entries.reduce((a, b) => a.value >= b.value ? a : b);
  return boutiqueNames[top.key];
}

String _filterLabel(AnalyticsFilter filter, AppLocalizations l10n) {
  switch (filter) {
    case AnalyticsFilter.allTime:
      return l10n.allTime;
    case AnalyticsFilter.today:
      return l10n.today;
    case AnalyticsFilter.thisWeek:
      return l10n.thisWeek;
    case AnalyticsFilter.thisMonth:
      return l10n.thisMonth;
  }
}

DateTime _filterStartDate(AnalyticsFilter filter) {
  final now = DateTime.now();
  switch (filter) {
    case AnalyticsFilter.today:
      return DateTime(now.year, now.month, now.day);
    case AnalyticsFilter.thisWeek:
      final start = now.subtract(Duration(days: now.weekday - 1));
      return DateTime(start.year, start.month, start.day);
    case AnalyticsFilter.thisMonth:
      return DateTime(now.year, now.month, 1);
    case AnalyticsFilter.allTime:
      return DateTime(2000); // unused
  }
}

// Builds a Firestore query with both filters applied server-side —
// only matching documents are transferred over the wire.
Query<Map<String, dynamic>> _buildOrdersQuery(AnalyticsFilter filter) {
  Query<Map<String, dynamic>> query = FirebaseFirestore.instance
      .collectionGroup('orders')
      .where('sourceUserOrderId', isNotEqualTo: null);

  if (filter != AnalyticsFilter.allTime) {
    query = query.where(
      'createdAt',
      isGreaterThanOrEqualTo: Timestamp.fromDate(_filterStartDate(filter)),
    );
  }

  return query;
}

// ── Page ──────────────────────────────────────────────────────────────────────

class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key});

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage> {
  AnalyticsFilter _selectedFilter = AnalyticsFilter.allTime;
  late Future<QuerySnapshot<Map<String, dynamic>>> _analyticsFuture;

  @override
  void initState() {
    super.initState();
    _analyticsFuture = _buildOrdersQuery(_selectedFilter).get();
  }

  void _applyFilter(AnalyticsFilter filter) {
    setState(() {
      _selectedFilter = filter;
      _analyticsFuture = _buildOrdersQuery(filter).get();
    });
  }

  Widget _filterChip(AnalyticsFilter filter, AppLocalizations l10n) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () => _applyFilter(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.deepAccent : AppColors.field,
          border: Border.all(
            color: isSelected ? AppColors.deepAccent : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Text(
          _filterLabel(filter, l10n),
          style: AppTextStyles.labelLarge.copyWith(
            color: isSelected ? Colors.white : AppColors.secondaryText,
          ),
        ),
      ),
    );
  }

  Widget _filterBar(AppLocalizations l10n) {
    return SizedBox(
      height: 44,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip(AnalyticsFilter.allTime, l10n),
          const SizedBox(width: 8),
          _filterChip(AnalyticsFilter.today, l10n),
          const SizedBox(width: 8),
          _filterChip(AnalyticsFilter.thisWeek, l10n),
          const SizedBox(width: 8),
          _filterChip(AnalyticsFilter.thisMonth, l10n),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                future: _analyticsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                      ),
                    );
                  }

                  if (snapshot.hasError || !snapshot.hasData) {
                    return ErrorStateWidget.inline(
                      title: l10n.failedToLoadAnalytics,
                      message: l10n.pullDownToRetry,
                      onRetry: () => setState(() {
                        _analyticsFuture =
                            _buildOrdersQuery(_selectedFilter).get();
                      }),
                      type: ErrorType.network,
                    );
                  }

                  final docs = snapshot.data!.docs
                      .cast<QueryDocumentSnapshot<Map<String, dynamic>>>();

                  double totalRevenue = 0;
                  for (final doc in docs) {
                    totalRevenue += _parseTotal(doc.data()['total']);
                  }

                  final totalOrders = docs.length;
                  final averageOrderValue =
                      totalOrders == 0 ? 0.0 : totalRevenue / totalOrders;
                  final placedOrders = _countStatus(docs, 'Placed');
                  final processingOrders = _countStatus(docs, 'Processing');
                  final shippedOrders = _countStatus(docs, 'Shipped');
                  final deliveredOrders = _countStatus(docs, 'Delivered');
                  final topBoutique =
                      _topBoutiqueName(docs) ?? l10n.noSalesYet;

                  return SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.analytics,
                          style: AppTextStyles.displayMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.marketplacePerformanceOverview,
                          style: AppTextStyles.bodyMedium,
                        ),
                        const SizedBox(height: 18),
                        _filterBar(l10n),
                        const SizedBox(height: 22),

                        _AnalyticsCard(
                          title: l10n.totalRevenue,
                          value: _fmt(totalRevenue),
                          icon: Icons.trending_up_rounded,
                          subtitle: _filterLabel(_selectedFilter, l10n),
                        ),
                        const SizedBox(height: 12),
                        _AnalyticsCard(
                          title: l10n.totalOrders,
                          value: totalOrders.toString(),
                          icon: Icons.receipt_long_outlined,
                          subtitle: l10n.ordersInSelectedPeriod,
                        ),
                        const SizedBox(height: 12),
                        _AnalyticsCard(
                          title: l10n.averageOrderValue,
                          value: _fmt(averageOrderValue),
                          icon: Icons.analytics_outlined,
                          subtitle: l10n.revenueDividedByOrderCount,
                        ),
                        const SizedBox(height: 12),
                        _AnalyticsCard(
                          title: l10n.topBoutique,
                          value: topBoutique,
                          icon: Icons.storefront_outlined,
                          subtitle: l10n.basedOnTotalSales,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          l10n.orderStatus,
                          style: AppTextStyles.headingSmall,
                        ),
                        const SizedBox(height: 12),
                        _AnalyticsCard(
                          title: l10n.placedOrders,
                          value: placedOrders.toString(),
                          icon: Icons.shopping_bag_outlined,
                        ),
                        const SizedBox(height: 12),
                        _AnalyticsCard(
                          title: l10n.processingOrders,
                          value: processingOrders.toString(),
                          icon: Icons.sync_outlined,
                        ),
                        const SizedBox(height: 12),
                        _AnalyticsCard(
                          title: l10n.shippedOrders,
                          value: shippedOrders.toString(),
                          icon: Icons.local_shipping_outlined,
                        ),
                        const SizedBox(height: 12),
                        _AnalyticsCard(
                          title: l10n.deliveredOrders,
                          value: deliveredOrders.toString(),
                          icon: Icons.check_circle_outline,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ── Analytics card widget ─────────────────────────────────────────────────────

class _AnalyticsCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final String? subtitle;

  const _AnalyticsCard({
    required this.title,
    required this.value,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.softAccent.withValues(alpha: 0.22),
            child: Icon(icon, color: AppColors.deepAccent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.headingMedium,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: AppTextStyles.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}