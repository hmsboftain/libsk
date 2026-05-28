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
  final colorInputController = TextEditingController();
  final deliveryTimeframeController = TextEditingController();
  final sizeNameController = TextEditingController();
  final sizeStockController = TextEditingController();

  bool _isLoading = false;
  bool _madeToOrder = false;

  List<String> currentImageUrls = [];
  List<File> selectedNewImages = [];
  List<String> _imagesToDelete = [];

  List<String> selectedCategories = [];
  List<Map<String, dynamic>> sizeEntries = [];
  List<String> colorTags = [];

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

    _loadCategories();
    _loadSizeEntries();
    _loadColors();

    _madeToOrder = widget.productData['madeToOrder'] == true;
    deliveryTimeframeController.text =
        widget.productData['deliveryTimeframe']?.toString() ?? '';
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
    colorInputController.dispose();
    deliveryTimeframeController.dispose();
    sizeNameController.dispose();
    sizeStockController.dispose();
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

  void _addSizeEntry() {
    final l10n = AppLocalizations.of(context)!;
    final name = sizeNameController.text.trim();
    final stock = int.tryParse(sizeStockController.text.trim());

    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.enterSizeName)));
      return;
    }
    if (stock == null || stock < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.enterValidStock)));
      return;
    }
    setState(() {
      sizeEntries.add({'name': name, 'stock': stock});
      sizeNameController.clear();
      sizeStockController.clear();
    });
  }

  void _removeSizeEntry(int index) =>
      setState(() => sizeEntries.removeAt(index));

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

      // Upload new images — track for cleanup if Firestore write fails
      uploadedNewUrls = await StorageService.uploadImages(
        selectedNewImages,
        'product_images',
      );

      final allImageUrls = [...currentImageUrls, ...uploadedNewUrls];

      // Single Firestore write — imageUrls[0] is the primary, no separate imageUrl field
      await FirebaseFirestore.instance
          .collection('boutiques')
          .doc(boutiqueId)
          .collection('products')
          .doc(widget.productId)
          .update({
            'title': title,
            'description': description,
            'price': price,
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
            'updatedAt': FieldValue.serverTimestamp(),
          });

      // Firestore write confirmed — safe to delete removed images
      for (final url in _imagesToDelete) {
        await StorageService.deleteImageByUrl(
          url,
        ).catchError((e) => debugPrint('Image delete error: $e'));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.productUpdatedSuccessfully)));
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('UPDATE PRODUCT ERROR: $e');

      // Firestore write failed — clean up newly uploaded images
      for (final url in uploadedNewUrls) {
        await StorageService.deleteImageByUrl(
          url,
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

  Widget _buildCategorySection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(l10n.categories),
        Text(l10n.selectAllThatApply, style: AppTextStyles.bodySmall),
        const SizedBox(height: 10),
        if (selectedCategories.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selectedCategories.map((category) {
              return InputChip(
                label: Text(category, style: AppTextStyles.labelSmall),
                deleteIconColor: AppColors.deepAccent,
                onDeleted: () => _toggleCategory(category),
                backgroundColor: AppColors.selectedSoft,
                side: const BorderSide(color: AppColors.border, width: 0.5),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: AppColors.field,
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: AppCategories.all.length,
            separatorBuilder: (_, __) => const Divider(
              height: 1,
              thickness: 0.5,
              color: AppColors.border,
            ),
            itemBuilder: (context, index) {
              final category = AppCategories.all[index];
              final isSelected = selectedCategories.contains(category);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _toggleCategory(category),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            category,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: isSelected
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        Icon(
                          isSelected
                              ? Icons.check_box_outlined
                              : Icons.check_box_outline_blank,
                          size: 20,
                          color: isSelected
                              ? AppColors.deepAccent
                              : AppColors.softAccent,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: sizeNameController,
                decoration: _inputDecoration(l10n.sizeHint),
                textCapitalization: TextCapitalization.characters,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: sizeStockController,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration(l10n.stock),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: _addSizeEntry,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.deepAccent,
              side: const BorderSide(color: AppColors.deepAccent, width: 0.5),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text(l10n.addSize, style: AppTextStyles.labelLarge),
          ),
        ),
        if (sizeEntries.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...sizeEntries.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.field,
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.sizeStockEntry(
                        item['name'].toString(),
                        item['stock'].toString(),
                      ),
                      style: AppTextStyles.bodyMedium,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _removeSizeEntry(index),
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.deepAccent,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
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
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSectionCard(child: _buildCategorySection(l10n)),
                      const SizedBox(height: 16),
                      _buildSectionCard(child: _buildSizesSection(l10n)),
                      const SizedBox(height: 16),
                      _buildSectionCard(child: _buildColorsSection(l10n)),
                      const SizedBox(height: 16),
                      _buildSectionCard(child: _buildMadeToOrderSection(l10n)),
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
