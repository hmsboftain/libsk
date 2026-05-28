import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import 'edit_boutique_page.dart';
import '../widgets/theme.dart';

// ── Pure helpers ──────────────────────────────────────────────────────────────

Widget _buildSectionCard({required Widget child}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border.all(color: AppColors.border, width: 0.5),
    ),
    child: child,
  );
}

Widget _buildInfoRow({required String label, required String value}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
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

Widget _buildImageBox({
  required String title,
  required String? imageUrl,
  required double height,
  required String errorText,
  required String emptyText,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: AppTextStyles.labelLarge),
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.imagePlaceholder,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: imageUrl != null && imageUrl.isNotEmpty
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: height,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    errorText,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  emptyText,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
      ),
    ],
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

class MyBoutiquePage extends StatefulWidget {
  const MyBoutiquePage({super.key});

  @override
  State<MyBoutiquePage> createState() => _MyBoutiquePageState();
}

class _MyBoutiquePageState extends State<MyBoutiquePage> {
  Map<String, dynamic>? _boutiqueData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBoutique();
  }

  Future<void> _loadBoutique() async {
    setState(() => _isLoading = true);
    try {
      final data = await FirestoreService.getOwnerBoutiqueData();
      if (!mounted) return;
      setState(() {
        _boutiqueData = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.failedToLoadBoutique),
        ),
      );
    }
  }

  Future<void> _onRefresh() => _loadBoutique();

  Future<void> _openEditPage() async {
    if (_boutiqueData == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditBoutiquePage(boutiqueData: _boutiqueData!),
      ),
    );
    if (result == true) await _loadBoutique();
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
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.deepAccent,
                      onRefresh: _onRefresh,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.myBoutique,
                              style: AppTextStyles.headingMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.myBoutiqueDescription,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.secondaryText,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _buildSectionCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildInfoRow(
                                    label: l10n.boutiqueName,
                                    value:
                                        _boutiqueData?['name']?.toString() ??
                                        l10n.myBoutiqueDefault,
                                  ),
                                  _buildInfoRow(
                                    label: l10n.description,
                                    value:
                                        _boutiqueData?['description']
                                            ?.toString() ??
                                        l10n.noDescriptionAddedYet,
                                  ),
                                  _buildImageBox(
                                    title: l10n.logoImage,
                                    imageUrl: _boutiqueData?['logoPath']
                                        ?.toString(),
                                    height: 140,
                                    errorText: l10n.imageCouldNotLoad,
                                    emptyText: l10n.noImageUploaded,
                                  ),
                                  const SizedBox(height: 18),
                                  _buildImageBox(
                                    title: l10n.bannerImage,
                                    imageUrl: _boutiqueData?['bannerPath']
                                        ?.toString(),
                                    height: 180,
                                    errorText: l10n.imageCouldNotLoad,
                                    emptyText: l10n.noImageUploaded,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 22),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _openEditPage,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.deepAccent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.zero,
                                  ),
                                ),
                                child: Text(
                                  l10n.editBoutique,
                                  style: AppTextStyles.button,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
