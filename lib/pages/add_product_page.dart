import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:libsk/l10n/app_localizations.dart';

import '../core/constants/app_categories.dart';
import '../core/utils/validators.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import '../widgets/chip_selector.dart';
import '../widgets/theme.dart';

// ── Pure helpers ──────────────────────────────────────────────────────────────

const _border = OutlineInputBorder(
  borderRadius: BorderRadius.zero,
  borderSide: BorderSide(color: AppColors.border, width: 0.5),
);

InputDecoration _inputDecoration(String hintText) {
  return InputDecoration(
    hintText: hintText,
    filled: true,
    fillColor: AppColors.field,
    hintStyle: AppTextStyles.bodyMedium.copyWith(
      color: AppColors.secondaryText,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: _border,
    enabledBorder: _border,
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: AppColors.deepAccent, width: 1),
    ),
    errorBorder: _border,
    focusedErrorBorder: _border,
  );
}

Widget _buildLabel(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: AppTextStyles.labelLarge),
  );
}

Widget _buildSectionCard({required Widget child}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border.all(color: AppColors.border, width: 0.5),
    ),
    child: child,
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final priceController = TextEditingController();
  final _salePriceController = TextEditingController();
  final colorInputController = TextEditingController();
  final deliveryTimeframeController = TextEditingController();

  bool _isLoading = false;
  bool _madeToOrder = false;
  bool _postToFeed = true;
  bool _isOutOfStock = false;
  bool _discountExpanded = false;

  List<File> selectedImages = [];
  List<String> selectedCategories = [];
  List<Map<String, dynamic>> sizeEntries = [];
  List<String> colorTags = [];

  // ── Size guide ─────────────────────────────────────────────────────────────
  File? _sizeGuideFile;

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    _salePriceController.dispose();
    colorInputController.dispose();
    deliveryTimeframeController.dispose();
    super.dispose();
  }

  // ── Image picking ─────────────────────────────────────────────────────────

  Future<void> _pickMultiImage() async {
    try {
      final images = await _picker.pickMultiImage(imageQuality: 85);
      if (images.isEmpty || !mounted) return;
      setState(() {
        selectedImages.addAll(images.map((x) => File(x.path)));
      });
    } catch (e) {
      debugPrint('ADD PRODUCT IMAGE ERROR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.failedToPickImage),
        ),
      );
    }
  }

  Future<void> _pickSizeGuide() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (image == null || !mounted) return;
      setState(() => _sizeGuideFile = File(image.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.failedToPickImage),
        ),
      );
    }
  }

  void _removeImage(int index) {
    setState(() => selectedImages.removeAt(index));
  }

  Widget _imageThumbnail(int index) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Stack(
        children: [
          Image.file(
            selectedImages[index],
            width: 96,
            height: 120,
            fit: BoxFit.cover,
          ),
          Positioned(
            top: 6,
            right: 6,
            child: GestureDetector(
              onTap: () => _removeImage(index),
              child: Container(
                padding: const EdgeInsets.all(4),
                color: AppColors.deepAccent,
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Category ──────────────────────────────────────────────────────────────

  void _toggleCategory(String category) {
    setState(() {
      selectedCategories.contains(category)
          ? selectedCategories.remove(category)
          : selectedCategories.add(category);
    });
  }

  // ── Colours ───────────────────────────────────────────────────────────────

  void _addColorTag() {
    final color = colorInputController.text.trim();
    if (color.isEmpty || colorTags.contains(color)) {
      colorInputController.clear();
      return;
    }
    setState(() {
      colorTags.add(color);
      colorInputController.clear();
    });
  }

  void _removeColorTag(String color) {
    setState(() => colorTags.remove(color));
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context)!;
    final title = titleController.text.trim();
    final description = descriptionController.text.trim();
    final priceText = priceController.text.trim();

    final preflight =
        Validators.maxLength(title, 100, 'Title') ??
        Validators.maxLength(description, 2000, 'Description') ??
        Validators.price(priceText);
    if (preflight != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(preflight)));
      return;
    }

    // Optional sale price — must be a positive number below the regular price.
    final salePriceText = _salePriceController.text.trim();
    double? salePrice;
    if (salePriceText.isNotEmpty) {
      final parsedSale = double.tryParse(salePriceText);
      final parsedPrice = double.tryParse(priceText);
      if (parsedSale == null ||
          parsedSale <= 0 ||
          (parsedPrice != null && parsedSale >= parsedPrice)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.salePriceMustBeLessThanPrice)),
        );
        return;
      }
      salePrice = parsedSale;
    }

    if (selectedImages.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.atLeastOneImageRequired)));
      return;
    }
    if (selectedCategories.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.atLeastOneCategoryRequired)));
      return;
    }
    if (sizeEntries.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.atLeastOneSizeRequired)));
      return;
    }
    if (_madeToOrder && deliveryTimeframeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.deliveryTimeframeRequired)));
      return;
    }

    setState(() => _isLoading = true);

    List<String> imageUrls = [];
    String? sizeGuideUrl;

    try {
      final price = double.parse(priceText);

      final sizes = sizeEntries
          .map((e) => e['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      final totalStock = sizeEntries.fold<int>(
        0,
        (total, e) => total + ((e['stock'] as int?) ?? 0),
      );

      final boutiqueId = await FirestoreService.getCurrentOwnerBoutiqueId();
      if (boutiqueId == null) {
        throw Exception('No boutique found for current owner');
      }

      imageUrls = await StorageService.uploadImages(
        selectedImages,
        'product_images/$boutiqueId',
      );

      // Upload size guide if one was selected
      if (_sizeGuideFile != null) {
        final guideUrls = await StorageService.uploadImages([
          _sizeGuideFile!,
        ], 'size_guides/$boutiqueId');
        if (guideUrls.isNotEmpty) sizeGuideUrl = guideUrls.first;
      }

      await FirestoreService.addProductForCurrentOwner(
        title: title,
        description: description,
        price: price,
        salePrice: salePrice,
        isOutOfStock: _isOutOfStock,
        imageUrl: imageUrls.first,
        imageUrls: imageUrls,
        stock: totalStock,
        sizes: sizes,
        sizeEntries: sizeEntries,
        category: selectedCategories,
        colors: colorTags,
        madeToOrder: _madeToOrder,
        deliveryTimeframe: _madeToOrder
            ? deliveryTimeframeController.text.trim()
            : null,
        sizeGuideUrl: sizeGuideUrl,
        postToFeed: _postToFeed,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.productAddedSuccessfully)));
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('SAVE PRODUCT ERROR: $e');

      // Clean up orphaned Storage files if Firestore write failed
      for (final url in imageUrls) {
        await StorageService.deleteImageByUrl(url);
      }
      if (sizeGuideUrl != null) {
        await StorageService.deleteImageByUrl(sizeGuideUrl);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.failedToAddProduct),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Section builders ──────────────────────────────────────────────────────

  // Collapsed by default — owners opt in to a sale price via a tappable row
  // that expands the field with a smooth fade/size transition.
  Widget _buildSalePriceSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _discountExpanded = !_discountExpanded;
            if (!_discountExpanded) _salePriceController.clear();
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.sell_outlined,
                  size: 18,
                  color: AppColors.deepAccent,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.discountThisItem,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.deepAccent,
                  ),
                ),
                const Spacer(),
                Icon(
                  _discountExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                  color: AppColors.deepAccent,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          firstCurve: Curves.easeInOut,
          secondCurve: Curves.easeInOut,
          sizeCurve: Curves.easeInOut,
          crossFadeState: _discountExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              TextFormField(
                controller: _salePriceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _inputDecoration(l10n.salePriceHint),
                validator: (v) {
                  if (!_discountExpanded) return null;
                  if (v == null || v.trim().isEmpty) return null;
                  final sale = double.tryParse(v.trim());
                  if (sale == null || sale <= 0) {
                    return l10n.enterValidPrice;
                  }
                  final price = double.tryParse(priceController.text.trim());
                  if (price != null && sale >= price) {
                    return l10n.salePriceMustBeLessThanPrice;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 6),
              Text(
                l10n.saleLessThanOriginalHint,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  _discountExpanded = false;
                  _salePriceController.clear();
                }),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.close,
                      size: 15,
                      color: AppColors.secondaryText,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.removeDiscount,
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(l10n.categories),
        Text(l10n.selectAllThatApply, style: AppTextStyles.bodySmall),
        const SizedBox(height: 12),
        ChipSelector(
          options: AppCategories.all,
          selected: selectedCategories,
          onToggle: _toggleCategory,
        ),
      ],
    );
  }

  Widget _buildSizesSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(l10n.sizesAndStock),
        Text(l10n.addEachSizeWithStockCount, style: AppTextStyles.bodySmall),
        const SizedBox(height: 12),
        SizeChipSelector(
          initialEntries: sizeEntries,
          stockLabel: l10n.stock,
          onChanged: (entries) => sizeEntries = entries,
        ),
      ],
    );
  }

  // ── Size guide section ────────────────────────────────────────────────────

  Widget _buildSizeGuideSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.sizeGuide, style: AppTextStyles.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    l10n.sizeGuideSubtitle,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_sizeGuideFile != null) ...[
          Stack(
            children: [
              ClipRect(
                child: Image.file(
                  _sizeGuideFile!,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => setState(() => _sizeGuideFile = null),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    color: AppColors.deepAccent,
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _pickSizeGuide,
            child: Text(
              l10n.changeImage,
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.deepAccent,
              ),
            ),
          ),
        ] else
          GestureDetector(
            onTap: _pickSizeGuide,
            child: Container(
              width: double.infinity,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.field,
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.straighten_outlined,
                    size: 22,
                    color: AppColors.deepAccent,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.uploadSizeGuide,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildColorsSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(l10n.colours),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: colorInputController,
                decoration: _inputDecoration(l10n.addAColour),
                textCapitalization: TextCapitalization.words,
                onFieldSubmitted: (_) => _addColorTag(),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _addColorTag,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.deepAccent,
                side: const BorderSide(color: AppColors.deepAccent, width: 0.5),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              child: Text(l10n.add),
            ),
          ],
        ),
        if (colorTags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colorTags.map((color) {
              return InputChip(
                label: Text(color, style: AppTextStyles.labelSmall),
                deleteIconColor: AppColors.deepAccent,
                onDeleted: () => _removeColorTag(color),
                backgroundColor: AppColors.selectedSoft,
                side: const BorderSide(color: AppColors.border, width: 0.5),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildMadeToOrderSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.madeToOrder, style: AppTextStyles.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    l10n.madeToOrderSubtitle,
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            Switch(
              value: _madeToOrder,
              onChanged: (value) {
                setState(() {
                  _madeToOrder = value;
                  if (!value) deliveryTimeframeController.clear();
                });
              },
              activeThumbColor: AppColors.deepAccent,
              activeTrackColor: AppColors.softAccent,
            ),
          ],
        ),
        if (_madeToOrder) ...[
          const SizedBox(height: 14),
          _buildLabel(l10n.deliveryTimeframe),
          TextFormField(
            controller: deliveryTimeframeController,
            decoration: _inputDecoration(l10n.deliveryTimeframeHint),
          ),
        ],
      ],
    );
  }

  Widget _buildAvailabilitySection(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.markAsOutOfStock, style: AppTextStyles.labelLarge),
              const SizedBox(height: 4),
              Text(
                l10n.markAsOutOfStockSubtitle,
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
        ),
        Switch(
          value: _isOutOfStock,
          onChanged: (value) => setState(() => _isOutOfStock = value),
          activeThumbColor: AppColors.deepAccent,
          activeTrackColor: AppColors.softAccent,
        ),
      ],
    );
  }

  Widget _buildPostToFeedSection(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.showInFeed, style: AppTextStyles.labelLarge),
              const SizedBox(height: 4),
              Text(
                l10n.showInFeedSubtitle,
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
        ),
        Switch(
          value: _postToFeed,
          onChanged: (value) => setState(() => _postToFeed = value),
          activeThumbColor: AppColors.deepAccent,
          activeTrackColor: AppColors.softAccent,
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.addProduct, style: AppTextStyles.headingMedium),
                      const SizedBox(height: 8),
                      Text(
                        l10n.createNewProductForBoutique,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.secondaryText,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Core details ──────────────────────────────
                      _buildSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel(l10n.productImages),
                            GestureDetector(
                              onTap: _pickMultiImage,
                              child: Container(
                                width: double.infinity,
                                height: 180,
                                decoration: BoxDecoration(
                                  color: AppColors.imagePlaceholder,
                                  border: Border.all(
                                    color: AppColors.border,
                                    width: 0.5,
                                  ),
                                ),
                                child: selectedImages.isNotEmpty
                                    ? ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.all(10),
                                        itemCount: selectedImages.length,
                                        itemBuilder: (_, index) =>
                                            _imageThumbnail(index),
                                      )
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.add_photo_alternate_outlined,
                                            size: 34,
                                            color: AppColors.deepAccent,
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            l10n.tapToUploadImages,
                                            style: AppTextStyles.bodyMedium
                                                .copyWith(
                                                  color:
                                                      AppColors.secondaryText,
                                                ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            _buildLabel(l10n.productTitle),
                            TextFormField(
                              controller: titleController,
                              decoration: _inputDecoration(
                                l10n.enterProductTitle,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return l10n.titleRequired;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            _buildLabel(l10n.description),
                            TextFormField(
                              controller: descriptionController,
                              maxLines: 4,
                              decoration: _inputDecoration(
                                l10n.enterProductDescription,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return l10n.descriptionRequired;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            _buildLabel(l10n.price),
                            TextFormField(
                              controller: priceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: _inputDecoration(l10n.priceExample),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return l10n.priceRequired;
                                }
                                if (double.tryParse(v.trim()) == null) {
                                  return l10n.enterValidPrice;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            _buildSalePriceSection(l10n),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),
                      _buildSectionCard(child: _buildCategorySection(l10n)),

                      const SizedBox(height: 16),
                      _buildSectionCard(child: _buildSizesSection(l10n)),

                      // ── Size guide — lives right below the sizes card ──
                      const SizedBox(height: 16),
                      _buildSectionCard(child: _buildSizeGuideSection(l10n)),

                      const SizedBox(height: 16),
                      _buildSectionCard(child: _buildColorsSection(l10n)),

                      const SizedBox(height: 16),
                      _buildSectionCard(child: _buildMadeToOrderSection(l10n)),

                      const SizedBox(height: 16),
                      _buildSectionCard(child: _buildAvailabilitySection(l10n)),

                      const SizedBox(height: 16),
                      _buildSectionCard(child: _buildPostToFeedSection(l10n)),

                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _saveProduct,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.deepAccent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  l10n.saveProduct,
                                  style: AppTextStyles.button,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
