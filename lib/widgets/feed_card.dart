import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';

import '../core/services/analytics_service.dart';
import '../core/services/performance_service.dart';
import '../core/utils/image_sizing.dart';
import '../models/product.dart';
import '../pages/boutique_storefront_page.dart';
import '../pages/product_page.dart';
import '../services/follow_service.dart';
import '../services/saved_items_controller.dart';
import 'boutique_logo_avatar.dart';
import 'feed_add_to_cart_sheet.dart';
import 'follow_button.dart';
import 'product_badges.dart';
import 'theme.dart';

/// Why a given product is appearing in the feed. Drives the header subtitle.
enum FeedBadge { followed, hot, sponsored, recommended }

/// A single shoppable feed post: boutique header, swipeable product image
/// carousel, name/price, add-to-cart, and a favourite (save) action. The
/// boutique name/avatar opens the storefront; tapping the image opens the
/// product. Built in isolation from a [Product]; the feed assembly supplies the
/// [badge] and, when known, the [boutiqueLogoUrl].
class FeedCard extends StatefulWidget {
  final Product product;
  final FeedBadge badge;
  final String boutiqueLogoUrl;

  /// Position of this card in the assembled feed. Used to attribute promo slot
  /// analytics for sponsored cards.
  final int feedPosition;

  /// Shared feed-level follow state (finding 4.1) — the follow button reads and
  /// writes through this instead of opening its own per-card listener.
  final FollowController followController;

  /// Shared feed-level saved-items state (finding 4.2) — the heart reads and
  /// writes through this instead of issuing its own per-card get.
  final SavedItemsController savedController;

  const FeedCard({
    super.key,
    required this.product,
    required this.followController,
    required this.savedController,
    this.badge = FeedBadge.followed,
    this.boutiqueLogoUrl = '',
    this.feedPosition = 0,
  });

  @override
  State<FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<FeedCard> {
  final _pageController = PageController();
  int _currentImage = 0;

  // Times how long the card's product image takes to appear. Started on mount,
  // stopped the first time an image loads (or fails).
  Trace? _imageTrace;
  bool _imageTraceStopped = false;

  Product get product => widget.product;
  bool get _soldOut => product.isSoldOut;
  bool get _isSponsored => widget.badge == FeedBadge.sponsored;

  @override
  void initState() {
    super.initState();
    if (_isSponsored) {
      AnalyticsService.instance.logPromoSlotView(
        product.boutiqueId,
        widget.feedPosition,
      );
    }
    _imageTrace = PerformanceService.instance.traceImageLoad('feed');
    _imageTrace!.start();
  }

  void _stopImageTrace() {
    if (_imageTraceStopped) return;
    _imageTraceStopped = true;
    _imageTrace?.stop();
  }

  /// All gallery images, falling back to the single primary image.
  List<String> get _images {
    if (product.imageUrls.isNotEmpty) return product.imageUrls;
    if (product.imageUrl.isNotEmpty) return [product.imageUrl];
    return const [];
  }

  @override
  void dispose() {
    _stopImageTrace();
    _pageController.dispose();
    super.dispose();
  }

  void _openProduct() {
    if (_isSponsored) {
      AnalyticsService.instance.logPromoSlotTap(
        product.boutiqueId,
        widget.feedPosition,
      );
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductPage(
          productId: product.id,
          boutiqueId: product.boutiqueId,
          imageUrl: product.displayImageUrl,
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
  }

  void _openBoutique() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BoutiqueStorefrontPage(boutiqueId: product.boutiqueId),
      ),
    );
  }

  Future<void> _openSheet() async {
    if (_soldOut) return;
    final added = await FeedAddToCartSheet.show(context, product);
    if (added == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.itemAddedToCart),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  String _subtitle() {
    switch (widget.badge) {
      case FeedBadge.followed:
        final t = _relativeTime(product.feedPostedAt);
        return t.isEmpty ? 'Following' : 'Following · $t';
      case FeedBadge.sponsored:
        return 'Sponsored';
      case FeedBadge.hot:
        return 'Trending';
      case FeedBadge.recommended:
        return 'Recommended for you';
    }
  }

  static String _relativeTime(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  Widget _placeholderBox() => Container(
    color: AppColors.imagePlaceholder,
    alignment: Alignment.center,
    child: const Icon(
      Icons.image_not_supported_outlined,
      color: AppColors.secondaryText,
      size: 32,
    ),
  );

  Widget _buildCarousel() {
    final images = _images;

    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 4 / 5,
          child: images.isEmpty
              ? GestureDetector(onTap: _openProduct, child: _placeholderBox())
              : PageView.builder(
                  controller: _pageController,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _currentImage = i),
                  itemBuilder: (context, index) => GestureDetector(
                    onTap: _openProduct,
                    child: CachedNetworkImage(
                      imageUrl: images[index],
                      memCacheWidth: fullBleedCacheWidth(context),
                      maxWidthDiskCache: maxImageDiskCacheWidth,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      imageBuilder: (context, imageProvider) {
                        _stopImageTrace();
                        return Image(
                          image: imageProvider,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        );
                      },
                      placeholder: (_, __) =>
                          Container(color: AppColors.imagePlaceholder),
                      errorWidget: (_, __, ___) {
                        _stopImageTrace();
                        return _placeholderBox();
                      },
                    ),
                  ),
                ),
        ),

        // Out-of-stock overlay
        if (_soldOut)
          OutOfStockOverlay(label: AppLocalizations.of(context)!.outOfStock),

        // Image counter (e.g. 2/4) — only when multiple images
        if (images.length > 1)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
              ),
              child: Text(
                '${_currentImage + 1}/${images.length}',
                style: AppTextStyles.labelSmall.copyWith(color: Colors.white),
              ),
            ),
          ),

        // Page dots — only when multiple images
        if (images.length > 1)
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(images.length, (i) {
                final active = i == _currentImage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 7 : 6,
                  height: active ? 7 : 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _openBoutique,
                  child: BoutiqueLogoAvatar(
                    imageUrl: widget.boutiqueLogoUrl,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: GestureDetector(
                    onTap: _openBoutique,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          product.boutiqueName.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.capsLabel.copyWith(
                            color: AppColors.primaryText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(_subtitle(), style: AppTextStyles.labelSmall),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FollowButton(
                  boutiqueId: product.boutiqueId,
                  boutiqueName: product.boutiqueName,
                  controller: widget.followController,
                ),
              ],
            ),
          ),

          // ── Image carousel ──────────────────────────────────────
          _buildCarousel(),

          // ── Name + price ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 0),
            child: GestureDetector(
              onTap: _openProduct,
              behavior: HitTestBehavior.opaque,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      product.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.headingSmall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ProductPriceText(
                    price: product.price,
                    salePrice: product.salePrice,
                    saleBadgeLabel: AppLocalizations.of(context)!.saleBadge,
                  ),
                ],
              ),
            ),
          ),

          // ── Actions ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _soldOut ? null : _openSheet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.deepAccent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.softAccent,
                        disabledForegroundColor: Colors.white,
                        elevation: 0,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                      child: Text(
                        _soldOut ? l10n.outOfStock : l10n.addToCart,
                        style: AppTextStyles.button,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _FeedFavouriteButton(
                  product: product,
                  controller: widget.savedController,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom-right favourite (save) toggle for a feed card. Self-contained state.
/// Reuses the same [FirestoreService] save methods as the product page heart,
/// so an item favourited here appears in the user's saved items alongside any
/// other.
class _FeedFavouriteButton extends StatefulWidget {
  final Product product;
  final SavedItemsController controller;
  const _FeedFavouriteButton({required this.product, required this.controller});

  @override
  State<_FeedFavouriteButton> createState() => _FeedFavouriteButtonState();
}

class _FeedFavouriteButtonState extends State<_FeedFavouriteButton> {
  bool _busy = false;

  Product get _product => widget.product;
  SavedItemsController get _controller => widget.controller;

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    // Decide the action from current state before the optimistic flip.
    final willSave = !_controller.isSaved(_product.id);
    try {
      await _controller.toggle(_product);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(willSave ? l10n.itemSaved : l10n.itemRemovedFromSaved),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds when the shared saved-set changes (incl. another card for the
    // same product), so state stays consistent without a per-card listener.
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final saved = _controller.isSaved(_product.id);
        return GestureDetector(
          onTap: _busy ? null : _toggle,
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Icon(
              saved ? Icons.favorite : Icons.favorite_border,
              size: 20,
              color: saved ? AppColors.deepAccent : AppColors.primaryText,
            ),
          ),
        );
      },
    );
  }
}
