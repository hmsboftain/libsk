import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import 'product_page.dart';
import '../widgets/boutique_logo_avatar.dart';
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
    final boutiqueRef = FirebaseFirestore.instance
        .collection('boutiques')
        .doc(widget.boutiqueId);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: boutiqueRef.snapshots(),
          builder: (context, boutiqueSnapshot) {
            if (boutiqueSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AppColors.deepAccent,
                  strokeWidth: 1.5,
                ),
              );
            }
            if (boutiqueSnapshot.hasError ||
                !boutiqueSnapshot.hasData ||
                !boutiqueSnapshot.data!.exists) {
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
                      stream: boutiqueRef.collection('products').snapshots(),
                      builder: (context, productsSnapshot) {
                        if (productsSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColors.deepAccent,
                                strokeWidth: 1.5,
                              ),
                            ),
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
                                  final data = doc.data();
                                  final productId = doc.id;
                                  final title =
                                      data['title']?.toString() ??
                                      'Untitled Product';
                                  final description =
                                      data['description']?.toString() ??
                                      'No description';
                                  final imageUrl =
                                      data['imageUrl']?.toString() ?? '';
                                  final imageUrlsData = data['imageUrls'];
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
                                  final double price = _p(data);
                                  final stockValue = data['stock'] ?? 0;
                                  final int stock = stockValue is int
                                      ? stockValue
                                      : int.tryParse(stockValue.toString()) ??
                                            0;
                                  final sizesData = data['sizes'];
                                  final List<String> sizes = sizesData is List
                                      ? sizesData
                                            .map((s) => s.toString())
                                            .toList()
                                      : [];

                                  return GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ProductPage(
                                          productId: productId,
                                          boutiqueId: widget.boutiqueId,
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
                                          '${price.toStringAsFixed(0)} KWD',
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
