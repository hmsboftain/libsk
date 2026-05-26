import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';

import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  final PageController _pageController = PageController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int selectedImageIndex = 0;
  String selectedSize = '';
  String selectedColor = '';

  bool showProductDetails = false;
  bool showMaterialCare = false;
  bool showSizeFit = false;

  bool liked = false;
  bool isLoadingLike = true;

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _productStream {
    return _firestore
        .collection('boutiques')
        .doc(widget.boutiqueId)
        .collection('products')
        .doc(widget.productId)
        .snapshots();
  }

  @override
  void initState() {
    super.initState();
    loadSavedStatus();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _fallbackProductData() {
    return {
      'title': widget.title,
      'description': widget.description,
      'price': widget.price,
      'stock': widget.stock,
      'sizes': widget.sizes,
      'imageUrl': widget.imageUrl,
      'imageUrls': widget.imageUrls,
      'boutiqueName': widget.boutiqueName,
    };
  }

  Map<String, dynamic> _resolveProductData(
    DocumentSnapshot<Map<String, dynamic>>? snapshot,
  ) {
    final fallback = _fallbackProductData();
    final live = snapshot?.data();

    if (live == null || live.isEmpty) {
      return fallback;
    }

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
          .map((entry) {
            if (entry is Map) {
              return entry['name']?.toString().trim() ?? '';
            }
            return entry.toString().trim();
          })
          .where((size) => size.isNotEmpty)
          .toList();
    }

    final sizes = data['sizes'];
    if (sizes is List) {
      return sizes
          .map((size) => size.toString().trim())
          .where((size) => size.isNotEmpty)
          .toList();
    }

    return widget.sizes;
  }

  double _parsePrice(Map<String, dynamic> data) {
    final priceValue = data['price'] ?? widget.price;
    if (priceValue is num) {
      return priceValue.toDouble();
    }
    return double.tryParse(priceValue.toString()) ?? widget.price;
  }

  int _parseStock(Map<String, dynamic> data) {
    final stockValue = data['stock'] ?? widget.stock;
    if (stockValue is int) {
      return stockValue;
    }
    return int.tryParse(stockValue.toString()) ?? widget.stock;
  }

  List<String> _galleryImages(Map<String, dynamic> data) {
    final imageUrlsData = data['imageUrls'];
    if (imageUrlsData is List && imageUrlsData.isNotEmpty) {
      return imageUrlsData
          .map((image) => image.toString().trim())
          .where((image) => image.isNotEmpty)
          .toList();
    }

    final imageUrl = data['imageUrl']?.toString().trim() ?? '';
    if (imageUrl.isNotEmpty) {
      return [imageUrl];
    }

    if (widget.imageUrls.isNotEmpty) {
      return widget.imageUrls
          .map((image) => image.trim())
          .where((image) => image.isNotEmpty)
          .toList();
    }

    if (widget.imageUrl.trim().isNotEmpty) {
      return [widget.imageUrl];
    }

    return [];
  }

  String _parseTitle(Map<String, dynamic> data) {
    final title = data['title']?.toString().trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    return widget.title;
  }

  String _parseDescription(Map<String, dynamic> data) {
    final description = data['description']?.toString().trim();
    if (description != null && description.isNotEmpty) {
      return description;
    }
    return widget.description;
  }

  String _parseBoutiqueName(Map<String, dynamic> data) {
    final boutiqueName = data['boutiqueName']?.toString().trim();
    if (boutiqueName != null && boutiqueName.isNotEmpty) {
      return boutiqueName;
    }
    return widget.boutiqueName;
  }

  void _applyDefaultSelections(List<String> sizes, List<String> colors) {
    var changed = false;

    if (selectedSize.isEmpty && sizes.isNotEmpty) {
      selectedSize = sizes.first;
      changed = true;
    } else if (selectedSize.isNotEmpty &&
        sizes.isNotEmpty &&
        !sizes.contains(selectedSize)) {
      selectedSize = sizes.first;
      changed = true;
    }

    if (colors.isNotEmpty) {
      if (selectedColor.isEmpty || !colors.contains(selectedColor)) {
        selectedColor = colors.first;
        changed = true;
      }
    } else if (selectedColor.isNotEmpty) {
      selectedColor = '';
      changed = true;
    }

    if (changed && mounted) {
      setState(() {});
    }
  }

  void _scheduleDefaultSelections(List<String> sizes, List<String> colors) {
    final needsSync =
        (selectedSize.isEmpty && sizes.isNotEmpty) ||
        (selectedSize.isNotEmpty &&
            sizes.isNotEmpty &&
            !sizes.contains(selectedSize)) ||
        (colors.isNotEmpty &&
            (selectedColor.isEmpty || !colors.contains(selectedColor))) ||
        (colors.isEmpty && selectedColor.isNotEmpty);

    if (!needsSync) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyDefaultSelections(sizes, colors);
    });
  }

  Future<void> loadSavedStatus() async {
    try {
      final result = await FirestoreService.isItemSaved(widget.productId);

      if (!mounted) return;
      setState(() {
        liked = result;
        isLoadingLike = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoadingLike = false;
      });
    }
  }

  Future<void> toggleLike(Map<String, dynamic> data) async {
    final images = _galleryImages(data);
    final mainImageUrl = images.isNotEmpty ? images.first : widget.imageUrl;
    final sizes = _parseSizes(data);
    final title = _parseTitle(data);
    final description = _parseDescription(data);
    final boutiqueName = _parseBoutiqueName(data);
    final price = _parsePrice(data);
    final stock = _parseStock(data);

    try {
      if (liked) {
        await FirestoreService.removeSavedItem(widget.productId);
      } else {
        await FirestoreService.saveItem(
          productId: widget.productId,
          boutiqueId: widget.boutiqueId,
          imageUrl: mainImageUrl,
          imageUrls: images,
          title: title,
          boutiqueName: boutiqueName,
          price: price,
          description: description,
          sizes: sizes,
          stock: stock,
        );
      }

      if (!mounted) return;

      setState(() {
        liked = !liked;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            liked
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

  Future<void> addProductToCart(Map<String, dynamic> data) async {
    final images = _galleryImages(data);
    final mainImageUrl = images.isNotEmpty ? images.first : widget.imageUrl;
    final stock = _parseStock(data);

    if (stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.thisProductIsOutOfStock),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    if (selectedSize.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.pleaseSelectASize),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    final colors = _parseColors(data);
    if (colors.isNotEmpty &&
        (selectedColor.isEmpty || !colors.contains(selectedColor))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a colour'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    try {
      await FirestoreService.addToCart(
        productId: widget.productId,
        boutiqueId: widget.boutiqueId,
        imageUrl: mainImageUrl,
        title: _parseTitle(data),
        description: _parseDescription(data),
        size: selectedSize,
        color: colors.isNotEmpty ? selectedColor : '',
        price: _parsePrice(data),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.itemAddedToCart),
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

  Widget _buildHeartButton(Map<String, dynamic> data) {
    return GestureDetector(
      onTap: isLoadingLike ? null : () => toggleLike(data),
      child: SizedBox(
        width: 32,
        height: 32,
        child: Center(
          child: isLoadingLike
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.deepAccent,
                  ),
                )
              : Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  color: liked ? AppColors.deepAccent : AppColors.primaryText,
                  size: 22,
                ),
        ),
      ),
    );
  }

  Widget buildProductImageGallery(Map<String, dynamic> data) {
    final images = _galleryImages(data);

    return GestureDetector(
      onDoubleTap: isLoadingLike ? null : () => toggleLike(data),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 4 / 5,
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
                    onPageChanged: (index) {
                      setState(() {
                        selectedImageIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      return CachedNetworkImage(
                        imageUrl: images[index],
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Container(color: AppColors.imagePlaceholder),
                        errorWidget: (context, url, error) => Container(
                          color: AppColors.imagePlaceholder,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.image_not_supported_outlined,
                            size: 40,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Positioned(top: 16, right: 16, child: _buildHeartButton(data)),
        ],
      ),
    );
  }

  Widget buildImageDots(List<String> images) {
    if (images.length <= 1) {
      return const SizedBox(height: 24);
    }

    return Column(
      children: [
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(images.length, (index) {
            return GestureDetector(
              onTap: () {
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                );

                setState(() {
                  selectedImageIndex = index;
                });
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: selectedImageIndex == index ? 18 : 10,
                height: 10,
                decoration: BoxDecoration(
                  color: selectedImageIndex == index
                      ? AppColors.deepAccent
                      : Colors.transparent,
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget buildSizeChip(String size) {
    final bool isSelected = selectedSize == size;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          selectedSize = size;
        });
      },
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

  Widget buildColorChip(String color) {
    final bool isSelected = selectedColor == color;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => selectedColor = color),
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

  Widget buildDropdownSection({
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

  Widget _buildProductContent(Map<String, dynamic> data) {
    final sizes = _parseSizes(data);
    final colors = _parseColors(data);
    final images = _galleryImages(data);
    final stock = _parseStock(data);
    final price = _parsePrice(data);
    final title = _parseTitle(data);
    final description = _parseDescription(data);
    final boutiqueName = _parseBoutiqueName(data);
    final bool hasSizes = sizes.isNotEmpty;

    _scheduleDefaultSelections(sizes, colors);

    if (selectedImageIndex >= images.length && images.isNotEmpty) {
      selectedImageIndex = 0;
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          const AppHeader(showBackButton: true),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: buildProductImageGallery(data),
          ),
          buildImageDots(images),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.headingMedium),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "${AppLocalizations.of(context)!.by} $boutiqueName",
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  stock > 0
                      ? "${AppLocalizations.of(context)!.inStock}: $stock"
                      : AppLocalizations.of(context)!.outOfStock,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: stock > 0
                        ? AppColors.primaryText
                        : AppColors.deepAccent,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${price.toStringAsFixed(0)} KWD",
                            style: AppTextStyles.headingSmall,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            AppLocalizations.of(context)!.size,
                            style: AppTextStyles.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          if (hasSizes)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: sizes
                                  .map((size) => buildSizeChip(size))
                                  .toList(),
                            )
                          else
                            Text(
                              AppLocalizations.of(context)!.noSizesAvailable,
                              style: AppTextStyles.bodySmall,
                            ),
                          if (colors.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text('COLOURS', style: AppTextStyles.labelLarge),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: colors
                                  .map((color) => buildColorChip(color))
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 145,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () => addProductToCart(data),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.deepAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.addToCart,
                          style: AppTextStyles.button,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                buildDropdownSection(
                  title: AppLocalizations.of(context)!.productDetails,
                  isOpen: showProductDetails,
                  onTap: () {
                    setState(() {
                      showProductDetails = !showProductDetails;
                    });
                  },
                  content: description,
                ),
                buildDropdownSection(
                  title: AppLocalizations.of(context)!.materialCare,
                  isOpen: showMaterialCare,
                  onTap: () {
                    setState(() {
                      showMaterialCare = !showMaterialCare;
                    });
                  },
                  content: AppLocalizations.of(
                    context,
                  )!.materialAndCareDetailsCanBeAddedLater,
                ),
                buildDropdownSection(
                  title: AppLocalizations.of(context)!.sizeFit,
                  isOpen: showSizeFit,
                  onTap: () {
                    setState(() {
                      showSizeFit = !showSizeFit;
                    });
                  },
                  content: hasSizes
                      ? "${AppLocalizations.of(context)!.availableSizes} ${sizes.join(', ')}"
                      : AppLocalizations.of(
                          context,
                        )!.noSizeInformationAvailable,
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
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
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    AppLocalizations.of(context)!.somethingWentWrong,
                    style: AppTextStyles.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final data = _resolveProductData(snapshot.data);
            return _buildProductContent(data);
          },
        ),
      ),
    );
  }
}
