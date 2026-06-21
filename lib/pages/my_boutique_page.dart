import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../widgets/error_state_widget.dart';
import '../models/product.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import '../widgets/theme.dart';
import 'add_product_page.dart';
import 'edit_boutique_page.dart';
import 'edit_product_page.dart';
import '../core/constants/countries.dart';
import '../services/currency_service.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

// ── Page ──────────────────────────────────────────────────────────────────────

class MyBoutiquePage extends StatefulWidget {
  const MyBoutiquePage({super.key});

  @override
  State<MyBoutiquePage> createState() => _MyBoutiquePageState();
}

class _MyBoutiquePageState extends State<MyBoutiquePage> {
  Map<String, dynamic>? _boutiqueData;
  String? _boutiqueId;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final id = await FirestoreService.getCurrentOwnerBoutiqueId();
      if (id == null || id.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = AppLocalizations.of(context)!.noBoutiqueFound;
          _isLoading = false;
        });
        return;
      }

      final data = await FirestoreService.getOwnerBoutiqueData();
      if (!mounted) return;
      setState(() {
        _boutiqueId = id;
        _boutiqueData = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _onRefresh() => _load();

  Future<void> _editBoutique() async {
    if (_boutiqueData == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditBoutiquePage(boutiqueData: _boutiqueData!),
      ),
    );
    if (result == true && mounted) await _load();
  }

  Future<void> _addProduct() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddProductPage()),
    );
    if (result == true && mounted) await _load();
  }

  Future<void> _editProduct(
    String productId,
    Map<String, dynamic> productData,
  ) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EditProductPage(productId: productId, productData: productData),
      ),
    );
    if (result == true && mounted) await _load();
  }

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
                  : _error != null
                  ? RefreshIndicator(
                      color: AppColors.deepAccent,
                      onRefresh: _onRefresh,
                      child: ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _error!,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.secondaryText,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _buildContent(l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    final name = _boutiqueData?['name']?.toString() ?? l10n.boutique;
    final description = _boutiqueData?['description']?.toString() ?? '';
    final logoUrl = _boutiqueData?['logoPath']?.toString() ?? '';
    final bannerUrl = _boutiqueData?['bannerPath']?.toString() ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'B';

    return RefreshIndicator(
      color: AppColors.deepAccent,
      onRefresh: _onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Boutique header ─────────────────────────────────────
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Banner
                Container(
                  width: double.infinity,
                  height: 150,
                  color: AppColors.imagePlaceholder,
                  child: bannerUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: bannerUrl,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: AppColors.imagePlaceholder),
                          errorWidget: (_, __, ___) =>
                              Container(color: AppColors.imagePlaceholder),
                        )
                      : null,
                ),
                // Logo overlapping the banner
                Positioned(
                  bottom: -32,
                  left: 20,
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      border: Border.all(color: AppColors.border, width: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: logoUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: logoUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Center(
                                child: Text(
                                  initial,
                                  style: AppTextStyles.headingLarge,
                                ),
                              ),
                              errorWidget: (_, __, ___) => Center(
                                child: Text(
                                  initial,
                                  style: AppTextStyles.headingLarge,
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                initial,
                                style: AppTextStyles.headingLarge,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),

            // Name, description, edit button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: AppTextStyles.headingLarge),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: AppTextStyles.bodySmall.copyWith(
                              height: 1.4,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _editBoutique,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.deepAccent,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        'Edit',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.deepAccent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(color: AppColors.border, thickness: 0.5),
            ),
            const SizedBox(height: 20),

            // ── Products section ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(l10n.products, style: AppTextStyles.headingSmall),
                  const Spacer(),
                  GestureDetector(
                    onTap: _addProduct,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(color: AppColors.deepAccent),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(l10n.addProduct, style: AppTextStyles.button),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Product list
            _boutiqueId == null
                ? const SizedBox()
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirestoreService.getOwnerProductsStream(
                      _boutiqueId!,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
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

                      if (snapshot.hasError) {
                        return ErrorStateWidget.inline(
                          title: l10n.failedToLoadProducts,
                          message: l10n.pullDownToRetry,
                          onRetry: () => setState(() {}),
                          type: ErrorType.network,
                        );
                      }

                      final docs = snapshot.data?.docs ?? [];

                      if (docs.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 40,
                          ),
                          child: Center(
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.inventory_2_outlined,
                                  size: 40,
                                  color: AppColors.softAccent,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  l10n.noMatchingProductsFound,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                GestureDetector(
                                  onTap: _addProduct,
                                  child: Text(
                                    'Add your first product',
                                    style: AppTextStyles.labelLarge.copyWith(
                                      color: AppColors.deepAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: docs
                              .map(
                                (doc) => _ProductCard(
                                  doc: doc,
                                  l10n: l10n,
                                  onEdit: () =>
                                      _editProduct(doc.id, doc.data()),
                                  onDelete: () => _deleteProduct(doc.id),
                                ),
                              )
                              .toList(),
                        ),
                      );
                    },
                  ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// ── Product card widget ───────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final AppLocalizations l10n;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.doc,
    required this.l10n,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final product = Product.fromFirestore(doc);
    final data = doc.data();

    final title = product.title.isNotEmpty
        ? product.title
        : l10n.untitledProduct;
    final displayImageUrl = product.displayImageUrl;
    final price = data['price'];
    final stock = data['stock'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          Container(
            width: 72,
            height: 90,
            decoration: BoxDecoration(
              color: AppColors.imagePlaceholder,
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: displayImageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: displayImageUrl,
                    width: 72,
                    height: 90,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: AppColors.imagePlaceholder),
                    errorWidget: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: AppColors.softAccent,
                        size: 22,
                      ),
                    ),
                  )
                : const Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: AppColors.softAccent,
                      size: 22,
                    ),
                  ),
          ),
          const SizedBox(width: 14),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${_fmt((price is num) ? price.toDouble() : double.tryParse('${price ?? 0}') ?? 0)}  ·  ${l10n.stockLabel(stock?.toString() ?? '0')}',
                  style: AppTextStyles.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onEdit,
                        child: Container(
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppColors.deepAccent,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            l10n.editProduct,
                            style: AppTextStyles.labelLarge.copyWith(
                              color: AppColors.deepAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: onDelete,
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.border,
                            width: 0.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: AppColors.secondaryText,
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
