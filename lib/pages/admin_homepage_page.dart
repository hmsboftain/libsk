import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';

class AdminHomepagePage extends StatelessWidget {
  const AdminHomepagePage({super.key});

  Future<void> toggleBoutiqueVisibility({
    required String boutiqueId,
    required bool currentValue,
  }) async {
    await FirebaseFirestore.instance
        .collection('boutiques')
        .doc(boutiqueId)
        .update({
      'isVisibleOnHome': !currentValue,
    });
  }

  Future<void> toggleProductFeatured({
    required String boutiqueId,
    required String productId,
    required bool currentValue,
  }) async {
    await FirebaseFirestore.instance
        .collection('boutiques')
        .doc(boutiqueId)
        .collection('products')
        .doc(productId)
        .update({
      'isFeaturedOnHome': !currentValue,
    });
  }

  Future<void> featureBoutiqueForDays({
    required String boutiqueId,
    required int days,
  }) async {
    final expiresAt = Timestamp.fromDate(
      DateTime.now().add(Duration(days: days)),
    );

    await FirebaseFirestore.instance
        .collection('boutiques')
        .doc(boutiqueId)
        .update({
      'isVisibleOnHome': true,
      'homeFeatureDays': days,
      'homeExpiresAt': expiresAt,
    });
  }

  Future<void> featureProductForDays({
    required String boutiqueId,
    required String productId,
    required int days,
  }) async {
    final expiresAt = Timestamp.fromDate(
      DateTime.now().add(Duration(days: days)),
    );

    await FirebaseFirestore.instance
        .collection('boutiques')
        .doc(boutiqueId)
        .collection('products')
        .doc(productId)
        .update({
      'isFeaturedOnHome': true,
      'featuredDays': days,
      'featuredExpiresAt': expiresAt,
    });
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

  Widget buildInfoText(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        color: AppColors.secondaryText,
        height: 1.4,
      ),
    );
  }

  Widget _buildDaysButton(String text, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.softAccent.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.deepAccent,
            ),
          ),
        ),
      ),
    );
  }

  Widget buildToggleCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required VoidCallback on7Days,
    required VoidCallback on14Days,
    required VoidCallback on30Days,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.softAccent..withValues(alpha: 0.22),
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
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.secondaryText,
                        height: 1.4,
                      ),
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

  @override
  Widget build(BuildContext context) {
    final boutiquesStream = FirebaseFirestore.instance
        .collection('boutiques')
        .orderBy('name')
        .snapshots();

    final featuredProductsStream =
    FirebaseFirestore.instance.collectionGroup('products').snapshots();

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
                    const Text(
                      'HOMEPAGE CONTROL',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    buildInfoText(
                      'Choose which boutiques appear on the homepage and which products appear in featured pieces.',
                    ),
                    const SizedBox(height: 24),
                    buildSectionTitle('Homepage Boutiques'),
                    const SizedBox(height: 8),
                    buildInfoText(
                      'Turn boutiques on or off for the Explore Boutiques section on the home page.',
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: boutiquesStream,
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
                          return const Text(
                            'Failed to load boutiques',
                            style: TextStyle(color: AppColors.secondaryText),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];
                        docs.sort((a, b) {
                          final nameA = a.data()['name']?.toString() ?? '';
                          final nameB = b.data()['name']?.toString() ?? '';
                          return nameA
                              .toLowerCase()
                              .compareTo(nameB.toLowerCase());
                        });

                        if (docs.isEmpty) {
                          return const Text(
                            'No boutiques found.',
                            style: TextStyle(color: AppColors.secondaryText),
                          );
                        }

                        return Column(
                          children: docs.map((doc) {
                            final data = doc.data();
                            final boutiqueId = doc.id;
                            final boutiqueName =
                                data['name']?.toString() ?? 'Boutique';
                            final isVisibleOnHome =
                                data['isVisibleOnHome'] == true;
                            final homeOrder =
                                data['homeOrder']?.toString() ?? 'No order set';

                            return buildToggleCard(
                              title: boutiqueName,
                              subtitle: 'Homepage order: $homeOrder',
                              value: isVisibleOnHome,
                              onChanged: (_) async {
                                await toggleBoutiqueVisibility(
                                  boutiqueId: boutiqueId,
                                  currentValue: isVisibleOnHome,
                                );
                              },
                              on7Days: () async {
                                await featureBoutiqueForDays(
                                  boutiqueId: boutiqueId,
                                  days: 7,
                                );
                              },
                              on14Days: () async {
                                await featureBoutiqueForDays(
                                  boutiqueId: boutiqueId,
                                  days: 14,
                                );
                              },
                              on30Days: () async {
                                await featureBoutiqueForDays(
                                  boutiqueId: boutiqueId,
                                  days: 30,
                                );
                              },
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    buildSectionTitle('Featured Products'),
                    const SizedBox(height: 8),
                    buildInfoText(
                      'Turn products on or off for the Featured Pieces section on the home page.',
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: featuredProductsStream,
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
                          return const Text(
                            'Failed to load products',
                            style: TextStyle(color: AppColors.secondaryText),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];
                        docs.sort((a, b) {
                          final titleA = a.data()['title']?.toString() ?? '';
                          final titleB = b.data()['title']?.toString() ?? '';
                          return titleA
                              .toLowerCase()
                              .compareTo(titleB.toLowerCase());
                        });

                        if (docs.isEmpty) {
                          return const Text(
                            'No products found.',
                            style: TextStyle(color: AppColors.secondaryText),
                          );
                        }

                        return Column(
                          children: docs.map((doc) {
                            final data = doc.data();
                            final productId = doc.id;
                            final boutiqueId = doc.reference.parent.parent!.id;

                            final title =
                                data['title']?.toString() ?? 'Untitled Product';
                            final boutiqueName =
                                data['boutiqueName']?.toString() ?? 'Boutique';
                            final isFeaturedOnHome =
                                data['isFeaturedOnHome'] == true;
                            final featuredOrder =
                                data['featuredOrder']?.toString() ??
                                    'No order set';

                            return buildToggleCard(
                              title: title,
                              subtitle:
                              '$boutiqueName • Featured order: $featuredOrder',
                              value: isFeaturedOnHome,
                              onChanged: (_) async {
                                await toggleProductFeatured(
                                  boutiqueId: boutiqueId,
                                  productId: productId,
                                  currentValue: isFeaturedOnHome,
                                );
                              },
                              on7Days: () async {
                                await featureProductForDays(
                                  boutiqueId: boutiqueId,
                                  productId: productId,
                                  days: 7,
                                );
                              },
                              on14Days: () async {
                                await featureProductForDays(
                                  boutiqueId: boutiqueId,
                                  productId: productId,
                                  days: 14,
                                );
                              },
                              on30Days: () async {
                                await featureProductForDays(
                                  boutiqueId: boutiqueId,
                                  productId: productId,
                                  days: 30,
                                );
                              },
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