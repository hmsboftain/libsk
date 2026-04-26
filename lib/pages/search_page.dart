import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import 'product_page.dart';
import 'boutique_storefront_page.dart';
import '../widgets/theme.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String query = "";

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    setState(() {});
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 65,
      height: 75,
      color: AppColors.imagePlaceholder,
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: Colors.black54,
      ),
    );
  }

  Widget searchResultCard({
    required String imageUrl,
    required String title,
    required String subtitle,
    required String trailingText,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.field,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imageUrl.isNotEmpty
                  ? Image.network(
                imageUrl,
                width: 65,
                height: 75,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _imagePlaceholder();
                },
              )
                  : _imagePlaceholder(),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            if (trailingText.isNotEmpty)
              Text(
                trailingText,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Query<Map<String, dynamic>> _productQuery(String searchText) {
    return _firestore
        .collectionGroup('products')
        .orderBy('title')
        .startAt([searchText])
        .endAt(['$searchText\uf8ff'])
        .limit(25);
  }

  Query<Map<String, dynamic>> _boutiqueQuery(String searchText) {
    return _firestore
        .collection('boutiques')
        .orderBy('name')
        .startAt([searchText])
        .endAt(['$searchText\uf8ff'])
        .limit(25);
  }

  @override
  Widget build(BuildContext context) {
    final searchText = query.trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context)!.search,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: searchController,
                        onChanged: (value) {
                          setState(() {
                            query = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(context)!
                              .searchProductsOrBoutiques,
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: AppColors.field,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (searchText.length < 2)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text(
                              'Type at least 2 characters to search.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        )
                      else ...[
                        Text(
                          AppLocalizations.of(context)!.products,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _productQuery(searchText).snapshots(),
                          builder: (context, productsSnapshot) {
                            if (productsSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.deepAccent,
                                  ),
                                ),
                              );
                            }

                            if (productsSnapshot.hasError) {
                              return Text(
                                AppLocalizations.of(context)!
                                    .failedToLoadSearchResults,
                                style: const TextStyle(color: Colors.black54),
                              );
                            }

                            final productDocs =
                                productsSnapshot.data?.docs ?? [];

                            if (productDocs.isEmpty) {
                              return Text(
                                AppLocalizations.of(context)!
                                    .noMatchingProductsFound,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54,
                                ),
                              );
                            }

                            return Column(
                              children: productDocs.map((doc) {
                                final data = doc.data();

                                final priceValue = data['price'] ?? 0;
                                final double price = priceValue is num
                                    ? priceValue.toDouble()
                                    : double.tryParse(
                                    priceValue.toString()) ??
                                    0;

                                final stockValue = data['stock'] ?? 0;
                                final int stock = stockValue is int
                                    ? stockValue
                                    : int.tryParse(stockValue.toString()) ?? 0;

                                final sizesData = data['sizes'];
                                final List<String> sizes = sizesData is List
                                    ? sizesData
                                    .map((size) => size.toString())
                                    .toList()
                                    : <String>[];

                                final productId = doc.id;
                                final boutiqueId =
                                    doc.reference.parent.parent?.id ?? '';
                                final title =
                                    data['title']?.toString() ?? 'Product';
                                final brand =
                                    data['boutiqueName']?.toString() ??
                                        AppLocalizations.of(context)!.boutique;
                                final imageUrl =
                                    data['imageUrl']?.toString() ?? '';
                                final imageUrlsData = data['imageUrls'];

                                final List<String> imageUrls =
                                imageUrlsData is List
                                    ? imageUrlsData
                                    .map((image) => image.toString())
                                    .toList()
                                    : imageUrl.isNotEmpty
                                    ? [imageUrl]
                                    : [];

                                final displayImageUrl = imageUrls.isNotEmpty
                                    ? imageUrls.first
                                    : imageUrl;

                                final description =
                                    data['description']?.toString() ?? '';

                                return searchResultCard(
                                  imageUrl: displayImageUrl,
                                  title: title,
                                  subtitle: brand,
                                  trailingText:
                                  "${price.toStringAsFixed(0)} KWD",
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
                                          boutiqueName: brand,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              }).toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 26),
                        Text(
                          AppLocalizations.of(context)!.boutiques,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _boutiqueQuery(searchText).snapshots(),
                          builder: (context, boutiquesSnapshot) {
                            if (boutiquesSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.deepAccent,
                                  ),
                                ),
                              );
                            }

                            if (boutiquesSnapshot.hasError) {
                              return Text(
                                AppLocalizations.of(context)!
                                    .failedToLoadSearchResults,
                                style: const TextStyle(color: Colors.black54),
                              );
                            }

                            final boutiqueDocs =
                                boutiquesSnapshot.data?.docs ?? [];

                            if (boutiqueDocs.isEmpty) {
                              return Text(
                                AppLocalizations.of(context)!
                                    .noMatchingBoutiquesFound,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54,
                                ),
                              );
                            }

                            return Column(
                              children: boutiqueDocs.map((doc) {
                                final data = doc.data();

                                final boutiqueId = doc.id;
                                final title =
                                    data['name']?.toString() ?? 'Boutique';
                                final displayImageUrl =
                                    data['logoPath']?.toString() ?? '';

                                return searchResultCard(
                                  imageUrl: displayImageUrl,
                                  title: title,
                                  subtitle:
                                  AppLocalizations.of(context)!.boutique,
                                  trailingText: "",
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            BoutiqueStorefrontPage(
                                              boutiqueId: boutiqueId,
                                            ),
                                      ),
                                    );
                                  },
                                );
                              }).toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 30),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}