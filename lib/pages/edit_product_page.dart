import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

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

  late final TextEditingController titleController;
  late final TextEditingController descriptionController;
  late final TextEditingController priceController;
  final TextEditingController colorInputController = TextEditingController();
  final TextEditingController deliveryTimeframeController =
      TextEditingController();
  final TextEditingController sizeNameController = TextEditingController();
  final TextEditingController sizeStockController = TextEditingController();

  static const List<String> availableCategories = [
    'Abaya',
    'Blazers',
    'Blouses & Shirts',
    'Casual Wear',
    'Coats',
    'Dresses',
    "Dra'a",
    'Gowns',
    'Jackets',
    'Jumpsuits',
    'Office Attire',
    'Pants',
    'Shoes',
    'Skirts',
    'Tops',
  ];

  bool isLoading = false;
  bool madeToOrder = false;

  List<String> currentImageUrls = [];
  List<File> selectedNewImages = [];
  List<String> imagesToDelete = [];

  List<String> selectedCategories = [];
  List<Map<String, dynamic>> sizeEntries = [];
  List<String> colorTags = [];

  @override
  void initState() {
    super.initState();

    final imageUrl = widget.productData['imageUrl']?.toString() ?? '';
    final imageUrlsData = widget.productData['imageUrls'];

    if (imageUrlsData is List && imageUrlsData.isNotEmpty) {
      currentImageUrls =
          imageUrlsData.map((image) => image.toString()).toList();
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

    madeToOrder = widget.productData['madeToOrder'] == true;
    deliveryTimeframeController.text =
        widget.productData['deliveryTimeframe']?.toString() ?? '';
  }

  void _loadCategories() {
    final categoryData = widget.productData['category'];

    if (categoryData is List) {
      selectedCategories = categoryData
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList();
    } else if (categoryData is String && categoryData.isNotEmpty) {
      selectedCategories = [categoryData];
    }
  }

  void _loadSizeEntries() {
    final sizeEntriesData = widget.productData['sizeEntries'];

    if (sizeEntriesData is List && sizeEntriesData.isNotEmpty) {
      sizeEntries = sizeEntriesData.map((entry) {
        if (entry is Map) {
          final stockValue = entry['stock'];
          final stock = stockValue is int
              ? stockValue
              : int.tryParse(stockValue?.toString() ?? '') ?? 0;

          return {
            'name': entry['name']?.toString() ?? '',
            'stock': stock,
          };
        }
        return {'name': '', 'stock': 0};
      }).where((entry) => (entry['name'] as String).isNotEmpty).toList();
      return;
    }

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
    final colorsData = widget.productData['colors'];

    if (colorsData is List) {
      colorTags = colorsData
          .map((color) => color.toString())
          .where((color) => color.isNotEmpty)
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

  Future<void> pickNewImages() async {
    try {
      final picker = ImagePicker();
      final images = await picker.pickMultiImage(imageQuality: 85);

      if (images.isEmpty) return;

      setState(() {
        selectedNewImages.addAll(images.map((image) => File(image.path)));
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to pick images')),
      );
    }
  }

  Future<String> uploadImageToStorage(File imageFile) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw Exception('User not logged in');
    }

    final fileName = DateTime.now().millisecondsSinceEpoch.toString();
    final ref = FirebaseStorage.instance
        .ref()
        .child('product_images')
        .child(uid)
        .child('$fileName.jpg');

    await ref.putFile(imageFile);
    return ref.getDownloadURL();
  }

  Future<List<String>> uploadImagesToStorage(List<File> images) async {
    final List<String> urls = [];

    for (final image in images) {
      final url = await uploadImageToStorage(image);
      urls.add(url);
    }

    return urls;
  }

  Future<void> deleteImageFromStorage(String imageUrl) async {
    try {
      await FirebaseStorage.instance.refFromURL(imageUrl).delete();
    } catch (e) {
      debugPrint('Failed to delete old product image: $e');
    }
  }

  void toggleCategory(String category) {
    setState(() {
      if (selectedCategories.contains(category)) {
        selectedCategories.remove(category);
      } else {
        selectedCategories.add(category);
      }
    });
  }

  void addSizeEntry() {
    final name = sizeNameController.text.trim();
    final stock = int.tryParse(sizeStockController.text.trim());

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a size name')),
      );
      return;
    }

    if (stock == null || stock < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid stock number')),
      );
      return;
    }

    setState(() {
      sizeEntries.add({'name': name, 'stock': stock});
      sizeNameController.clear();
      sizeStockController.clear();
    });
  }

  void removeSizeEntry(int index) {
    setState(() {
      sizeEntries.removeAt(index);
    });
  }

  void addColorTag() {
    final color = colorInputController.text.trim();
    if (color.isEmpty) return;

    if (colorTags.contains(color)) {
      colorInputController.clear();
      return;
    }

    setState(() {
      colorTags.add(color);
      colorInputController.clear();
    });
  }

  void removeColorTag(String color) {
    setState(() {
      colorTags.remove(color);
    });
  }

  Future<void> updateProduct() async {
    if (!_formKey.currentState!.validate()) return;

    if (currentImageUrls.isEmpty && selectedNewImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one product image')),
      );
      return;
    }

    if (selectedCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one category')),
      );
      return;
    }

    if (sizeEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one size with stock')),
      );
      return;
    }

    if (madeToOrder && deliveryTimeframeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a delivery timeframe')),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final boutiqueId = await FirestoreService.getCurrentOwnerBoutiqueId();

      if (boutiqueId == null) {
        throw Exception('No boutique found for current owner');
      }

      final title = titleController.text.trim();
      final description = descriptionController.text.trim();
      final price = double.parse(priceController.text.trim());

      final sizes = sizeEntries
          .map((entry) => entry['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();

      final totalStock = sizeEntries.fold<int>(
        0,
        (total, entry) => total + ((entry['stock'] as int?) ?? 0),
      );

      final uploadedNewUrls = await uploadImagesToStorage(selectedNewImages);
      final allImageUrls = [...currentImageUrls, ...uploadedNewUrls];
      final mainImageUrl = allImageUrls.first;

      await FirebaseFirestore.instance
          .collection('boutiques')
          .doc(boutiqueId)
          .collection('products')
          .doc(widget.productId)
          .update({
        'title': title,
        'description': description,
        'price': price,
        'imageUrl': mainImageUrl,
        'imageUrls': allImageUrls,
        'stock': totalStock,
        'sizes': sizes,
        'sizeEntries': sizeEntries,
        'category': selectedCategories,
        'colors': colorTags,
        'madeToOrder': madeToOrder,
        'deliveryTimeframe':
            madeToOrder ? deliveryTimeframeController.text.trim() : null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      for (final imageUrl in imagesToDelete) {
        await deleteImageFromStorage(imageUrl);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product updated successfully')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('UPDATE PRODUCT ERROR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void removeCurrentImage(int index) {
    if (currentImageUrls.length + selectedNewImages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product must have at least one image')),
      );
      return;
    }

    final removedImage = currentImageUrls[index];

    setState(() {
      currentImageUrls.removeAt(index);
      imagesToDelete.add(removedImage);
    });
  }

  void makeCurrentImageMain(int index) {
    if (index == 0) return;

    setState(() {
      final selectedImage = currentImageUrls.removeAt(index);
      currentImageUrls.insert(0, selectedImage);
    });
  }

  void removeNewImage(int index) {
    if (currentImageUrls.length + selectedNewImages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product must have at least one image')),
      );
      return;
    }

    setState(() {
      selectedNewImages.removeAt(index);
    });
  }

  InputDecoration buildInputDecoration(String hintText) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: AppColors.border, width: 0.5),
    );

    return InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: AppColors.field,
      hintStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.secondaryText,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: AppColors.deepAccent, width: 1),
      ),
      errorBorder: border,
      focusedErrorBorder: border,
    );
  }

  Widget buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: AppTextStyles.labelLarge),
    );
  }

  Widget buildSectionCard({required Widget child}) {
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

  Widget buildImagePreview({
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

  Widget buildImagePicker() {
    final totalImages = currentImageUrls.length + selectedNewImages.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: pickNewImages,
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
                  'Tap to add more images',
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
                        buildImagePreview(
                          image: Image.network(
                            imageUrl,
                            width: 96,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                          onRemove: () => removeCurrentImage(index),
                        ),
                        Positioned(
                          bottom: 6,
                          left: 6,
                          right: 6,
                          child: GestureDetector(
                            onTap: () => makeCurrentImageMain(index),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              color: isMain
                                  ? AppColors.deepAccent
                                  : AppColors.deepAccent.withValues(alpha: 0.7),
                              child: Text(
                                isMain ? 'Main' : 'Make main',
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
                  final imageFile = entry.value;

                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: buildImagePreview(
                      image: Image.file(
                        imageFile,
                        width: 96,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                      onRemove: () => removeNewImage(index),
                    ),
                  );
                }),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCategorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildLabel('Categories'),
        Text(
          'Select all that apply',
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: 10),
        if (selectedCategories.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selectedCategories.map((category) {
              return InputChip(
                label: Text(category, style: AppTextStyles.labelSmall),
                deleteIconColor: AppColors.deepAccent,
                onDeleted: () => toggleCategory(category),
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
            itemCount: availableCategories.length,
            separatorBuilder: (_, __) => const Divider(
              height: 1,
              thickness: 0.5,
              color: AppColors.border,
            ),
            itemBuilder: (context, index) {
              final category = availableCategories[index];
              final isSelected = selectedCategories.contains(category);

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => toggleCategory(category),
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

  Widget _buildSizesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildLabel('Sizes & stock'),
        Text(
          'Add each size with its own stock count',
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: sizeNameController,
                decoration: buildInputDecoration('Size (e.g. S, M, 38)'),
                textCapitalization: TextCapitalization.characters,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: sizeStockController,
                keyboardType: TextInputType.number,
                decoration: buildInputDecoration('Stock'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: addSizeEntry,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.deepAccent,
              side: const BorderSide(color: AppColors.deepAccent, width: 0.5),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text('Add size', style: AppTextStyles.labelLarge),
          ),
        ),
        if (sizeEntries.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...sizeEntries.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final name = item['name']?.toString() ?? '';
            final stock = item['stock']?.toString() ?? '0';

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
                      '$name — $stock in stock',
                      style: AppTextStyles.bodyMedium,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => removeSizeEntry(index),
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

  Widget _buildColorsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildLabel('Colours'),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: colorInputController,
                decoration: buildInputDecoration('Add a colour'),
                textCapitalization: TextCapitalization.words,
                onFieldSubmitted: (_) => addColorTag(),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: addColorTag,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.deepAccent,
                side: const BorderSide(color: AppColors.deepAccent, width: 0.5),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              child: const Text('Add'),
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
                onDeleted: () => removeColorTag(color),
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

  Widget _buildMadeToOrderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Made to order', style: AppTextStyles.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Enable if this item is produced after purchase',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            Switch(
              value: madeToOrder,
              onChanged: (value) {
                setState(() {
                  madeToOrder = value;
                  if (!value) {
                    deliveryTimeframeController.clear();
                  }
                });
              },
              activeThumbColor: AppColors.deepAccent,
              activeTrackColor: AppColors.softAccent,
            ),
          ],
        ),
        if (madeToOrder) ...[
          const SizedBox(height: 14),
          buildLabel('Delivery timeframe'),
          TextFormField(
            controller: deliveryTimeframeController,
            decoration: buildInputDecoration('e.g. 7–10 business days'),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
                        'EDIT PRODUCT',
                        style: AppTextStyles.headingMedium.copyWith(
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Update your product details and images.',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.secondaryText,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      buildSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            buildLabel('Product images'),
                            buildImagePicker(),
                            const SizedBox(height: 18),
                            buildLabel('Product title'),
                            TextFormField(
                              controller: titleController,
                              decoration: buildInputDecoration(
                                'Enter product title',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Title is required';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            buildLabel('Description'),
                            TextFormField(
                              controller: descriptionController,
                              maxLines: 4,
                              decoration: buildInputDecoration(
                                'Enter product description',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Description is required';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            buildLabel('Price'),
                            TextFormField(
                              controller: priceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: buildInputDecoration('Example: 35'),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Price is required';
                                }
                                if (double.tryParse(value.trim()) == null) {
                                  return 'Enter a valid price';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      buildSectionCard(child: _buildCategorySection()),
                      const SizedBox(height: 16),
                      buildSectionCard(child: _buildSizesSection()),
                      const SizedBox(height: 16),
                      buildSectionCard(child: _buildColorsSection()),
                      const SizedBox(height: 16),
                      buildSectionCard(child: _buildMadeToOrderSection()),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : updateProduct,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.deepAccent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Save changes',
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
