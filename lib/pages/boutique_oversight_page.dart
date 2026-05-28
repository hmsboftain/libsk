import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import 'boutique_storefront_page.dart';
import '../widgets/theme.dart';

// ── Pure helpers ──────────────────────────────────────────────────────────────

double _sumSales(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  return docs.fold(0.0, (total, doc) {
    final v = doc.data()['total'] ?? 0;
    return total +
        (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
  });
}

String _getOwnerName(Map<String, dynamic>? ownerData, AppLocalizations l10n) {
  if (ownerData == null) return l10n.unknownOwner;
  final name =
      ownerData['Name']?.toString().trim() ??
      ownerData['name']?.toString().trim() ??
      ownerData['fullName']?.toString().trim() ??
      '';
  return name.isNotEmpty ? name : l10n.unknownOwner;
}

String _getOwnerEmail(Map<String, dynamic>? ownerData, AppLocalizations l10n) {
  if (ownerData == null) return l10n.noEmail;
  final email =
      ownerData['Email']?.toString().trim() ??
      ownerData['email']?.toString().trim() ??
      '';
  return email.isNotEmpty ? email : l10n.noEmail;
}

// ── Page ──────────────────────────────────────────────────────────────────────

class BoutiqueOversightPage extends StatefulWidget {
  final String boutiqueId;

  const BoutiqueOversightPage({super.key, required this.boutiqueId});

  @override
  State<BoutiqueOversightPage> createState() => _BoutiqueOversightPageState();
}

class _BoutiqueOversightPageState extends State<BoutiqueOversightPage> {
  // Pinned once — avoids re-firing 4 Firestore reads on every rebuild
  late final Future<Map<String, dynamic>> _overviewFuture;

  @override
  void initState() {
    super.initState();
    _overviewFuture = _loadBoutiqueOverview();
  }

  Future<Map<String, dynamic>> _loadBoutiqueOverview() async {
    final firestore = FirebaseFirestore.instance;
    final boutiqueRef = firestore
        .collection('boutiques')
        .doc(widget.boutiqueId);

    final boutiqueSnapshot = await boutiqueRef.get();
    if (!boutiqueSnapshot.exists) throw Exception('Boutique not found');

    final boutiqueData = boutiqueSnapshot.data() ?? {};
    final ownerUid = boutiqueData['ownerUid']?.toString() ?? '';

    // Products, orders, and owner read in parallel
    final results = await Future.wait([
      boutiqueRef.collection('products').get(),
      boutiqueRef.collection('orders').get(),
      ownerUid.isNotEmpty
          ? firestore.collection('boutique_owners').doc(ownerUid).get()
          : Future<DocumentSnapshot<Map<String, dynamic>>?>.value(null),
    ]);

    return {
      'boutiqueData': boutiqueData,
      'productDocs': (results[0] as QuerySnapshot<Map<String, dynamic>>).docs,
      'orderDocs': (results[1] as QuerySnapshot<Map<String, dynamic>>).docs,
      'ownerData': (results[2] as DocumentSnapshot<Map<String, dynamic>>?)
          ?.data(),
    };
  }

  void _openStorefront(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BoutiqueStorefrontPage(boutiqueId: widget.boutiqueId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // AppHeader stays fixed — visible on loading and error states too
            const AppHeader(showBackButton: true),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _overviewFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                      ),
                    );
                  }

                  if (snapshot.hasError || !snapshot.hasData) {
                    return Center(
                      child: Text(
                        l10n.failedToLoadBoutiqueOverview,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.secondaryText,
                        ),
                      ),
                    );
                  }

                  final overview = snapshot.data!;
                  final boutiqueData =
                      overview['boutiqueData'] as Map<String, dynamic>? ?? {};
                  final productDocs =
                      overview['productDocs']
                          as List<
                            QueryDocumentSnapshot<Map<String, dynamic>>
                          >? ??
                      [];
                  final orderDocs =
                      overview['orderDocs']
                          as List<
                            QueryDocumentSnapshot<Map<String, dynamic>>
                          >? ??
                      [];
                  final ownerData =
                      overview['ownerData'] as Map<String, dynamic>?;

                  final boutiqueName =
                      boutiqueData['name']?.toString() ?? l10n.boutique;
                  final boutiqueDescription =
                      boutiqueData['description']?.toString() ??
                      l10n.noDescription;
                  final ownerUid = boutiqueData['ownerUid']?.toString() ?? '';
                  final logoPath = boutiqueData['logoPath']?.toString() ?? '';

                  final totalSales = _sumSales(orderDocs);
                  final ownerName = _getOwnerName(ownerData, l10n);
                  final ownerEmail = _getOwnerEmail(ownerData, l10n);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(boutiqueName, style: AppTextStyles.displayMedium),
                        const SizedBox(height: 8),
                        Text(
                          boutiqueDescription,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.secondaryText,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (logoPath.isNotEmpty)
                          Center(
                            child: Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.border,
                                  width: 0.5,
                                ),
                                color: AppColors.imagePlaceholder,
                              ),
                              child: ClipOval(
                                child: Image.network(
                                  logoPath,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.storefront_outlined,
                                    color: AppColors.deepAccent,
                                    size: 32,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),

                        // ── Stats ───────────────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: _OversightStatCard(
                                title: l10n.products,
                                value: productDocs.length.toString(),
                                subtitle: l10n.totalProducts,
                                icon: Icons.checkroom_outlined,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _OversightStatCard(
                                title: l10n.orders,
                                value: orderDocs.length.toString(),
                                subtitle: l10n.boutiqueOrders,
                                icon: Icons.receipt_long_outlined,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _OversightStatCard(
                          title: l10n.sales,
                          value: '${totalSales.toStringAsFixed(0)} KWD',
                          subtitle: l10n.totalBoutiqueSales,
                          icon: Icons.trending_up_rounded,
                        ),

                        const SizedBox(height: 24),

                        // ── Owner details ───────────────────────────
                        Text(
                          l10n.ownerDetails,
                          style: AppTextStyles.headingSmall,
                        ),
                        const SizedBox(height: 12),
                        _InfoBox(label: l10n.ownerName, value: ownerName),
                        _InfoBox(label: l10n.ownerEmail, value: ownerEmail),
                        _InfoBox(label: l10n.ownerUid, value: ownerUid),

                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: () => _openStorefront(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.deepAccent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                            child: Text(
                              l10n.openStorefront,
                              style: AppTextStyles.button,
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
    );
  }
}

// ── Stat card widget ──────────────────────────────────────────────────────────

class _OversightStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  const _OversightStatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
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
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info box widget ───────────────────────────────────────────────────────────

class _InfoBox extends StatelessWidget {
  final String label;
  final String value;

  const _InfoBox({required this.label, required this.value});

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
          Text(
            label,
            style: AppTextStyles.labelLarge.copyWith(
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value.isEmpty ? '-' : value,
            style: AppTextStyles.bodyMedium.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}
