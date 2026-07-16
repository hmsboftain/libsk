import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/utils/image_sizing.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../core/constants/countries.dart';
import '../services/currency_service.dart';
import '../services/firestore_service.dart';
import '../widgets/added_to_cart_sheet.dart';
import '../widgets/error_state_widget.dart';
import '../widgets/theme.dart';
import 'cart_page.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

// Ink — the brand's near-black used for product-page chrome (back/heart
// buttons, pagination dots). Defined locally; the design system's primaryText
// is pure black, whereas these floating elements use the warmer Ink tone.
const Color _ink = Color(0xFF2C2925);

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
  final _specialRequestController = TextEditingController();

  int _selectedImageIndex = 0;
  String _selectedSize = '';
  String _selectedColor = '';
  bool _showProductDetails = false;
  bool _liked = false;
  bool _isLoadingLike = true;

  // Debounce guard for Add to Cart — blocks a rapid second tap from adding the
  // same item twice while the first add is still in flight.
  bool _isAddingToCart = false;

  // Per-boutique setting: whether the live stock count is shown to customers.
  // Defaults to true; overridden once the boutique settings doc is read.
  bool _showStockCount = true;

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
    _loadBoutiqueSettings();
  }

  Future<void> _loadBoutiqueSettings() async {
    try {
      final doc = await _firestore
          .collection('boutiques')
          .doc(widget.boutiqueId)
          .get();
      final v = doc.data()?['showStockCount'];
      if (mounted && v is bool && v != _showStockCount) {
        setState(() => _showStockCount = v);
      }
    } catch (_) {
      // Leave the default (visible) on error.
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _specialRequestController.dispose();
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
    if (v is List) {
      return v
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
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
    if (sizes is List) {
      return sizes
          .map((s) => s.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
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

  List<String> _galleryImages(Map<String, dynamic> data) {
    final d = data['imageUrls'];
    if (d is List && d.isNotEmpty) {
      return d
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final u = data['imageUrl']?.toString().trim() ?? '';
    if (u.isNotEmpty) return [u];
    if (widget.imageUrls.isNotEmpty) {
      return widget.imageUrls
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
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

  String _parseCategory(Map<String, dynamic> data) {
    final v = data['category'];
    if (v is List && v.isNotEmpty) {
      return v.first.toString().trim();
    }
    if (v is String) return v.trim();
    return '';
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
                  memCacheWidth: fullBleedCacheWidth(context),
                  maxWidthDiskCache: maxImageDiskCacheWidth,
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
    // Re-entrancy guard: a second tap that lands before the disabled button has
    // rebuilt is dropped here, so the item can't be added twice.
    if (_isAddingToCart) return;

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

    setState(() => _isAddingToCart = true);
    var added = false;
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
        specialRequest: _specialRequestController.text,
      );
      added = true;
    } catch (e) {
      if (mounted) {
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
    } finally {
      if (mounted) setState(() => _isAddingToCart = false);
    }

    if (!added || !mounted) return;
    // Note is consumed — clear it so it can't silently carry to a later add.
    _specialRequestController.clear();

    final goToCart = await AddedToCartSheet.show(context);
    if (goToCart == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const CartPage()),
      );
    }
  }

  // ── Widget builders ───────────────────────────────────────────────────────

  // Circular chrome button floating over the image (back / favourite).
  Widget _buildCircleButton({
    required Widget child,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Ink at ~45% opacity.
          color: _ink.withValues(alpha: 0.45),
        ),
        child: Center(child: child),
      ),
    );
  }

  Widget _buildHeartButton(Map<String, dynamic> data) {
    return _buildCircleButton(
      onTap: _isLoadingLike ? null : () => _toggleLike(data),
      child: _isLoadingLike
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.white,
              ),
            )
          : Icon(
              _liked ? Icons.favorite : Icons.favorite_border,
              color: Colors.white,
              size: 18,
            ),
    );
  }

  // Full-bleed carousel taking ~58% of screen height, square top corners and
  // rounded bottom corners, with floating back / favourite buttons and
  // bottom-left pagination dots overlaid.
  Widget _buildImageGallery(Map<String, dynamic> data) {
    final images = _galleryImages(data);
    final topInset = MediaQuery.of(context).padding.top;
    final height = MediaQuery.of(context).size.height * 0.58;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: GestureDetector(
        onDoubleTap: _isLoadingLike ? null : () => _toggleLike(data),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              child: SizedBox(
                height: height,
                width: double.infinity,
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
                          memCacheWidth: fullBleedCacheWidth(context),
                          maxWidthDiskCache: maxImageDiskCacheWidth,
                          width: double.infinity,
                          height: height,
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
            Positioned(
              top: topInset + 14,
              left: 14,
              child: _buildCircleButton(
                onTap: () => Navigator.of(context).maybePop(),
                child: const Icon(
                  Icons.chevron_left,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            Positioned(
              top: topInset + 14,
              right: 14,
              child: _buildHeartButton(data),
            ),
            if (images.length > 1)
              Positioned(left: 14, bottom: 14, child: _buildImageDots(images)),
          ],
        ),
      ),
    );
  }

  Widget _buildImageDots(List<String> images) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(images.length, (index) {
        final isActive = _selectedImageIndex == index;
        return GestureDetector(
          onTap: () {
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
            );
            setState(() => _selectedImageIndex = index);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 5),
            width: isActive ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? _ink : _ink.withValues(alpha: 0.40),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
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
    final title = _parseTitle(data);
    final description = _parseDescription(data);
    final category = _parseCategory(data);
    final hasSizes = sizes.isNotEmpty;

    final isMTO = data['madeToOrder'] == true;
    final timeframe = data['deliveryTimeframe']?.toString().trim() ?? '';
    final guideUrl = data['sizeGuideUrl']?.toString().trim() ?? '';

    _scheduleDefaultSelections(sizes, colors);
    if (_selectedImageIndex >= images.length && images.isNotEmpty) {
      _selectedImageIndex = 0;
    }

    return SingleChildScrollView(
      // Dragging/scrolling dismisses the keyboard, so the customer can scroll
      // away from the Special Request field without it staying stuck open.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Full-bleed gallery ───────────────────────────────────────
          _buildImageGallery(data),
          const SizedBox(height: 18),

          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Price + stock/MTO row ────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      _fmt(price),
                      style: const TextStyle(
                        fontFamily: 'CormorantGaramond',
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                      ),
                    ),
                    const Spacer(),
                    if (!isMTO && _showStockCount)
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
                const SizedBox(height: 6),

                // ── Product name ─────────────────────────────────────────
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'CormorantGaramond',
                    fontSize: 18,
                    fontStyle: FontStyle.italic,
                    color: _ink,
                  ),
                ),

                // ── Category ─────────────────────────────────────────────
                if (category.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    category.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      // 0.06em at 11px ≈ 0.66
                      letterSpacing: 0.66,
                      color: AppColors.deepAccent,
                    ),
                  ),
                ],
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

                // ── SIZE header + size guide link ────────────────────────
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

                // ── Colours ──────────────────────────────────────────────
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

                // ── Special request (optional, per item) ──────────────────
                const SizedBox(height: 20),
                Text(l10n.specialRequest, style: AppTextStyles.labelLarge),
                const SizedBox(height: 12),
                TextField(
                  controller: _specialRequestController,
                  minLines: 2,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: AppTextStyles.bodyMedium,
                  decoration: InputDecoration(
                    hintText: l10n.specialRequestHint,
                    hintStyle: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.secondaryText,
                    ),
                    filled: true,
                    fillColor: AppColors.field,
                    contentPadding: const EdgeInsets.all(14),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: AppColors.border, width: 0.5),
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: AppColors.border, width: 0.5),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: AppColors.deepAccent, width: 1),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Add to cart ──────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isAddingToCart
                        ? null
                        : () => _addProductToCart(data),
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
                    child: _isAddingToCart
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(l10n.addToCart, style: AppTextStyles.button),
                  ),
                ),
                const SizedBox(height: 24),

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      // top: false so the carousel runs flush to the screen edge; the floating
      // back / favourite buttons inset themselves below the status bar.
      // Tap anywhere off a field (e.g. the Special Request box) to drop the
      // keyboard; child gestures still win, so chips/gallery keep working.
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
        top: false,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _productStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.deepAccent,
                ),
              );
            }
            if (snapshot.hasError) {
              return ErrorStateWidget.inline(
                title: l10n.somethingWentWrong,
                message: l10n.somethingWentWrong,
                onRetry: () => setState(() {}),
                type: ErrorType.network,
              );
            }
            if (snapshot.hasData && !snapshot.data!.exists) {
              return const NotFoundPage();
            }
            return _buildProductContent(_resolveProductData(snapshot.data));
          },
        ),
        ),
      ),
    );
  }
}
