import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
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

Widget _buildImagePreview({
  required Widget image,
  required VoidCallback onRemove,
}) {
  return Stack(
    children: [
      image,
      Positioned(
        top: 6,
        right: 6,
        child: GestureDetector(
          onTap: onRemove,
          child: Container(
            padding: const EdgeInsets.all(4),
            color: AppColors.deepAccent,
            child: const Icon(Icons.close, color: Colors.white, size: 14),
          ),
        ),
      ),
    ],
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

class EditProductPage extends StatefulWidget {
  final String productId;
  final Map<String, dynamic> productData;

  const EditProductPage({
    super.key,
    required this.productId,
    required this.productData,
  });

  @override
  State<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController titleController;
  late final TextEditingController descriptionController;
  late final TextEditingController priceController;
  late final TextEditingController salePriceController;
  final colorInputController = TextEditingController();
  final deliveryTimeframeController = TextEditingController();

  bool _isLoading = false;
  bool _madeToOrder = false;
  bool _postToFeed = false;
  bool _isOutOfStock = false;

  List<String> currentImageUrls = [];
  List<File> selectedNewImages = [];
  final List<String> _imagesToDelete = [];

  List<String> selectedCategories = [];
  List<Map<String, dynamic>> sizeEntries = [];
  List<String> colorTags = [];

  // ── Size guide ─────────────────────────────────────────────────────────────
  // Existing URL loaded from Firestore (null = none set)
  String? _existingSizeGuideUrl;
  // New file picked by owner to replace the existing one
  File? _newSizeGuideFile;
  // Whether the owner explicitly removed the existing guide without replacing it
  bool _sizeGuideRemoved = false;

  @override
  void initState() {
    super.initState();

    final imageUrlsData = widget.productData['imageUrls'];
    final imageUrl = widget.productData['imageUrl']?.toString() ?? '';

    if (imageUrlsData is List && imageUrlsData.isNotEmpty) {
      currentImageUrls = imageUrlsData.map((e) => e.toString()).toList();
    } else if (imageUrl.isNotEmpty) {
      currentImageUrls = [imageUrl];
    }

    titleController = TextEditingController(
      text: widget.productData['title']?.toString() ?? '',
    );
    descriptionController = TextEditingController(
      text: widget.productData['description']?.toString() ?? '',
    );
    priceController = TextEditingController(
      text: widget.productData['price']?.toString() ?? '',
    );
    salePriceController = TextEditingController(
      text: widget.productData['salePrice']?.toString() ?? '',
    );

    _loadCategories();
    _loadSizeEntries();
    _loadColors();

    _isOutOfStock = widget.productData['isOutOfStock'] == true;
    _madeToOrder = widget.productData['madeToOrder'] == true;
    deliveryTimeframeController.text =
        widget.productData['deliveryTimeframe']?.toString() ?? '';
    _postToFeed = widget.productData['postedToFeed'] == true;

    // Load existing size guide URL
    final guideUrl = widget.productData['sizeGuideUrl']?.toString() ?? '';
    if (guideUrl.isNotEmpty) _existingSizeGuideUrl = guideUrl;
  }

  void _loadCategories() {
    final data = widget.productData['category'];
    if (data is List) {
      selectedCategories = data
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (data is String && data.isNotEmpty) {
      selectedCategories = [data];
    }
  }

  void _loadSizeEntries() {
    final data = widget.productData['sizeEntries'];
    if (data is List && data.isNotEmpty) {
      sizeEntries = data
          .map((entry) {
            if (entry is Map) {
              final stockValue = entry['stock'];
              final stock = stockValue is int
                  ? stockValue
                  : int.tryParse(stockValue?.toString() ?? '') ?? 0;
              return {'name': entry['name']?.toString() ?? '', 'stock': stock};
            }
            return {'name': '', 'stock': 0};
          })
          .where((e) => (e['name'] as String).isNotEmpty)
          .toList();
      return;
    }

    // Legacy: flat sizes list with single stock count
    final sizes = widget.productData['sizes'];
    final stockValue = widget.productData['stock'];
    final totalStock = stockValue is int
        ? stockValue
        : int.tryParse(stockValue?.toString() ?? '') ?? 0;

    if (sizes is List && sizes.isNotEmpty) {
      for (var i = 0; i < sizes.length; i++) {
        sizeEntries.add({
          'name': sizes[i].toString(),
          'stock': i == 0 ? totalStock : 0,
        });
      }
    }
  }

  void _loadColors() {
    final data = widget.productData['colors'];
    if (data is List) {
      colorTags = data
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    salePriceController.dispose();
    colorInputController.dispose();
    deliveryTimeframeController.dispose();
    super.dispose();
  }

  // ── Image management ──────────────────────────────────────────────────────

  Future<void> _pickNewImages() async {
    try {
      final images = await _picker.pickMultiImage(imageQuality: 85);
      if (images.isEmpty || !mounted) return;
      setState(() {
        selectedNewImages.addAll(images.map((e) => File(e.path)));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.failedToPickImages),
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
      setState(() {
        _newSizeGuideFile = File(image.path);
        _sizeGuideRemoved = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.failedToPickImage),
        ),
      );
    }
  }

  void _removeCurrentImage(int index) {
    if (currentImageUrls.length + selectedNewImages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.productMustHaveAtLeastOneImage,
          ),
        ),
      );
      return;
    }
    setState(() {
      _imagesToDelete.add(currentImageUrls[index]);
      currentImageUrls.removeAt(index);
    });
  }

  void _makeCurrentImageMain(int index) {
    if (index == 0) return;
    setState(() {
      currentImageUrls.insert(0, currentImageUrls.removeAt(index));
    });
  }

  void _removeNewImage(int index) {
    if (currentImageUrls.length + selectedNewImages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.productMustHaveAtLeastOneImage,
          ),
        ),
      );
      return;
    }
    setState(() => selectedNewImages.removeAt(index));
  }

  // ── Category / sizes / colours ────────────────────────────────────────────

  void _toggleCategory(String category) {
    setState(() {
      selectedCategories.contains(category)
          ? selectedCategories.remove(category)
          : selectedCategories.add(category);
    });
  }

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

  void _removeColorTag(String color) => setState(() => colorTags.remove(color));

  // ── Update ────────────────────────────────────────────────────────────────

  Future<void> _updateProduct() async {
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
    final salePriceText = salePriceController.text.trim();
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

    if (currentImageUrls.isEmpty && selectedNewImages.isEmpty) {
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

    List<String> uploadedNewUrls = [];
    String? uploadedSizeGuideUrl;

    try {
      final boutiqueId = await FirestoreService.getCurrentOwnerBoutiqueId();
      if (boutiqueId == null) throw Exception('No boutique found');

      final price = double.parse(priceText);
      final sizes = sizeEntries
          .map((e) => e['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      final totalStock = sizeEntries.fold<int>(
        0,
        (total, e) => total + ((e['stock'] as int?) ?? 0),
      );

      uploadedNewUrls = await StorageService.uploadImages(
        selectedNewImages,
        'product_images/$boutiqueId',
      );

      // Handle size guide upload / removal
      String? finalSizeGuideUrl = _existingSizeGuideUrl;
      if (_newSizeGuideFile != null) {
        final guideUrls = await StorageService.uploadImages([
          _newSizeGuideFile!,
        ], 'size_guides/$boutiqueId');
        if (guideUrls.isNotEmpty) {
          uploadedSizeGuideUrl = guideUrls.first;
          finalSizeGuideUrl = uploadedSizeGuideUrl;
        }
      } else if (_sizeGuideRemoved) {
        finalSizeGuideUrl = null;
      }

      final allImageUrls = [...currentImageUrls, ...uploadedNewUrls];
      final wasPosted = widget.productData['postedToFeed'] == true;

      final updateData = <String, dynamic>{
        'boutiqueId': boutiqueId,
        'title': title,
        'description': description,
        'price': price,
        'salePrice': salePrice,
        'isOutOfStock': _isOutOfStock,
        'imageUrls': allImageUrls,
        'stock': totalStock,
        'sizes': sizes,
        'sizeEntries': sizeEntries,
        'category': selectedCategories,
        'colors': colorTags,
        'madeToOrder': _madeToOrder,
        'deliveryTimeframe': _madeToOrder
            ? deliveryTimeframeController.text.trim()
            : null,
        'postedToFeed': _postToFeed,
        'updatedAt': FieldValue.serverTimestamp(),
        // Null removes the field; a URL sets/updates it
        'sizeGuideUrl': finalSizeGuideUrl,
      };

      if (_postToFeed && !wasPosted) {
        updateData['feedPostedAt'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance
          .collection('boutiques')
          .doc(boutiqueId)
          .collection('products')
          .doc(widget.productId)
          .update(updateData);

      // Firestore confirmed — safe to delete removed product images
      for (final url in _imagesToDelete) {
        await StorageService.deleteImageByUrl(
          url,
        ).catchError((e) => debugPrint('Image delete error: $e'));
      }

      // If owner replaced the size guide, delete the old one from Storage
      if (_newSizeGuideFile != null && _existingSizeGuideUrl != null) {
        await StorageService.deleteImageByUrl(
          _existingSizeGuideUrl!,
        ).catchError((e) => debugPrint('Size guide delete error: $e'));
      }
      // If owner removed without replacing, delete old one
      if (_sizeGuideRemoved && _existingSizeGuideUrl != null) {
        await StorageService.deleteImageByUrl(
          _existingSizeGuideUrl!,
        ).catchError((e) => debugPrint('Size guide delete error: $e'));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.productUpdatedSuccessfully)));
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('UPDATE PRODUCT ERROR: $e');

      for (final url in uploadedNewUrls) {
        await StorageService.deleteImageByUrl(
          url,
        ).catchError((err) => debugPrint('Cleanup error: $err'));
      }
      if (uploadedSizeGuideUrl != null) {
        await StorageService.deleteImageByUrl(
          uploadedSizeGuideUrl,
        ).catchError((err) => debugPrint('Cleanup error: $err'));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.failedToUpdateProduct)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Section builders ──────────────────────────────────────────────────────

  Widget _buildImagePickerSection(AppLocalizations l10n) {
    final totalImages = currentImageUrls.length + selectedNewImages.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _pickNewImages,
          child: Container(
            width: double.infinity,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.imagePlaceholder,
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 32,
                  color: AppColors.deepAccent,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.tapToAddMoreImages,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (totalImages > 0)
          SizedBox(
            height: 150,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...currentImageUrls.asMap().entries.map((entry) {
                  final index = entry.key;
                  final imageUrl = entry.value;
                  final isMain = index == 0;

                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Stack(
                      children: [
                        _buildImagePreview(
                          image: Image.network(
                            imageUrl,
                            width: 96,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                          onRemove: () => _removeCurrentImage(index),
                        ),
                        Positioned(
                          bottom: 6,
                          left: 6,
                          right: 6,
                          child: GestureDetector(
                            onTap: () => _makeCurrentImageMain(index),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              color: isMain
                                  ? AppColors.deepAccent
                                  : AppColors.deepAccent.withValues(alpha: 0.7),
                              child: Text(
                                isMain ? l10n.mainImage : l10n.makeMain,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                ...selectedNewImages.asMap().entries.map((entry) {
                  final index = entry.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _buildImagePreview(
                      image: Image.file(
                        entry.value,
                        width: 96,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                      onRemove: () => _removeNewImage(index),
                    ),
                  );
                }),
              ],
            ),
          ),
      ],
    );
  }

  // ── Size guide section ────────────────────────────────────────────────────

  Widget _buildSizeGuideSection(AppLocalizations l10n) {
    // Determine what to show:
    // 1. New file picked → show local preview
    // 2. Existing URL (not removed) → show network image
    // 3. Nothing → show upload prompt
    final hasNewFile = _newSizeGuideFile != null;
    final hasExisting = _existingSizeGuideUrl != null && !_sizeGuideRemoved;
    final hasAnything = hasNewFile || hasExisting;

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
        if (hasAnything) ...[
          Stack(
            children: [
              ClipRect(
                child: hasNewFile
                    ? Image.file(
                        _newSizeGuideFile!,
                        width: double.infinity,
                        height: 180,
                        fit: BoxFit.cover,
                      )
                    : Image.network(
                        _existingSizeGuideUrl!,
                        width: double.infinity,
                        height: 180,
                        fit: BoxFit.cover,
                      ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _newSizeGuideFile = null;
                    _sizeGuideRemoved = true;
                  }),
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
                      Text(
                        l10n.editProduct,
                        style: AppTextStyles.headingMedium.copyWith(
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.editProductDescription,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.secondaryText,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),

                      _buildSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel(l10n.productImages),
                            _buildImagePickerSection(l10n),
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
                            _buildLabel(l10n.salePrice),
                            TextFormField(
                              controller: salePriceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: _inputDecoration(l10n.salePriceHint),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
                                final sale = double.tryParse(v.trim());
                                if (sale == null || sale <= 0) {
                                  return l10n.enterValidPrice;
                                }
                                final price = double.tryParse(
                                  priceController.text.trim(),
                                );
                                if (price != null && sale >= price) {
                                  return l10n.salePriceMustBeLessThanPrice;
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSectionCard(child: _buildCategorySection(l10n)),
                      const SizedBox(height: 16),
                      _buildSectionCard(child: _buildSizesSection(l10n)),

                      // ── Size guide — right below sizes ────────────
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
                          onPressed: _isLoading ? null : _updateProduct,
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
                                  l10n.saveChanges,
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
