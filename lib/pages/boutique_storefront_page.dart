import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../navigation/app_header.dart';
import 'product_page.dart';
import '../widgets/boutique_logo_avatar.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/skeleton_loaders.dart';
import '../widgets/theme.dart';

enum SortOption { newest, oldest, priceLow, priceHigh }

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

  @override
  void initState() {
    super.initState();
    _boutiqueRef = FirebaseFirestore.instance
        .collection('boutiques')
        .doc(widget.boutiqueId);
    _boutiqueStream = _boutiqueRef.snapshots();
    _productsStream = _boutiqueRef.collection('products').snapshots();
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

  double _p(Map<String, dynamic> data) {
    final v = data['price'] ?? 0;
    return v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
  }

  Widget _buildSortBar(int count) {
    const options = [
      (SortOption.newest, 'Newest'),
      (SortOption.oldest, 'Oldest'),
      (SortOption.priceLow, 'Price ↑'),
      (SortOption.priceHigh, 'Price ↓'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            '$count ${count == 1 ? 'product' : 'products'}',
            style: AppTextStyles.capsLabel,
          ),
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
                title: 'Something went wrong',
                message: 'Pull down to retry',
                onRetry: () => setState(() {}),
                type: ErrorType.network,
              );
            }
            if (boutiqueSnapshot.hasData &&
                !boutiqueSnapshot.data!.exists) {
              return const NotFoundPage(
                message: 'This boutique is no longer available.',
              );
            }
            if (!boutiqueSnapshot.hasData) {
              return Center(
                child: Text(
                  'Boutique not found',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
              );
            }

            final boutiqueData = boutiqueSnapshot.data!.data() ?? {};
            final boutiqueName = boutiqueData['name']?.toString() ?? 'Boutique';
            final boutiqueDescription =
                boutiqueData['description']?.toString() ??
                'No description available.';
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

                    // Banner + logo
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
                                placeholder: (context, url) => Container(
                                  height: 220,
                                  color: AppColors.field,
                                ),
                                errorWidget: (context, url, error) => Container(
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
                          Text(boutiqueName, style: AppTextStyles.headingLarge),
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

                    // Products
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
                                'No products available yet',
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
                            _buildSortBar(docs.length),
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
                                itemBuilder: (context, index) {
                                  final doc = docs[index];
                                  final product = Product.fromFirestore(doc);
                                  final title = product.title.isNotEmpty
                                      ? product.title
                                      : 'Untitled Product';
                                  final description =
                                      product.description.isNotEmpty
                                      ? product.description
                                      : 'No description';
                                  final displayImageUrl = product.displayImageUrl;
                                  final stock = product.stock;

                                  return GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ProductPage(
                                          productId: product.id,
                                          boutiqueId: widget.boutiqueId,
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                                      placeholder:
                                                          (
                                                            context,
                                                            url,
                                                          ) => Container(
                                                            color: AppColors
                                                                .imagePlaceholder,
                                                          ),
                                                      errorWidget:
                                                          (
                                                            context,
                                                            url,
                                                            error,
                                                          ) => Container(
                                                            color: AppColors
                                                                .imagePlaceholder,
                                                            alignment: Alignment
                                                                .center,
                                                            child: const Icon(
                                                              Icons
                                                                  .image_not_supported_outlined,
                                                              color: AppColors
                                                                  .secondaryText,
                                                              size: 30,
                                                            ),
                                                          ),
                                                    )
                                                  : Container(
                                                      color: AppColors
                                                          .imagePlaceholder,
                                                      alignment:
                                                          Alignment.center,
                                                      child: const Icon(
                                                        Icons
                                                            .image_not_supported_outlined,
                                                        color: AppColors
                                                            .secondaryText,
                                                        size: 30,
                                                      ),
                                                    ),
                                            ),
                                            if (stock <= 0)
                                              Positioned(
                                                top: 10,
                                                left: 10,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.deepAccent
                                                        .withValues(alpha: 0.9),
                                                    border: Border.all(
                                                      color: AppColors.border,
                                                      width: 0.5,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    'Sold Out',
                                                    style: AppTextStyles
                                                        .labelSmall
                                                        .copyWith(
                                                          color: Colors.white,
                                                        ),
                                                  ),
                                                ),
                                              ),
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
                                        Text(
                                          boutiqueName,
                                          style: AppTextStyles.bodySmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${product.price.toStringAsFixed(0)} KWD',
                                          style: AppTextStyles.labelLarge,
                                        ),
                                      ],
                                    ),
                                  );
                                },
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
