import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../models/product.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';
import 'add_product_page.dart';
import 'my_boutique_page.dart';
import 'owner_orders_page.dart';
import 'owner_products_page.dart';

// ── Pure helpers ──────────────────────────────────────────────────────────────

double _getTodaySales(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  final now = DateTime.now();
  return docs.fold(0.0, (total, doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    if (createdAt is! Timestamp) return total;
    final date = createdAt.toDate();
    if (date.year != now.year || date.month != now.month || date.day != now.day)
      return total;
    final v = data['total'];
    return total +
        (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
  });
}

List<double> _getWeeklySales(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final weekTotals = List<double>.filled(7, 0);

  for (final doc in docs) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    if (createdAt is! Timestamp) continue;
    final date = createdAt.toDate();
    final orderDay = DateTime(date.year, date.month, date.day);
    final diff = startOfToday.difference(orderDay).inDays;
    if (diff < 0 || diff > 6) continue;
    final index = 6 - diff;
    final v = data['total'];
    weekTotals[index] += v is num
        ? v.toDouble()
        : double.tryParse(v.toString()) ?? 0;
  }
  return weekTotals;
}

String _formatKwd(double value) => '${value.toStringAsFixed(0)} KWD';

Widget _buildSectionTitle(String title) =>
    Text(title, style: AppTextStyles.headingSmall);

// ── Page ──────────────────────────────────────────────────────────────────────

class OwnerDashboardPage extends StatefulWidget {
  const OwnerDashboardPage({super.key});

  @override
  State<OwnerDashboardPage> createState() => _OwnerDashboardPageState();
}

class _OwnerDashboardPageState extends State<OwnerDashboardPage> {
  Map<String, dynamic>? _ownerData;
  Map<String, dynamic>? _boutiqueData;
  String? _boutiqueId;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  // Owner data and boutique id are independent — run in parallel
  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final results = await Future.wait([
        FirestoreService.getCurrentOwnerData(),
        FirestoreService.getCurrentOwnerBoutiqueId(),
      ]);

      final currentOwnerData = results[0] as Map<String, dynamic>?;
      final id = results[1] as String?;

      if (id == null || id.isEmpty) {
        if (!mounted) return;
        setState(() {
          _ownerData = currentOwnerData;
          _boutiqueId = null;
          _boutiqueData = null;
          _isLoading = false;
        });
        return;
      }

      final currentBoutiqueData = await FirestoreService.getOwnerBoutiqueData();

      if (!mounted) return;
      setState(() {
        _ownerData = currentOwnerData;
        _boutiqueId = id;
        _boutiqueData = currentBoutiqueData;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _onRefresh() => _loadDashboardData();

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
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                      ),
                    )
                  : _loadError != null
                  ? _buildErrorState(l10n.failedToLoadDashboard)
                  : _boutiqueId == null
                  ? _buildErrorState(l10n.noBoutiqueFound)
                  : _buildDashboardStreams(l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return RefreshIndicator(
      color: AppColors.deepAccent,
      onRefresh: _onRefresh,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.secondaryText,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardStreams(AppLocalizations l10n) {
    // Two nested StreamBuilders — products and orders are both live.
    // TODO: replace with CombineLatestStream from rxdart when added.
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.getOwnerProductsStream(_boutiqueId!),
      builder: (context, productSnapshot) {
        if (productSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.deepAccent),
          );
        }
        if (productSnapshot.hasError) {
          return _buildErrorState(l10n.failedToLoadProducts);
        }

        final productDocs = productSnapshot.data?.docs ?? [];
        final productCount = productDocs.length;
        final lowStockCount = productDocs.where((doc) {
          final stock = doc.data()['stock'];
          return stock is num && stock <= 3;
        }).length;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.getOwnerOrdersStream(_boutiqueId!),
          builder: (context, orderSnapshot) {
            if (orderSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.deepAccent),
              );
            }
            if (orderSnapshot.hasError) {
              return _buildErrorState(l10n.failedToLoadOrders);
            }

            final orderDocs = orderSnapshot.data?.docs ?? [];
            final todaySales = _getTodaySales(orderDocs);
            final weeklySales = _getWeeklySales(orderDocs);
            final orderCount = orderDocs.length;

            return RefreshIndicator(
              color: AppColors.deepAccent,
              onRefresh: _onRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.welcomeBack, style: AppTextStyles.capsLabel),
                    const SizedBox(height: 6),
                    Text(
                      _ownerData?['Name']?.toString() ?? l10n.ownerFallback,
                      style: AppTextStyles.displayMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _boutiqueData?['name']?.toString() ?? l10n.boutique,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _boutiqueData?['description']?.toString() ??
                          l10n.dashboardDescription,
                      style: AppTextStyles.bodyMedium.copyWith(
                        height: 1.5,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Stats ─────────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _DashboardStatCard(
                            title: l10n.todaysSales,
                            value: _formatKwd(todaySales),
                            subtitle: todaySales > 0
                                ? l10n.updatedFromRealOrders
                                : l10n.noSalesToday,
                            icon: Icons.trending_up_rounded,
                            isHighlighted: true,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _DashboardStatCard(
                            title: l10n.products,
                            value: productCount.toString(),
                            subtitle: l10n.activeListings,
                            icon: Icons.inventory_2_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _DashboardStatCard(
                            title: l10n.orders,
                            value: orderCount.toString(),
                            subtitle: l10n.ordersCountSubtitle(orderCount),
                            icon: Icons.receipt_long_outlined,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _DashboardStatCard(
                            title: l10n.lowStock,
                            value: lowStockCount.toString(),
                            subtitle: lowStockCount == 1
                                ? l10n.needsRestock
                                : l10n.needRestock,
                            icon: Icons.warning_amber_rounded,
                            isHighlighted: true,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    // ── Sales chart ───────────────────────────────────
                    _buildSectionTitle(l10n.salesOverview),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                l10n.weeklySales,
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                _formatKwd(
                                  weeklySales.fold(
                                    0.0,
                                    (total, v) => total + v,
                                  ),
                                ),
                                style: AppTextStyles.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.weeklySalesDescription,
                            style: AppTextStyles.bodySmall.copyWith(
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
                                lineColor: AppColors.deepAccent,
                                gridColor: AppColors.softAccent,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children:
                                [
                                      l10n.dayMon,
                                      l10n.dayTue,
                                      l10n.dayWed,
                                      l10n.dayThu,
                                      l10n.dayFri,
                                      l10n.daySat,
                                      l10n.daySun,
                                    ]
                                    .map(
                                      (d) => Text(
                                        d,
                                        style: AppTextStyles.bodySmall,
                                      ),
                                    )
                                    .toList(),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    // ── Quick actions ─────────────────────────────────
                    _buildSectionTitle(l10n.quickActions),
                    const SizedBox(height: 10),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 1.35,
                      children: [
                        _ActionCard(
                          title: l10n.myBoutique,
                          subtitle: l10n.viewBoutiqueDetails,
                          icon: Icons.storefront_outlined,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MyBoutiquePage(),
                              ),
                            );
                            if (mounted) await _loadDashboardData();
                          },
                        ),
                        _ActionCard(
                          title: l10n.myProducts,
                          subtitle: l10n.manageProductList,
                          icon: Icons.checkroom_outlined,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const OwnerProductsPage(),
                            ),
                          ),
                        ),
                        _ActionCard(
                          title: l10n.addProduct,
                          subtitle: l10n.createANewListing,
                          icon: Icons.add_box_outlined,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AddProductPage(),
                              ),
                            );
                            if (mounted) await _loadDashboardData();
                          },
                        ),
                        _ActionCard(
                          title: l10n.orders,
                          subtitle: l10n.trackIncomingSales,
                          icon: Icons.receipt_long_outlined,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const OwnerOrdersPage(),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    // ── Inventory notes ───────────────────────────────
                    _buildSectionTitle(l10n.inventoryNotes),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: productDocs.isEmpty
                          ? Text(
                              l10n.noProductNotesYet,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.secondaryText,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: () {
                                final previewDocs = productDocs
                                    .take(3)
                                    .toList();
                                return previewDocs.asMap().entries.map((entry) {
                                  final isLast =
                                      entry.key == previewDocs.length - 1;
                                  final product = Product.fromFirestore(
                                    entry.value,
                                  );
                                  final title = product.title.isNotEmpty
                                      ? product.title
                                      : l10n.untitledProduct;
                                  final stock = product.stock;
                                  final subtitle = stock <= 3
                                      ? l10n.lowStockSubtitle
                                      : l10n.stockLooksGood;
                                  final count = stock <= 3
                                      ? l10n.stockLeft(stock.toString())
                                      : l10n.inStockWithCount(stock.toString());

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
                                }).toList();
                              }(),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Dashboard stat card widget ────────────────────────────────────────────────

class _DashboardStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final bool isHighlighted;

  const _DashboardStatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.isHighlighted = false,
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
              color: isHighlighted
                  ? AppColors.deepAccent
                  : AppColors.secondaryText,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action card widget ────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.deepAccent, size: 24),
            const SizedBox(height: 15),
            Text(
              title,
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w500,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppTextStyles.bodySmall.copyWith(height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Inventory row widget ──────────────────────────────────────────────────────

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
            color: AppColors.softAccent.withValues(alpha: 0.25),
            border: Border.all(color: AppColors.border, width: 0.5),
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
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              Text(subtitle, style: AppTextStyles.bodySmall),
            ],
          ),
        ),
        Text(
          count,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.deepAccent,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Sales chart painter ───────────────────────────────────────────────────────

class SalesChartPainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;
  final Color gridColor;

  const SalesChartPainter({
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
      ..color = lineColor.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 4; i++) {
      final y = size.height / 4 * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (values.isEmpty) return;

    if (values.length == 1) {
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        4,
        Paint()..color = lineColor,
      );
      return;
    }

    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final range = maxValue == minValue ? 1.0 : maxValue - minValue;

    final points = <Offset>[
      for (int i = 0; i < values.length; i++)
        Offset(
          size.width / (values.length - 1) * i,
          size.height -
              ((values[i] - minValue) / range * (size.height - 20)) -
              10,
        ),
    ];

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final cx = (prev.dx + curr.dx) / 2;
      path.cubicTo(cx, prev.dy, cx, curr.dy, curr.dx, curr.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    for (final point in points) {
      canvas.drawCircle(point, 4, Paint()..color = lineColor);
      canvas.drawCircle(
        point,
        7,
        Paint()..color = lineColor.withValues(alpha: 0.15),
      );
    }
  }

  @override
  bool shouldRepaint(covariant SalesChartPainter old) =>
      old.values != values ||
      old.lineColor != lineColor ||
      old.gridColor != gridColor;
}
