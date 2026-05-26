import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../models/product.dart';
import '../navigation/app_header.dart';
import 'product_page.dart';
import 'boutique_storefront_page.dart';
import '../widgets/theme.dart';
import '../widgets/rotating_hero_banner.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/skeleton_loaders.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _boutiquesStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>>
  _featuredProductsStream;

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
  }

  // Streams are real-time; pull-to-refresh exists only as a UX affordance.
  Future<void> _onRefresh() async {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.deepAccent,
          onRefresh: _onRefresh,
          child: SingleChildScrollView(
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
                    'Featured Pieces',
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
                        title: 'Something went wrong',
                        message: 'Pull down to retry',
                        onRetry: () => setState(() {}),
                        type: ErrorType.network,
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          AppLocalizations.of(
                            context,
                          )!.noFeaturedProductsAvailable,
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
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final product = Product.fromFirestore(doc);
                          final String title = product.title.isNotEmpty
                              ? product.title
                              : AppLocalizations.of(context)!.untitledProduct;
                          final String description =
                              product.description.isNotEmpty
                              ? product.description
                              : AppLocalizations.of(context)!.noDescription;
                          final String boutiqueName =
                              product.boutiqueName.isNotEmpty
                              ? product.boutiqueName
                              : AppLocalizations.of(context)!.boutique;
                          final String displayImageUrl = product.displayImageUrl;

                          return GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ProductPage(
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
                                          border: Border.all(
                                            color: AppColors.border,
                                            width: 0.5,
                                          ),
                                        ),
                                        child: displayImageUrl.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: displayImageUrl,
                                                fit: BoxFit.cover,
                                                width: double.infinity,
                                                placeholder: (context, url) =>
                                                    Container(
                                                      color: AppColors
                                                          .imagePlaceholder,
                                                    ),
                                                errorWidget:
                                                    (
                                                      context,
                                                      url,
                                                      error,
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
                                            color: AppColors.background
                                                .withValues(alpha: 0.92),
                                            border: Border.all(
                                              color: AppColors.border,
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Text(
                                            'FEATURED',
                                            style: AppTextStyles.capsLabel
                                                .copyWith(fontSize: 9),
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
                                  'KD ${product.price.toStringAsFixed(0)}',
                                  style: AppTextStyles.labelLarge.copyWith(
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          );
                        },
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
                    'Top Boutiques',
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
                        title: 'Something went wrong',
                        message: 'Pull down to retry',
                        onRetry: () => setState(() {}),
                        type: ErrorType.network,
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          AppLocalizations.of(context)!.noBoutiquesAvailable,
                          style: AppTextStyles.bodySmall,
                        ),
                      );
                    }

                    return Column(
                      children: docs.map((doc) {
                        final data = doc.data();
                        final boutiqueId = doc.id;
                        final logoUrl = data['logoPath']?.toString() ?? '';
                        final boutiqueName =
                            data['name']?.toString() ?? 'Boutique';

                        return GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BoutiqueStorefrontPage(
                                boutiqueId: boutiqueId,
                              ),
                            ),
                          ),
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              border: Border.all(
                                color: AppColors.border,
                                width: 0.5,
                              ),
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
                                          placeholder: (context, url) =>
                                              Container(
                                                color:
                                                    AppColors.imagePlaceholder,
                                              ),
                                          errorWidget: (context, url, error) =>
                                              Center(
                                                child: Text(
                                                  boutiqueName.isNotEmpty
                                                      ? boutiqueName[0]
                                                            .toUpperCase()
                                                      : 'B',
                                                  style: AppTextStyles
                                                      .headingMedium,
                                                ),
                                              ),
                                        )
                                      : Center(
                                          child: Text(
                                            boutiqueName.isNotEmpty
                                                ? boutiqueName[0].toUpperCase()
                                                : 'B',
                                            style: AppTextStyles.headingMedium,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    boutiqueName,
                                    style: AppTextStyles.bodyLarge,
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 12,
                                  color: AppColors.softAccent,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
