import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/product_badges.dart';
import '../widgets/theme.dart';

// ── Pure helpers ──────────────────────────────────────────────────────────────

Widget _buildDropdownSection({
  required String title,
  required bool isOpen,
  required VoidCallback onTap,
  required String content,
}) {
  return Column(
    children: [
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Text(title, style: AppTextStyles.labelLarge),
              const Spacer(),
              Icon(
                isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: AppColors.primaryText,
              ),
            ],
          ),
        ),
      ),
      if (isOpen)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            content,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.secondaryText,
              height: 1.5,
            ),
          ),
        ),
      const Divider(color: AppColors.border, thickness: 0.5),
    ],
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

class ProductPage extends StatefulWidget {
  final String productId;
  final String boutiqueId;
  final String imageUrl;
  final List<String> imageUrls;
  final String title;
  final double price;
  final String description;
  final List<String> sizes;
  final int stock;
  final String boutiqueName;

  const ProductPage({
    super.key,
    required this.productId,
    required this.boutiqueId,
    required this.imageUrl,
    this.imageUrls = const [],
    required this.title,
    required this.price,
    required this.description,
    required this.sizes,
    required this.stock,
    required this.boutiqueName,
  });

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  final _pageController = PageController();
  final _firestore = FirebaseFirestore.instance;

  int _selectedImageIndex = 0;
  String _selectedSize = '';
  String _selectedColor = '';
  bool _showProductDetails = false;
  bool _liked = false;
  bool _isLoadingLike = true;

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _productStream;

  @override
  void initState() {
    super.initState();
    _productStream = _firestore
        .collection('boutiques')
        .doc(widget.boutiqueId)
        .collection('products')
        .doc(widget.productId)
        .snapshots();
    _loadSavedStatus();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ── Data helpers ──────────────────────────────────────────────────────────

  Map<String, dynamic> _fallbackProductData() => {
    'title': widget.title,
    'description': widget.description,
    'price': widget.price,
    'stock': widget.stock,
    'sizes': widget.sizes,
    'imageUrl': widget.imageUrl,
    'imageUrls': widget.imageUrls,
    'boutiqueName': widget.boutiqueName,
  };

  Map<String, dynamic> _resolveProductData(
    DocumentSnapshot<Map<String, dynamic>>? snapshot,
  ) {
    final fallback = _fallbackProductData();
    final live = snapshot?.data();
    if (live == null || live.isEmpty) return fallback;
    return {
      ...fallback,
      ...live,
      if (live['boutiqueName'] == null) 'boutiqueName': widget.boutiqueName,
    };
  }

  List<String> _parseColors(Map<String, dynamic> data) {
    final v = data['colors'];
    if (v is List)
      return v
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    return [];
  }

  List<String> _parseSizes(Map<String, dynamic> data) {
    final sizeEntries = data['sizeEntries'];
    if (sizeEntries is List && sizeEntries.isNotEmpty) {
      return sizeEntries
          .map(
            (e) => e is Map
                ? e['name']?.toString().trim() ?? ''
                : e.toString().trim(),
          )
          .where((s) => s.isNotEmpty)
          .toList();
    }
    final sizes = data['sizes'];
    if (sizes is List)
      return sizes
          .map((s) => s.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    return widget.sizes;
  }

  double _parsePrice(Map<String, dynamic> data) {
    final v = data['price'] ?? widget.price;
    return v is num
        ? v.toDouble()
        : double.tryParse(v.toString()) ?? widget.price;
  }

  int _parseStock(Map<String, dynamic> data) {
    final v = data['stock'] ?? widget.stock;
    return v is int ? v : int.tryParse(v.toString()) ?? widget.stock;
  }

  bool _isOutOfStock(Map<String, dynamic> data) => data['isOutOfStock'] == true;

  /// Active sale price, only when set and genuinely below the regular price.
  double? _salePrice(Map<String, dynamic> data) {
    final price = _parsePrice(data);
    final v = data['salePrice'];
    final sale = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
    return (sale != null && sale > 0 && sale < price) ? sale : null;
  }

  List<String> _galleryImages(Map<String, dynamic> data) {
    final d = data['imageUrls'];
    if (d is List && d.isNotEmpty)
      return d
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    final u = data['imageUrl']?.toString().trim() ?? '';
    if (u.isNotEmpty) return [u];
    if (widget.imageUrls.isNotEmpty)
      return widget.imageUrls
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    if (widget.imageUrl.trim().isNotEmpty) return [widget.imageUrl];
    return [];
  }

  String _parseTitle(Map<String, dynamic> data) {
    final v = data['title']?.toString().trim();
    return (v != null && v.isNotEmpty) ? v : widget.title;
  }

  String _parseDescription(Map<String, dynamic> data) {
    final v = data['description']?.toString().trim();
    return (v != null && v.isNotEmpty) ? v : widget.description;
  }

  String _parseBoutiqueName(Map<String, dynamic> data) {
    final v = data['boutiqueName']?.toString().trim();
    return (v != null && v.isNotEmpty) ? v : widget.boutiqueName;
  }

  void _applyDefaultSelections(List<String> sizes, List<String> colors) {
    var changed = false;
    if (_selectedSize.isEmpty && sizes.isNotEmpty) {
      _selectedSize = sizes.first;
      changed = true;
    } else if (_selectedSize.isNotEmpty &&
        sizes.isNotEmpty &&
        !sizes.contains(_selectedSize)) {
      _selectedSize = sizes.first;
      changed = true;
    }
    if (colors.isNotEmpty) {
      if (_selectedColor.isEmpty || !colors.contains(_selectedColor)) {
        _selectedColor = colors.first;
        changed = true;
      }
    } else if (_selectedColor.isNotEmpty) {
      _selectedColor = '';
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  void _scheduleDefaultSelections(List<String> sizes, List<String> colors) {
    final needsSync =
        (_selectedSize.isEmpty && sizes.isNotEmpty) ||
        (_selectedSize.isNotEmpty &&
            sizes.isNotEmpty &&
            !sizes.contains(_selectedSize)) ||
        (colors.isNotEmpty &&
            (_selectedColor.isEmpty || !colors.contains(_selectedColor))) ||
        (colors.isEmpty && _selectedColor.isNotEmpty);
    if (!needsSync) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyDefaultSelections(sizes, colors);
    });
  }

  // ── Size guide ────────────────────────────────────────────────────────────

  void _openSizeGuide(String url) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 8, 0),
              child: Row(
                children: [
                  Text(
                    AppLocalizations.of(context)!.sizeGuide,
                    style: AppTextStyles.headingSmall,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, thickness: 0.5),
            Expanded(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.deepAccent,
                    ),
                  ),
                  errorWidget: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 48,
                      color: AppColors.softAccent,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Save / cart ───────────────────────────────────────────────────────────

  Future<void> _loadSavedStatus() async {
    try {
      final result = await FirestoreService.isItemSaved(widget.productId);
      if (!mounted) return;
      setState(() {
        _liked = result;
        _isLoadingLike = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingLike = false);
    }
  }

  Future<void> _toggleLike(Map<String, dynamic> data) async {
    final images = _galleryImages(data);
    try {
      if (_liked) {
        await FirestoreService.removeSavedItem(widget.productId);
      } else {
        await FirestoreService.saveItem(
          productId: widget.productId,
          boutiqueId: widget.boutiqueId,
          imageUrl: images.isNotEmpty ? images.first : widget.imageUrl,
          imageUrls: images,
          title: _parseTitle(data),
          boutiqueName: _parseBoutiqueName(data),
          price: _parsePrice(data),
          description: _parseDescription(data),
          sizes: _parseSizes(data),
          stock: _parseStock(data),
        );
      }
      if (!mounted) return;
      setState(() => _liked = !_liked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _liked
                ? AppLocalizations.of(context)!.itemSaved
                : AppLocalizations.of(context)!.itemRemovedFromSavedItems,
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.somethingWentWrong),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _addProductToCart(Map<String, dynamic> data) async {
    final l10n = AppLocalizations.of(context)!;
    final images = _galleryImages(data);
    final stock = _parseStock(data);
    final colors = _parseColors(data);

    if (stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.thisProductIsOutOfStock),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
    if (_selectedSize.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseSelectASize),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
    if (colors.isNotEmpty &&
        (_selectedColor.isEmpty || !colors.contains(_selectedColor))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseSelectAColour),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    try {
      await FirestoreService.addToCart(
        productId: widget.productId,
        boutiqueId: widget.boutiqueId,
        imageUrl: images.isNotEmpty ? images.first : widget.imageUrl,
        title: _parseTitle(data),
        description: _parseDescription(data),
        size: _selectedSize,
        color: colors.isNotEmpty ? _selectedColor : '',
        price: _parsePrice(data),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.itemAddedToCart),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final detail = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.primaryText,
          content: Text(
            (detail == null || detail.isEmpty)
                ? l10n.somethingWentWrong
                : detail,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.background,
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ── Widget builders ───────────────────────────────────────────────────────

  Widget _buildHeartButton(Map<String, dynamic> data) {
    return GestureDetector(
      onTap: _isLoadingLike ? null : () => _toggleLike(data),
      child: SizedBox(
        width: 32,
        height: 32,
        child: Center(
          child: _isLoadingLike
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.deepAccent,
                  ),
                )
              : Icon(
                  _liked ? Icons.favorite : Icons.favorite_border,
                  color: _liked ? AppColors.deepAccent : AppColors.primaryText,
                  size: 22,
                ),
        ),
      ),
    );
  }

  Widget _buildImageGallery(Map<String, dynamic> data) {
    final images = _galleryImages(data);
    final soldOut = _parseStock(data) <= 0 || _isOutOfStock(data);
    return GestureDetector(
      onDoubleTap: _isLoadingLike ? null : () => _toggleLike(data),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 4 / 5,
            child: Opacity(
              opacity: soldOut ? 0.5 : 1.0,
              child: images.isEmpty
                  ? Container(
                      color: AppColors.imagePlaceholder,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.image_not_supported_outlined,
                        size: 40,
                        color: AppColors.secondaryText,
                      ),
                    )
                  : PageView.builder(
                      controller: _pageController,
                      itemCount: images.length,
                      onPageChanged: (index) =>
                          setState(() => _selectedImageIndex = index),
                      itemBuilder: (context, index) => CachedNetworkImage(
                        imageUrl: images[index],
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: AppColors.imagePlaceholder),
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.imagePlaceholder,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.image_not_supported_outlined,
                            size: 40,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          Positioned(top: 16, right: 16, child: _buildHeartButton(data)),
        ],
      ),
    );
  }

  Widget _buildImageDots(List<String> images) {
    if (images.length <= 1) return const SizedBox(height: 24);
    return Column(
      children: [
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            images.length,
            (index) => GestureDetector(
              onTap: () {
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                );
                setState(() => _selectedImageIndex = index);
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _selectedImageIndex == index ? 18 : 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _selectedImageIndex == index
                      ? AppColors.deepAccent
                      : Colors.transparent,
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSizeChip(String size) {
    final isSelected = _selectedSize == size;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedSize = size),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.deepAccent : Colors.transparent,
          border: Border.all(
            color: isSelected ? AppColors.deepAccent : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Text(
          size,
          style: AppTextStyles.labelLarge.copyWith(
            fontSize: 12,
            color: isSelected ? Colors.white : AppColors.primaryText,
          ),
        ),
      ),
    );
  }

  Widget _buildColorChip(String color) {
    final isSelected = _selectedColor == color;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedColor = color),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.deepAccent : Colors.transparent,
          border: Border.all(
            color: isSelected ? AppColors.deepAccent : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Text(
          color,
          style: AppTextStyles.labelLarge.copyWith(
            fontSize: 12,
            color: isSelected ? Colors.white : AppColors.primaryText,
          ),
        ),
      ),
    );
  }

  Widget _buildProductContent(Map<String, dynamic> data) {
    final l10n = AppLocalizations.of(context)!;

    final sizes = _parseSizes(data);
    final colors = _parseColors(data);
    final images = _galleryImages(data);
    final stock = _parseStock(data);
    final price = _parsePrice(data);
    final salePrice = _salePrice(data);
    final soldOut = stock <= 0 || _isOutOfStock(data);
    final title = _parseTitle(data);
    final description = _parseDescription(data);
    final boutiqueName = _parseBoutiqueName(data);
    final hasSizes = sizes.isNotEmpty;

    final isMTO = data['madeToOrder'] == true;
    final timeframe = data['deliveryTimeframe']?.toString().trim() ?? '';
    final guideUrl = data['sizeGuideUrl']?.toString().trim() ?? '';

    _scheduleDefaultSelections(sizes, colors);
    if (_selectedImageIndex >= images.length && images.isNotEmpty)
      _selectedImageIndex = 0;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppHeader(showBackButton: true),

          // ── Gallery ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildImageGallery(data),
          ),
          _buildImageDots(images),

          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title + boutique ─────────────────────────────────────
                Text(title, style: AppTextStyles.headingMedium),
                const SizedBox(height: 4),
                Text(
                  l10n.byBoutique(boutiqueName),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 18),

                // ── Price + stock/MTO row ────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ProductPriceText(
                      price: price,
                      salePrice: salePrice,
                      saleBadgeLabel: l10n.saleBadge,
                      style: AppTextStyles.headingSmall,
                    ),
                    const Spacer(),
                    if (!isMTO)
                      Text(
                        stock > 0
                            ? l10n.inStockWithCount(stock.toString())
                            : l10n.outOfStock,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: stock > 0
                              ? AppColors.secondaryText
                              : AppColors.deepAccent,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Made-to-order banner ─────────────────────────────────
                if (isMTO) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.field,
                      border: Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.access_time_rounded,
                            size: 20,
                            color: AppColors.deepAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.madeToOrder,
                              style: AppTextStyles.labelLarge.copyWith(
                                color: AppColors.deepAccent,
                              ),
                            ),
                            if (timeframe.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                timeframe,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Description ──────────────────────────────────────────
                Text(
                  description,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.secondaryText,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Size + colour selectors (hidden when sold out) ───────
                if (!soldOut) ...[
                  // ── SIZE header + size guide link ──────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(l10n.sizeSection, style: AppTextStyles.labelLarge),
                      if (guideUrl.isNotEmpty) ...[
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _openSizeGuide(guideUrl),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.straighten_outlined,
                                size: 14,
                                color: AppColors.secondaryText,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                l10n.sizeGuide,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.secondaryText,
                                  decoration: TextDecoration.underline,
                                  decorationColor: AppColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (hasSizes)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: sizes.map(_buildSizeChip).toList(),
                    )
                  else
                    Text(l10n.noSizesAvailable, style: AppTextStyles.bodySmall),

                  // ── Colours ──────────────────────────────────────────
                  if (colors.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(l10n.colours, style: AppTextStyles.labelLarge),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: colors.map(_buildColorChip).toList(),
                    ),
                  ],
                ],

                const SizedBox(height: 28),

                // ── Product details accordion ────────────────────────────
                _buildDropdownSection(
                  title: l10n.productDetails,
                  isOpen: _showProductDetails,
                  onTap: () => setState(
                    () => _showProductDetails = !_showProductDetails,
                  ),
                  content: description,
                ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Sticky add-to-cart footer ──────────────────────────────────────────
  Widget _buildStickyAddToCart(Map<String, dynamic> data) {
    final l10n = AppLocalizations.of(context)!;
    final soldOut = _parseStock(data) <= 0 || _isOutOfStock(data);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: soldOut ? null : () => _addProductToCart(data),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepAccent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.softAccent,
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              child: Text(
                soldOut ? l10n.outOfStock : l10n.addToCart,
                style: AppTextStyles.button,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _productStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.deepAccent,
                ),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: ErrorStateWidget.inline(
                title: l10n.somethingWentWrong,
                message: l10n.somethingWentWrong,
                onRetry: () => setState(() {}),
                type: ErrorType.network,
              ),
            ),
          );
        }
        if (snapshot.hasData && !snapshot.data!.exists) {
          return const NotFoundPage();
        }
        final data = _resolveProductData(snapshot.data);
        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(child: _buildProductContent(data)),
          bottomNavigationBar: _buildStickyAddToCart(data),
        );
      },
    );
  }
}
