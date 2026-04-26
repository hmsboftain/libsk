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

  static const backgroundColor = AppColors.background;
  static const cardColor = AppColors.card;
  static const borderColor = AppColors.border;
  static const fieldColor = AppColors.field;
  static const primaryText = AppColors.primaryText;
  static const secondaryText = AppColors.secondaryText;
  static const softAccent = AppColors.softAccent;
  static const deepAccent = AppColors.deepAccent;

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

  Widget buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: softAccent.withOpacity(0.22),
            child: Icon(
              icon,
              color: deepAccent,
              size: 20,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              color: secondaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: primaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: secondaryText,
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
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: secondaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(
              fontSize: 15,
              color: primaryText,
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
        color: primaryText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final boutiqueRef =
    FirebaseFirestore.instance.collection('boutiques').doc(boutiqueId);

    final productsStream = boutiqueRef.collection('products').snapshots();
    final ordersStream = boutiqueRef.collection('orders').snapshots();

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: boutiqueRef.snapshots(),
          builder: (context, boutiqueSnapshot) {
            if (boutiqueSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: deepAccent),
              );
            }

            if (boutiqueSnapshot.hasError) {
              return const Center(
                child: Text(
                  'Failed to load boutique',
                  style: TextStyle(color: secondaryText),
                ),
              );
            }

            if (!boutiqueSnapshot.hasData || !boutiqueSnapshot.data!.exists) {
              return const Center(
                child: Text(
                  'Boutique not found',
                  style: TextStyle(color: secondaryText),
                ),
              );
            }

            final boutiqueData = boutiqueSnapshot.data!.data() ?? {};
            final boutiqueName =
                boutiqueData['name']?.toString() ?? 'Boutique';
            final boutiqueDescription =
                boutiqueData['description']?.toString() ?? 'No description';
            final ownerUid = boutiqueData['ownerUid']?.toString() ?? '';
            final logoPath = boutiqueData['logoPath']?.toString() ?? '';

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: productsStream,
              builder: (context, productsSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: ordersStream,
                  builder: (context, ordersSnapshot) {
                    if (productsSnapshot.connectionState ==
                        ConnectionState.waiting ||
                        ordersSnapshot.connectionState ==
                            ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: deepAccent),
                      );
                    }

                    if (productsSnapshot.hasError || ordersSnapshot.hasError) {
                      return const Center(
                        child: Text(
                          'Failed to load boutique overview',
                          style: TextStyle(color: secondaryText),
                        ),
                      );
                    }

                    final productDocs = productsSnapshot.data?.docs ?? [];
                    final orderDocs = ordersSnapshot.data?.docs ?? [];
                    final totalSales = _sumSales(orderDocs);

                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: ownerUid.isEmpty
                          ? null
                          : FirebaseFirestore.instance
                          .collection('boutique_owners')
                          .doc(ownerUid)
                          .snapshots(),
                      builder: (context, ownerSnapshot) {
                        final ownerData = ownerSnapshot.data?.data();

                        final ownerName =
                        ownerData?['Name']?.toString().trim().isNotEmpty ==
                            true
                            ? ownerData!['Name'].toString().trim()
                            : ownerData?['name']
                            ?.toString()
                            .trim()
                            .isNotEmpty ==
                            true
                            ? ownerData!['name'].toString().trim()
                            : ownerData?['fullName']
                            ?.toString()
                            .trim()
                            .isNotEmpty ==
                            true
                            ? ownerData!['fullName']
                            .toString()
                            .trim()
                            : 'Unknown Owner';

                        final ownerEmail =
                        ownerData?['Email']?.toString().trim().isNotEmpty ==
                            true
                            ? ownerData!['Email'].toString().trim()
                            : ownerData?['email']
                            ?.toString()
                            .trim()
                            .isNotEmpty ==
                            true
                            ? ownerData!['email'].toString().trim()
                            : 'No email';

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
                                  color: primaryText,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                boutiqueDescription,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: secondaryText,
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
                                      border: Border.all(color: borderColor),
                                      color: fieldColor,
                                    ),
                                    child: ClipOval(
                                      child: Image.network(
                                        logoPath,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          return const Icon(
                                            Icons.storefront_outlined,
                                            color: deepAccent,
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
                                value:
                                '${totalSales.toStringAsFixed(0)} KWD',
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
                                        builder: (context) =>
                                            BoutiqueStorefrontPage(
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
                                      borderRadius:
                                      BorderRadius.circular(16),
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
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}