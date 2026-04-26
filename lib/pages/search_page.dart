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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
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

  @override
  Widget build(BuildContext context) {
    final searchText = query.toLowerCase().trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _firestore.collection('boutiques').snapshots(),
                builder: (context, boutiquesSnapshot) {
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _firestore.collectionGroup('products').snapshots(),
                    builder: (context, productsSnapshot) {
                      final isLoading = boutiquesSnapshot.connectionState ==
                          ConnectionState.waiting ||
                          productsSnapshot.connectionState ==
                              ConnectionState.waiting;

                      if (boutiquesSnapshot.hasError ||
                          productsSnapshot.hasError) {
                        return Center(
                          child: Text(
                            AppLocalizations.of(context)!
                                .failedToLoadSearchResults,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        );
                      }

                      final boutiqueDocs = boutiquesSnapshot.data?.docs ?? [];
                      final productDocs = productsSnapshot.data?.docs ?? [];

                      final List<Map<String, dynamic>> boutiques =
                      boutiqueDocs.map((doc) {
                        final data = doc.data();
                        return <String, dynamic>{
                          "boutiqueId": doc.id,
                          "title": data['name']?.toString() ?? '',
                          "imageUrl": data['logoPath']?.toString() ?? '',
                        };
                      }).toList();

                      final List<Map<String, dynamic>> products =
                      productDocs.map((doc) {
                        final data = doc.data();

                        final dynamic priceValue = data['price'] ?? 0;
                        final double price = priceValue is num
                            ? priceValue.toDouble()
                            : double.tryParse(priceValue.toString()) ?? 0;

                        final dynamic stockValue = data['stock'] ?? 0;
                        final int stock = stockValue is int
                            ? stockValue
                            : int.tryParse(stockValue.toString()) ?? 0;

                        final dynamic sizesData = data['sizes'];
                        final List<String> sizes = sizesData is List
                            ? sizesData.map((size) => size.toString()).toList()
                            : <String>[];

                        final parentBoutique =
                            doc.reference.parent.parent?.id ?? '';

                        return <String, dynamic>{
                          "productId": doc.id,
                          "boutiqueId": parentBoutique,
                          "title": data['title']?.toString() ?? '',
                          "brand": data['boutiqueName']?.toString() ??
                              AppLocalizations.of(context)!.boutique,
                          "price": price,
                          "imageUrl": data['imageUrl']?.toString() ?? '',
                          "description": data['description']?.toString() ?? '',
                          "sizes": sizes,
                          "stock": stock,
                        };
                      }).toList();

                      final List<Map<String, dynamic>> productResults =
                      searchText.isEmpty
                          ? products
                          : products.where((product) {
                        final title =
                        (product["title"] as String).toLowerCase();
                        final brand =
                        (product["brand"] as String).toLowerCase();
                        return title.contains(searchText) ||
                            brand.contains(searchText);
                      }).toList();

                      final List<Map<String, dynamic>> boutiqueResults =
                      searchText.isEmpty
                          ? boutiques
                          : boutiques.where((boutique) {
                        final title = (boutique["title"] as String)
                            .toLowerCase();
                        return title.contains(searchText);
                      }).toList();

                      return SingleChildScrollView(
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
                            if (isLoading)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 40),
                                  child: CircularProgressIndicator(
                                    color: AppColors.deepAccent,
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
                              if (productResults.isEmpty)
                                Text(
                                  AppLocalizations.of(context)!
                                      .noMatchingProductsFound,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black54,
                                  ),
                                )
                              else
                                Column(
                                  children: productResults.map((product) {
                                    final String imageUrl =
                                    product["imageUrl"] as String;
                                    final String title =
                                    product["title"] as String;
                                    final String brand =
                                    product["brand"] as String;
                                    final double price =
                                    product["price"] as double;
                                    final String productId =
                                    product["productId"] as String;
                                    final String boutiqueId =
                                    product["boutiqueId"] as String;
                                    final String description =
                                    product["description"] as String;
                                    final List<String> sizes =
                                    List<String>.from(
                                      product["sizes"] as List<dynamic>,
                                    );
                                    final int stock = product["stock"] as int;

                                    return searchResultCard(
                                      imageUrl: imageUrl,
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
                                              imageUrl: imageUrl,
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
                              if (boutiqueResults.isEmpty)
                                Text(
                                  AppLocalizations.of(context)!
                                      .noMatchingBoutiquesFound,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black54,
                                  ),
                                )
                              else
                                Column(
                                  children: boutiqueResults.map((boutique) {
                                    final String imageUrl =
                                    boutique["imageUrl"] as String;
                                    final String title =
                                    boutique["title"] as String;
                                    final String boutiqueId =
                                    boutique["boutiqueId"] as String;

                                    return searchResultCard(
                                      imageUrl: imageUrl,
                                      title: title,
                                      subtitle: AppLocalizations.of(context)!
                                          .boutique,
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
                                ),
                              const SizedBox(height: 30),
                            ],
                          ],
                        ),
                      );
                    },
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