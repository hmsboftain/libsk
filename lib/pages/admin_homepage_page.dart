import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../models/product.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';

// ── Pure helpers ──────────────────────────────────────────────────────────────

Widget _buildSectionTitle(String title) =>
    Text(title, style: AppTextStyles.headingSmall);

Widget _buildInfoText(String text) =>
    Text(text, style: AppTextStyles.bodySmall.copyWith(height: 1.4));

Widget _buildDaysButton(String text, VoidCallback onTap) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.zero,
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.softAccent.withValues(alpha: 0.25),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Text(
          text,
          style: AppTextStyles.labelSmall.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.deepAccent,
          ),
        ),
      ),
    ),
  );
}

Future<void> _toggleBoutiqueVisibility({
  required String boutiqueId,
  required bool currentValue,
}) async {
  await FirebaseFirestore.instance
      .collection('boutiques')
      .doc(boutiqueId)
      .update({'isVisibleOnHome': !currentValue});
}

Future<void> _toggleProductFeatured({
  required String boutiqueId,
  required String productId,
  required bool currentValue,
}) async {
  await FirebaseFirestore.instance
      .collection('boutiques')
      .doc(boutiqueId)
      .collection('products')
      .doc(productId)
      .update({'isFeaturedOnHome': !currentValue});
}

// Sets an expiry timestamp so the feature can be auto-removed later
Future<void> _featureBoutiqueForDays({
  required String boutiqueId,
  required int days,
}) async {
  await FirebaseFirestore.instance
      .collection('boutiques')
      .doc(boutiqueId)
      .update({
        'isVisibleOnHome': true,
        'homeFeatureDays': days,
        'homeExpiresAt': Timestamp.fromDate(
          DateTime.now().add(Duration(days: days)),
        ),
      });
}

Future<void> _featureProductForDays({
  required String boutiqueId,
  required String productId,
  required int days,
}) async {
  await FirebaseFirestore.instance
      .collection('boutiques')
      .doc(boutiqueId)
      .collection('products')
      .doc(productId)
      .update({
        'isFeaturedOnHome': true,
        'featuredDays': days,
        'featuredExpiresAt': Timestamp.fromDate(
          DateTime.now().add(Duration(days: days)),
        ),
      });
}

// ── Page ──────────────────────────────────────────────────────────────────────

class AdminHomepagePage extends StatefulWidget {
  const AdminHomepagePage({super.key});

  @override
  State<AdminHomepagePage> createState() => _AdminHomepagePageState();
}

class _AdminHomepagePageState extends State<AdminHomepagePage> {
  // Created once — avoids opening new Firestore listeners on every rebuild
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _boutiquesStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _productsStream;

  @override
  void initState() {
    super.initState();
    // Query is already ordered — client-side sort removed
    _boutiquesStream = FirebaseFirestore.instance
        .collection('boutiques')
        .orderBy('name')
        .snapshots();

    // collectionGroup reads all products — acceptable for admin control panel
    // but consider paginating or adding a filter when the catalog grows large
    _productsStream = FirebaseFirestore.instance
        .collectionGroup('products')
        .orderBy('title')
        .snapshots();
  }

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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.homepageControl,
                      style: AppTextStyles.displayMedium,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoText(l10n.homepageControlDescription),
                    const SizedBox(height: 24),

                    // ── Homepage Boutiques ────────────────────────────
                    _buildSectionTitle(l10n.homepageBoutiques),
                    const SizedBox(height: 8),
                    _buildInfoText(l10n.homepageBoutiquesDescription),
                    const SizedBox(height: 12),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _boutiquesStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: CircularProgressIndicator(
                                color: AppColors.deepAccent,
                              ),
                            ),
                          );
                        }

                        if (snapshot.hasError) {
                          return Text(
                            l10n.failedToLoadBoutiques,
                            style: AppTextStyles.bodyMedium,
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];

                        if (docs.isEmpty) {
                          return Text(
                            l10n.noBoutiquesFound,
                            style: AppTextStyles.bodyMedium,
                          );
                        }

                        return Column(
                          children: docs.map((doc) {
                            final data = doc.data();
                            final boutiqueId = doc.id;
                            final boutiqueName =
                                data['name']?.toString() ?? l10n.boutique;
                            final isVisibleOnHome =
                                data['isVisibleOnHome'] == true;
                            final homeOrder =
                                data['homeOrder']?.toString() ??
                                l10n.noOrderSet;

                            return _ToggleCard(
                              title: boutiqueName,
                              subtitle: l10n.homepageOrderSubtitle(homeOrder),
                              value: isVisibleOnHome,
                              onChanged: (_) => _toggleBoutiqueVisibility(
                                boutiqueId: boutiqueId,
                                currentValue: isVisibleOnHome,
                              ),
                              on7Days: () => _featureBoutiqueForDays(
                                boutiqueId: boutiqueId,
                                days: 7,
                              ),
                              on14Days: () => _featureBoutiqueForDays(
                                boutiqueId: boutiqueId,
                                days: 14,
                              ),
                              on30Days: () => _featureBoutiqueForDays(
                                boutiqueId: boutiqueId,
                                days: 30,
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // ── Featured Products ─────────────────────────────
                    _buildSectionTitle(l10n.featuredProducts),
                    const SizedBox(height: 8),
                    _buildInfoText(l10n.featuredProductsDescription),
                    const SizedBox(height: 12),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _productsStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: CircularProgressIndicator(
                                color: AppColors.deepAccent,
                              ),
                            ),
                          );
                        }

                        if (snapshot.hasError) {
                          return Text(
                            l10n.failedToLoadProducts,
                            style: AppTextStyles.bodyMedium,
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];

                        if (docs.isEmpty) {
                          return Text(
                            l10n.noProductsFound,
                            style: AppTextStyles.bodyMedium,
                          );
                        }

                        return Column(
                          children: docs.map((doc) {
                            final data = doc.data();
                            final product = Product.fromFirestore(doc);
                            final productId = product.id;
                            final boutiqueId = doc.reference.parent.parent!.id;
                            final title = product.title.isNotEmpty
                                ? product.title
                                : l10n.untitledProduct;
                            final boutiqueName = product.boutiqueName.isNotEmpty
                                ? product.boutiqueName
                                : l10n.boutique;
                            final isFeaturedOnHome =
                                data['isFeaturedOnHome'] == true;
                            final featuredOrder =
                                data['featuredOrder']?.toString() ??
                                l10n.noOrderSet;

                            return _ToggleCard(
                              title: title,
                              subtitle: l10n.featuredOrderSubtitle(
                                boutiqueName,
                                featuredOrder,
                              ),
                              value: isFeaturedOnHome,
                              onChanged: (_) => _toggleProductFeatured(
                                boutiqueId: boutiqueId,
                                productId: productId,
                                currentValue: isFeaturedOnHome,
                              ),
                              on7Days: () => _featureProductForDays(
                                boutiqueId: boutiqueId,
                                productId: productId,
                                days: 7,
                              ),
                              on14Days: () => _featureProductForDays(
                                boutiqueId: boutiqueId,
                                productId: productId,
                                days: 14,
                              ),
                              on30Days: () => _featureProductForDays(
                                boutiqueId: boutiqueId,
                                productId: productId,
                                days: 30,
                              ),
                            );
                          }).toList(),
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
}

// ── Toggle card widget ────────────────────────────────────────────────────────

class _ToggleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback on7Days;
  final VoidCallback on14Days;
  final VoidCallback on30Days;

  const _ToggleCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.on7Days,
    required this.on14Days,
    required this.on30Days,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.softAccent.withValues(alpha: 0.22),
                child: const Icon(
                  Icons.tune_rounded,
                  color: AppColors.deepAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: AppColors.deepAccent,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildDaysButton('7d', on7Days),
              _buildDaysButton('14d', on14Days),
              _buildDaysButton('30d', on30Days),
            ],
          ),
        ],
      ),
    );
  }
}
