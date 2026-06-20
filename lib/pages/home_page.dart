import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../models/product.dart';
import '../navigation/app_header.dart';
import '../services/feed_service.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/feed_card.dart';
import '../widgets/rotating_hero_banner.dart';
import '../widgets/skeleton_loaders.dart';
import '../widgets/theme.dart';
import 'boutique_storefront_page.dart';
import 'product_page.dart';
import '../core/constants/countries.dart';
import '../services/currency_service.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _firestore = FirebaseFirestore.instance;
  final _scrollController = ScrollController();
  final _feedService = FeedService();

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _boutiquesStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>>
  _featuredProductsStream;

  // ── Feed state ──────────────────────────────────────────────────────────
  final List<FeedEntry> _feed = [];
  bool _feedLoading = true;
  bool _feedLoadingMore = false;
  bool _feedHasMore = true;
  DocumentSnapshot<Map<String, dynamic>>? _feedCursor;

  @override
  void initState() {
    super.initState();

    _boutiquesStream = _firestore
        .collection('boutiques')
        .where('isVisibleOnHome', isEqualTo: true)
        .where('homeExpiresAt', isGreaterThan: Timestamp.now())
        .orderBy('homeExpiresAt')
        .orderBy('homeOrder')
        .snapshots();

    _featuredProductsStream = _firestore
        .collectionGroup('products')
        .where('isFeaturedOnHome', isEqualTo: true)
        .where('featuredExpiresAt', isGreaterThan: Timestamp.now())
        .orderBy('featuredExpiresAt')
        .orderBy('featuredOrder')
        .snapshots();

    _scrollController.addListener(_onScroll);
    _loadInitialFeed();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_feedLoadingMore || !_feedHasMore) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 500) {
      _loadMoreFeed();
    }
  }

  Future<void> _loadInitialFeed() async {
    setState(() => _feedLoading = true);
    try {
      final sponsored = await _feedService.fetchSponsored();
      final page = await _feedService.fetchMainPage();

      // Top up a sparse followed feed with trending, de-duped by product id.
      final ids = page.entries.map((e) => e.product.id).toSet();
      var combined = page.entries;
      if (page.entries.length < FeedService.pageSize) {
        final trending = await _feedService.fetchTrending();
        combined = [
          ...page.entries,
          ...trending.where((e) => !ids.contains(e.product.id)),
        ];
        ids.addAll(combined.map((e) => e.product.id));
      }

      final sponsoredDeduped = sponsored
          .where((e) => !ids.contains(e.product.id))
          .toList();
      final interleaved = _feedService.interleave(combined, sponsoredDeduped);

      if (!mounted) return;
      setState(() {
        _feed
          ..clear()
          ..addAll(interleaved);
        _feedCursor = page.lastDoc;
        _feedHasMore = page.hasMore;
        _feedLoading = false;
      });
    } catch (e) {
      debugPrint('FEED LOAD ERROR: $e');
      if (!mounted) return;
      setState(() => _feedLoading = false);
    }
  }

  Future<void> _loadMoreFeed() async {
    if (_feedLoadingMore || !_feedHasMore || _feedCursor == null) return;
    setState(() => _feedLoadingMore = true);
    try {
      final page = await _feedService.fetchMainPage(startAfter: _feedCursor);
      if (!mounted) return;
      setState(() {
        _feed.addAll(page.entries);
        _feedCursor = page.lastDoc;
        _feedHasMore = page.hasMore;
        _feedLoadingMore = false;
      });
    } catch (e) {
      debugPrint('FEED LOAD MORE ERROR: $e');
      if (!mounted) return;
      setState(() => _feedLoadingMore = false);
    }
  }

  // Featured streams are real-time; refresh just rebuilds the feed.
  Future<void> _onRefresh() async {
    _feedService.clearCache();
    await _loadInitialFeed();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.deepAccent,
          onRefresh: _onRefresh,
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppHeader(),
                const RotatingHeroBanner(),
                const SizedBox(height: 32),

                // ── Featured Pieces ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    l10n.featuredPieces,
                    style: AppTextStyles.headingLarge,
                  ),
                ),
                const SizedBox(height: 16),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _featuredProductsStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: FeaturedProductsGridSkeleton(),
                      );
                    }
                    if (snapshot.hasError) {
                      return ErrorStateWidget.inline(
                        title: l10n.somethingWentWrong,
                        message: l10n.pullDownToRetry,
                        onRetry: () => setState(() {}),
                        type: ErrorType.network,
                      );
                    }
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          l10n.noFeaturedProductsAvailable,
                          style: AppTextStyles.bodySmall,
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: docs.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.62,
                            ),
                        itemBuilder: (context, index) =>
                            _FeaturedProductCard(doc: docs[index], l10n: l10n),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 36),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(color: AppColors.border, thickness: 0.5),
                ),
                const SizedBox(height: 28),

                // ── Top Boutiques ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    l10n.topBoutiques,
                    style: AppTextStyles.headingLarge,
                  ),
                ),
                const SizedBox(height: 16),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _boutiquesStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: BoutiquesListSkeleton(),
                      );
                    }
                    if (snapshot.hasError) {
                      return ErrorStateWidget.inline(
                        title: l10n.somethingWentWrong,
                        message: l10n.pullDownToRetry,
                        onRetry: () => setState(() {}),
                        type: ErrorType.network,
                      );
                    }
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          l10n.noBoutiquesAvailable,
                          style: AppTextStyles.bodySmall,
                        ),
                      );
                    }
                    return Column(
                      children: docs
                          .map((doc) => _HomeBoutiqueCard(doc: doc, l10n: l10n))
                          .toList(),
                    );
                  },
                ),

                const SizedBox(height: 36),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(color: AppColors.border, thickness: 0.5),
                ),
                const SizedBox(height: 28),

                // ── For You feed ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('For You', style: AppTextStyles.headingLarge),
                ),
                const SizedBox(height: 16),
                _buildFeedSection(),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeedSection() {
    if (_feedLoading) return const FeedSkeleton();

    if (_feed.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'Follow boutiques to see their latest pieces here.',
          style: AppTextStyles.bodySmall,
        ),
      );
    }

    return Column(
      children: [
        ..._feed.map(
          (entry) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FeedCard(
              product: entry.product,
              badge: entry.badge,
              boutiqueLogoUrl: entry.boutiqueLogoUrl,
            ),
          ),
        ),
        if (_feedLoadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.deepAccent,
                strokeWidth: 1.5,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Featured product card widget ──────────────────────────────────────────────

class _FeaturedProductCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final AppLocalizations l10n;

  const _FeaturedProductCard({required this.doc, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final product = Product.fromFirestore(doc);
    final title = product.title.isNotEmpty
        ? product.title
        : l10n.untitledProduct;
    final description = product.description.isNotEmpty
        ? product.description
        : l10n.noDescription;
    final boutiqueName = product.boutiqueName.isNotEmpty
        ? product.boutiqueName
        : l10n.boutique;
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
            title: title,
            price: product.price,
            description: description,
            sizes: product.sizes,
            stock: product.stock,
            boutiqueName: boutiqueName,
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
                  decoration: BoxDecoration(
                    color: AppColors.imagePlaceholder,
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: displayImageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: displayImageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          placeholder: (_, __) =>
                              Container(color: AppColors.imagePlaceholder),
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
                  bottom: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background.withValues(alpha: 0.92),
                      border: Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: Text(
                      l10n.featured.toUpperCase(),
                      style: AppTextStyles.capsLabel.copyWith(fontSize: 9),
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
            _fmt(product.price),
            style: AppTextStyles.labelLarge.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Home boutique card widget ─────────────────────────────────────────────────

class _HomeBoutiqueCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final AppLocalizations l10n;

  const _HomeBoutiqueCard({required this.doc, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final boutiqueId = doc.id;
    final logoUrl = data['logoPath']?.toString() ?? '';
    final boutiqueName = data['name']?.toString() ?? l10n.boutique;
    final initial = boutiqueName.isNotEmpty
        ? boutiqueName[0].toUpperCase()
        : 'B';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BoutiqueStorefrontPage(boutiqueId: boutiqueId),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              color: AppColors.imagePlaceholder,
              child: logoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: logoUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: AppColors.imagePlaceholder),
                      errorWidget: (_, __, ___) => Center(
                        child: Text(
                          initial,
                          style: AppTextStyles.headingMedium,
                        ),
                      ),
                    )
                  : Center(
                      child: Text(initial, style: AppTextStyles.headingMedium),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(boutiqueName, style: AppTextStyles.bodyLarge)),
            const Icon(
              Icons.arrow_forward_ios,
              size: 12,
              color: AppColors.softAccent,
            ),
          ],
        ),
      ),
    );
  }
}
