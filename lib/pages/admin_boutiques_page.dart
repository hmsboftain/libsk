import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../widgets/error_state_widget.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/boutiques_card.dart';
import 'boutique_oversight_page.dart';
import '../widgets/theme.dart';

class AdminBoutiquesPage extends StatefulWidget {
  const AdminBoutiquesPage({super.key});

  @override
  State<AdminBoutiquesPage> createState() => _AdminBoutiquesPageState();
}

class _AdminBoutiquesPageState extends State<AdminBoutiquesPage> {
  // Created once — avoids opening a new Firestore listener on every rebuild
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _boutiquesStream;

  @override
  void initState() {
    super.initState();
    _boutiquesStream = FirestoreService.getAllBoutiquesStream();
  }

  Future<void> _editWasalBranchCode(
    String boutiqueId,
    String boutiqueName,
    String currentCode,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: currentCode);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(boutiqueName, style: AppTextStyles.headingSmall),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: l10n.wasalBranchCode,
            hintText: l10n.wasalBranchCodeHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel, style: AppTextStyles.labelLarge),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: Text(l10n.save, style: AppTextStyles.button),
          ),
        ],
      ),
    );

    if (saved != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('boutiques')
          .doc(boutiqueId)
          .update({'wasalBranchCode': controller.text.trim()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.wasalBranchCodeSaved),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
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
          children: [
            const AppHeader(showBackButton: true),
            const SizedBox(height: 12),
            Text(l10n.allBoutiques, style: AppTextStyles.headingLarge),
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 0.5, color: AppColors.border),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _boutiquesStream,
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
                      title: l10n.failedToLoadBoutiques,
                      message: l10n.pullDownToRetry,
                      onRetry: () => setState(() {}),
                      type: ErrorType.network,
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        l10n.noBoutiquesAvailable,
                        style: AppTextStyles.bodyMedium,
                      ),
                    );
                  }

                  return ListView.builder(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      final boutiqueId = doc.id;
                      final imageUrl = data['logoPath']?.toString() ?? '';
                      final boutiqueName =
                          data['name']?.toString() ?? l10n.boutique;

                      // Long-press: set the boutique's Wasal branch code
                      // (created in the Wasal merchant dashboard first).
                      // Deliveries can't be dispatched for a boutique
                      // without one.
                      return GestureDetector(
                        onLongPress: () => _editWasalBranchCode(
                          boutiqueId,
                          boutiqueName,
                          data['wasalBranchCode']?.toString() ?? '',
                        ),
                        child: BoutiquesCard(
                          imageUrl: imageUrl,
                          boutiqueName: boutiqueName,
                          isLiked: false,
                          onLikeTap: () {},
                          showLikeButton: false,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  BoutiqueOversightPage(boutiqueId: boutiqueId),
                            ),
                          ),
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
      ),
    );
  }
}
