import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../core/constants/countries.dart';
import '../models/product.dart';
import '../navigation/app_header.dart';
import '../services/currency_service.dart';
import '../widgets/theme.dart';
import 'product_page.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

enum CategorySort { newest, priceLow, priceHigh }

// ── Pure helpers ──────────────────────────────────────────────────────────────

double _price(Map<String, dynamic> data) {
  final v = data['price'] ?? 0;
  return v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
}

// ── Page ──────────────────────────────────────────────────────────────────────

class CategoryProductsPage extends StatefulWidget {
  final String? category; // null = All
  final String displayLabel;

  const CategoryProductsPage({
    super.key,
    required this.category,
    required this.displayLabel,
  });

  @override
  State<CategoryProductsPage> createState() => _CategoryProductsPageState();
}

class _CategoryProductsPageState extends State<CategoryProductsPage> {
  CategorySort _sort = CategorySort.newest;

  // Full collection stream — category filter is client-side because some
  // products store category as a String and others as a List.
  // TODO: migrate all products to List format, then switch to:
  // .where('category', arrayContains: widget.category)
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = FirebaseFirestore.instance
        .collectionGroup('products')
        .snapshots();
  }

  bool _matchesCategory(Map<String, dynamic> data) {
    if (widget.category == null) return true;
    final cat = data['category'];
    if (cat is List) return cat.contains(widget.category);
    if (cat is String) return cat == widget.category;
    return false;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterAndSort(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final filtered = widget.category == null
        ? docs
        : docs.where((doc) => _matchesCategory(doc.data())).toList();

    final sorted = List.of(filtered);
    switch (_sort) {
      case CategorySort.newest:
        sorted.sort((a, b) {
          final aT = a.data()['createdAt'];
          final bT = b.data()['createdAt'];
          if (aT is Timestamp && bT is Timestamp) return bT.compareTo(aT);
          return 0;
        });
        break;
      case CategorySort.priceLow:
        sorted.sort((a, b) => _price(a.data()).compareTo(_price(b.data())));
        break;
      case CategorySort.priceHigh:
        sorted.sort((a, b) => _price(b.data()).compareTo(_price(a.data())));
        break;
    }
    return sorted;
  }

  Widget _sortChip(String label, CategorySort option) {
    final isSelected = _sort == option;
    return GestureDetector(
      onTap: () => setState(() => _sort = option),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                stream: _stream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                        strokeWidth: 1.5,
                      ),
                    );
                  }

                  final rawDocs = snapshot.data?.docs ?? [];
                  final docs = _filterAndSort(rawDocs);

                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                              child: Text(
                                widget.displayLabel,
                                style: AppTextStyles.displayMedium,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                              child: Text(
                                l10n.itemsAcrossAllBoutiques(docs.length),
                                style: AppTextStyles.bodySmall,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Row(
                                children: [
                                  _sortChip(
                                    l10n.sortNewest,
                                    CategorySort.newest,
                                  ),
                                  const SizedBox(width: 8),
                                  _sortChip(
                                    l10n.sortPriceLow,
                                    CategorySort.priceLow,
                                  ),
                                  const SizedBox(width: 8),
                                  _sortChip(
                                    l10n.sortPriceHigh,
                                    CategorySort.priceHigh,
                                  ),
                                ],
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
                          ],
                        ),
                      ),
                      if (docs.isEmpty)
                        SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.search_off_outlined,
                                  size: 40,
                                  color: AppColors.softAccent,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  l10n.noProductsInCategory(
                                    widget.displayLabel,
                                  ),
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                          sliver: SliverGrid(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) =>
                                  _CategoryProductCard(doc: docs[index]),
                              childCount: docs.length,
                            ),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.58,
                                ),
                          ),
                        ),
                    ],
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

// ── Product grid card widget ──────────────────────────────────────────────────

class _CategoryProductCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  const _CategoryProductCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final product = Product.fromFirestore(doc);
    final displayImageUrl = product.displayImageUrl;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductPage(
            productId: product.id,
            boutiqueId: product.boutiqueId,
            imageUrl: displayImageUrl,
            imageUrls: product.imageUrls,
            title: product.title,
            price: product.price,
            description: product.description,
            sizes: product.sizes,
            stock: product.stock,
            boutiqueName: product.boutiqueName,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.imagePlaceholder,
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: displayImageUrl.isNotEmpty
                  ? Image.network(
                      displayImageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => const Center(
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
          ),
          const SizedBox(height: 8),
          Text(
            product.boutiqueName.toUpperCase(),
            style: AppTextStyles.capsLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            product.title,
            style: AppTextStyles.headingSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 5),
          Text(
            _fmt(product.price),
            style: AppTextStyles.labelLarge,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
