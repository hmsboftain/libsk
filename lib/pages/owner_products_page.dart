import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import 'edit_product_page.dart';
import '../widgets/theme.dart';

class OwnerProductsPage extends StatefulWidget {
  const OwnerProductsPage({super.key});

  @override
  State<OwnerProductsPage> createState() => _OwnerProductsPageState();
}

class _OwnerProductsPageState extends State<OwnerProductsPage> {
  String? boutiqueId;
  bool isLoading = true;
  String? errorMessage;

  static const backgroundColor = AppColors.background;
  static const cardColor = AppColors.card;
  static const fieldColor = AppColors.field;
  static const borderColor = AppColors.border;
  static const primaryText = AppColors.primaryText;
  static const secondaryText = AppColors.secondaryText;
  static const softAccent = AppColors.softAccent;
  static const deepAccent = AppColors.deepAccent;

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
          backgroundColor: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Delete Product',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: primaryText,
            ),
          ),
          content: const Text(
            'Are you sure you want to delete this product?',
            style: TextStyle(
              color: secondaryText,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: deepAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('boutiques')
          .doc(boutiqueId)
          .collection('products')
          .doc(productId)
          .delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete product')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: isLoading
                  ? const Center(
                child: CircularProgressIndicator(
                  color: deepAccent,
                ),
              )
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Text(
                      'MY PRODUCTS',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: primaryText,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  Expanded(
                    child: errorMessage != null
                        ? RefreshIndicator(
                      onRefresh: _onRefresh,
                      child: ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(
                                fontSize: 15,
                                color: secondaryText,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    )
                        : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirestoreService.getOwnerProductsStream(
                        boutiqueId!,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: deepAccent,
                            ),
                          );
                        }

                        if (snapshot.hasError) {
                          return const Center(
                            child: Text(
                              'Failed to load products',
                              style: TextStyle(
                                color: secondaryText,
                              ),
                            ),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];

                        if (docs.isEmpty) {
                          return RefreshIndicator(
                            onRefresh: _onRefresh,
                            child: const SingleChildScrollView(
                              physics: AlwaysScrollableScrollPhysics(),
                              child: SizedBox(
                                height: 400,
                                child: Center(
                                  child: Text(
                                    'No products yet',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: secondaryText,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        return RefreshIndicator(
                          onRefresh: _onRefresh,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final doc = docs[index];
                              final data = doc.data();

                              final title = data['title'] ?? 'No title';
                              final description = data['description'] ?? 'No description';
                              final imageUrl = data['imageUrl'] ?? '';
                              final price = data['price'];
                              final stock = data['stock'];

                              return Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: imageUrl.toString().isNotEmpty
                                          ? Image.network(
                                        imageUrl,
                                        width: 82,
                                        height: 100,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            width: 82,
                                            height: 100,
                                            color: fieldColor,
                                            child: const Icon(
                                              Icons.image_not_supported_outlined,
                                              color: deepAccent,
                                            ),
                                          );
                                        },
                                      )
                                          : Container(
                                        width: 82,
                                        height: 100,
                                        color: fieldColor,
                                        child: const Icon(
                                          Icons.image_not_supported_outlined,
                                          color: deepAccent,
                                        ),
                                      ),
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
                                              color: primaryText,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            description,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: secondaryText,
                                              height: 1.4,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            '${price ?? 0} KWD',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: primaryText,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Stock: ${stock ?? 0}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: secondaryText,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton(
                                                  onPressed: () async {
                                                    await Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) => EditProductPage(
                                                          productId: doc.id,
                                                          productData: data,
                                                        ),
                                                      ),
                                                    );
                                                    if (!mounted) return;
                                                    setState(() {});
                                                  },
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: deepAccent,
                                                    backgroundColor: AppColors.softAccent.withOpacity(0.08),
                                                    side: const BorderSide(color: deepAccent),
                                                    elevation: 0,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                                  ),
                                                  child: const Text(
                                                    'Edit',
                                                    style: TextStyle(fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: ElevatedButton(
                                                  onPressed: () {
                                                    deleteProduct(doc.id);
                                                  },
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.black,
                                                    foregroundColor: Colors.white,
                                                    elevation: 0,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                                  ),
                                                  child: const Text(
                                                    'Delete',
                                                    style: TextStyle(fontWeight: FontWeight.w600),
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