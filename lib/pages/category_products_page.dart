import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/utils/image_sizing.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../models/product.dart';
import '../navigation/app_header.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/product_badges.dart';
import '../widgets/theme.dart';
import 'product_page.dart';
import '../core/services/promo_click_service.dart';

enum CategorySort { newest, priceLow, priceHigh }

/// Merge promoted [pinned] entries ahead of the [organic] list, dropping any
/// organic entry that is already pinned so a promoted product is shown once,
/// at the top — never duplicated further down its own category.
///
/// Pure and generic over [keyOf] so it can be unit-tested without Firestore
/// (see test/category_pins_test.dart).
List<T> mergePinnedFirst<T>(
  List<T> pinned,
  List<T> organic,
  String Function(T) keyOf,
) {
  if (pinned.isEmpty) return organic;
  final pinnedKeys = pinned.map(keyOf).toSet();
  return [...pinned, ...organic.where((e) => !pinnedKeys.contains(keyOf(e)))];
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
  static const int _pageSize = 20;

  // top_of_category allows 6 items per category per day; the headroom covers a
  // capacity change without silently dropping a pin someone paid for.
  static const int _pinLimit = 12;

  CategorySort _sort = CategorySort.newest;
  final ScrollController _scrollController = ScrollController();

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot<Map<String, dynamic>>? _cursor;

  // Products a boutique has PAID to pin at the top of this category
  // (top_of_category placement). Fetched once and prepended to the list, never
  // paginated: the placement caps a category at 6 pinned items per day, so this
  // stays tiny. Independent of _sort — a pin outranks whatever the shopper has
  // sorted by, which is the whole thing the boutique bought.
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _pinnedDocs = [];

  // Non-null when the initial load failed (e.g. a missing Firestore index
  // throwing failed-precondition). Kept distinct from "loaded but empty" so a
  // broken query never silently masquerades as "no products in this category".
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadPinned();
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

  // Paid pins for this category. The rendering fields are written by the promo
  // activator (applyPromoRendering) when a booking's window opens and cleared
  // when it ends, so "currently pinned" is exactly: tagged with this category
  // AND not yet expired.
  //
  // The "All" view (category == null) pins nothing — the placement is sold per
  // category, so there is no such thing as a pin across every category.
  Future<void> _loadPinned() async {
    final category = widget.category;
    if (category == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collectionGroup('products')
          .where('promotedCategories', arrayContains: category)
          .where('categoryPromoUntil', isGreaterThan: Timestamp.now())
          .limit(_pinLimit)
          .get();
      if (!mounted) return;
      setState(() {
        _pinnedDocs
          ..clear()
          ..addAll(snap.docs);
      });
    } catch (e) {
      // Pins are an enhancement on top of the category list: a failure here
      // (e.g. a missing index) must never take the page down with it. It DOES
      // mean a boutique paid for a pin that isn't showing, so it is logged
      // rather than swallowed silently.
      debugPrint('CATEGORY PINS ERROR: $e');
    }
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
      _error = null;
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
      // Record the failure so build() can show an error state instead of an
      // empty one. A missing index surfaces here as failed-precondition.
      debugPrint('CATEGORY LOAD ERROR: $e');
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
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
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
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

                  // Failed load (e.g. missing index) — show a retriable error,
                  // never the "no products" empty state.
                  if (_error != null) {
                    return ErrorStateWidget.inline(
                      title: l10n.somethingWentWrong,
                      message: l10n.failedToLoadProducts,
                      onRetry: _loadInitial,
                      type: ErrorType.generic,
                    );
                  }

                  // Paid pins ride above the organic list in every sort mode,
                  // deduped so a pinned product never appears twice. Merged at
                  // render time (not in _docs) so pagination and its cursor keep
                  // tracking the organic query alone.
                  final docs = mergePinnedFirst(
                    _pinnedDocs,
                    _docs,
                    (d) => d.reference.path,
                  );
                  // Identify paid cards by path rather than by index: a pinned
                  // product is deduped out of the organic list, so "the first N
                  // are the pins" holds today but would break silently the moment
                  // the merge changes.
                  final pinnedPaths =
                      _pinnedDocs.map((d) => d.reference.path).toSet();

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
                              (context, index) => _CategoryProductCard(
                                doc: docs[index],
                                isPromoted: pinnedPaths
                                    .contains(docs[index].reference.path),
                                category: widget.category,
                              ),
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
      ),
    );
  }
}

// ── Product grid card widget ──────────────────────────────────────────────────

class _CategoryProductCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  /// True when this card is here because a boutique PAID to pin it
  /// (top_of_category), rather than because it organically matched the
  /// category. Drives the "· PROMOTED" ad disclosure.
  final bool isPromoted;

  /// The category being browsed. Required to attribute a pin click: one product
  /// can be pinned in two categories by two different bookings, and a tap here
  /// belongs to whichever booking bought THIS category.
  final String? category;

  const _CategoryProductCard({
    required this.doc,
    this.isPromoted = false,
    this.category,
  });

  @override
  Widget build(BuildContext context) {
    final product = Product.fromFirestore(doc);
    final displayImageUrl = product.displayImageUrl;

    return GestureDetector(
      onTap: () {
        // Only a pinned card can be a paid click. An organic result that happens
        // to belong to a boutique with a live booking elsewhere is NOT this
        // placement, so it must not be credited to it — hence the isPromoted
        // gate on top of the stamp lookup.
        if (isPromoted && category != null) {
          PromoClickService.instance.logStamped(
            promoStampFor(
              product.promoAttribution,
              PromoPlacement.topOfCategory,
              category: category,
            ),
            subjectId: product.id,
          );
        }
        Navigator.push(
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
        );
      },
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
                          memCacheWidth: gridTileCacheWidth,
                          maxWidthDiskCache: maxImageDiskCacheWidth,
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
            // Ad disclosure rides the existing boutique caps line rather than
            // adding one: the grid tile is a fixed aspect ratio with an Expanded
            // image, so a fourth text line on promoted cards ONLY would shrink
            // their image and leave the row visually misaligned against the
            // organic cards beside it. The "·" separator matches the feed's own
            // idiom ("Following · 2h").
            isPromoted
                ? '${product.boutiqueName.toUpperCase()} · '
                    '${AppLocalizations.of(context)!.promotedBadge}'
                : product.boutiqueName.toUpperCase(),
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
