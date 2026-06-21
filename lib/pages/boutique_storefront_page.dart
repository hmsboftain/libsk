import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../models/product.dart';
import '../navigation/app_header.dart';
import '../services/follow_service.dart';
import '../widgets/boutique_logo_avatar.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/follow_button.dart';
import '../widgets/product_badges.dart';
import '../widgets/skeleton_loaders.dart';
import '../widgets/theme.dart';
import 'product_page.dart';

enum SortOption { newest, oldest, priceLow, priceHigh }

// ── Pure helpers ──────────────────────────────────────────────────────────────

double _p(Map<String, dynamic> data) {
  final v = data['price'] ?? 0;
  return v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
}

// ── Page ──────────────────────────────────────────────────────────────────────

class BoutiqueStorefrontPage extends StatefulWidget {
  final String boutiqueId;
  const BoutiqueStorefrontPage({super.key, required this.boutiqueId});

  @override
  State<BoutiqueStorefrontPage> createState() => _BoutiqueStorefrontPageState();
}

class _BoutiqueStorefrontPageState extends State<BoutiqueStorefrontPage> {
  SortOption _sortOption = SortOption.newest;

  late final DocumentReference<Map<String, dynamic>> _boutiqueRef;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _boutiqueStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _productsStream;
  late final Stream<int> _followerCountStream;

  @override
  void initState() {
    super.initState();
    _boutiqueRef = FirebaseFirestore.instance
        .collection('boutiques')
        .doc(widget.boutiqueId);
    _boutiqueStream = _boutiqueRef.snapshots();
    _productsStream = _boutiqueRef.collection('products').snapshots();
    // Use FollowService stream so count updates immediately when follow/unfollow
    _followerCountStream = FollowService().followerCount(widget.boutiqueId);
  }

  Future<void> _onRefresh() async => setState(() {});

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = List.of(docs);
    switch (_sortOption) {
      case SortOption.newest:
        sorted.sort((a, b) {
          final aT = a.data()['createdAt'];
          final bT = b.data()['createdAt'];
          if (aT is Timestamp && bT is Timestamp) return bT.compareTo(aT);
          return 0;
        });
        break;
      case SortOption.oldest:
        sorted.sort((a, b) {
          final aT = a.data()['createdAt'];
          final bT = b.data()['createdAt'];
          if (aT is Timestamp && bT is Timestamp) return aT.compareTo(bT);
          return 0;
        });
        break;
      case SortOption.priceLow:
        sorted.sort((a, b) => _p(a.data()).compareTo(_p(b.data())));
        break;
      case SortOption.priceHigh:
        sorted.sort((a, b) => _p(b.data()).compareTo(_p(a.data())));
        break;
    }
    return sorted;
  }

  Widget _buildSortBar(int count, AppLocalizations l10n) {
    final options = [
      (SortOption.newest, l10n.sortNewest),
      (SortOption.oldest, l10n.sortOldest),
      (SortOption.priceLow, l10n.sortPriceLow),
      (SortOption.priceHigh, l10n.sortPriceHigh),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(l10n.productsCount(count), style: AppTextStyles.capsLabel),
          const Spacer(),
          SizedBox(
            height: 34,
            child: ListView.separated(
              shrinkWrap: true,
              scrollDirection: Axis.horizontal,
              itemCount: options.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final option = options[index];
                final isSelected = _sortOption == option.$1;
                return GestureDetector(
                  onTap: () => setState(() => _sortOption = option.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.deepAccent
                          : AppColors.field,
                      border: Border.all(
                        color: isSelected
                            ? AppColors.deepAccent
                            : AppColors.border,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      option.$2,
                      style: AppTextStyles.labelSmall.copyWith(
                        fontWeight: FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : AppColors.secondaryText,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _boutiqueStream,
          builder: (context, boutiqueSnapshot) {
            if (boutiqueSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AppColors.deepAccent,
                  strokeWidth: 1.5,
                ),
              );
            }
            if (boutiqueSnapshot.hasError) {
              return ErrorStateWidget.inline(
                title: l10n.somethingWentWrong,
                message: l10n.pullDownToRetry,
                onRetry: () => setState(() {}),
                type: ErrorType.network,
              );
            }
            if (boutiqueSnapshot.hasData && !boutiqueSnapshot.data!.exists) {
              return NotFoundPage(message: l10n.boutiqueNoLongerAvailable);
            }
            if (!boutiqueSnapshot.hasData) {
              return Center(
                child: Text(
                  l10n.boutiqueNotFound,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
              );
            }

            final boutiqueData = boutiqueSnapshot.data!.data() ?? {};
            final boutiqueName =
                boutiqueData['name']?.toString() ?? l10n.boutique;
            final boutiqueDescription =
                boutiqueData['description']?.toString() ??
                l10n.noDescriptionAvailable;
            final logoPath = boutiqueData['logoPath']?.toString() ?? '';
            final bannerPath = boutiqueData['bannerPath']?.toString() ?? '';

            return RefreshIndicator(
              onRefresh: _onRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppHeader(showBackButton: true),

                    // ── Banner + logo ──────────────────────────────
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        bannerPath.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: bannerPath,
                                height: 220,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  height: 220,
                                  color: AppColors.field,
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  height: 220,
                                  color: AppColors.field,
                                ),
                              )
                            : Container(
                                height: 220,
                                width: double.infinity,
                                color: AppColors.field,
                              ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  AppColors.background.withValues(alpha: 0.9),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -36,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.background,
                                width: 4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: BoutiqueLogoAvatar(
                              imageUrl: logoPath,
                              size: 80,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 48),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  boutiqueName,
                                  style: AppTextStyles.headingLarge,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: FollowButton(
                                  boutiqueId: widget.boutiqueId,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),

                          // ── Live follower count ──────────────────
                          StreamBuilder<int>(
                            stream: _followerCountStream,
                            builder: (context, snapshot) {
                              final count = snapshot.data ?? 0;
                              return Text(
                                '$count follower${count == 1 ? '' : 's'}',
                                style: AppTextStyles.bodySmall,
                              );
                            },
                          ),

                          const SizedBox(height: 6),
                          Text(
                            boutiqueDescription,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.secondaryText,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Divider(color: AppColors.border, thickness: 0.5),
                    ),
                    const SizedBox(height: 14),

                    // ── Products ───────────────────────────────────
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _productsStream,
                      builder: (context, productsSnapshot) {
                        if (productsSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: FeaturedProductsGridSkeleton(),
                          );
                        }

                        final rawDocs = productsSnapshot.data?.docs ?? [];
                        if (rawDocs.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 60),
                            child: Center(
                              child: Text(
                                l10n.noProductsAvailableYet,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ),
                          );
                        }

                        final docs = _sortDocs(rawDocs);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSortBar(docs.length, l10n),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: GridView.builder(
                                itemCount: docs.length,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 14,
                                      mainAxisSpacing: 20,
                                      childAspectRatio: 0.58,
                                    ),
                                itemBuilder: (context, index) =>
                                    _StorefrontProductCard(
                                      doc: docs[index],
                                      boutiqueId: widget.boutiqueId,
                                      boutiqueName: boutiqueName,
                                      l10n: l10n,
                                    ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Storefront product card ───────────────────────────────────────────────────

class _StorefrontProductCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String boutiqueId;
  final String boutiqueName;
  final AppLocalizations l10n;

  const _StorefrontProductCard({
    required this.doc,
    required this.boutiqueId,
    required this.boutiqueName,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final product = Product.fromFirestore(doc);
    final title = product.title.isNotEmpty
        ? product.title
        : l10n.untitledProduct;
    final description = product.description.isNotEmpty
        ? product.description
        : l10n.noDescription;
    final displayImageUrl = product.displayImageUrl;
    final stock = product.stock;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductPage(
            productId: product.id,
            boutiqueId: boutiqueId,
            imageUrl: displayImageUrl,
            imageUrls: product.imageUrls,
            title: title,
            price: product.price,
            description: description,
            sizes: product.sizes,
            stock: stock,
            boutiqueName: boutiqueName,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 4 / 5,
                child: displayImageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: displayImageUrl,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: AppColors.imagePlaceholder),
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.imagePlaceholder,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.image_not_supported_outlined,
                            color: AppColors.secondaryText,
                            size: 30,
                          ),
                        ),
                      )
                    : Container(
                        color: AppColors.imagePlaceholder,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.secondaryText,
                          size: 30,
                        ),
                      ),
              ),
              if (product.isSoldOut)
                OutOfStockOverlay(label: l10n.outOfStock),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelLarge,
          ),
          const SizedBox(height: 2),
          Text(boutiqueName, style: AppTextStyles.bodySmall),
          const SizedBox(height: 4),
          ProductPriceText(
            price: product.price,
            salePrice: product.salePrice,
            saleBadgeLabel: l10n.saleBadge,
          ),
        ],
      ),
    );
  }
}
