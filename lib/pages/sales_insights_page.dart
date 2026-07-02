import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/utils/image_sizing.dart';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';
import '../core/constants/countries.dart';
import '../services/currency_service.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

// ── Pure helpers ──────────────────────────────────────────────────────────────

double _orderTotal(Map<String, dynamic> data) {
  final v = data['total'];
  return v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
}

String _formatKwd(double value) => _fmt(value);

// ── Page ──────────────────────────────────────────────────────────────────────

class SalesInsightsPage extends StatefulWidget {
  final String boutiqueId;
  const SalesInsightsPage({super.key, required this.boutiqueId});

  @override
  State<SalesInsightsPage> createState() => _SalesInsightsPageState();
}

class _SalesInsightsPageState extends State<SalesInsightsPage> {
  bool _isLoading = true;

  double _totalRevenue = 0;
  double _thisWeekRevenue = 0;
  double _lastWeekRevenue = 0;
  int _totalOrders = 0;
  int _thisWeekOrders = 0;

  List<Product> _topSellers = [];
  List<Product> _leastSellers = [];

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    setState(() => _isLoading = true);

    try {
      // Fetch orders and products in parallel
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('boutiques')
            .doc(widget.boutiqueId)
            .collection('orders')
            .get(),
        FirestoreService.getOwnerProductsStream(widget.boutiqueId).first,
      ]);

      final orderSnap = results[0];
      final productSnap = results[1];

      // Revenue calculations
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final startOfWeek = startOfToday.subtract(
        Duration(days: startOfToday.weekday - 1),
      );
      final startOfLastWeek = startOfWeek.subtract(const Duration(days: 7));

      double total = 0;
      double thisWeek = 0;
      double lastWeek = 0;

      for (final doc in orderSnap.docs) {
        final data = doc.data();
        final amount = _orderTotal(data);
        total += amount;

        final createdAt = data['createdAt'];
        if (createdAt is Timestamp) {
          final date = createdAt.toDate();
          if (!date.isBefore(startOfWeek)) {
            thisWeek += amount;
          } else if (!date.isBefore(startOfLastWeek)) {
            lastWeek += amount;
          }
        }
      }

      // Count this week's orders
      int weekOrders = 0;
      for (final doc in orderSnap.docs) {
        final createdAt = doc.data()['createdAt'];
        if (createdAt is Timestamp &&
            !createdAt.toDate().isBefore(startOfWeek)) {
          weekOrders++;
        }
      }

      // Product performance by salesCount
      final products = productSnap.docs
          .map((doc) => Product.fromFirestore(doc))
          .toList();

      // Top sellers: highest salesCount first
      final withSales = products.where((p) {
        // salesCount lives on the raw doc, not the Product model
        final doc = productSnap.docs.firstWhere((d) => d.id == p.id);
        final sc = doc.data()['salesCount'];
        return sc is num && sc > 0;
      }).toList();

      withSales.sort((a, b) {
        final aDoc = productSnap.docs.firstWhere((d) => d.id == a.id);
        final bDoc = productSnap.docs.firstWhere((d) => d.id == b.id);
        final aSales = (aDoc.data()['salesCount'] as num?) ?? 0;
        final bSales = (bDoc.data()['salesCount'] as num?) ?? 0;
        return bSales.compareTo(aSales);
      });

      // Least sellers: products with lowest salesCount (including 0)
      final allSorted = List<Product>.from(products);
      allSorted.sort((a, b) {
        final aDoc = productSnap.docs.firstWhere((d) => d.id == a.id);
        final bDoc = productSnap.docs.firstWhere((d) => d.id == b.id);
        final aSales = (aDoc.data()['salesCount'] as num?) ?? 0;
        final bSales = (bDoc.data()['salesCount'] as num?) ?? 0;
        return aSales.compareTo(bSales);
      });

      if (!mounted) return;
      setState(() {
        _totalRevenue = total;
        _thisWeekRevenue = thisWeek;
        _lastWeekRevenue = lastWeek;
        _totalOrders = orderSnap.docs.length;
        _thisWeekOrders = weekOrders;
        _topSellers = withSales.take(5).toList();
        _leastSellers = allSorted.take(5).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('SALES INSIGHTS ERROR: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  double get _weekChange {
    if (_lastWeekRevenue == 0) return _thisWeekRevenue > 0 ? 100 : 0;
    return ((_thisWeekRevenue - _lastWeekRevenue) / _lastWeekRevenue) * 100;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                        strokeWidth: 1.5,
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.deepAccent,
                      onRefresh: _loadInsights,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sales Insights',
                              style: AppTextStyles.displayMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'How your boutique is performing',
                              style: AppTextStyles.bodySmall,
                            ),
                            const SizedBox(height: 24),

                            // ── Revenue overview ──────────────────────
                            _buildRevenueCards(),
                            const SizedBox(height: 14),
                            _buildWeekComparison(),

                            const SizedBox(height: 28),

                            // ── Top sellers ───────────────────────────
                            Text(
                              'Top Sellers',
                              style: AppTextStyles.headingSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Products with the most sales',
                              style: AppTextStyles.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            _topSellers.isEmpty
                                ? _emptySection('No sales yet')
                                : Column(
                                    children: _topSellers
                                        .map(
                                          (p) => _ProductRankCard(
                                            product: p,
                                            metricLabel: 'sold',
                                          ),
                                        )
                                        .toList(),
                                  ),

                            const SizedBox(height: 28),

                            // ── Least sellers ─────────────────────────
                            Text(
                              'Needs Attention',
                              style: AppTextStyles.headingSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Products with the fewest sales',
                              style: AppTextStyles.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            _leastSellers.isEmpty
                                ? _emptySection('No products yet')
                                : Column(
                                    children: _leastSellers
                                        .map(
                                          (p) => _ProductRankCard(
                                            product: p,
                                            metricLabel: 'sold',
                                            isLow: true,
                                          ),
                                        )
                                        .toList(),
                                  ),
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

  Widget _buildRevenueCards() {
    return Row(
      children: [
        Expanded(
          child: _InsightCard(
            title: 'Total Revenue',
            value: _formatKwd(_totalRevenue),
            subtitle: '$_totalOrders orders',
            icon: Icons.account_balance_wallet_outlined,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _InsightCard(
            title: 'This Week',
            value: _formatKwd(_thisWeekRevenue),
            subtitle: '$_thisWeekOrders orders',
            icon: Icons.trending_up_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildWeekComparison() {
    final change = _weekChange;
    final isUp = change > 0;
    final isDown = change < 0;
    final changeText = isUp
        ? '+${change.toStringAsFixed(0)}%'
        : isDown
        ? '${change.toStringAsFixed(0)}%'
        : '0%';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(
            isUp
                ? Icons.arrow_upward_rounded
                : isDown
                ? Icons.arrow_downward_rounded
                : Icons.remove_rounded,
            size: 20,
            color: AppColors.deepAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$changeText vs last week',
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            'Last week: ${_formatKwd(_lastWeekRevenue)}',
            style: AppTextStyles.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _emptySection(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Center(
        child: Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.secondaryText,
          ),
        ),
      ),
    );
  }
}

// ── Insight card widget ───────────────────────────────────────────────────────

class _InsightCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  const _InsightCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.softAccent.withValues(alpha: 0.22),
            child: Icon(icon, color: AppColors.deepAccent, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: AppTextStyles.labelLarge.copyWith(
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(value, style: AppTextStyles.headingLarge),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.secondaryText,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Product rank card widget ──────────────────────────────────────────────────

class _ProductRankCard extends StatelessWidget {
  final Product product;
  final String metricLabel;
  final bool isLow;

  const _ProductRankCard({
    required this.product,
    required this.metricLabel,
    this.isLow = false,
  });

  @override
  Widget build(BuildContext context) {
    final title = product.title.isNotEmpty ? product.title : 'Untitled product';
    final imageUrl = product.displayImageUrl;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.imagePlaceholder,
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    memCacheWidth: gridTileCacheWidth,
                    maxWidthDiskCache: maxImageDiskCacheWidth,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: AppColors.imagePlaceholder),
                    errorWidget: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: AppColors.softAccent,
                        size: 18,
                      ),
                    ),
                  )
                : const Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: AppColors.softAccent,
                      size: 18,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _fmt(product.price),
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
          if (isLow)
            Icon(
              Icons.arrow_downward_rounded,
              size: 16,
              color: AppColors.secondaryText,
            ),
        ],
      ),
    );
  }
}
