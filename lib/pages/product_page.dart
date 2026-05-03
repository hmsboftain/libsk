import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

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

  int selectedImageIndex = 0;
  String selectedSize = "";

  bool showProductDetails = false;
  bool showMaterialCare = false;
  bool showSizeFit = false;

  bool liked = false;
  bool isLoadingLike = true;

  @override
  void initState() {
    super.initState();

    if (widget.sizes.isNotEmpty) {
      selectedSize = widget.sizes.first;
    }

    loadSavedStatus();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<String> get galleryImages {
    if (widget.imageUrls.isNotEmpty) {
      return widget.imageUrls.where((image) => image.trim().isNotEmpty).toList();
    }

    if (widget.imageUrl.trim().isNotEmpty) {
      return [widget.imageUrl];
    }

    return [];
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

  Future<void> toggleLike() async {
    final mainImageUrl =
    galleryImages.isNotEmpty ? galleryImages.first : widget.imageUrl;

    try {
      if (liked) {
        await FirestoreService.removeSavedItem(widget.productId);
      } else {
        await FirestoreService.saveItem(
          productId: widget.productId,
          boutiqueId: widget.boutiqueId,
          imageUrl: mainImageUrl,
          imageUrls: galleryImages,
          title: widget.title,
          boutiqueName: widget.boutiqueName,
          price: widget.price,
          description: widget.description,
          sizes: widget.sizes,
          stock: widget.stock,
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

  Future<void> addProductToCart() async {
    final mainImageUrl =
    galleryImages.isNotEmpty ? galleryImages.first : widget.imageUrl;

    if (widget.stock <= 0) {
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

    try {
      await FirestoreService.addToCart(
        productId: widget.productId,
        boutiqueId: widget.boutiqueId,
        imageUrl: mainImageUrl,
        title: widget.title,
        description: widget.description,
        size: selectedSize,
        price: widget.price,
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

  Widget buildProductImageGallery() {
    final images = galleryImages;

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: SizedBox(
            height: 500,
            width: double.infinity,
            child: images.isEmpty
                ? Container(
              color: AppColors.field,
              alignment: Alignment.center,
              child: const Icon(
                Icons.image_not_supported_outlined,
                size: 40,
                color: Colors.black54,
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
                return Image.network(
                  images[index],
                  width: double.infinity,
                  height: 500,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: AppColors.field,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.image_not_supported_outlined,
                        size: 40,
                        color: Colors.black54,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: GestureDetector(
            onTap: isLoadingLike ? null : toggleLike,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.card,
              child: isLoadingLike
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
                  : Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                color: liked ? Colors.red : Colors.black,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildImageDots() {
    final images = galleryImages;

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
                  borderRadius: BorderRadius.circular(20),
                  color: selectedImageIndex == index
                      ? Colors.black
                      : Colors.transparent,
                  border: Border.all(color: Colors.black54),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasSizes = widget.sizes.isNotEmpty;

    if (selectedImageIndex >= galleryImages.length && galleryImages.isNotEmpty) {
      selectedImageIndex = 0;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const AppHeader(showBackButton: true),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: buildProductImageGallery(),
              ),
              buildImageDots(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.description,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${AppLocalizations.of(context)!.by} ${widget.boutiqueName}",
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.stock > 0
                          ? "${AppLocalizations.of(context)!.inStock}: ${widget.stock}"
                          : AppLocalizations.of(context)!.outOfStock,
                      style: TextStyle(
                        fontSize: 13,
                        color: widget.stock > 0 ? Colors.black54 : Colors.red,
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
                                "${widget.price.toStringAsFixed(0)} KWD",
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                AppLocalizations.of(context)!.size,
                                style: const TextStyle(fontSize: 15),
                              ),
                              const SizedBox(height: 8),
                              if (hasSizes)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: widget.sizes.map((size) {
                                    return buildSizeCircle(size);
                                  }).toList(),
                                )
                              else
                                Text(
                                  AppLocalizations.of(context)!.noSizesAvailable,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black54,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 145,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: addProductToCart,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: Text(
                              AppLocalizations.of(context)!.addToCart,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                              ),
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
                      content: widget.description,
                    ),
                    buildDropdownSection(
                      title: AppLocalizations.of(context)!.materialCare,
                      isOpen: showMaterialCare,
                      onTap: () {
                        setState(() {
                          showMaterialCare = !showMaterialCare;
                        });
                      },
                      content: AppLocalizations.of(context)!
                          .materialAndCareDetailsCanBeAddedLater,
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
                          ? "${AppLocalizations.of(context)!.availableSizes} ${widget.sizes.join(', ')}"
                          : AppLocalizations.of(context)!
                          .noSizeInformationAvailable,
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildSizeCircle(String size) {
    final bool isSelected = selectedSize == size;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedSize = size;
        });
      },
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? Colors.black : Colors.white,
          border: Border.all(color: Colors.black),
        ),
        child: Text(
          size,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : Colors.black,
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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Icon(
                  isOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
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
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
          ),
        const Divider(
          color: Colors.black12,
          thickness: 1,
        ),
      ],
    );
  }
}