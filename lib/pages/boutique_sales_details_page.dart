import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';

class BoutiqueSalesDetailsPage extends StatelessWidget {
  final String boutiqueId;
  final String boutiqueName;

  const BoutiqueSalesDetailsPage({
    super.key,
    required this.boutiqueId,
    required this.boutiqueName,
  });

  double _parseTotal(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  int _parseInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
  }

  String _buildOrderNumber(Map<String, dynamic> data) {
    final value = data['orderNumber']?.toString().trim() ?? '';
    return value.isNotEmpty ? value : 'Unknown Order';
  }

  String _buildDate(Map<String, dynamic> data) {
    final value = data['date']?.toString().trim() ?? '';
    return value.isNotEmpty ? value : 'No date';
  }

  Map<String, dynamic> _buildBestSellingItem(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> orderDocs,
      ) {
    final Map<String, Map<String, dynamic>> salesMap = {};

    for (final doc in orderDocs) {
      final data = doc.data();
      final rawItems = data['items'];

      if (rawItems is List) {
        for (final rawItem in rawItems) {
          if (rawItem is Map) {
            final item = Map<String, dynamic>.from(rawItem);
            final title = item['title']?.toString() ?? 'Untitled Product';
            final quantity = _parseInt(item['quantity']);

            if (!salesMap.containsKey(title)) {
              salesMap[title] = {
                'title': title,
                'quantity': 0,
              };
            }

            salesMap[title]!['quantity'] =
                (salesMap[title]!['quantity'] as int) + quantity;
          }
        }
      }
    }

    if (salesMap.isEmpty) {
      return {
        'title': 'No sales data',
        'quantity': 0,
      };
    }

    final values = salesMap.values.toList();
    values.sort(
          (a, b) => (b['quantity'] as int).compareTo(a['quantity'] as int),
    );
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

  List<String> _buildMonthLabels() {
    final now = DateTime.now();
    final List<String> labels = [];

    for (int i = 5; i >= 0; i--) {
      final date = DateTime(now.year, now.month - i, 1);
      labels.add(_monthShortName(date.month));
    }

    return labels;
  }

  String _monthShortName(int month) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[month - 1];
  }

  Widget buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.softAccent..withValues(alpha: 0.22),
            child: Icon(
              icon,
              color: AppColors.deepAccent,
              size: 20,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.secondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.primaryText,
      ),
    );
  }

  Widget buildRecentOrderCard(Map<String, dynamic> data) {
    final orderNumber = _buildOrderNumber(data);
    final customerName = data['customerName']?.toString() ?? 'Unknown Customer';
    final total = _parseTotal(data['total']);
    final date = _buildDate(data);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            orderNumber,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            customerName,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            date,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${total.toStringAsFixed(0)} KWD',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                    return const Center(
                      child: Text(
                        'Failed to load boutique details',
                        style: TextStyle(color: AppColors.secondaryText),
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

                  final bestSellingItem = _buildBestSellingItem(orderDocs);
                  final monthlySales = _buildMonthlySales(orderDocs);
                  final monthLabels = _buildMonthLabels();

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          boutiqueName,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Boutique sales overview',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.secondaryText,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: buildStatCard(
                                title: 'Total Sales',
                                value: '${totalSales.toStringAsFixed(0)} KWD',
                                subtitle: 'All boutique sales',
                                icon: Icons.trending_up_rounded,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: buildStatCard(
                                title: 'Orders',
                                value: orderDocs.length.toString(),
                                subtitle: 'Total boutique orders',
                                icon: Icons.receipt_long_outlined,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: buildStatCard(
                                title: 'Items Sold',
                                value: totalItems.toString(),
                                subtitle: 'Total sold items',
                                icon: Icons.inventory_2_outlined,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: buildStatCard(
                                title: 'Best Seller',
                                value:
                                bestSellingItem['title']?.toString() ?? '-',
                                subtitle: '${bestSellingItem['quantity']} sold',
                                icon: Icons.star_outline,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        buildSectionTitle('Monthly Sales'),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: AppColors.border),
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
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                )
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        buildSectionTitle('Recent Sales'),
                        const SizedBox(height: 12),
                        if (orderDocs.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Text(
                              'No sales found.',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          )
                        else
                          ...orderDocs.take(8).map((doc) {
                            return buildRecentOrderCard(doc.data());
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

class MonthlySalesBarPainter extends CustomPainter {
  final List<double> values;

  MonthlySalesBarPainter({
    required this.values,
  });

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
        const Radius.circular(8),
      );

      canvas.drawRRect(rect, barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant MonthlySalesBarPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}