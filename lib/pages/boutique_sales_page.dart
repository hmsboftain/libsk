import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../widgets/error_state_widget.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import 'boutique_sales_details_page.dart';
import '../widgets/theme.dart';
import '../core/constants/countries.dart';
import '../services/currency_service.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

// ── Pure helpers ──────────────────────────────────────────────────────────────

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
  AppLocalizations l10n,
) async {
  final firestore = FirebaseFirestore.instance;

  final boutiqueIds = orderDocs
      .map((doc) => _getBoutiqueIdFromReference(doc.reference))
      .whereType<String>()
      .toSet()
      .toList();

  final snapshots = await Future.wait(
    boutiqueIds.map((boutiqueId) {
      return firestore.collection('boutiques').doc(boutiqueId).get();
    }),
  );

  final Map<String, String> names = {};

  for (int i = 0; i < boutiqueIds.length; i++) {
    final data = snapshots[i].data();
    names[boutiqueIds[i]] = data?['name']?.toString() ?? l10n.boutique;
  }

  return names;
}

// ── Page ──────────────────────────────────────────────────────────────────────

class BoutiqueSalesPage extends StatefulWidget {
  const BoutiqueSalesPage({super.key});

  @override
  State<BoutiqueSalesPage> createState() => _BoutiqueSalesPageState();
}

class _BoutiqueSalesPageState extends State<BoutiqueSalesPage> {
  late final Future<QuerySnapshot<Map<String, dynamic>>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _ordersFuture = FirestoreService.getAllBoutiqueOrdersOnce();
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
              child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                future: _ordersFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return ErrorStateWidget.inline(
                      title: l10n.failedToLoadBoutiqueSales,
                      message: l10n.pullDownToRetry,
                      onRetry: () => setState(() {}),
                      type: ErrorType.network,
                    );
                  }

                  final allOrderDocs = snapshot.data?.docs ?? [];

                  final orderDocs = allOrderDocs.where((doc) {
                    final boutiqueId = _getBoutiqueIdFromReference(
                      doc.reference,
                    );
                    return boutiqueId != null;
                  }).toList();

                  if (orderDocs.isEmpty) {
                    return Center(
                      child: Text(
                        l10n.noBoutiqueSalesFound,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.secondaryText,
                        ),
                      ),
                    );
                  }

                  final Map<
                    String,
                    List<QueryDocumentSnapshot<Map<String, dynamic>>>
                  >
                  groupedOrders = {};

                  for (final doc in orderDocs) {
                    final boutiqueId = _getBoutiqueIdFromReference(
                      doc.reference,
                    );
                    if (boutiqueId == null) continue;

                    groupedOrders.putIfAbsent(boutiqueId, () => []);
                    groupedOrders[boutiqueId]!.add(doc);
                  }

                  return FutureBuilder<Map<String, String>>(
                    future: _loadBoutiqueNames(orderDocs, l10n),
                    builder: (context, namesSnapshot) {
                      if (namesSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.deepAccent,
                          ),
                        );
                      }

                      final boutiqueNames = namesSnapshot.data ?? {};
                      final boutiqueIds = groupedOrders.keys.toList();

                      boutiqueIds.sort((a, b) {
                        final nameA = boutiqueNames[a] ?? a;
                        final nameB = boutiqueNames[b] ?? b;
                        return nameA.toLowerCase().compareTo(
                          nameB.toLowerCase(),
                        );
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
                            Text(
                              l10n.boutiqueSalesTitle,
                              style: AppTextStyles.displayMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.boutiquesWithSales(
                                boutiqueIds.length.toString(),
                              ),
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.secondaryText,
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
                                  boutiqueNames[boutiqueId] ?? l10n.boutique;

                              return _BoutiqueSalesCard(
                                boutiqueId: boutiqueId,
                                boutiqueName: boutiqueName,
                                totalOrders: docs.length,
                                totalSales: totalSales,
                                maxSales: maxSales,
                                l10n: l10n,
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

// ── Boutique sales card widget ────────────────────────────────────────────────

class _BoutiqueSalesCard extends StatelessWidget {
  final String boutiqueId;
  final String boutiqueName;
  final int totalOrders;
  final double totalSales;
  final double maxSales;
  final AppLocalizations l10n;

  const _BoutiqueSalesCard({
    required this.boutiqueId,
    required this.boutiqueName,
    required this.totalOrders,
    required this.totalSales,
    required this.maxSales,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final initials = boutiqueName.trim().isNotEmpty
        ? boutiqueName.trim()[0].toUpperCase()
        : '?';

    final barWidth = maxSales > 0 ? (totalSales / maxSales) : 0.0;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BoutiqueSalesDetailsPage(
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
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: AppColors.selectedSoft,
              child: Text(
                initials,
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.deepAccent,
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
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.orderCountLabel(totalOrders.toString()),
                    style: AppTextStyles.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: barWidth.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: AppColors.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.deepAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Text(
              _fmt(totalSales),
              style: AppTextStyles.labelLarge,
            ),
          ],
        ),
      ),
    );
  }
}
