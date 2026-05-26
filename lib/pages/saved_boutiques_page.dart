import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import 'boutique_storefront_page.dart';
import '../widgets/theme.dart';

class SavedBoutiquesPage extends StatefulWidget {
  const SavedBoutiquesPage({super.key});

  @override
  State<SavedBoutiquesPage> createState() => _SavedBoutiquesPageState();
}

class _SavedBoutiquesPageState extends State<SavedBoutiquesPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _savedBoutiquesStream;

  @override
  void initState() {
    super.initState();
    _savedBoutiquesStream = FirestoreService.getSavedBoutiquesStream();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _savedBoutiquesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                        strokeWidth: 1.5,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        loc.failedToLoadSavedBoutiques,
                        style: AppTextStyles.bodySmall,
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  return RefreshIndicator(
                    color: AppColors.deepAccent,
                    onRefresh: () async => setState(() {}),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Title ──────────────────────────────────
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                            child: Text(
                              'Saved Boutiques',
                              style: AppTextStyles.displayMedium,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                            child: Text(
                              'Boutiques you follow',
                              style: AppTextStyles.bodySmall,
                            ),
                          ),

                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Divider(
                              color: AppColors.border,
                              thickness: 0.5,
                            ),
                          ),

                          const SizedBox(height: 12),

                          if (docs.isEmpty)
                            SizedBox(
                              height: 400,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.storefront_outlined,
                                      size: 48,
                                      color: AppColors.softAccent,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      loc.noSavedBoutiquesYet,
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else ...[
                            // ── Count ─────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                              child: Text(
                                '${docs.length} ${docs.length == 1 ? 'boutique' : 'boutiques'}',
                                style: AppTextStyles.capsLabel,
                              ),
                            ),

                            // ── List ──────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Column(
                                children: docs.map((doc) {
                                  final boutique = doc.data();
                                  final String boutiqueId =
                                      boutique['boutiqueId'] ?? '';
                                  final String imageUrl =
                                      boutique['imageUrl'] ?? '';
                                  final String boutiqueName =
                                      boutique['boutiqueName'] ?? 'Boutique';

                                  return GestureDetector(
                                    onTap: () {
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
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      decoration: BoxDecoration(
                                        color: AppColors.card,
                                        border: Border.all(
                                          color: AppColors.border,
                                          width: 0.5,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          // Logo banner
                                          Container(
                                            width: double.infinity,
                                            height: 110,
                                            color: AppColors.imagePlaceholder,
                                            child: imageUrl.isNotEmpty
                                                ? Image.network(
                                                    imageUrl,
                                                    width: double.infinity,
                                                    height: 110,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (_, __, ___) =>
                                                            const SizedBox(),
                                                  )
                                                : null,
                                          ),

                                          // Info row
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              14,
                                              12,
                                              14,
                                              12,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    boutiqueName,
                                                    style:
                                                        AppTextStyles.bodyLarge,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                GestureDetector(
                                                  onTap: () async {
                                                    final messenger =
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        );
                                                    await FirestoreService.removeSavedBoutique(
                                                      boutiqueId,
                                                    );
                                                    if (!mounted) return;
                                                    messenger.showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          loc.boutiqueRemovedFromSaved,
                                                        ),
                                                        duration:
                                                            const Duration(
                                                              seconds: 1,
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                  child: Container(
                                                    width: 28,
                                                    height: 28,
                                                    decoration: BoxDecoration(
                                                      border: Border.all(
                                                        color: AppColors.border,
                                                        width: 0.5,
                                                      ),
                                                    ),
                                                    child: const Icon(
                                                      Icons.favorite,
                                                      size: 14,
                                                      color:
                                                          AppColors.deepAccent,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),

                            const SizedBox(height: 30),
                          ],
                        ],
                      ),
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
