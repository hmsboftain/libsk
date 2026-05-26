import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import 'edit_product_page.dart';
import '../widgets/theme.dart';
import 'package:firebase_storage/firebase_storage.dart';

class OwnerProductsPage extends StatefulWidget {
  const OwnerProductsPage({super.key});

  @override
  State<OwnerProductsPage> createState() => _OwnerProductsPageState();
}

class _OwnerProductsPageState extends State<OwnerProductsPage> {
  String? boutiqueId;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadBoutiqueId();
  }

  Future<void> loadBoutiqueId() async {
    try {
      final id = await FirestoreService.getCurrentOwnerBoutiqueId();

      if (!mounted) return;

      if (id == null) {
        setState(() {
          errorMessage = 'No boutique found for this owner.';
          isLoading = false;
        });
        return;
      }

      setState(() {
        boutiqueId = id;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Failed to load boutique products.';
        isLoading = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
      boutiqueId = null;
    });
    await loadBoutiqueId();
  }

  Future<void> deleteProduct(String productId) async {
    if (boutiqueId == null) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.background,
          shape: const RoundedRectangleBorder(),
          title: const Text(
            'Delete Product',
            style: AppTextStyles.headingSmall,
          ),
          content: Text(
            'Are you sure you want to delete this product?',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.secondaryText,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.deepAccent,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    try {
      final productRef = FirebaseFirestore.instance
          .collection('boutiques')
          .doc(boutiqueId)
          .collection('products')
          .doc(productId);

      final productDoc = await productRef.get();
      final data = productDoc.data();
      final imageUrl = data?['imageUrl']?.toString() ?? '';
      final imageUrlsData = data?['imageUrls'];

      final List<String> imageUrls = imageUrlsData is List
          ? imageUrlsData.map((image) => image.toString()).toList()
          : imageUrl.isNotEmpty
          ? [imageUrl]
          : [];

      await productRef.delete();

      for (final image in imageUrls) {
        try {
          await FirebaseStorage.instance.refFromURL(image).delete();
        } catch (e) {
          debugPrint('Failed to delete product image: $e');
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Product deleted')));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to delete product')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                          child: Text(
                            'MY PRODUCTS',
                            style: AppTextStyles.headingMedium.copyWith(
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        Expanded(
                          child: errorMessage != null
                              ? RefreshIndicator(
                                  color: AppColors.deepAccent,
                                  onRefresh: _onRefresh,
                                  child: ListView(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Text(
                                          errorMessage!,
                                          style: AppTextStyles.bodyMedium
                                              .copyWith(
                                                color: AppColors.secondaryText,
                                              ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : StreamBuilder<
                                  QuerySnapshot<Map<String, dynamic>>
                                >(
                                  stream:
                                      FirestoreService.getOwnerProductsStream(
                                        boutiqueId!,
                                      ),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                        child: CircularProgressIndicator(
                                          color: AppColors.deepAccent,
                                        ),
                                      );
                                    }

                                    if (snapshot.hasError) {
                                      return Center(
                                        child: Text(
                                          'Failed to load products',
                                          style: AppTextStyles.bodyMedium
                                              .copyWith(
                                                color: AppColors.secondaryText,
                                              ),
                                        ),
                                      );
                                    }

                                    final docs = snapshot.data?.docs ?? [];

                                    if (docs.isEmpty) {
                                      return RefreshIndicator(
                                        onRefresh: _onRefresh,
                                        child: SingleChildScrollView(
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          child: SizedBox(
                                            height: 400,
                                            child: Center(
                                              child: Text(
                                                'No products yet',
                                                style: AppTextStyles.bodyMedium
                                                    .copyWith(
                                                      color: AppColors
                                                          .secondaryText,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }

                                    return RefreshIndicator(
                                      color: AppColors.deepAccent,
                                      onRefresh: _onRefresh,
                                      child: ListView.builder(
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        padding: const EdgeInsets.fromLTRB(
                                          20,
                                          8,
                                          20,
                                          24,
                                        ),
                                        itemCount: docs.length,
                                        itemBuilder: (context, index) {
                                          final doc = docs[index];
                                          final data = doc.data();

                                          final title =
                                              data['title'] ?? 'No title';
                                          final description =
                                              data['description'] ??
                                              'No description';
                                          final imageUrl =
                                              data['imageUrl']?.toString() ??
                                              '';
                                          final imageUrlsData =
                                              data['imageUrls'];

                                          final List<String> imageUrls =
                                              imageUrlsData is List
                                              ? imageUrlsData
                                                    .map(
                                                      (image) =>
                                                          image.toString(),
                                                    )
                                                    .toList()
                                              : imageUrl.isNotEmpty
                                              ? [imageUrl]
                                              : [];

                                          final displayImageUrl =
                                              imageUrls.isNotEmpty
                                              ? imageUrls.first
                                              : imageUrl;

                                          final price = data['price'];
                                          final stock = data['stock'];

                                          return Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 14,
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
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  width: 80,
                                                  height: 100,
                                                  decoration: BoxDecoration(
                                                    color: AppColors
                                                        .imagePlaceholder,
                                                    border: Border.all(
                                                      color: AppColors.border,
                                                      width: 0.5,
                                                    ),
                                                  ),
                                                  child:
                                                      displayImageUrl.isNotEmpty
                                                      ? Image.network(
                                                          displayImageUrl,
                                                          width: 80,
                                                          height: 100,
                                                          fit: BoxFit.cover,
                                                          errorBuilder:
                                                              (
                                                                context,
                                                                error,
                                                                stackTrace,
                                                              ) {
                                                                return const Center(
                                                                  child: Icon(
                                                                    Icons
                                                                        .image_not_supported_outlined,
                                                                    color: AppColors
                                                                        .softAccent,
                                                                    size: 24,
                                                                  ),
                                                                );
                                                              },
                                                        )
                                                      : const Center(
                                                          child: Icon(
                                                            Icons
                                                                .image_not_supported_outlined,
                                                            color: AppColors
                                                                .softAccent,
                                                            size: 24,
                                                          ),
                                                        ),
                                                ),
                                                const SizedBox(width: 14),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        title,
                                                        style: AppTextStyles
                                                            .bodyLarge
                                                            .copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        description,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: AppTextStyles
                                                            .bodySmall
                                                            .copyWith(
                                                              height: 1.4,
                                                            ),
                                                      ),
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                      Text(
                                                        '${price ?? 0} KWD',
                                                        style: AppTextStyles
                                                            .labelLarge,
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        'Stock: ${stock ?? 0}',
                                                        style: AppTextStyles
                                                            .bodySmall,
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: OutlinedButton(
                                                              onPressed: () async {
                                                                await Navigator.push(
                                                                  context,
                                                                  MaterialPageRoute(
                                                                    builder: (context) => EditProductPage(
                                                                      productId:
                                                                          doc.id,
                                                                      productData:
                                                                          data,
                                                                    ),
                                                                  ),
                                                                );
                                                                if (!mounted)
                                                                  return;
                                                                setState(() {});
                                                              },
                                                              child: const Text(
                                                                'Edit',
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 10,
                                                          ),
                                                          Expanded(
                                                            child: ElevatedButton(
                                                              onPressed: () {
                                                                deleteProduct(
                                                                  doc.id,
                                                                );
                                                              },
                                                              child: const Text(
                                                                'Delete',
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
