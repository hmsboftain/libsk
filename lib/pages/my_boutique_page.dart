import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import 'edit_boutique_page.dart';
import '../widgets/theme.dart';

class MyBoutiquePage extends StatefulWidget {
  const MyBoutiquePage({super.key});

  @override
  State<MyBoutiquePage> createState() => _MyBoutiquePageState();
}

class _MyBoutiquePageState extends State<MyBoutiquePage> {
  Map<String, dynamic>? boutiqueData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadBoutique();
  }

  Future<void> loadBoutique() async {
    try {
      final data = await FirestoreService.getOwnerBoutiqueData();

      if (!mounted) return;

      setState(() {
        boutiqueData = data;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load boutique')),
      );
    }
  }

  Future<void> _onRefresh() async {
    await loadBoutique();
  }

  Future<void> openEditPage() async {
    if (boutiqueData == null) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditBoutiquePage(
          boutiqueData: boutiqueData!,
        ),
      ),
    );

    if (result == true) {
      await loadBoutique();
    }
  }

  Widget buildSectionCard({required Widget child}) {
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

  Widget buildInfoRow({
    required String label,
    required String value,
  }) {
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

  Widget buildImageBox({
    required String title,
    required String? imageUrl,
    required double height,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.labelLarge,
        ),
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
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Text(
                  'Image could not load',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
              );
            },
          )
              : Center(
            child: Text(
              'No image uploaded',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final boutiqueName = boutiqueData?['name']?.toString() ?? 'My Boutique';
    final description =
        boutiqueData?['description']?.toString() ?? 'No description added yet.';
    final logoPath = boutiqueData?['logoPath']?.toString();
    final bannerPath = boutiqueData?['bannerPath']?.toString();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: isLoading
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
                        'MY BOUTIQUE',
                        style: AppTextStyles.headingMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'View and manage your boutique details.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.secondaryText,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      buildSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            buildInfoRow(
                              label: 'Boutique Name',
                              value: boutiqueName,
                            ),
                            buildInfoRow(
                              label: 'Description',
                              value: description,
                            ),
                            buildImageBox(
                              title: 'Logo Image',
                              imageUrl: logoPath,
                              height: 140,
                            ),
                            const SizedBox(height: 18),
                            buildImageBox(
                              title: 'Banner Image',
                              imageUrl: bannerPath,
                              height: 180,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: openEditPage,
                          child: const Text('Edit Boutique'),
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