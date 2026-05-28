import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import '../navigation/app_header.dart';
import '../navigation/main_navigation_bar.dart';
import '../services/firestore_service.dart';
import '../main.dart';
import '../widgets/theme.dart';
import 'help_and_support_page.dart';
import 'owner_dashboard_page.dart';
import 'saved_addresses_page.dart';
import 'saved_boutiques_page.dart';
import 'saved_items_page.dart';
import 'super_admin_dashboard_page.dart';
import 'your_account_page.dart';

// ── Pure helpers ──────────────────────────────────────────────────────────────

Widget _buildTile({
  required IconData icon,
  required String title,
  required VoidCallback onTap,
}) {
  return Column(
    children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppColors.primaryText),
        title: Text(title, style: AppTextStyles.bodyLarge),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: AppColors.secondaryText,
        ),
        onTap: onTap,
      ),
      const Divider(),
    ],
  );
}

Future<void> _launchUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ── Page ──────────────────────────────────────────────────────────────────────

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isOwner = false;
  bool _isSuperAdmin = false;
  bool _isCheckingAccess = true;

  @override
  void initState() {
    super.initState();
    _checkAccessStatus();
  }

  Future<void> _checkAccessStatus() async {
    try {
      final results = await Future.wait([
        FirestoreService.isCurrentUserApprovedOwner(),
        FirestoreService.isCurrentUserSuperAdmin(),
      ]);
      if (!mounted) return;
      setState(() {
        _isOwner = results[0];
        _isSuperAdmin = results[1];
        _isCheckingAccess = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isOwner = false;
        _isSuperAdmin = false;
        _isCheckingAccess = false;
      });
    }
  }

  void _toggleLanguage() {
    final currentLocale = Localizations.localeOf(context).languageCode;
    LibskApp.setLocale(
      context,
      currentLocale == 'ar' ? const Locale('en') : const Locale('ar'),
    );
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    try {
      await FirestoreService.deleteCurrentUserFcmToken();
    } catch (_) {}
    await FirestoreService.setCurrentUserOffline();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => MainNavigationPage(onLanguageChange: (_) {}),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final user = FirebaseAuth.instance.currentUser;
    final displayName =
        (user?.displayName != null && user!.displayName!.trim().isNotEmpty)
        ? user.displayName!
        : l10n.user;
    final email = user?.email ?? l10n.noEmail;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

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

                    // ── Avatar ────────────────────────────────────────
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 35,
                          backgroundColor: AppColors.deepAccent,
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
                                style: AppTextStyles.headingMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 30),

                    // ── Account ───────────────────────────────────────
                    Text(l10n.accountSection, style: AppTextStyles.capsLabel),
                    const SizedBox(height: 10),
                    _buildTile(
                      icon: Icons.person_outline,
                      title: l10n.yourAccount,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const YourAccountPage(),
                          ),
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                    _buildTile(
                      icon: Icons.favorite,
                      title: l10n.savedItems,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SavedItemsPage(),
                        ),
                      ),
                    ),
                    _buildTile(
                      icon: Icons.store,
                      title: l10n.savedBoutiques,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SavedBoutiquesPage(),
                        ),
                      ),
                    ),
                    _buildTile(
                      icon: Icons.location_on,
                      title: l10n.savedAddresses,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SavedAddressesPage(),
                        ),
                      ),
                    ),

                    // ── Access check loading ──────────────────────────
                    if (_isCheckingAccess) ...[
                      const SizedBox(height: 20),
                      const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.deepAccent,
                          ),
                        ),
                      ),
                    ],

                    // ── Super admin ───────────────────────────────────
                    if (!_isCheckingAccess && _isSuperAdmin) ...[
                      const SizedBox(height: 30),
                      Text(l10n.adminSection, style: AppTextStyles.capsLabel),
                      const SizedBox(height: 10),
                      _buildTile(
                        icon: Icons.admin_panel_settings_outlined,
                        title: l10n.superAdminDashboard,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SuperAdminDashboardPage(),
                          ),
                        ),
                      ),
                    ],

                    // ── Boutique owner ────────────────────────────────
                    if (!_isCheckingAccess && _isOwner) ...[
                      const SizedBox(height: 30),
                      Text(
                        l10n.boutiqueSection,
                        style: AppTextStyles.capsLabel,
                      ),
                      const SizedBox(height: 10),
                      _buildTile(
                        icon: Icons.storefront_outlined,
                        title: l10n.boutiqueDashboard,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const OwnerDashboardPage(),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 30),

                    // ── Language ──────────────────────────────────────
                    Text(l10n.languages, style: AppTextStyles.capsLabel),
                    const SizedBox(height: 10),
                    _buildTile(
                      icon: Icons.language,
                      title: isArabic ? '🇰🇼 العربية' : '🇬🇧 English',
                      onTap: _toggleLanguage,
                    ),

                    const SizedBox(height: 30),

                    // ── Support & legal ───────────────────────────────
                    Text(l10n.supportSection, style: AppTextStyles.capsLabel),
                    const SizedBox(height: 10),
                    _buildTile(
                      icon: Icons.help_outline,
                      title: l10n.helpSupport,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const HelpSupportPage(),
                        ),
                      ),
                    ),
                    _buildTile(
                      icon: Icons.privacy_tip_outlined,
                      title: l10n.privacyPolicy,
                      onTap: () => _launchUrl('https://libsk.com/privacy.html'),
                    ),
                    _buildTile(
                      icon: Icons.description_outlined,
                      title: l10n.termsOfUse,
                      onTap: () => _launchUrl('https://libsk.com/terms.html'),
                    ),

                    const SizedBox(height: 30),

                    // ── Logout ────────────────────────────────────────
                    _buildTile(
                      icon: Icons.logout,
                      title: l10n.logout,
                      onTap: _logout,
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
}
