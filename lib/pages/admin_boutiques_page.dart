import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

  // Superadmin-only boutique settings edited inline (no separate page): the
  // Wasal branch code, the Payzah commission rate and the Payzah vendor key.
  // The first two live on the boutique doc (firestore.rules blocks owners from
  // changing them). The vendor key is a payment credential, so it lives in the
  // deny-all boutiqueSecrets collection and is set through a callable instead.
  Future<void> _editBoutiqueSettings(
    String boutiqueId,
    String boutiqueName,
    String currentCode,
    String currentCommissionPercent,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    final branchController = TextEditingController(text: currentCode);
    // The boutique's current rate, or 15 (Standard) when none is set yet.
    // Founding Partner (12%) vs Standard (15%) is a per-boutique decision made
    // here by hand — the helper text says so; nothing infers it.
    final commissionController = TextEditingController(
      text: currentCommissionPercent.isEmpty ? '15' : currentCommissionPercent,
    );
    // Write-only: the stored key never comes back to the client (only its last
    // 4 characters), so this starts empty and blank keeps the key on file.
    final vendorKeyController = TextEditingController();
    final vendorKeyStatus = functions
        .httpsCallable('getBoutiquePayzahVendorKeyStatus')
        .call({'boutiqueId': boutiqueId})
        .then((r) => Map<String, dynamic>.from(r.data as Map));

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(boutiqueName, style: AppTextStyles.headingSmall),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: branchController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: l10n.wasalBranchCode,
                  hintText: l10n.wasalBranchCodeHint,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commissionController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.commissionPercentLabel,
                  helperText: l10n.commissionPercentHint,
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: vendorKeyController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.payzahVendorKeyLabel,
                  hintText: l10n.payzahVendorKeyHint,
                ),
              ),
              const SizedBox(height: 8),
              FutureBuilder<Map<String, dynamic>>(
                future: vendorKeyStatus,
                builder: (_, snap) {
                  if (!snap.hasData) return const SizedBox.shrink();
                  final isSet = snap.data!['isSet'] == true;
                  return Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      isSet
                          ? l10n.payzahVendorKeyOnFile(
                              '${snap.data!['last4'] ?? ''}',
                            )
                          : l10n.payzahVendorKeyMissing,
                      style: AppTextStyles.bodySmall,
                    ),
                  );
                },
              ),
            ],
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

    final update = <String, dynamic>{
      'wasalBranchCode': branchController.text.trim(),
    };
    // Commission is optional to touch: only write it when a value is entered,
    // and reject anything outside 0–100 rather than storing a bad rate.
    final commissionText = commissionController.text.trim();
    if (commissionText.isNotEmpty) {
      final parsed = num.tryParse(commissionText);
      if (parsed == null || parsed < 0 || parsed > 100) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.commissionPercentInvalid)),
        );
        return;
      }
      update['commissionPercent'] = parsed;
    }
    final vendorKey = vendorKeyController.text.trim();

    try {
      await FirebaseFirestore.instance
          .collection('boutiques')
          .doc(boutiqueId)
          .update(update);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
      return;
    }

    // Separate step, reported separately: the boutique doc is already saved,
    // so a key failure must not read as "nothing saved".
    var vendorKeySaved = false;
    if (vendorKey.isNotEmpty) {
      try {
        await functions.httpsCallable('setBoutiquePayzahVendorKey').call({
          'boutiqueId': boutiqueId,
          'vendorKey': vendorKey,
        });
        vendorKeySaved = true;
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.payzahVendorKeySaveFailed)),
        );
        return;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          vendorKeySaved
              ? l10n.payzahVendorKeySaved
              : update.containsKey('commissionPercent')
              ? l10n.commissionPercentSaved
              : l10n.wasalBranchCodeSaved,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
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
                      // (created in the Wasal merchant dashboard first;
                      // deliveries can't be dispatched without one), its
                      // Payzah commission rate and its Payzah vendor key
                      // (checkout is blocked for the boutique without one).
                      final commissionPercent =
                          data['commissionPercent'];
                      return GestureDetector(
                        onLongPress: () => _editBoutiqueSettings(
                          boutiqueId,
                          boutiqueName,
                          data['wasalBranchCode']?.toString() ?? '',
                          commissionPercent == null
                              ? ''
                              : commissionPercent.toString(),
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
