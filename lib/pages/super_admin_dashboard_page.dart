import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import 'admin_boutiques_page.dart';
import 'all_users_page.dart';
import 'filtered_users_page.dart';
import 'global_orders_page.dart';
import 'admin_homepage_page.dart';
import 'boutique_sales_page.dart';
import '../widgets/theme.dart';
import 'disputes_page.dart';
import 'send_notification_page.dart';
import 'admin_analytics_page.dart';
import 'boutique_onboarding_page.dart';
import 'admin_revenue_page.dart';
import 'hero_banner_management_page.dart';

class SuperAdminDashboardPage extends StatefulWidget {
  const SuperAdminDashboardPage({super.key});

  @override
  State<SuperAdminDashboardPage> createState() =>
      _SuperAdminDashboardPageState();
}

class _SuperAdminDashboardPageState extends State<SuperAdminDashboardPage> {
  bool _isReindexing = false;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _boutiquesStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _ordersStream;

  @override
  void initState() {
    super.initState();
    _usersStream = FirestoreService.getAllUsersStream();
    _boutiquesStream = FirestoreService.getAllBoutiquesStream();
    _ordersStream = FirestoreService.getAllBoutiqueOrdersStream();
  }

  int _countRecentlyActiveUsers(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final now = DateTime.now();
    return docs.where((doc) {
      final lastSeenValue = doc.data()['lastSeenAt'];
      if (lastSeenValue is! Timestamp) return false;
      final lastSeen = lastSeenValue.toDate();
      return now.difference(lastSeen).inMinutes <= 5;
    }).length;
  }

  double _sumSales(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    double total = 0;
    for (final doc in docs) {
      final value = doc.data()['total'] ?? 0;
      total += value is num
          ? value.toDouble()
          : double.tryParse(value.toString()) ?? 0;
    }
    return total;
  }

  int _countRole(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String role,
  ) {
    return docs.where((doc) => doc.data()['role'] == role).length;
  }

  Future<void> _reindexAlgolia() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: const RoundedRectangleBorder(),
        title: Text('Reindex Algolia', style: AppTextStyles.headingSmall),
        content: Text(
          'This will push all existing products and boutiques to Algolia search. Only needed once after setup.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: Text('Run Reindex', style: AppTextStyles.button),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isReindexing = true);

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('algoliaReindex');
      final result = await callable.call();
      final data = Map<String, dynamic>.from(result.data as Map);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reindex complete — ${data['productsIndexed']} products, ${data['boutiquesIndexed']} boutiques indexed.',
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? 'Reindex failed')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isReindexing = false);
    }
  }

  Widget buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    VoidCallback? onTap,
    bool compactValue = false,
  }) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.zero,
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
                stream: _usersStream,
                builder: (context, usersSnapshot) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _boutiquesStream,
                    builder: (context, boutiquesSnapshot) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _ordersStream,
                        builder: (context, ordersSnapshot) {
                          if (usersSnapshot.connectionState ==
                                  ConnectionState.waiting ||
                              boutiquesSnapshot.connectionState ==
                                  ConnectionState.waiting ||
                              ordersSnapshot.connectionState ==
                                  ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.deepAccent,
                              ),
                            );
                          }

                          if (usersSnapshot.hasError ||
                              boutiquesSnapshot.hasError ||
                              ordersSnapshot.hasError) {
                            return const Center(
                              child: Text(
                                'Failed to load admin dashboard',
                                style: AppTextStyles.bodyMedium,
                              ),
                            );
                          }

                          final userDocs = usersSnapshot.data?.docs ?? [];
                          final boutiqueDocs =
                              boutiquesSnapshot.data?.docs ?? [];
                          final allOrderDocs = ordersSnapshot.data?.docs ?? [];

                          final boutiqueOrderDocs = allOrderDocs.where((doc) {
                            return doc.data()['sourceUserOrderId'] != null;
                          }).toList();

                          final totalUsers = userDocs.length;
                          final recentlyActiveUsers = _countRecentlyActiveUsers(
                            userDocs,
                          );
                          final totalBoutiques = boutiqueDocs.length;
                          final totalOrders = boutiqueOrderDocs.length;
                          final totalSales = _sumSales(boutiqueOrderDocs);
                          final regularUsers = _countRole(userDocs, 'user');
                          final boutiqueOwners = _countRole(
                            userDocs,
                            'boutique_owner',
                          );
                          final admins = _countRole(userDocs, 'admin');
                          final superAdmins = _countRole(
                            userDocs,
                            'super_admin',
                          );

                          return SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'SUPER ADMIN',
                                  style: AppTextStyles.displayMedium,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Overview of your marketplace activity.',
                                  style: AppTextStyles.bodyMedium,
                                ),
                                const SizedBox(height: 24),

                                // ── Stats ──────────────────────────────
                                Row(
                                  children: [
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Total Users',
                                        value: totalUsers.toString(),
                                        subtitle: 'All registered users',
                                        icon: Icons.people_alt_outlined,
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const AllUsersPage(),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Recently Active',
                                        value: recentlyActiveUsers.toString(),
                                        subtitle: 'Seen in last 5 min',
                                        icon: Icons.wifi_tethering_outlined,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'All Boutiques',
                                        value: totalBoutiques.toString(),
                                        subtitle: 'All boutique documents',
                                        icon: Icons.storefront_outlined,
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const AdminBoutiquesPage(),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Global Orders',
                                        value: totalOrders.toString(),
                                        subtitle: 'Across all boutiques',
                                        icon: Icons.receipt_long_outlined,
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const GlobalOrdersPage(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                buildStatCard(
                                  title: 'Total Sales',
                                  value: '${totalSales.toStringAsFixed(0)} KWD',
                                  subtitle: 'Tap to view boutique sales',
                                  icon: Icons.trending_up_rounded,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const BoutiqueSalesPage(),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 24),

                                // ── User Management ─────────────────────
                                const Text(
                                  'User Management',
                                  style: AppTextStyles.headingSmall,
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Regular Users',
                                        value: regularUsers.toString(),
                                        subtitle: 'Customer accounts',
                                        icon: Icons.person_outline,
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const FilteredUsersPage(
                                                  title: 'Regular Users',
                                                  roles: ['user'],
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Boutique Owners',
                                        value: boutiqueOwners.toString(),
                                        subtitle: 'Owner accounts',
                                        icon:
                                            Icons.store_mall_directory_outlined,
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const FilteredUsersPage(
                                                  title: 'Boutique Owners',
                                                  roles: ['boutique_owner'],
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
                                      child: buildStatCard(
                                        title: 'Admins',
                                        value: admins.toString(),
                                        subtitle: 'Admin accounts',
                                        icon:
                                            Icons.admin_panel_settings_outlined,
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const FilteredUsersPage(
                                                  title: 'Admins',
                                                  roles: ['admin'],
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Super Admin',
                                        value: superAdmins.toString(),
                                        subtitle: 'Full access account',
                                        icon: Icons.verified_user_outlined,
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const FilteredUsersPage(
                                                  title: 'Super Admin',
                                                  roles: ['super_admin'],
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 24),

                                // ── Marketplace Control ──────────────────
                                const Text(
                                  'Marketplace Control',
                                  style: AppTextStyles.headingSmall,
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Homepage',
                                        value: 'Featured',
                                        subtitle: 'Boutiques & products',
                                        icon: Icons.home_outlined,
                                        compactValue: true,
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const AdminHomepagePage(),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Hero Banners',
                                        value: 'Manage',
                                        subtitle: 'Upload & schedule banners',
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
                                      child: buildStatCard(
                                        title: 'Disputes',
                                        value: 'Review',
                                        subtitle: 'Customer order disputes',
                                        icon: Icons.flag_outlined,
                                        compactValue: true,
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const DisputesPage(),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Notifications',
                                        value: 'Send',
                                        subtitle: 'Message users',
                                        icon:
                                            Icons.notifications_active_outlined,
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
                                      child: buildStatCard(
                                        title: 'Analytics',
                                        value: 'Reports',
                                        subtitle: 'View insights',
                                        icon: Icons.analytics_outlined,
                                        compactValue: true,
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const AdminAnalyticsPage(),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Revenue',
                                        value: 'Breakdown',
                                        subtitle: 'Commissions & subscriptions',
                                        icon: Icons.account_balance_outlined,
                                        compactValue: true,
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const AdminRevenuePage(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 24),

                                // ── Boutique Management ──────────────────
                                const Text(
                                  'Boutique Management',
                                  style: AppTextStyles.headingSmall,
                                ),
                                const SizedBox(height: 10),
                                buildStatCard(
                                  title: 'Boutique Onboarding',
                                  value: 'Onboard',
                                  subtitle:
                                      'Register a new boutique owner with tier selection',
                                  icon: Icons.store_outlined,
                                  compactValue: true,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const BoutiqueOnboardingPage(),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 24),

                                // ── Search & Data ────────────────────────
                                const Text(
                                  'Search & Data',
                                  style: AppTextStyles.headingSmall,
                                ),
                                const SizedBox(height: 10),

                                // Reindex Algolia
                                InkWell(
                                  borderRadius: BorderRadius.zero,
                                  onTap: _isReindexing ? null : _reindexAlgolia,
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppColors.card,
                                      border: Border.all(
                                        color: AppColors.border,
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: AppColors.softAccent
                                              .withValues(alpha: 0.22),
                                          child: _isReindexing
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 1.5,
                                                        color: AppColors
                                                            .deepAccent,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.manage_search_outlined,
                                                  color: AppColors.deepAccent,
                                                  size: 20,
                                                ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _isReindexing
                                                    ? 'Indexing...'
                                                    : 'Reindex Algolia',
                                                style: AppTextStyles.labelLarge,
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                'Push all products & boutiques to search index',
                                                style: AppTextStyles.labelSmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.arrow_forward_ios,
                                          size: 12,
                                          color: AppColors.softAccent,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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
}
