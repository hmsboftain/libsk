import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../widgets/error_state_widget.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';
import 'admin_analytics_page.dart';
import 'admin_boutiques_page.dart';
import 'admin_homepage_page.dart';
import 'admin_revenue_page.dart';
import 'all_users_page.dart';
import 'boutique_onboarding_page.dart';
import 'boutique_sales_page.dart';
import 'discount_codes_page.dart';
import 'disputes_page.dart';
import 'filtered_users_page.dart';
import 'global_orders_page.dart';
import 'hero_banner_management_page.dart';
import 'promo_banner_approval_page.dart';
import 'promo_credit_admin_page.dart';
import 'send_notification_page.dart';
import '../core/constants/countries.dart';
import '../services/currency_service.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

class _DashboardData {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> users;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> boutiques;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> orders;
  const _DashboardData({
    required this.users,
    required this.boutiques,
    required this.orders,
  });
}

int _countRecentlyActiveUsers(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final now = DateTime.now();
  return docs.where((doc) {
    final v = doc.data()['lastSeenAt'];
    if (v is! Timestamp) return false;
    return now.difference(v.toDate()).inMinutes <= 5;
  }).length;
}

double _sumSales(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  return docs.fold(0.0, (total, doc) {
    final v = doc.data()['total'] ?? 0;
    return total +
        (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
  });
}

int _countRole(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  String role,
) => docs.where((doc) => doc.data()['role'] == role).length;

class SuperAdminDashboardPage extends StatefulWidget {
  const SuperAdminDashboardPage({super.key});

  @override
  State<SuperAdminDashboardPage> createState() =>
      _SuperAdminDashboardPageState();
}

class _SuperAdminDashboardPageState extends State<SuperAdminDashboardPage> {
  late Future<_DashboardData> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
  }

  Future<_DashboardData> _loadDashboard() async {
    final filteredOrdersQuery = FirebaseFirestore.instance
        .collectionGroup('orders')
        .where('sourceUserOrderId', isNotEqualTo: null);
    final results = await Future.wait([
      FirestoreService.getAllUsersOnce(),
      FirestoreService.getAllBoutiquesStream().first,
      filteredOrdersQuery.get(),
    ]);
    return _DashboardData(
      users: results[0].docs
          .cast<QueryDocumentSnapshot<Map<String, dynamic>>>(),
      boutiques: results[1].docs
          .cast<QueryDocumentSnapshot<Map<String, dynamic>>>(),
      orders: results[2].docs
          .cast<QueryDocumentSnapshot<Map<String, dynamic>>>(),
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
              child: FutureBuilder<_DashboardData>(
                future: _dashboardFuture,
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
                      title: l10n.failedToLoadDashboard,
                      message: l10n.pullDownToRetry,
                      onRetry: () => setState(() {
                        _dashboardFuture = _loadDashboard();
                      }),
                      type: ErrorType.network,
                    );
                  }

                  final data = snapshot.data!;
                  final totalUsers = data.users.length;
                  final recentlyActive = _countRecentlyActiveUsers(data.users);
                  final totalBoutiques = data.boutiques.length;
                  final totalOrders = data.orders.length;
                  final totalSales = _sumSales(data.orders);
                  final regularUsers = _countRole(data.users, 'user');
                  final boutiqueOwners = _countRole(
                    data.users,
                    'boutique_owner',
                  );
                  final admins = _countRole(data.users, 'admin');
                  final superAdmins = _countRole(data.users, 'super_admin');

                  return SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.superAdmin,
                          style: AppTextStyles.displayMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.marketplaceActivityOverview,
                          style: AppTextStyles.bodyMedium,
                        ),
                        const SizedBox(height: 24),

                        // ── Overview ─────────────────────────────
                        Text(l10n.overview, style: AppTextStyles.headingSmall),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                title: l10n.totalUsers,
                                value: '$totalUsers',
                                subtitle: l10n.allRegisteredUsers,
                                icon: Icons.people_alt_outlined,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AllUsersPage(),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _StatCard(
                                title: l10n.recentlyActive,
                                value: '$recentlyActive',
                                subtitle: l10n.seenInLast5Min,
                                icon: Icons.wifi_tethering_outlined,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                title: l10n.allBoutiques,
                                value: '$totalBoutiques',
                                subtitle: l10n.allBoutiqueDocuments,
                                icon: Icons.storefront_outlined,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AdminBoutiquesPage(),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _StatCard(
                                title: l10n.globalOrders,
                                value: '$totalOrders',
                                subtitle: l10n.acrossAllBoutiques,
                                icon: Icons.receipt_long_outlined,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const GlobalOrdersPage(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _StatCard(
                          title: l10n.totalSales,
                          value: _fmt(totalSales),
                          subtitle: l10n.tapToViewBoutiqueSales,
                          icon: Icons.trending_up_rounded,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BoutiqueSalesPage(),
                            ),
                          ),
                        ),

                        // ── User management ───────────────────────
                        const SizedBox(height: 24),
                        Text(
                          l10n.userManagement,
                          style: AppTextStyles.headingSmall,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                title: l10n.regularUsers,
                                value: '$regularUsers',
                                subtitle: l10n.customerAccounts,
                                icon: Icons.person_outline,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FilteredUsersPage(
                                      title: l10n.regularUsers,
                                      roles: const ['user'],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _StatCard(
                                title: l10n.boutiqueOwners,
                                value: '$boutiqueOwners',
                                subtitle: l10n.ownerAccounts,
                                icon: Icons.store_mall_directory_outlined,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FilteredUsersPage(
                                      title: l10n.boutiqueOwners,
                                      roles: const ['boutique_owner'],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                title: l10n.admins,
                                value: '$admins',
                                subtitle: l10n.adminAccounts,
                                icon: Icons.admin_panel_settings_outlined,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FilteredUsersPage(
                                      title: l10n.admins,
                                      roles: const ['admin'],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _StatCard(
                                title: l10n.superAdmin,
                                value: '$superAdmins',
                                subtitle: l10n.fullAccessAccount,
                                icon: Icons.verified_user_outlined,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FilteredUsersPage(
                                      title: l10n.superAdmin,
                                      roles: const ['super_admin'],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // ── Marketplace control ───────────────────
                        const SizedBox(height: 24),
                        Text(
                          l10n.marketplaceControl,
                          style: AppTextStyles.headingSmall,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                title: l10n.homepage,
                                value: l10n.featured,
                                subtitle: l10n.boutiquesAndProducts,
                                icon: Icons.home_outlined,
                                compactValue: true,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AdminHomepagePage(),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _StatCard(
                                title: l10n.heroBanners,
                                value: l10n.manage,
                                subtitle: l10n.uploadAndScheduleBanners,
                                icon: Icons.image_outlined,
                                compactValue: true,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const HeroBannerManagementPage(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                title: l10n.disputes,
                                value: l10n.review,
                                subtitle: l10n.customerOrderDisputes,
                                icon: Icons.flag_outlined,
                                compactValue: true,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const DisputesPage(),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _StatCard(
                                title: l10n.notifications,
                                value: l10n.send,
                                subtitle: l10n.messageUsers,
                                icon: Icons.notifications_active_outlined,
                                compactValue: true,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const SendNotificationPage(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                title: l10n.analytics,
                                value: l10n.reports,
                                subtitle: l10n.viewInsights,
                                icon: Icons.analytics_outlined,
                                compactValue: true,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AdminAnalyticsPage(),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _StatCard(
                                title: l10n.revenue,
                                value: l10n.breakdown,
                                subtitle: l10n.commissionsAndPromoSlots,
                                icon: Icons.account_balance_outlined,
                                compactValue: true,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AdminRevenuePage(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // ── Promotions ────────────────────────────
                        const SizedBox(height: 24),
                        Text('Promotions', style: AppTextStyles.headingSmall),
                        const SizedBox(height: 10),
                        _StatCard(
                          title: 'Discount Codes',
                          value: 'Manage',
                          subtitle:
                              'Create and toggle discount codes for buyers.',
                          icon: Icons.local_offer_outlined,
                          compactValue: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DiscountCodesPage(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _StatCard(
                          title: l10n.promoBannerApprovals,
                          value: l10n.review,
                          subtitle: l10n.promoBannerApprovalsSubtitle,
                          icon: Icons.verified_outlined,
                          compactValue: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PromoBannerApprovalPage(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _StatCard(
                          title: l10n.promoCreditAdmin,
                          value: l10n.promoCreditLaunchRecharge,
                          subtitle: l10n.promoCreditAdminSubtitle,
                          icon: Icons.card_giftcard_outlined,
                          compactValue: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PromoCreditAdminPage(),
                            ),
                          ),
                        ),

                        // ── Boutique management ───────────────────
                        const SizedBox(height: 24),
                        Text(
                          l10n.boutiqueManagement,
                          style: AppTextStyles.headingSmall,
                        ),
                        const SizedBox(height: 10),
                        _StatCard(
                          title: l10n.boutiqueOnboarding,
                          value: l10n.onboard,
                          subtitle: l10n.boutiqueOnboardingSubtitle,
                          icon: Icons.store_outlined,
                          compactValue: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BoutiqueOnboardingPage(),
                            ),
                          ),
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

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool compactValue;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.onTap,
    this.compactValue = false,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelLarge.copyWith(
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: compactValue
                ? AppTextStyles.headingSmall
                : AppTextStyles.headingMedium,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall,
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return InkWell(borderRadius: BorderRadius.zero, onTap: onTap, child: card);
  }
}
