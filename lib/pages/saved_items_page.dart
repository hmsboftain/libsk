import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../widgets/product_card.dart';
import '../services/firestore_service.dart';
import 'product_page.dart';
import '../widgets/theme.dart';

class SavedItemsPage extends StatefulWidget {
  const SavedItemsPage({super.key});

  @override
  State<SavedItemsPage> createState() => _SavedItemsPageState();
}

class _SavedItemsPageState extends State<SavedItemsPage> {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            const SizedBox(height: 12),
            Text(
              loc.savedItems,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirestoreService.getSavedItemsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        loc.failedToLoadSavedItems,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: () async {
                        setState(() {});
                      },
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SizedBox(
                          height: 400,
                          child: Center(
                            child: Text(
                              loc.noSavedItemsYet,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      setState(() {});
                    },
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 16,
                        children: docs.map((doc) {
                          final item = doc.data();

                          final String productId = item["productId"] ?? "";
                          final String boutiqueId = item["boutiqueId"] ?? "";
                          final String imageUrl = item["imageUrl"] ?? "";
                          final imageUrlsData = item["imageUrls"];
                          final List<String> imageUrls = imageUrlsData is List
                              ? imageUrlsData.map((image) => image.toString()).toList()
                              : imageUrl.isNotEmpty
                              ? [imageUrl]
                              : [];
                          final displayImageUrl = imageUrls.isNotEmpty ? imageUrls.first : imageUrl;
                          final String title = item["title"] ?? "";
                          final String boutiqueName = item["boutiqueName"] ?? "";
                          final String description = item["description"] ?? "";

                          final dynamic priceValue = item["price"] ?? 0;
                          final double price = priceValue is num
                              ? priceValue.toDouble()
                              : double.tryParse(priceValue.toString()) ?? 0;

                          final dynamic stockValue = item["stock"] ?? 0;
                          final int stock = stockValue is int
                              ? stockValue
                              : int.tryParse(stockValue.toString()) ?? 0;

                          final dynamic sizesData = item["sizes"];
                          final List<String> sizes = sizesData is List
                              ? sizesData.map((size) => size.toString()).toList()
                              : [];

                          return buildProductCard(
                            imageUrl: displayImageUrl,
                            title: title,
                            brand: boutiqueName,
                            price: "${price.toStringAsFixed(0)} KWD",
                            isLiked: true,
                            onLikeTap: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              await FirestoreService.removeSavedItem(productId);
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(loc.itemRemovedFromSaved),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
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
                          );
                        }).toList(),
                      ),
                    ),
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