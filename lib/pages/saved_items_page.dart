import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';
import 'product_page.dart';
import '../core/constants/countries.dart';
import '../services/currency_service.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

enum SavedSortOption { newest, priceLow, priceHigh }

// ── Pure helpers ──────────────────────────────────────────────────────────────

double _price(Map<String, dynamic> data) {
  final v = data['price'] ?? 0;
  return v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
}

// ── Page ──────────────────────────────────────────────────────────────────────

class SavedItemsPage extends StatefulWidget {
  const SavedItemsPage({super.key});

  @override
  State<SavedItemsPage> createState() => _SavedItemsPageState();
}

class _SavedItemsPageState extends State<SavedItemsPage> {
  SavedSortOption _sort = SavedSortOption.newest;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _savedItemsStream;

  @override
  void initState() {
    super.initState();
    _savedItemsStream = FirestoreService.getSavedItemsStream();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = List.of(docs);
    switch (_sort) {
      case SavedSortOption.newest:
        sorted.sort((a, b) {
          final aT = a.data()['createdAt'];
          final bT = b.data()['createdAt'];
          if (aT is Timestamp && bT is Timestamp) return bT.compareTo(aT);
          return 0;
        });
        break;
      case SavedSortOption.priceLow:
        sorted.sort((a, b) => _price(a.data()).compareTo(_price(b.data())));
        break;
      case SavedSortOption.priceHigh:
        sorted.sort((a, b) => _price(b.data()).compareTo(_price(a.data())));
        break;
    }
    return sorted;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _savedItemsStream,
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
                        l10n.failedToLoadSavedItems,
                        style: AppTextStyles.bodySmall,
                      ),
                    );
                  }

                  final rawDocs = snapshot.data?.docs ?? [];
                  // Sort once — not per-itemBuilder call
                  final sortedDocs = _sortDocs(rawDocs);

                  return RefreshIndicator(
                    color: AppColors.deepAccent,
                    onRefresh: () async => setState(() {}),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                            child: Text(
                              l10n.savedItems,
                              style: AppTextStyles.displayMedium,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                            child: Text(
                              l10n.yourCuratedWishlist,
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
                                      l10n.noSavedItemsYet,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    l10n.itemsCount(rawDocs.length),
                                    style: AppTextStyles.capsLabel,
                                  ),
                                  const Spacer(),
                                  _sortChip(
                                    l10n.sortNewest,
                                    SavedSortOption.newest,
                                  ),
                                  const SizedBox(width: 6),
                                  _sortChip(
                                    l10n.sortPriceLow,
                                    SavedSortOption.priceLow,
                                  ),
                                  const SizedBox(width: 6),
                                  _sortChip(
                                    l10n.sortPriceHigh,
                                    SavedSortOption.priceHigh,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: sortedDocs.length,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 0.58,
                                    ),
                                itemBuilder: (context, index) =>
                                    _SavedProductCard(
                                      doc: sortedDocs[index],
                                      l10n: l10n,
                                    ),
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

// ── Saved product card widget ─────────────────────────────────────────────────

class _SavedProductCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final AppLocalizations l10n;

  const _SavedProductCard({required this.doc, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final item = doc.data();
    final productId = item['productId']?.toString() ?? '';
    final boutiqueId = item['boutiqueId']?.toString() ?? '';
    final imageUrl = item['imageUrl']?.toString() ?? '';
    final imageUrlsData = item['imageUrls'];
    final List<String> imageUrls = imageUrlsData is List
        ? imageUrlsData.map((e) => e.toString()).toList()
        : imageUrl.isNotEmpty
        ? [imageUrl]
        : [];
    final displayImageUrl = imageUrls.isNotEmpty ? imageUrls.first : imageUrl;
    final title = item['title']?.toString() ?? '';
    final boutiqueName = item['boutiqueName']?.toString() ?? '';
    final description = item['description']?.toString() ?? '';
    final itemPrice = _price(item);
    final stockValue = item['stock'] ?? 0;
    final stock = stockValue is int
        ? stockValue
        : int.tryParse(stockValue.toString()) ?? 0;
    final sizesData = item['sizes'];
    final sizes = sizesData is List
        ? sizesData.map((s) => s.toString()).toList()
        : <String>[];

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductPage(
            productId: productId,
            boutiqueId: boutiqueId,
            imageUrl: displayImageUrl,
            imageUrls: imageUrls,
            title: title,
            price: itemPrice,
            description: description,
            sizes: sizes,
            stock: stock,
            boutiqueName: boutiqueName,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4 / 5,
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.imagePlaceholder,
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: displayImageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: displayImageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorWidget: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              size: 24,
                              color: AppColors.softAccent,
                            ),
                          ),
                        )
                      : const Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 24,
                            color: AppColors.softAccent,
                          ),
                        ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await FirestoreService.removeSavedItem(productId);
                        if (!context.mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(l10n.itemRemovedFromSaved),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      } catch (_) {
                        if (!context.mounted) return;
                        messenger.showSnackBar(
                          SnackBar(content: Text(l10n.somethingWentWrong)),
                        );
                      }
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.background.withValues(alpha: 0.9),
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: const Icon(
                        Icons.favorite,
                        size: 14,
                        color: AppColors.deepAccent,
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
          Text(_fmt(itemPrice), style: AppTextStyles.labelLarge),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
