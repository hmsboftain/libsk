import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../widgets/product_card.dart';
import '../widgets/boutiques_logo.dart';
import '../navigation/app_header.dart';
import 'product_page.dart';
import 'boutique_storefront_page.dart';
import '../widgets/theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _onRefresh() async {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final boutiquesStream = _firestore
        .collection('boutiques')
        .where('isVisibleOnHome', isEqualTo: true)
        .where('homeExpiresAt', isGreaterThan: Timestamp.now())
        .orderBy('homeExpiresAt')
        .orderBy('homeOrder')
        .snapshots();

    final featuredProductsStream = _firestore
        .collectionGroup('products')
        .where('isFeaturedOnHome', isEqualTo: true)
        .where('featuredExpiresAt', isGreaterThan: Timestamp.now())
        .orderBy('featuredExpiresAt')
        .orderBy('featuredOrder')
        .snapshots();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppHeader(),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset(
                      "assets/home_banner.png",
                      height: 280,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      bottom: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          border: Border.all(color: Colors.black26, width: 1.5),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.exploreRamadanCollection,
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        AppLocalizations.of(context)!.featuredPieces,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_forward_ios_outlined, size: 24),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: featuredProductsStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          AppLocalizations.of(context)!
                              .failedToLoadFeaturedProducts,
                        ),
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];

                    if (docs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          AppLocalizations.of(context)!
                              .noFeaturedProductsAvailable,
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: docs.map((doc) {
                          final data = doc.data();

                          final String productId = doc.id;
                          final String boutiqueId =
                              doc.reference.parent.parent!.id;

                          final String title = data['title']?.toString() ??
                              AppLocalizations.of(context)!.untitledProduct;
                          final String description =
                              data['description']?.toString() ??
                                  AppLocalizations.of(context)!.noDescription;

                          final String imageUrl =
                              data['imageUrl']?.toString() ?? '';
                          final imageUrlsData = data['imageUrls'];

                          final List<String> imageUrls = imageUrlsData is List
                              ? imageUrlsData
                              .map((image) => image.toString())
                              .toList()
                              : imageUrl.isNotEmpty
                              ? [imageUrl]
                              : [];

                          final displayImageUrl =
                          imageUrls.isNotEmpty ? imageUrls.first : imageUrl;

                          final String boutiqueName =
                              data['boutiqueName']?.toString() ??
                                  AppLocalizations.of(context)!.boutique;

                          final priceValue = data['price'] ?? 0;
                          final double price = priceValue is num
                              ? priceValue.toDouble()
                              : double.tryParse(priceValue.toString()) ?? 0;

                          final stockValue = data['stock'] ?? 0;
                          final int stock = stockValue is int
                              ? stockValue
                              : int.tryParse(stockValue.toString()) ?? 0;

                          final sizesData = data['sizes'];
                          final List<String> sizes = sizesData is List
                              ? sizesData.map((size) => size.toString()).toList()
                              : [];

                          return Row(
                            children: [
                              buildProductCard(
                                imageUrl: displayImageUrl,
                                title: title,
                                brand: boutiqueName,
                                price: "${price.toStringAsFixed(0)} KWD",
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ProductPage(
                                        productId: productId,
                                        boutiqueId: boutiqueId,
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
                                  );
                                },
                              ),
                              const SizedBox(width: 12),
                            ],
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        AppLocalizations.of(context)!.exploreBoutiques,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_forward_ios, size: 18),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: boutiquesStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          AppLocalizations.of(context)!.failedToLoadBoutiques,
                        ),
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];

                    if (docs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          AppLocalizations.of(context)!.noBoutiquesAvailable,
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: docs.map((doc) {
                          final data = doc.data();
                          final boutiqueId = doc.id;
                          final logoUrl = data['logoPath']?.toString() ?? '';

                          return Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: buildBoutiquesLogo(
                              logoUrl,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => BoutiqueStorefrontPage(
                                      boutiqueId: boutiqueId,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}