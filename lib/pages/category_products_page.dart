import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../models/product.dart';
import '../navigation/app_header.dart';
import '../widgets/product_badges.dart';
import '../widgets/theme.dart';
import 'product_page.dart';

enum CategorySort { newest, priceLow, priceHigh }

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
  static const int _pageSize = 20;

  CategorySort _sort = CategorySort.newest;
  final ScrollController _scrollController = ScrollController();

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot<Map<String, dynamic>>? _cursor;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // Server-side: category filtered by arrayContains, sorted, page-limited.
  Query<Map<String, dynamic>> _baseQuery() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collectionGroup(
      'products',
    );
    if (widget.category != null) {
      q = q.where('category', arrayContains: widget.category);
    }
    switch (_sort) {
      case CategorySort.newest:
        q = q.orderBy('createdAt', descending: true);
        break;
      case CategorySort.priceLow:
        q = q.orderBy('price');
        break;
      case CategorySort.priceHigh:
        q = q.orderBy('price', descending: true);
        break;
    }
    return q.limit(_pageSize);
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) _loadMore();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _docs.clear();
      _cursor = null;
      _hasMore = true;
    });
    try {
      final snap = await _baseQuery().get();
      if (!mounted) return;
      setState(() {
        _docs.addAll(snap.docs);
        _cursor = snap.docs.isNotEmpty ? snap.docs.last : null;
        _hasMore = snap.docs.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      debugPrint('CATEGORY LOAD ERROR: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final snap = await _baseQuery().startAfterDocument(_cursor!).get();
      if (!mounted) return;
      setState(() {
        _docs.addAll(snap.docs);
        _cursor = snap.docs.isNotEmpty ? snap.docs.last : _cursor;
        _hasMore = snap.docs.length == _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('CATEGORY LOAD MORE ERROR: $e');
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _changeSort(CategorySort option) {
    if (_sort == option) return;
    setState(() => _sort = option);
    _loadInitial();
  }

  Widget _sortChip(String label, CategorySort option) {
    final isSelected = _sort == option;
    return GestureDetector(
      onTap: () => _changeSort(option),
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
              child: Builder(
                builder: (context) {
                  if (_loading) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                        strokeWidth: 1.5,
                      ),
                    );
                  }

                  final docs = _docs;

                  return CustomScrollView(
                    controller: _scrollController,
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
                      if (_loadingMore)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColors.deepAccent,
                                strokeWidth: 1.5,
                              ),
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
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.imagePlaceholder,
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: displayImageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: displayImageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
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
                if (product.isSoldOut)
                  OutOfStockOverlay(
                    label: AppLocalizations.of(context)!.outOfStock,
                  ),
              ],
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
          ProductPriceText(
            price: product.price,
            salePrice: product.salePrice,
            saleBadgeLabel: AppLocalizations.of(context)!.saleBadge,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
