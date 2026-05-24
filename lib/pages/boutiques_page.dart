import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import 'boutique_storefront_page.dart';
import '../widgets/theme.dart';

class BoutiquesPage extends StatefulWidget {
  const BoutiquesPage({super.key});

  @override
  State<BoutiquesPage> createState() => _BoutiquesPageState();
}

class _BoutiquesPageState extends State<BoutiquesPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> toggleBoutiqueLike({
    required String boutiqueId,
    required String imageUrl,
    required String boutiqueName,
    required bool isCurrentlyLiked,
  }) async {
    try {
      if (isCurrentlyLiked) {
        await FirestoreService.removeSavedBoutique(boutiqueId);
      } else {
        await FirestoreService.saveBoutique(
          boutiqueId: boutiqueId,
          imageUrl: imageUrl,
          boutiqueName: boutiqueName,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCurrentlyLiked
                ? 'Boutique removed from saved boutiques'
                : 'Boutique saved',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _openBoutiqueStorefront(String boutiqueId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BoutiqueStorefrontPage(boutiqueId: boutiqueId),
      ),
    );
  }

  Set<String> _getSavedBoutiqueIds(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.map((doc) => doc.id).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final boutiquesStream =
        _firestore.collection('boutiques').orderBy('name').snapshots();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppHeader(),

            // ── Page Title ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(
                'Boutiques',
                style: AppTextStyles.displayMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'Curated independent labels',
                style: AppTextStyles.bodySmall,
              ),
            ),

            // ── Search ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.field,
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.search,
                      size: 18,
                      color: AppColors.secondaryText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: AppTextStyles.bodyMedium,
                        decoration: InputDecoration(
                          hintText: 'Search boutiques...',
                          hintStyle: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.secondaryText,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (val) =>
                            setState(() => _searchQuery = val.toLowerCase()),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            const Divider(height: 1, color: AppColors.border, thickness: 0.5),

            // ── Boutiques List ───────────────────────────────────────────
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirestoreService.getSavedBoutiquesStream(),
                builder: (context, savedSnapshot) {
                  final savedDocs = savedSnapshot.data?.docs ?? [];
                  final savedBoutiqueIds = _getSavedBoutiqueIds(savedDocs);

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: boutiquesStream,
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
                            'Failed to load boutiques',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.secondaryText,
                            ),
                          ),
                        );
                      }

                      var docs = snapshot.data?.docs ?? [];

                      // Apply search filter
                      if (_searchQuery.isNotEmpty) {
                        docs = docs.where((doc) {
                          final name =
                              doc.data()['name']?.toString().toLowerCase() ??
                                  '';
                          return name.contains(_searchQuery);
                        }).toList();
                      }

                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            'No boutiques found',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.secondaryText,
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data();

                          final boutiqueId = doc.id;
                          final logoUrl = data['logoPath']?.toString() ?? '';
                          final boutiqueName =
                              data['name']?.toString() ?? 'Boutique';
                          final isLiked =
                              savedBoutiqueIds.contains(boutiqueId);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              border: Border.all(
                                color: AppColors.border,
                                width: 0.5,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Logo banner
                                Container(
                                  width: double.infinity,
                                  height: 110,
                                  color: AppColors.imagePlaceholder,
                                  child: Stack(
                                    children: [
                                      if (logoUrl.isNotEmpty)
                                        Image.network(
                                          logoUrl,
                                          width: double.infinity,
                                          height: 110,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const SizedBox(),
                                        ),
                                      Positioned(
                                        top: 10,
                                        right: 10,
                                        child: GestureDetector(
                                          onTap: () => toggleBoutiqueLike(
                                            boutiqueId: boutiqueId,
                                            imageUrl: logoUrl,
                                            boutiqueName: boutiqueName,
                                            isCurrentlyLiked: isLiked,
                                          ),
                                          child: Icon(
                                            isLiked
                                                ? Icons.favorite
                                                : Icons.favorite_border,
                                            color: isLiked
                                                ? AppColors.deepAccent
                                                : AppColors.primaryText,
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
                                          style: AppTextStyles.bodyLarge,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () => _openBoutiqueStorefront(
                                          boutiqueId,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: AppColors.border,
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Text(
                                            'VISIT',
                                            style: AppTextStyles.capsLabel
                                                .copyWith(
                                              fontSize: 11,
                                              color: AppColors.primaryText,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
