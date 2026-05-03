import 'package:cloud_firestore/cloud_firestore.dart';
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

class SuperAdminDashboardPage extends StatelessWidget {
  const SuperAdminDashboardPage({super.key});

  int _countRecentlyActiveUsers(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final now = DateTime.now();

    return docs.where((doc) {
      final lastSeenValue = doc.data()['lastSeenAt'];

      if (lastSeenValue is! Timestamp) return false;

      final lastSeen = lastSeenValue.toDate();
      final difference = now.difference(lastSeen);

      return difference.inMinutes <= 5;
    }).length;
  }

  double _sumSales(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    double total = 0;

    for (final doc in docs) {
      final value = doc.data()['total'] ?? 0;

      if (value is num) {
        total += value.toDouble();
      } else {
        total += double.tryParse(value.toString()) ?? 0;
      }
    }

    return total;
  }

  int _countRole(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      String role,
      ) {
    return docs.where((doc) => doc.data()['role'] == role).length;
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
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.softAccent.withValues(alpha:0.22),
            child: Icon(
              icon,
              color: AppColors.deepAccent,
              size: 20,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.secondaryText,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compactValue ? 18 : 24,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.secondaryText,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: card,
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
                stream: FirestoreService.getAllUsersStream(),
                builder: (context, usersSnapshot) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirestoreService.getAllBoutiquesStream(),
                    builder: (context, boutiquesSnapshot) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirestoreService.getAllBoutiqueOrdersStream(),
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
                                style: TextStyle(
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            );
                          }

                          final userDocs = usersSnapshot.data?.docs ?? [];
                          final boutiqueDocs =
                              boutiquesSnapshot.data?.docs ?? [];
                          final allOrderDocs = ordersSnapshot.data?.docs ?? [];

                          final boutiqueOrderDocs = allOrderDocs.where((doc) {
                            final data = doc.data();
                            return data['sourceUserOrderId'] != null;
                          }).toList();

                          final totalUsers = userDocs.length;
                          final recentlyActiveUsers =
                          _countRecentlyActiveUsers(userDocs);
                          final totalBoutiques = boutiqueDocs.length;
                          final totalOrders = boutiqueOrderDocs.length;
                          final totalSales = _sumSales(boutiqueOrderDocs);

                          final regularUsers = _countRole(userDocs, 'user');
                          final boutiqueOwners =
                          _countRole(userDocs, 'boutique_owner');
                          final admins = _countRole(userDocs, 'admin');
                          final superAdmins =
                          _countRole(userDocs, 'super_admin');

                          return SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'SUPER ADMIN',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryText,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Overview of your marketplace activity.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.secondaryText,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Total Users',
                                        value: totalUsers.toString(),
                                        subtitle: 'All registered users',
                                        icon: Icons.people_alt_outlined,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                              const AllUsersPage(),
                                            ),
                                          );
                                        },
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
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                              const AdminBoutiquesPage(),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Global Orders',
                                        value: totalOrders.toString(),
                                        subtitle: 'Across all boutiques',
                                        icon: Icons.receipt_long_outlined,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                              const GlobalOrdersPage(),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                InkWell(
                                  borderRadius: BorderRadius.circular(22),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                        const BoutiqueSalesPage(),
                                      ),
                                    );
                                  },
                                  child: buildStatCard(
                                    title: 'Total Sales',
                                    value:
                                    '${totalSales.toStringAsFixed(0)} KWD',
                                    subtitle: 'Tap to view boutique sales',
                                    icon: Icons.trending_up_rounded,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                const Text(
                                  'User Management',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryText,
                                  ),
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
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                              const FilteredUsersPage(
                                                title: 'Regular Users',
                                                roles: ['user'],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Boutique Owners',
                                        value: boutiqueOwners.toString(),
                                        subtitle: 'Owner accounts',
                                        icon: Icons
                                            .store_mall_directory_outlined,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                              const FilteredUsersPage(
                                                title: 'Boutique Owners',
                                                roles: ['boutique_owner'],
                                              ),
                                            ),
                                          );
                                        },
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
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                              const FilteredUsersPage(
                                                title: 'Admins',
                                                roles: ['admin'],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Super Admin',
                                        value: superAdmins.toString(),
                                        subtitle: 'Full access account',
                                        icon: Icons.verified_user_outlined,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                              const FilteredUsersPage(
                                                title: 'Super Admin',
                                                roles: ['super_admin'],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                const Text(
                                  'Marketplace Control',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryText,
                                  ),
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
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                              const AdminHomepagePage(),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Disputes',
                                        value: 'Review',
                                        subtitle: 'Customer order disputes',
                                        icon: Icons.flag_outlined,
                                        compactValue: true,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                              const DisputesPage(),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Notifications',
                                        value: 'Send',
                                        compactValue: true,
                                        subtitle: 'Message users',
                                        icon: Icons
                                            .notifications_active_outlined,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                              const SendNotificationPage(),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: buildStatCard(
                                        title: 'Analytics',
                                        value: 'Reports',
                                        compactValue: true,
                                        subtitle: 'View insights',
                                        icon: Icons.analytics_outlined,
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                              const AdminAnalyticsPage(),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
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