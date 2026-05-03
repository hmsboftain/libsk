import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../navigation/app_header.dart';
import 'owner_products_page.dart';
import 'add_product_page.dart';
import 'my_boutique_page.dart';
import 'owner_orders_page.dart';
import '../widgets/theme.dart';

class OwnerDashboardPage extends StatefulWidget {
  const OwnerDashboardPage({super.key});

  @override
  State<OwnerDashboardPage> createState() => _OwnerDashboardPageState();
}

class _OwnerDashboardPageState extends State<OwnerDashboardPage> {
  Map<String, dynamic>? ownerData;
  Map<String, dynamic>? boutiqueData;
  String? boutiqueId;
  bool isLoading = true;
  String? loadError;

  @override
  void initState() {
    super.initState();
    loadDashboardData();
  }

  Future<void> loadDashboardData() async {
    try {
      final currentOwnerData = await FirestoreService.getCurrentOwnerData();
      final id = await FirestoreService.getCurrentOwnerBoutiqueId();

      if (id == null || id.isEmpty) {
        if (!mounted) return;
        setState(() {
          ownerData = currentOwnerData;
          boutiqueId = null;
          boutiqueData = null;
          isLoading = false;
          loadError = null;
        });
        return;
      }

      final currentBoutiqueData = await FirestoreService.getOwnerBoutiqueData();

      if (!mounted) return;

      setState(() {
        ownerData = currentOwnerData;
        boutiqueId = id;
        boutiqueData = currentBoutiqueData;
        isLoading = false;
        loadError = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        loadError = e.toString();
      });
    }
  }

  Future<void> _onRefresh() async {
    setState(() {
      isLoading = true;
    });
    await loadDashboardData();
  }
  double getTodaySales(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final now = DateTime.now();

    double total = 0;

    for (final doc in docs) {
      final data = doc.data();

      final createdAt = data['createdAt'];
      final orderDate =
      createdAt is Timestamp ? createdAt.toDate() : null;

      if (orderDate == null) continue;

      final isToday = orderDate.year == now.year &&
          orderDate.month == now.month &&
          orderDate.day == now.day;

      if (!isToday) continue;

      final orderTotal = data['total'];

      if (orderTotal is num) {
        total += orderTotal.toDouble();
      } else {
        total += double.tryParse(orderTotal.toString()) ?? 0;
      }
    }

    return total;
  }

  List<double> getWeeklySales(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final now = DateTime.now();

    final startOfToday = DateTime(now.year, now.month, now.day);

    final weekTotals = List<double>.filled(7, 0);

    for (final doc in docs) {
      final data = doc.data();

      final createdAt = data['createdAt'];
      final orderDate =
      createdAt is Timestamp ? createdAt.toDate() : null;

      if (orderDate == null) continue;

      final orderDay =
      DateTime(orderDate.year, orderDate.month, orderDate.day);

      final difference = startOfToday.difference(orderDay).inDays;

      if (difference < 0 || difference > 6) continue;

      final index = 6 - difference;

      final orderTotal = data['total'];

      double value = 0;
      if (orderTotal is num) {
        value = orderTotal.toDouble();
      } else {
        value = double.tryParse(orderTotal.toString()) ?? 0;
      }

      weekTotals[index] += value;
    }

    return weekTotals;
  }

  String formatKwd(double value) {
    return '${value.toStringAsFixed(0)} KWD';
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = AppColors.background;
    final cardColor = AppColors.card;
    final borderColor = AppColors.border;
    final primaryText = AppColors.primaryText;
    final secondaryText = AppColors.secondaryText;
    final softAccent = AppColors.softAccent;
    final deepAccent = AppColors.deepAccent;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: isLoading
                  ? Center(
                child: CircularProgressIndicator(
                  color: deepAccent,
                ),
              )
                  : loadError != null
                  ? RefreshIndicator(
                onRefresh: _onRefresh,
                child: ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Failed to load dashboard\n\n$loadError',
                        style: TextStyle(
                          fontSize: 15,
                          color: secondaryText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              )
                  : boutiqueId == null
                  ? RefreshIndicator(
                onRefresh: _onRefresh,
                child: ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No boutique found for this owner.',
                        style: TextStyle(
                          fontSize: 15,
                          color: secondaryText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              )
                  : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirestoreService.getOwnerProductsStream(
                  boutiqueId!,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: deepAccent,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return RefreshIndicator(
                      onRefresh: _onRefresh,
                      child: ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Failed to load products\n\n${snapshot.error}',
                              style: TextStyle(
                                fontSize: 15,
                                color: secondaryText,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final productDocs = snapshot.data?.docs ?? [];
                  final productCount = productDocs.length;

                  final lowStockCount = productDocs.where((doc) {
                    final data = doc.data();
                    final stock = data['stock'];

                    if (stock is int) return stock <= 3;
                    if (stock is num) return stock <= 3;

                    return false;
                  }).length;

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirestoreService.getOwnerOrdersStream(boutiqueId!),
                    builder: (context, orderSnapshot) {
                      if (orderSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return Center(
                          child: CircularProgressIndicator(
                            color: deepAccent,
                          ),
                        );
                      }

                      if (orderSnapshot.hasError) {
                        return RefreshIndicator(
                          onRefresh: _onRefresh,
                          child: ListView(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Failed to load orders\n\n${orderSnapshot.error}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: secondaryText,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final orderDocs = orderSnapshot.data?.docs ?? [];
                      final todaySales = getTodaySales(orderDocs);
                      final weeklySales = getWeeklySales(orderDocs);
                      final orderCount = orderDocs.length;

                      return RefreshIndicator(
                        onRefresh: _onRefresh,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome back,',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: secondaryText,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                ownerData?['Name']?.toString() ?? 'Owner',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: primaryText,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                boutiqueData?['name']?.toString() ?? 'Boutique',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: secondaryText,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                boutiqueData?['description']?.toString() ??
                                    'Manage your boutique, products, and sales from one place.',
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: secondaryText,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  Expanded(
                                    child: buildStatCard(
                                      title: 'Today\'s Sales',
                                      value: formatKwd(todaySales),
                                      subtitle: todaySales > 0
                                          ? 'Updated from real orders'
                                          : 'No sales today',
                                      icon: Icons.trending_up_rounded,
                                      iconColor: deepAccent,
                                      subtitleColor: deepAccent,
                                      iconBackgroundColor:
                                      softAccent.withValues(alpha:0.22),
                                      borderColor: borderColor,
                                      cardColor: cardColor,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: buildStatCard(
                                      title: 'Products',
                                      value: productCount.toString(),
                                      subtitle: 'Active listings',
                                      icon: Icons.inventory_2_outlined,
                                      iconColor: deepAccent,
                                      subtitleColor: secondaryText,
                                      iconBackgroundColor:
                                      softAccent.withValues(alpha:0.22),
                                      borderColor: borderColor,
                                      cardColor: cardColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: buildStatCard(
                                      title: 'Orders',
                                      value: orderCount.toString(),
                                      subtitle: orderCount == 1
                                          ? '1 total order'
                                          : '$orderCount total orders',
                                      icon: Icons.receipt_long_outlined,
                                      iconColor: deepAccent,
                                      subtitleColor: secondaryText,
                                      iconBackgroundColor:
                                      softAccent.withValues(alpha:0.22),
                                      borderColor: borderColor,
                                      cardColor: cardColor,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: buildStatCard(
                                      title: 'Low Stock',
                                      value: lowStockCount.toString(),
                                      subtitle: lowStockCount == 1
                                          ? 'Needs restock'
                                          : 'Need restock',
                                      icon: Icons.warning_amber_rounded,
                                      iconColor: deepAccent,
                                      subtitleColor: deepAccent,
                                      iconBackgroundColor:
                                      softAccent.withValues(alpha:0.22),
                                      borderColor: borderColor,
                                      cardColor: cardColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 22),
                              buildSectionTitle('Sales Overview'),
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: borderColor,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Weekly Sales',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: primaryText,
                                          ),
                                        ),
                                        Text(
                                          formatKwd(
                                            weeklySales.fold(
                                              0,
                                                  (total, value) => total + value,
                                            ),
                                          ),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: secondaryText,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Based on real order totals from the last 7 days.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: secondaryText,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    SizedBox(
                                      height: 180,
                                      width: double.infinity,
                                      child: CustomPaint(
                                        painter: SalesChartPainter(
                                          values: weeklySales,
                                          lineColor: deepAccent,
                                          gridColor: softAccent,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Mon',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: secondaryText,
                                          ),
                                        ),
                                        Text(
                                          'Tue',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: secondaryText,
                                          ),
                                        ),
                                        Text(
                                          'Wed',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: secondaryText,
                                          ),
                                        ),
                                        Text(
                                          'Thu',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: secondaryText,
                                          ),
                                        ),
                                        Text(
                                          'Fri',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: secondaryText,
                                          ),
                                        ),
                                        Text(
                                          'Sat',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: secondaryText,
                                          ),
                                        ),
                                        Text(
                                          'Sun',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: secondaryText,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 22),
                              buildSectionTitle('Quick Actions'),
                              const SizedBox(height: 10),
                              GridView.count(
                                crossAxisCount: 2,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                childAspectRatio: 1.35,
                                children: [
                                  buildActionCard(
                                    title: 'My Boutique',
                                    subtitle: 'View boutique details',
                                    icon: Icons.storefront_outlined,
                                    iconColor: deepAccent,
                                    borderColor: borderColor,
                                    cardColor: cardColor,
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => const MyBoutiquePage(),
                                        ),
                                      );
                                      if (!mounted) return;
                                      await loadDashboardData();
                                    },
                                  ),
                                  buildActionCard(
                                    title: 'My Products',
                                    subtitle: 'Manage product list',
                                    icon: Icons.checkroom_outlined,
                                    iconColor: deepAccent,
                                    borderColor: borderColor,
                                    cardColor: cardColor,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => const OwnerProductsPage(),
                                        ),
                                      );
                                    },
                                  ),
                                  buildActionCard(
                                    title: 'Add Product',
                                    subtitle: 'Create a new listing',
                                    icon: Icons.add_box_outlined,
                                    iconColor: deepAccent,
                                    borderColor: borderColor,
                                    cardColor: cardColor,
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => const AddProductPage(),
                                        ),
                                      );
                                      if (!mounted) return;
                                      await loadDashboardData();
                                    },
                                  ),
                                  buildActionCard(
                                    title: 'Orders',
                                    subtitle: 'Track incoming sales',
                                    icon: Icons.receipt_long_outlined,
                                    iconColor: deepAccent,
                                    borderColor: borderColor,
                                    cardColor: cardColor,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => const OwnerOrdersPage(),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 22),
                              buildSectionTitle('Inventory Notes'),
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: borderColor,
                                  ),
                                ),
                                child: productDocs.isEmpty
                                    ? Text(
                                  'No product notes yet.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: secondaryText,
                                  ),
                                )
                                    : Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: productDocs.take(3).map((doc) {
                                    final data = doc.data();
                                    final title = data['title']
                                        ?.toString() ??
                                        'Untitled Product';
                                    final stockValue = data['stock'] ?? 0;

                                    final int stock = stockValue is int
                                        ? stockValue
                                        : int.tryParse(
                                        stockValue.toString()) ??
                                        0;

                                    String subtitle;
                                    String count;

                                    if (stock <= 3) {
                                      subtitle = 'Low stock';
                                      count = '$stock left';
                                    } else {
                                      subtitle = 'Stock looks good';
                                      count = '$stock in stock';
                                    }

                                    final previewDocs =
                                    productDocs.take(3).toList();
                                    final isLast =
                                        doc.id == previewDocs.last.id;

                                    return Padding(
                                      padding: EdgeInsets.only(
                                        bottom: isLast ? 0 : 14,
                                      ),
                                      child: InventoryRow(
                                        title: title,
                                        subtitle: subtitle,
                                        count: count,
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
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

  Widget buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color subtitleColor,
    required Color iconBackgroundColor,
    required Color borderColor,
    required Color cardColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: iconBackgroundColor,
            child: Icon(icon, color: iconColor, size: 20),
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
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: subtitleColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color borderColor,
    required Color cardColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(height: 15),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.secondaryText,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InventoryRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String count;

  const InventoryRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.softAccent.withValues(alpha:0.25),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.checkroom_outlined,
            color: AppColors.deepAccent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
        Text(
          count,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.deepAccent,
          ),
        ),
      ],
    );
  }
}

class SalesChartPainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;
  final Color gridColor;

  SalesChartPainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = lineColor.withValues(alpha:0.08)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 4; i++) {
      final y = (size.height / 4) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (values.isEmpty) return;

    if (values.length == 1) {
      final point = Offset(size.width / 2, size.height / 2);
      canvas.drawCircle(point, 4, Paint()..color = lineColor);
      return;
    }

    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final range = (maxValue - minValue) == 0 ? 1 : (maxValue - minValue);

    final points = <Offset>[];

    for (int i = 0; i < values.length; i++) {
      final x = (size.width / (values.length - 1)) * i;
      final normalized = (values[i] - minValue) / range;
      final y = size.height - (normalized * (size.height - 20)) - 10;
      points.add(Offset(x, y));
    }

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);

    for (int i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final controlX = (previous.dx + current.dx) / 2;
      path.cubicTo(
        controlX,
        previous.dy,
        controlX,
        current.dy,
        current.dx,
        current.dy,
      );
    }

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = lineColor;
    for (final point in points) {
      canvas.drawCircle(point, 4, dotPaint);
      canvas.drawCircle(
        point,
        7,
        Paint()..color = lineColor.withValues(alpha:0.15),
      );
    }
  }

  @override
  bool shouldRepaint(covariant SalesChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor;
  }
}