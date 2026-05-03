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
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
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
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryText,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.field,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: imageUrl != null && imageUrl.isNotEmpty
              ? ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Text(
                    'Image could not load',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 14,
                    ),
                  ),
                );
              },
            ),
          )
              : const Center(
            child: Text(
              'No image uploaded',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 14,
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
                onRefresh: _onRefresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MY BOUTIQUE',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'View and manage your boutique details.',
                        style: TextStyle(
                          fontSize: 14,
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Edit Boutique',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
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