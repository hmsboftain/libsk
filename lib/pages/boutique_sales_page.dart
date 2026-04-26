import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import 'boutique_sales_details_page.dart';
import '../widgets/theme.dart';

class BoutiqueSalesPage extends StatelessWidget {
  const BoutiqueSalesPage({super.key});

  static const backgroundColor = AppColors.background;
  static const cardColor = AppColors.card;
  static const borderColor = AppColors.border;
  static const primaryText = AppColors.primaryText;
  static const secondaryText = AppColors.secondaryText;
  static const deepAccent = AppColors.deepAccent;

  String? _getBoutiqueIdFromReference(
      DocumentReference<Map<String, dynamic>> reference,
      ) {
    final pathSegments = reference.path.split('/');
    final boutiqueIndex = pathSegments.indexOf('boutiques');

    if (boutiqueIndex != -1 && boutiqueIndex + 1 < pathSegments.length) {
      return pathSegments[boutiqueIndex + 1];
    }

    return null;
  }

  double _parseTotal(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  Future<Map<String, String>> _loadBoutiqueNames(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> orderDocs,
      ) async {
    final firestore = FirebaseFirestore.instance;
    final boutiqueIds = orderDocs
        .map((doc) => _getBoutiqueIdFromReference(doc.reference))
        .whereType<String>()
        .toSet()
        .toList();

    final Map<String, String> names = {};

    for (final boutiqueId in boutiqueIds) {
      final doc = await firestore.collection('boutiques').doc(boutiqueId).get();
      final data = doc.data();
      names[boutiqueId] = data?['name']?.toString() ?? 'Boutique';
    }

    return names;
  }

  Widget buildBoutiqueCard({
    required BuildContext context,
    required String boutiqueId,
    required String boutiqueName,
    required int totalOrders,
    required double totalSales,
    required double maxSales,
  }) {
    final initials = boutiqueName.trim().isNotEmpty
        ? boutiqueName.trim()[0].toUpperCase()
        : '?';

    final barWidth = maxSales > 0 ? (totalSales / maxSales) : 0.0;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BoutiqueSalesDetailsPage(
              boutiqueId: boutiqueId,
              boutiqueName: boutiqueName,
            ),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: AppColors.selectedSoft,
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: deepAccent,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    boutiqueName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: primaryText,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$totalOrders orders',
                    style: const TextStyle(
                      fontSize: 13,
                      color: secondaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: barWidth.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: borderColor,
                      valueColor:
                      const AlwaysStoppedAnimation<Color>(deepAccent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Text(
              '${totalSales.toStringAsFixed(0)} KWD',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirestoreService.getAllBoutiqueOrdersStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: deepAccent),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'Failed to load boutique sales',
                        style: TextStyle(color: secondaryText),
                      ),
                    );
                  }

                  final allOrderDocs = snapshot.data?.docs ?? [];

                  final orderDocs = allOrderDocs.where((doc) {
                    final boutiqueId = _getBoutiqueIdFromReference(doc.reference);
                    return boutiqueId != null;
                  }).toList();

                  if (orderDocs.isEmpty) {
                    return const Center(
                      child: Text(
                        'No boutique sales found.',
                        style: TextStyle(color: secondaryText),
                      ),
                    );
                  }

                  final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
                  groupedOrders = {};

                  for (final doc in orderDocs) {
                    final boutiqueId = _getBoutiqueIdFromReference(doc.reference);
                    if (boutiqueId == null) continue;

                    groupedOrders.putIfAbsent(boutiqueId, () => []);
                    groupedOrders[boutiqueId]!.add(doc);
                  }

                  return FutureBuilder<Map<String, String>>(
                    future: _loadBoutiqueNames(orderDocs),
                    builder: (context, namesSnapshot) {
                      if (namesSnapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: deepAccent),
                        );
                      }

                      final boutiqueNames = namesSnapshot.data ?? {};
                      final boutiqueIds = groupedOrders.keys.toList();

                      boutiqueIds.sort((a, b) {
                        final nameA = boutiqueNames[a] ?? a;
                        final nameB = boutiqueNames[b] ?? b;
                        return nameA.toLowerCase().compareTo(nameB.toLowerCase());
                      });

                      double maxSales = 0;

                      for (final boutiqueId in boutiqueIds) {
                        final docs = groupedOrders[boutiqueId]!;
                        double totalSales = 0;

                        for (final doc in docs) {
                          totalSales += _parseTotal(doc.data()['total']);
                        }

                        if (totalSales > maxSales) {
                          maxSales = totalSales;
                        }
                      }

                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'BOUTIQUE SALES',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: primaryText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${boutiqueIds.length} boutiques with sales',
                              style: const TextStyle(
                                fontSize: 14,
                                color: secondaryText,
                              ),
                            ),
                            const SizedBox(height: 20),
                            ...boutiqueIds.map((boutiqueId) {
                              final docs = groupedOrders[boutiqueId]!;
                              double totalSales = 0;

                              for (final doc in docs) {
                                totalSales += _parseTotal(doc.data()['total']);
                              }

                              final boutiqueName =
                                  boutiqueNames[boutiqueId] ?? 'Boutique';

                              return buildBoutiqueCard(
                                context: context,
                                boutiqueId: boutiqueId,
                                boutiqueName: boutiqueName,
                                totalOrders: docs.length,
                                totalSales: totalSales,
                                maxSales: maxSales,
                              );
                            }),
                          ],
                        ),
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