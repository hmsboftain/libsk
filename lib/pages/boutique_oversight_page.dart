import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import 'boutique_storefront_page.dart';
import '../widgets/theme.dart';

class BoutiqueOversightPage extends StatelessWidget {
  final String boutiqueId;

  const BoutiqueOversightPage({
    super.key,
    required this.boutiqueId,
  });

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

  Future<Map<String, dynamic>> _loadBoutiqueOverview() async {
    final firestore = FirebaseFirestore.instance;
    final boutiqueRef = firestore.collection('boutiques').doc(boutiqueId);

    final boutiqueSnapshot = await boutiqueRef.get();

    if (!boutiqueSnapshot.exists) {
      throw Exception('Boutique not found');
    }

    final boutiqueData = boutiqueSnapshot.data() ?? {};
    final ownerUid = boutiqueData['ownerUid']?.toString() ?? '';

    final productsFuture = boutiqueRef.collection('products').get();
    final ordersFuture = boutiqueRef.collection('orders').get();

    Future<DocumentSnapshot<Map<String, dynamic>>?> ownerFuture;

    if (ownerUid.isEmpty) {
      ownerFuture = Future.value(null);
    } else {
      ownerFuture = firestore.collection('boutique_owners').doc(ownerUid).get();
    }

    final results = await Future.wait([
      productsFuture,
      ordersFuture,
      ownerFuture,
    ]);

    final productsSnapshot =
    results[0] as QuerySnapshot<Map<String, dynamic>>;
    final ordersSnapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final ownerSnapshot =
    results[2] as DocumentSnapshot<Map<String, dynamic>>?;

    return {
      'boutiqueData': boutiqueData,
      'productDocs': productsSnapshot.docs,
      'orderDocs': ordersSnapshot.docs,
      'ownerData': ownerSnapshot?.data(),
    };
  }

  Widget buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
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
            backgroundColor: AppColors.softAccent.withValues(alpha: 0.22),
            child: Icon(
              icon,
              color: AppColors.deepAccent,
              size: 20,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.secondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildInfoBox({
    required String label,
    required String value,
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
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.primaryText,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
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

  String _getOwnerName(Map<String, dynamic>? ownerData) {
    if (ownerData == null) return 'Unknown Owner';

    final name = ownerData['Name']?.toString().trim() ?? '';
    final lowercaseName = ownerData['name']?.toString().trim() ?? '';
    final fullName = ownerData['fullName']?.toString().trim() ?? '';

    if (name.isNotEmpty) return name;
    if (lowercaseName.isNotEmpty) return lowercaseName;
    if (fullName.isNotEmpty) return fullName;

    return 'Unknown Owner';
  }

  String _getOwnerEmail(Map<String, dynamic>? ownerData) {
    if (ownerData == null) return 'No email';

    final emailUpper = ownerData['Email']?.toString().trim() ?? '';
    final emailLower = ownerData['email']?.toString().trim() ?? '';

    if (emailUpper.isNotEmpty) return emailUpper;
    if (emailLower.isNotEmpty) return emailLower;

    return 'No email';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _loadBoutiqueOverview(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AppColors.deepAccent,
                ),
              );
            }

            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Failed to load boutique overview',
                  style: TextStyle(color: AppColors.secondaryText),
                ),
              );
            }

            final overviewData = snapshot.data ?? {};
            final boutiqueData =
                overviewData['boutiqueData'] as Map<String, dynamic>? ?? {};
            final productDocs =
                overviewData['productDocs']
                as List<QueryDocumentSnapshot<Map<String, dynamic>>>? ??
                    [];
            final orderDocs =
                overviewData['orderDocs']
                as List<QueryDocumentSnapshot<Map<String, dynamic>>>? ??
                    [];
            final ownerData =
            overviewData['ownerData'] as Map<String, dynamic>?;

            final boutiqueName =
                boutiqueData['name']?.toString() ?? 'Boutique';
            final boutiqueDescription =
                boutiqueData['description']?.toString() ?? 'No description';
            final ownerUid = boutiqueData['ownerUid']?.toString() ?? '';
            final logoPath = boutiqueData['logoPath']?.toString() ?? '';

            final totalSales = _sumSales(orderDocs);
            final ownerName = _getOwnerName(ownerData);
            final ownerEmail = _getOwnerEmail(ownerData);

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppHeader(showBackButton: true),
                  const SizedBox(height: 12),
                  Text(
                    boutiqueName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    boutiqueDescription,
                    style: const TextStyle(
                      fontSize: 14,
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
                          ),
                          color: AppColors.field,
                        ),
                        child: ClipOval(
                          child: Image.network(
                            logoPath,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.storefront_outlined,
                                color: AppColors.deepAccent,
                                size: 32,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: buildStatCard(
                          title: 'Products',
                          value: productDocs.length.toString(),
                          subtitle: 'Total products',
                          icon: Icons.checkroom_outlined,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: buildStatCard(
                          title: 'Orders',
                          value: orderDocs.length.toString(),
                          subtitle: 'Boutique orders',
                          icon: Icons.receipt_long_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  buildStatCard(
                    title: 'Sales',
                    value: '${totalSales.toStringAsFixed(0)} KWD',
                    subtitle: 'Total boutique sales',
                    icon: Icons.trending_up_rounded,
                  ),
                  const SizedBox(height: 24),
                  buildSectionTitle('Owner Details'),
                  const SizedBox(height: 12),
                  buildInfoBox(
                    label: 'Owner Name',
                    value: ownerName,
                  ),
                  buildInfoBox(
                    label: 'Owner Email',
                    value: ownerEmail,
                  ),
                  buildInfoBox(
                    label: 'Owner UID',
                    value: ownerUid,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BoutiqueStorefrontPage(
                              boutiqueId: boutiqueId,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Open Storefront',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}