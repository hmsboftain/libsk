import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';
import '../core/constants/countries.dart';
import '../services/currency_service.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

// ── Pure helpers ──────────────────────────────────────────────────────────────

double _parseTotal(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value.toString()) ?? 0;
}

String _buildOrderNumber(Map<String, dynamic> data, AppLocalizations l10n) {
  final value = data['orderNumber']?.toString().trim() ?? '';
  return value.isNotEmpty ? value : l10n.unknownOrder;
}

String _buildDate(Map<String, dynamic> data, AppLocalizations l10n) {
  final value = data['date']?.toString().trim() ?? '';
  return value.isNotEmpty ? value : l10n.noDate;
}

Map<String, dynamic> _buildBestSellingItem(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> orderDocs,
  AppLocalizations l10n,
) {
  final Map<String, Map<String, dynamic>> salesMap = {};

  for (final doc in orderDocs) {
    final data = doc.data();
    final rawItems = data['items'];

    if (rawItems is List) {
      for (final rawItem in rawItems) {
        if (rawItem is Map) {
          final item = Map<String, dynamic>.from(rawItem);
          final title = item['title']?.toString() ?? l10n.untitledProduct;
          final quantity = _parseInt(item['quantity']);

          if (!salesMap.containsKey(title)) {
            salesMap[title] = {'title': title, 'quantity': 0};
          }

          salesMap[title]!['quantity'] =
              (salesMap[title]!['quantity'] as int) + quantity;
        }
      }
    }
  }

  if (salesMap.isEmpty) {
    return {'title': l10n.noSalesData, 'quantity': 0};
  }

  final values = salesMap.values.toList();
  values.sort((a, b) => (b['quantity'] as int).compareTo(a['quantity'] as int));
  return values.first;
}

List<double> _buildMonthlySales(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> orderDocs,
) {
  final now = DateTime.now();
  final List<double> monthlySales = List.filled(6, 0);

  for (final doc in orderDocs) {
    final data = doc.data();
    final createdAt = data['createdAt'];

    if (createdAt is Timestamp) {
      final date = createdAt.toDate();
      final monthDifference =
          (now.year - date.year) * 12 + (now.month - date.month);

      if (monthDifference >= 0 && monthDifference < 6) {
        final index = 5 - monthDifference;
        monthlySales[index] += _parseTotal(data['total']);
      }
    }
  }

  return monthlySales;
}

List<String> _buildMonthLabels(AppLocalizations l10n) {
  final now = DateTime.now();
  final List<String> labels = [];

  for (int i = 5; i >= 0; i--) {
    final date = DateTime(now.year, now.month - i, 1);
    labels.add(_monthShortName(date.month, l10n));
  }

  return labels;
}

String _monthShortName(int month, AppLocalizations l10n) {
  final names = [
    l10n.monthJan,
    l10n.monthFeb,
    l10n.monthMar,
    l10n.monthApr,
    l10n.monthMay,
    l10n.monthJun,
    l10n.monthJul,
    l10n.monthAug,
    l10n.monthSep,
    l10n.monthOct,
    l10n.monthNov,
    l10n.monthDec,
  ];
  return names[month - 1];
}

Widget _buildSectionTitle(String title) =>
    Text(title, style: AppTextStyles.headingSmall);

// ── Page ──────────────────────────────────────────────────────────────────────

class BoutiqueSalesDetailsPage extends StatelessWidget {
  final String boutiqueId;
  final String boutiqueName;

  const BoutiqueSalesDetailsPage({
    super.key,
    required this.boutiqueId,
    required this.boutiqueName,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final ordersStream = FirebaseFirestore.instance
        .collection('boutiques')
        .doc(boutiqueId)
        .collection('orders')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: ordersStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        l10n.failedToLoadBoutiqueDetails,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.secondaryText,
                        ),
                      ),
                    );
                  }

                  final orderDocs = snapshot.data?.docs ?? [];

                  double totalSales = 0;
                  int totalItems = 0;

                  for (final doc in orderDocs) {
                    final data = doc.data();
                    totalSales += _parseTotal(data['total']);
                    totalItems += _parseInt(data['itemCount']);
                  }

                  final bestSellingItem = _buildBestSellingItem(
                    orderDocs,
                    l10n,
                  );
                  final monthlySales = _buildMonthlySales(orderDocs);
                  final monthLabels = _buildMonthLabels(l10n);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(boutiqueName, style: AppTextStyles.displayMedium),
                        const SizedBox(height: 8),
                        Text(
                          l10n.boutiqueSalesOverview,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.secondaryText,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                title: l10n.totalSalesTitle,
                                value: _fmt(totalSales),
                                subtitle: l10n.allBoutiqueSales,
                                icon: Icons.trending_up_rounded,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _StatCard(
                                title: l10n.orders,
                                value: orderDocs.length.toString(),
                                subtitle: l10n.totalBoutiqueOrders,
                                icon: Icons.receipt_long_outlined,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                title: l10n.itemsSold,
                                value: totalItems.toString(),
                                subtitle: l10n.totalSoldItems,
                                icon: Icons.inventory_2_outlined,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _StatCard(
                                title: l10n.bestSeller,
                                value:
                                    bestSellingItem['title']?.toString() ?? '-',
                                subtitle: l10n.quantitySold(
                                  bestSellingItem['quantity'].toString(),
                                ),
                                icon: Icons.star_outline,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildSectionTitle(l10n.monthlySales),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            border: Border.all(
                              color: AppColors.border,
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 180,
                                width: double.infinity,
                                child: CustomPaint(
                                  painter: MonthlySalesBarPainter(
                                    values: monthlySales,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: monthLabels
                                    .map(
                                      (label) => Text(
                                        label,
                                        style: AppTextStyles.bodySmall,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildSectionTitle(l10n.recentSales),
                        const SizedBox(height: 12),
                        if (orderDocs.isEmpty)
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
                            child: Text(
                              l10n.noSalesFound,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.secondaryText,
                              ),
                            ),
                          )
                        else
                          ...orderDocs.take(8).map((doc) {
                            return _RecentOrderCard(
                              data: doc.data(),
                              l10n: l10n,
                            );
                          }),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stat card widget ──────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  const _StatCard({
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
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recent order card widget ──────────────────────────────────────────────────

class _RecentOrderCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final AppLocalizations l10n;

  const _RecentOrderCard({required this.data, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final orderNumber = _buildOrderNumber(data, l10n);
    final customerName =
        data['customerName']?.toString() ?? l10n.unknownCustomer;
    final total = _parseTotal(data['total']);
    final date = _buildDate(data, l10n);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            orderNumber,
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(customerName, style: AppTextStyles.bodySmall),
          const SizedBox(height: 4),
          Text(date, style: AppTextStyles.bodySmall),
          const SizedBox(height: 4),
          Text(
            _fmt(total),
            style: AppTextStyles.labelLarge,
          ),
        ],
      ),
    );
  }
}

// ── Monthly sales bar painter ─────────────────────────────────────────────────

class MonthlySalesBarPainter extends CustomPainter {
  final List<double> values;

  MonthlySalesBarPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = AppColors.softAccent
      ..strokeWidth = 1;

    final barPaint = Paint()
      ..color = AppColors.deepAccent
      ..style = PaintingStyle.fill;

    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      axisPaint,
    );

    if (values.isEmpty) return;

    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final safeMax = maxValue == 0 ? 1 : maxValue;

    final barWidth = size.width / (values.length * 1.8);

    for (int i = 0; i < values.length; i++) {
      final normalizedHeight = (values[i] / safeMax) * (size.height - 12);
      final left = (i * (size.width / values.length)) + (barWidth / 2);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left,
          size.height - normalizedHeight,
          barWidth,
          normalizedHeight,
        ),
        Radius.zero,
      );

      canvas.drawRRect(rect, barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant MonthlySalesBarPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}
