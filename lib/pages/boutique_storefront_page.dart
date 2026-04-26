import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import 'product_page.dart';
import '../widgets/boutique_logo_avatar.dart';
import '../widgets/theme.dart';

enum SortOption { newest, oldest, priceLow, priceHigh }

class BoutiqueStorefrontPage extends StatefulWidget {
  final String boutiqueId;

  const BoutiqueStorefrontPage({
    super.key,
    required this.boutiqueId,
  });

  @override
  State<BoutiqueStorefrontPage> createState() => _BoutiqueStorefrontPageState();
}

class _BoutiqueStorefrontPageState extends State<BoutiqueStorefrontPage> {
  SortOption _sortOption = SortOption.newest;

  Future<void> _onRefresh() async {
    setState(() {});
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final sorted = List.of(docs);

    switch (_sortOption) {
      case SortOption.newest:
        sorted.sort((a, b) {
          final aTime = a.data()['createdAt'];
          final bTime = b.data()['createdAt'];
          if (aTime is Timestamp && bTime is Timestamp) {
            return bTime.compareTo(aTime);
          }
          return 0;
        });
        break;
      case SortOption.oldest:
        sorted.sort((a, b) {
          final aTime = a.data()['createdAt'];
          final bTime = b.data()['createdAt'];
          if (aTime is Timestamp && bTime is Timestamp) {
            return aTime.compareTo(bTime);
          }
          return 0;
        });
        break;
      case SortOption.priceLow:
        sorted.sort((a, b) {
          final aPrice = (a.data()['price'] ?? 0) is num
              ? (a.data()['price'] as num).toDouble()
              : double.tryParse(a.data()['price'].toString()) ?? 0;
          final bPrice = (b.data()['price'] ?? 0) is num
              ? (b.data()['price'] as num).toDouble()
              : double.tryParse(b.data()['price'].toString()) ?? 0;
          return aPrice.compareTo(bPrice);
        });
        break;
      case SortOption.priceHigh:
        sorted.sort((a, b) {
          final aPrice = (a.data()['price'] ?? 0) is num
              ? (a.data()['price'] as num).toDouble()
              : double.tryParse(a.data()['price'].toString()) ?? 0;
          final bPrice = (b.data()['price'] ?? 0) is num
              ? (b.data()['price'] as num).toDouble()
              : double.tryParse(b.data()['price'].toString()) ?? 0;
          return bPrice.compareTo(aPrice);
        });
        break;
    }

    return sorted;
  }

  Widget _buildSortBar(int productCount) {
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
            '$productCount ${productCount == 1 ? 'product' : 'products'}',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.secondaryText,
              fontWeight: FontWeight.w500,
            ),
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
                    padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.deepAccent
                          : AppColors.field,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.deepAccent
                            : AppColors.border,
                      ),
                    ),
                    child: Text(
                      option.$2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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
    final boutiqueRef =
    FirebaseFirestore.instance.collection('boutiques').doc(widget.boutiqueId);

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
                ),
              );
            }

            if (boutiqueSnapshot.hasError) {
              return const Center(
                child: Text(
                  'Failed to load boutique',
                  style: TextStyle(color: AppColors.secondaryText),
                ),
              );
            }

            if (!boutiqueSnapshot.hasData || !boutiqueSnapshot.data!.exists) {
              return const Center(
                child: Text(
                  'Boutique not found',
                  style: TextStyle(color: AppColors.secondaryText),
                ),
              );
            }

            final boutiqueData = boutiqueSnapshot.data!.data() ?? {};
            final boutiqueName =
                boutiqueData['name']?.toString() ?? 'Boutique';
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
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        bannerPath.isNotEmpty
                            ? Image.network(
                          bannerPath,
                          height: 220,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
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
                                  AppColors.background.withValues(alpha:0.9),
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
                                  color: Colors.black.withValues(alpha:0.08),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child:
                            BoutiqueLogoAvatar(imageUrl: logoPath, size: 80),
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
                          Text(
                            boutiqueName,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryText,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            boutiqueDescription,
                            style: const TextStyle(
                              fontSize: 14,
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
                      child: Divider(),
                    ),
                    const SizedBox(height: 14),
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
                              ),
                            ),
                          );
                        }

                        if (productsSnapshot.hasError) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Text(
                                'Failed to load products',
                                style: TextStyle(
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ),
                          );
                        }

                        final rawDocs = productsSnapshot.data?.docs ?? [];

                        if (rawDocs.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 60),
                            child: Center(
                              child: Text(
                                'No products available yet',
                                style: TextStyle(
                                  fontSize: 15,
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
                              padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                              child: GridView.builder(
                                itemCount: docs.length,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 20,
                                  childAspectRatio: 0.62,
                                ),
                                itemBuilder: (context, index) {
                                  final doc = docs[index];
                                  final data = doc.data();

                                  final productId = doc.id;
                                  final title = data['title']?.toString() ??
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
                                      .map((image) => image.toString())
                                      .toList()
                                      : imageUrl.isNotEmpty
                                      ? [imageUrl]
                                      : [];

                                  final displayImageUrl = imageUrls.isNotEmpty
                                      ? imageUrls.first
                                      : imageUrl;

                                  final priceValue = data['price'] ?? 0;
                                  final stockValue = data['stock'] ?? 0;
                                  final sizesData = data['sizes'];

                                  final double price = priceValue is num
                                      ? priceValue.toDouble()
                                      : double.tryParse(
                                    priceValue.toString(),
                                  ) ??
                                      0;

                                  final int stock = stockValue is int
                                      ? stockValue
                                      : int.tryParse(stockValue.toString()) ??
                                      0;

                                  final List<String> sizes = sizesData is List
                                      ? sizesData
                                      .map((s) => s.toString())
                                      .toList()
                                      : [];

                                  return GestureDetector(
                                    onTap: () {
                                      Navigator.push(
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
                                      );
                                    },
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Stack(
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                              BorderRadius.circular(16),
                                              child: displayImageUrl.isNotEmpty
                                                  ? Image.network(
                                                displayImageUrl,
                                                height: 210,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context,
                                                    error,
                                                    stackTrace) =>
                                                    Container(
                                                      height: 210,
                                                      color: AppColors.field,
                                                      alignment:
                                                      Alignment.center,
                                                      child: const Icon(
                                                        Icons
                                                            .image_not_supported_outlined,
                                                        color: AppColors
                                                            .deepAccent,
                                                        size: 30,
                                                      ),
                                                    ),
                                              )
                                                  : Container(
                                                height: 210,
                                                color: AppColors.field,
                                                alignment:
                                                Alignment.center,
                                                child: const Icon(
                                                  Icons
                                                      .image_not_supported_outlined,
                                                  color: AppColors
                                                      .deepAccent,
                                                  size: 30,
                                                ),
                                              ),
                                            ),
                                            if (stock <= 0)
                                              Positioned(
                                                top: 10,
                                                left: 10,
                                                child: Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withValues(alpha:0.65),
                                                    borderRadius:
                                                    BorderRadius.circular(
                                                      8,
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    'Sold Out',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                      FontWeight.w600,
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
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primaryText,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          boutiqueName,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.secondaryText,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${price.toStringAsFixed(0)} KWD',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primaryText,
                                          ),
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