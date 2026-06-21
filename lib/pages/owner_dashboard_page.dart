import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../widgets/error_state_widget.dart';
import '../models/product.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';
import 'add_product_page.dart';
import 'my_boutique_page.dart';
import 'owner_discount_codes_page.dart';
import 'owner_orders_page.dart';
import 'sales_insights_page.dart';
import '../core/constants/countries.dart';
import '../services/currency_service.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

// ── Pure helpers ──────────────────────────────────────────────────────────────

int _pendingCount(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  return docs.where((doc) {
    final status = doc.data()['status']?.toString().toLowerCase() ?? '';
    return status == 'placed';
  }).length;
}

double _totalRevenue(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  return docs.fold(0.0, (total, doc) {
    final v = doc.data()['total'];
    return total +
        (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
  });
}

String _formatKwd(double value) => _fmt(value);

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
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
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
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return RefreshIndicator(
      color: AppColors.deepAccent,
      onRefresh: _onRefresh,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          SizedBox(
            height: 400,
            child: ErrorStateWidget.inline(
              title: message,
              message: AppLocalizations.of(context)!.pullDownToRetry,
              onRetry: _onRefresh,
              type: ErrorType.network,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardStreams(AppLocalizations l10n) {
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
        final lowStockProducts = productDocs.where((doc) {
          final stock = doc.data()['stock'];
          return stock is num && stock <= 3;
        }).toList();

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
            final pending = _pendingCount(orderDocs);
            final revenue = _totalRevenue(orderDocs);

            return RefreshIndicator(
              color: AppColors.deepAccent,
              onRefresh: _onRefresh,
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ───────────────────────────────────
                    Text(
                      _ownerData?['Name']?.toString() ?? l10n.ownerFallback,
                      style: AppTextStyles.displayMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _boutiqueData?['name']?.toString() ?? l10n.boutique,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 22),

                    // ── Stats ────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _DashboardStatCard(
                            title: l10n.pendingOrders,
                            value: pending.toString(),
                            subtitle: pending == 0
                                ? l10n.allCaughtUp
                                : l10n.ordersNeedAction(pending),
                            icon: Icons.schedule_rounded,
                            isHighlighted: pending > 0,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const OwnerOrdersPage(),
                              ),
                            ),
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
                            title: l10n.revenue,
                            value: _formatKwd(revenue),
                            subtitle: l10n.totalEarnings,
                            icon: Icons.account_balance_wallet_outlined,
                            isHighlighted: revenue > 0,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SalesInsightsPage(boutiqueId: _boutiqueId!),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _DashboardStatCard(
                            title: l10n.lowStock,
                            value: lowStockProducts.length.toString(),
                            subtitle: lowStockProducts.isEmpty
                                ? l10n.allGood
                                : lowStockProducts.length == 1
                                ? l10n.needsRestock
                                : l10n.needRestock,
                            icon: Icons.warning_amber_rounded,
                            isHighlighted: lowStockProducts.isNotEmpty,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // ── Low-stock alerts ─────────────────────────
                    Text(l10n.stockAlerts, style: AppTextStyles.headingSmall),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: lowStockProducts.isEmpty
                          ? Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  size: 20,
                                  color: AppColors.deepAccent,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  l10n.allStockLevelsGood,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: lowStockProducts.map((doc) {
                                final product = Product.fromFirestore(doc);
                                final title = product.title.isNotEmpty
                                    ? product.title
                                    : l10n.untitledProduct;
                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: doc == lowStockProducts.last
                                        ? 0
                                        : 12,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.warning_amber_rounded,
                                        size: 18,
                                        color: AppColors.deepAccent,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          title,
                                          style: AppTextStyles.bodyMedium
                                              .copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        l10n.stockLeft(
                                          product.stock.toString(),
                                        ),
                                        style: AppTextStyles.labelSmall
                                            .copyWith(
                                              color: AppColors.deepAccent,
                                              fontWeight: FontWeight.w500,
                                            ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                    ),

                    const SizedBox(height: 28),

                    // ── Quick actions ────────────────────────────
                    Text(l10n.quickActions, style: AppTextStyles.headingSmall),
                    const SizedBox(height: 10),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _ActionCard(
                              title: l10n.myBoutique,
                              subtitle: l10n.manageBoutiqueAndProducts,
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
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _ActionCard(
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
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── Promotions ───────────────────────────────
                    Text(l10n.promotions, style: AppTextStyles.headingSmall),
                    const SizedBox(height: 10),
                    _ActionCard(
                      title: l10n.discountCodes,
                      subtitle: l10n.discountCodesSubtitle,
                      icon: Icons.local_offer_outlined,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OwnerDiscountCodesPage(
                            boutiqueId: _boutiqueId!,
                            boutiqueName:
                                _boutiqueData?['name']?.toString() ?? '',
                          ),
                        ),
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

// ── Stat card ─────────────────────────────────────────────────────────────────

class _DashboardStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final bool isHighlighted;
  final VoidCallback? onTap;

  const _DashboardStatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.isHighlighted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
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
      ),
    );
  }
}

// ── Action card ───────────────────────────────────────────────────────────────

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
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
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
            const SizedBox(height: 6),
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
