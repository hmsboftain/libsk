import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

enum AnalyticsFilter { allTime, today, thisWeek, thisMonth }

class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key});

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage> {
  AnalyticsFilter selectedFilter = AnalyticsFilter.allTime;

  double _parseTotal(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  DateTime? _getCreatedAt(Map<String, dynamic> data) {
    final value = data['createdAt'];
    if (value is Timestamp) return value.toDate();
    return null;
  }

  bool _isInsideSelectedFilter(Map<String, dynamic> data) {
    if (selectedFilter == AnalyticsFilter.allTime) return true;

    final createdAt = _getCreatedAt(data);
    if (createdAt == null) return false;

    final now = DateTime.now();

    if (selectedFilter == AnalyticsFilter.today) {
      return createdAt.year == now.year &&
          createdAt.month == now.month &&
          createdAt.day == now.day;
    }

    if (selectedFilter == AnalyticsFilter.thisWeek) {
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final start = DateTime(
        startOfWeek.year,
        startOfWeek.month,
        startOfWeek.day,
      );
      return createdAt.isAfter(start) || createdAt.isAtSameMomentAs(start);
    }

    if (selectedFilter == AnalyticsFilter.thisMonth) {
      return createdAt.year == now.year && createdAt.month == now.month;
    }

    return true;
  }

  int _countStatus(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      String status,
      ) {
    return docs.where((doc) {
      return doc.data()['status']?.toString().toLowerCase() ==
          status.toLowerCase();
    }).length;
  }

  String _topBoutiqueName(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final Map<String, double> boutiqueSales = {};
    final Map<String, String> boutiqueNames = {};

    for (final doc in docs) {
      final data = doc.data();
      final total = _parseTotal(data['total']);
      final items = data['items'];

      if (items is List && items.isNotEmpty) {
        final firstItem = Map<String, dynamic>.from(items.first as Map);
        final boutiqueId = firstItem['boutiqueId']?.toString() ?? '';
        final boutiqueName =
            firstItem['boutiqueName']?.toString() ?? 'Boutique';

        if (boutiqueId.isNotEmpty) {
          boutiqueSales[boutiqueId] = (boutiqueSales[boutiqueId] ?? 0) + total;
          boutiqueNames[boutiqueId] = boutiqueName;
        }
      }
    }

    if (boutiqueSales.isEmpty) return 'No sales yet';

    String topBoutiqueId = boutiqueSales.keys.first;
    double topSales = boutiqueSales[topBoutiqueId] ?? 0;

    for (final entry in boutiqueSales.entries) {
      if (entry.value > topSales) {
        topBoutiqueId = entry.key;
        topSales = entry.value;
      }
    }

    return boutiqueNames[topBoutiqueId] ?? 'Boutique';
  }

  String _filterLabel(AnalyticsFilter filter) {
    switch (filter) {
      case AnalyticsFilter.allTime:
        return 'All Time';
      case AnalyticsFilter.today:
        return 'Today';
      case AnalyticsFilter.thisWeek:
        return 'This Week';
      case AnalyticsFilter.thisMonth:
        return 'This Month';
    }
  }

  Widget _filterChip(AnalyticsFilter filter) {
    final isSelected = selectedFilter == filter;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedFilter = filter;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.deepAccent : AppColors.field,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected ? AppColors.deepAccent : AppColors.border,
          ),
        ),
        child: Text(
          _filterLabel(filter),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.secondaryText,
          ),
        ),
      ),
    );
  }

  Widget _filterBar() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip(AnalyticsFilter.allTime),
          const SizedBox(width: 8),
          _filterChip(AnalyticsFilter.today),
          const SizedBox(width: 8),
          _filterChip(AnalyticsFilter.thisWeek),
          const SizedBox(width: 8),
          _filterChip(AnalyticsFilter.thisMonth),
        ],
      ),
    );
  }

  Widget _analyticsCard({
    required String title,
    required String value,
    required IconData icon,
    String? subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.softAccent.withValues(alpha:0.22),
            child: Icon(
              icon,
              color: AppColors.deepAccent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirestoreService.getAllBoutiqueOrdersStream(),
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
                        'Failed to load analytics',
                        style: TextStyle(color: AppColors.secondaryText),
                      ),
                    );
                  }

                  final allDocs = snapshot.data?.docs ?? [];

                  final orderDocs = allDocs.where((doc) {
                    final data = doc.data();
                    return data['sourceUserOrderId'] != null &&
                        _isInsideSelectedFilter(data);
                  }).toList();

                  double totalRevenue = 0;

                  for (final doc in orderDocs) {
                    totalRevenue += _parseTotal(doc.data()['total']);
                  }

                  final totalOrders = orderDocs.length;
                  final averageOrderValue =
                  totalOrders == 0 ? 0 : totalRevenue / totalOrders;

                  final placedOrders = _countStatus(orderDocs, 'Placed');
                  final processingOrders =
                  _countStatus(orderDocs, 'Processing');
                  final shippedOrders = _countStatus(orderDocs, 'Shipped');
                  final deliveredOrders = _countStatus(orderDocs, 'Delivered');

                  final topBoutique = _topBoutiqueName(orderDocs);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ANALYTICS',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Marketplace performance overview.',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.secondaryText,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _filterBar(),
                        const SizedBox(height: 22),
                        _analyticsCard(
                          title: 'Total Revenue',
                          value: '${totalRevenue.toStringAsFixed(0)} KWD',
                          icon: Icons.trending_up_rounded,
                          subtitle: _filterLabel(selectedFilter),
                        ),
                        const SizedBox(height: 12),
                        _analyticsCard(
                          title: 'Total Orders',
                          value: totalOrders.toString(),
                          icon: Icons.receipt_long_outlined,
                          subtitle: 'Orders in selected period',
                        ),
                        const SizedBox(height: 12),
                        _analyticsCard(
                          title: 'Average Order Value',
                          value:
                          '${averageOrderValue.toStringAsFixed(1)} KWD',
                          icon: Icons.analytics_outlined,
                          subtitle: 'Revenue divided by order count',
                        ),
                        const SizedBox(height: 12),
                        _analyticsCard(
                          title: 'Top Boutique',
                          value: topBoutique,
                          icon: Icons.storefront_outlined,
                          subtitle: 'Based on total sales',
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Order Status',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryText,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _analyticsCard(
                          title: 'Placed Orders',
                          value: placedOrders.toString(),
                          icon: Icons.shopping_bag_outlined,
                        ),
                        const SizedBox(height: 12),
                        _analyticsCard(
                          title: 'Processing Orders',
                          value: processingOrders.toString(),
                          icon: Icons.sync_outlined,
                        ),
                        const SizedBox(height: 12),
                        _analyticsCard(
                          title: 'Shipped Orders',
                          value: shippedOrders.toString(),
                          icon: Icons.local_shipping_outlined,
                        ),
                        const SizedBox(height: 12),
                        _analyticsCard(
                          title: 'Delivered Orders',
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
    );
  }
}