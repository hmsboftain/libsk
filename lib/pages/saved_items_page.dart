import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import 'product_page.dart';
import '../widgets/theme.dart';

enum SavedSortOption { newest, priceLow, priceHigh }

class SavedItemsPage extends StatefulWidget {
  const SavedItemsPage({super.key});

  @override
  State<SavedItemsPage> createState() => _SavedItemsPageState();
}

class _SavedItemsPageState extends State<SavedItemsPage> {
  SavedSortOption _sort = SavedSortOption.newest;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = List.of(docs);
    switch (_sort) {
      case SavedSortOption.newest:
        sorted.sort((a, b) {
          final aTime = a.data()['createdAt'];
          final bTime = b.data()['createdAt'];
          if (aTime is Timestamp && bTime is Timestamp) {
            return bTime.compareTo(aTime);
          }
          return 0;
        });
        break;
      case SavedSortOption.priceLow:
        sorted.sort((a, b) {
          final aP = _price(a.data());
          final bP = _price(b.data());
          return aP.compareTo(bP);
        });
        break;
      case SavedSortOption.priceHigh:
        sorted.sort((a, b) {
          final aP = _price(a.data());
          final bP = _price(b.data());
          return bP.compareTo(aP);
        });
        break;
    }
    return sorted;
  }

  double _price(Map<String, dynamic> data) {
    final v = data['price'] ?? 0;
    return v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
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
                stream: FirestoreService.getSavedItemsStream(),
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
                        loc.failedToLoadSavedItems,
                        style: AppTextStyles.bodySmall,
                      ),
                    );
                  }

                  final rawDocs = snapshot.data?.docs ?? [];

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
                              'Saved Items',
                              style: AppTextStyles.displayMedium,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                            child: Text(
                              'Your curated wishlist',
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

                          if (rawDocs.isEmpty)
                            SizedBox(
                              height: 400,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.favorite_border,
                                      size: 48,
                                      color: AppColors.softAccent,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      loc.noSavedItemsYet,
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else ...[
                            // ── Count + Sort ──────────────────────────
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '${rawDocs.length} ${rawDocs.length == 1 ? 'item' : 'items'}',
                                    style: AppTextStyles.capsLabel,
                                  ),
                                  const Spacer(),
                                  _sortChip('NEWEST', SavedSortOption.newest),
                                  const SizedBox(width: 6),
                                  _sortChip(
                                    'PRICE ↑',
                                    SavedSortOption.priceLow,
                                  ),
                                  const SizedBox(width: 6),
                                  _sortChip(
                                    'PRICE ↓',
                                    SavedSortOption.priceHigh,
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            // ── Grid ──────────────────────────────────
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _sortDocs(rawDocs).length,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 0.58,
                                    ),
                                itemBuilder: (context, index) {
                                  final doc = _sortDocs(rawDocs)[index];
                                  final item = doc.data();

                                  final String productId =
                                      item['productId'] ?? '';
                                  final String boutiqueId =
                                      item['boutiqueId'] ?? '';
                                  final String imageUrl =
                                      item['imageUrl'] ?? '';
                                  final imageUrlsData = item['imageUrls'];
                                  final List<String> imageUrls =
                                      imageUrlsData is List
                                      ? imageUrlsData
                                            .map((e) => e.toString())
                                            .toList()
                                      : imageUrl.isNotEmpty
                                      ? [imageUrl]
                                      : [];
                                  final displayImageUrl = imageUrls.isNotEmpty
                                      ? imageUrls.first
                                      : imageUrl;
                                  final String title = item['title'] ?? '';
                                  final String boutiqueName =
                                      item['boutiqueName'] ?? '';
                                  final String description =
                                      item['description'] ?? '';
                                  final double price = _price(item);
                                  final dynamic stockValue = item['stock'] ?? 0;
                                  final int stock = stockValue is int
                                      ? stockValue
                                      : int.tryParse(stockValue.toString()) ??
                                            0;
                                  final dynamic sizesData = item['sizes'];
                                  final List<String> sizes = sizesData is List
                                      ? sizesData
                                            .map((s) => s.toString())
                                            .toList()
                                      : [];

                                  return GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ProductPage(
                                            productId: productId,
                                            boutiqueId: boutiqueId,
                                            imageUrl: displayImageUrl,
                                            imageUrls: imageUrls,
                                            title: title,
                                            price: price,
                                            description: description,
                                            sizes: sizes,
                                            stock: stock,
                                            boutiqueName: boutiqueName,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Stack(
                                            children: [
                                              Container(
                                                width: double.infinity,
                                                decoration: BoxDecoration(
                                                  color: AppColors
                                                      .imagePlaceholder,
                                                  border: Border.all(
                                                    color: AppColors.border,
                                                    width: 0.5,
                                                  ),
                                                ),
                                                child:
                                                    displayImageUrl.isNotEmpty
                                                    ? Image.network(
                                                        displayImageUrl,
                                                        fit: BoxFit.cover,
                                                        width: double.infinity,
                                                        errorBuilder:
                                                            (
                                                              _,
                                                              __,
                                                              ___,
                                                            ) => const Center(
                                                              child: Icon(
                                                                Icons
                                                                    .image_not_supported_outlined,
                                                                size: 24,
                                                                color: AppColors
                                                                    .softAccent,
                                                              ),
                                                            ),
                                                      )
                                                    : const Center(
                                                        child: Icon(
                                                          Icons
                                                              .image_not_supported_outlined,
                                                          size: 24,
                                                          color: AppColors
                                                              .softAccent,
                                                        ),
                                                      ),
                                              ),
                                              // Heart button
                                              Positioned(
                                                top: 8,
                                                right: 8,
                                                child: GestureDetector(
                                                  onTap: () async {
                                                    final messenger =
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        );
                                                    await FirestoreService.removeSavedItem(
                                                      productId,
                                                    );
                                                    if (!mounted) return;
                                                    messenger.showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          loc.itemRemovedFromSaved,
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
                                                      color: AppColors
                                                          .background
                                                          .withValues(
                                                            alpha: 0.9,
                                                          ),
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
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          boutiqueName.toUpperCase(),
                                          style: AppTextStyles.capsLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          title,
                                          style: AppTextStyles.headingSmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          'KD ${price.toStringAsFixed(0)}',
                                          style: AppTextStyles.labelLarge,
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  );
                                },
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

  Widget _sortChip(String label, SavedSortOption option) {
    final isSelected = _sort == option;
    return GestureDetector(
      onTap: () => setState(() => _sort = option),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.deepAccent : Colors.transparent,
          border: Border.all(
            color: isSelected ? AppColors.deepAccent : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.capsLabel.copyWith(
            fontSize: 10,
            color: isSelected ? Colors.white : AppColors.secondaryText,
          ),
        ),
      ),
    );
  }
}
