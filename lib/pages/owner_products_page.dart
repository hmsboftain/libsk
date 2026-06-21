import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../widgets/error_state_widget.dart';
import '../models/product.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import '../widgets/theme.dart';
import 'edit_product_page.dart';
import '../core/constants/countries.dart';
import '../services/currency_service.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

// ── Page ──────────────────────────────────────────────────────────────────────

class OwnerProductsPage extends StatefulWidget {
  const OwnerProductsPage({super.key});

  @override
  State<OwnerProductsPage> createState() => _OwnerProductsPageState();
}

class _OwnerProductsPageState extends State<OwnerProductsPage> {
  String? _boutiqueId;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBoutiqueId();
  }

  Future<void> _loadBoutiqueId() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _boutiqueId = null;
    });

    try {
      final id = await FirestoreService.getCurrentOwnerBoutiqueId();
      if (!mounted) return;

      if (id == null) {
        setState(() {
          _errorMessage = AppLocalizations.of(context)!.noBoutiqueFound;
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _boutiqueId = id;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.failedToLoadProducts;
        _isLoading = false;
      });
    }
  }

  Future<void> _onRefresh() => _loadBoutiqueId();

  Future<void> _deleteProduct(String productId) async {
    final l10n = AppLocalizations.of(context)!;
    if (_boutiqueId == null) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: const RoundedRectangleBorder(),
        title: Text(l10n.deleteProduct, style: AppTextStyles.headingSmall),
        content: Text(
          l10n.deleteProductConfirm,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.secondaryText,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.cancel,
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: Text(l10n.deleteProduct, style: AppTextStyles.button),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      final productRef = FirebaseFirestore.instance
          .collection('boutiques')
          .doc(_boutiqueId)
          .collection('products')
          .doc(productId);

      final productDoc = await productRef.get();
      final data = productDoc.data();

      // Only read imageUrls — imageUrl standalone field was removed
      final imageUrlsData = data?['imageUrls'];
      final List<String> imageUrls = imageUrlsData is List
          ? imageUrlsData.map((e) => e.toString()).toList()
          : [];

      await productRef.delete();

      for (final url in imageUrls) {
        await StorageService.deleteImageByUrl(
          url,
        ).catchError((e) => debugPrint('Image cleanup error: $e'));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.productDeleted)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.failedToDeleteProduct)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: _isLoading
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
                            l10n.myProducts,
                            style: AppTextStyles.headingMedium.copyWith(
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _errorMessage != null
                              ? RefreshIndicator(
                                  color: AppColors.deepAccent,
                                  onRefresh: _onRefresh,
                                  child: ListView(
                                    children: [
                                      SizedBox(
                                        height: 400,
                                        child: ErrorStateWidget.inline(
                                          title: _errorMessage!,
                                          message: l10n.pullDownToRetry,
                                          onRetry: _onRefresh,
                                          type: ErrorType.network,
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
                                        _boutiqueId!,
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
                                          l10n.failedToLoadProducts,
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
                                                l10n.noMatchingProductsFound,
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
                                        itemBuilder: (context, index) =>
                                            _OwnerProductCard(
                                              doc: docs[index],
                                              l10n: l10n,
                                              onDelete: _deleteProduct,
                                            ),
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

// ── Product card widget ───────────────────────────────────────────────────────

class _OwnerProductCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final AppLocalizations l10n;
  final Future<void> Function(String productId) onDelete;

  const _OwnerProductCard({
    required this.doc,
    required this.l10n,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final product = Product.fromFirestore(doc);

    final title = product.title.isNotEmpty
        ? product.title
        : l10n.untitledProduct;
    final description = product.description.isNotEmpty
        ? product.description
        : l10n.noDescription;
    final displayImageUrl = product.displayImageUrl;
    final price = data['price'];
    final stock = data['stock'];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product image
          Container(
            width: 80,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.imagePlaceholder,
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: displayImageUrl.isNotEmpty
                ? Image.network(
                    displayImageUrl,
                    width: 80,
                    height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: AppColors.softAccent,
                        size: 24,
                      ),
                    ),
                  )
                : const Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: AppColors.softAccent,
                      size: 24,
                    ),
                  ),
          ),
          const SizedBox(width: 14),

          // Product details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(height: 1.4),
                ),
                const SizedBox(height: 10),
                Text(_fmt((price is num) ? price.toDouble() : double.tryParse('${price ?? 0}') ?? 0), style: AppTextStyles.labelLarge),
                const SizedBox(height: 6),
                Text(
                  l10n.stockLabel(stock?.toString() ?? '0'),
                  style: AppTextStyles.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditProductPage(
                              productId: doc.id,
                              productData: data,
                            ),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.deepAccent,
                          side: const BorderSide(
                            color: AppColors.deepAccent,
                            width: 0.5,
                          ),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text(
                          l10n.editProduct,
                          style: AppTextStyles.labelLarge,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => onDelete(doc.id),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.deepAccent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text(
                          l10n.deleteProduct,
                          style: AppTextStyles.button,
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
  }
}
