import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../widgets/error_state_widget.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';
import 'boutique_storefront_page.dart';

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

  Future<void> _removeBoutique(String boutiqueId) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    try {
      await FirestoreService.removeSavedBoutique(boutiqueId);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.boutiqueRemovedFromSaved),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
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
                    return ErrorStateWidget.inline(
                      title: l10n.failedToLoadSavedBoutiques,
                      message: l10n.pullDownToRetry,
                      onRetry: () => setState(() {}),
                      type: ErrorType.network,
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  return RefreshIndicator(
                    color: AppColors.deepAccent,
                    onRefresh: () async => setState(() {}),
                    child: SingleChildScrollView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                            child: Text(
                              l10n.savedBoutiques,
                              style: AppTextStyles.displayMedium,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                            child: Text(
                              l10n.boutiquesYouFollow,
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
                                      l10n.noSavedBoutiquesYet,
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                              child: Text(
                                l10n.boutiquesCount(docs.length),
                                style: AppTextStyles.capsLabel,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Column(
                                children: docs
                                    .map(
                                      (doc) => _SavedBoutiqueCard(
                                        doc: doc,
                                        l10n: l10n,
                                        onRemove: _removeBoutique,
                                      ),
                                    )
                                    .toList(),
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
      ),
    );
  }
}

// ── Saved boutique card widget ────────────────────────────────────────────────

class _SavedBoutiqueCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final AppLocalizations l10n;
  final Future<void> Function(String boutiqueId) onRemove;

  const _SavedBoutiqueCard({
    required this.doc,
    required this.l10n,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final boutique = doc.data();
    final boutiqueId = boutique['boutiqueId']?.toString() ?? '';
    final imageUrl = boutique['imageUrl']?.toString() ?? '';
    final boutiqueName = boutique['boutiqueName']?.toString() ?? l10n.boutique;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BoutiqueStorefrontPage(boutiqueId: boutiqueId),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          children: [
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
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      boutiqueName,
                      style: AppTextStyles.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => onRemove(boutiqueId),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: const Icon(
                        Icons.favorite,
                        size: 14,
                        color: AppColors.deepAccent,
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
  }
}
