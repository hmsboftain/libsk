import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../navigation/main_navigation_bar.dart';
import '../services/firestore_service.dart';
import '../main.dart';
import 'saved_items_page.dart';
import 'saved_boutiques_page.dart';
import 'saved_addresses_page.dart';
import 'your_account_page.dart';
import 'owner_dashboard_page.dart';
import 'super_admin_dashboard_page.dart';
import 'help_and_support_page.dart';
import '../widgets/theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool isOwner = false;
  bool isSuperAdmin = false;
  bool isCheckingAccess = true;

  @override
  void initState() {
    super.initState();
    checkAccessStatus();
  }

  Future<void> checkAccessStatus() async {
    try {
      final results = await Future.wait([
        FirestoreService.isCurrentUserApprovedOwner(),
        FirestoreService.isCurrentUserSuperAdmin(),
      ]);

      if (!mounted) return;

      setState(() {
        isOwner = results[0];
        isSuperAdmin = results[1];
        isCheckingAccess = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isOwner = false;
        isSuperAdmin = false;
        isCheckingAccess = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final displayName =
    (user?.displayName != null && user!.displayName!.trim().isNotEmpty)
        ? user.displayName!
        : AppLocalizations.of(context)!.user;

    final email = user?.email ?? AppLocalizations.of(context)!.noEmail;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 35,
                          backgroundColor: Colors.black,
                          child: Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 35,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 30),

                    Text(
                      AppLocalizations.of(context)!.accountSection,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),

                    _buildTile(
                      icon: Icons.person_outline,
                      title: AppLocalizations.of(context)!.yourAccount,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const YourAccountPage(),
                          ),
                        );
                        if (mounted) setState(() {});
                      },
                    ),

                    _buildTile(
                      icon: Icons.favorite,
                      title: AppLocalizations.of(context)!.savedItems,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SavedItemsPage(),
                          ),
                        );
                      },
                    ),

                    _buildTile(
                      icon: Icons.store,
                      title: AppLocalizations.of(context)!.savedBoutiques,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SavedBoutiquesPage(),
                          ),
                        );
                      },
                    ),

                    _buildTile(
                      icon: Icons.location_on,
                      title: AppLocalizations.of(context)!.savedAddresses,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SavedAddressesPage(),
                          ),
                        );
                      },
                    ),

                    if (isCheckingAccess) ...[
                      const SizedBox(height: 20),
                      const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],

                    if (!isCheckingAccess && isSuperAdmin) ...[
                      const SizedBox(height: 30),
                      Text(
                        AppLocalizations.of(context)!.adminSection,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildTile(
                        icon: Icons.admin_panel_settings_outlined,
                        title:
                        AppLocalizations.of(context)!.superAdminDashboard,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                              const SuperAdminDashboardPage(),
                            ),
                          );
                        },
                      ),
                    ],

                    if (!isCheckingAccess && isOwner) ...[
                      const SizedBox(height: 30),
                      Text(
                        AppLocalizations.of(context)!.boutiqueSection,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildTile(
                        icon: Icons.storefront_outlined,
                        title: AppLocalizations.of(context)!.boutiqueDashboard,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const OwnerDashboardPage(),
                            ),
                          );
                        },
                      ),
                    ],

                    const SizedBox(height: 30),

                    Text(
                      AppLocalizations.of(context)!.languages,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),

                    _buildTile(
                      icon: Icons.language,
                      title:
                      Localizations.localeOf(context).languageCode == 'ar'
                          ? '🇰🇼 العربية'
                          : '🇬🇧 English',
                      onTap: () {
                        final currentLocale =
                            Localizations.localeOf(context).languageCode;

                        if (currentLocale == 'ar') {
                          LibskApp.setLocale(context, const Locale('en'));
                        } else {
                          LibskApp.setLocale(context, const Locale('ar'));
                        }
                      },
                    ),

                    const SizedBox(height: 30),

                    Text(
                      AppLocalizations.of(context)!.supportSection,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),

                    _buildTile(
                      icon: Icons.help_outline,
                      title: AppLocalizations.of(context)!.helpSupport,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const HelpSupportPage(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 30),

                    _buildTile(
                      icon: Icons.logout,
                      title: AppLocalizations.of(context)!.logout,
                      onTap: () async {
                        final navigator = Navigator.of(context);

                        await FirestoreService.deleteCurrentUserFcmToken();
                        await FirestoreService.setCurrentUserOffline();
                        await FirebaseAuth.instance.signOut();

                        if (!mounted) return;

                        navigator.pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (context) => MainNavigationPage(
                              onLanguageChange: (_) {},
                            ),
                          ),
                              (route) => false,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(title),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: onTap,
        ),
        const Divider(),
      ],
    );
  }
}