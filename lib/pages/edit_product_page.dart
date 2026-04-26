import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  late final TextEditingController stockController;
  late final TextEditingController sizesController;

  bool isLoading = false;

  List<String> currentImageUrls = [];
  List<File> selectedNewImages = [];
  List<String> imagesToDelete = [];

  @override
  void initState() {
    super.initState();

    final sizes = widget.productData['sizes'];
    final imageUrl = widget.productData['imageUrl']?.toString() ?? '';
    final imageUrlsData = widget.productData['imageUrls'];

    if (imageUrlsData is List && imageUrlsData.isNotEmpty) {
      currentImageUrls = imageUrlsData.map((image) => image.toString()).toList();
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
    stockController = TextEditingController(
      text: widget.productData['stock']?.toString() ?? '',
    );
    sizesController = TextEditingController(
      text: sizes is List ? sizes.join(',') : '',
    );
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    stockController.dispose();
    sizesController.dispose();
    super.dispose();
  }

  Future<void> pickNewImages() async {
    try {
      final picker = ImagePicker();

      final images = await picker.pickMultiImage(
        imageQuality: 85,
      );

      if (images.isEmpty) return;

      setState(() {
        selectedNewImages = images.map((image) => File(image.path)).toList();
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to pick images')),
      );
    }
  }

  Future<String> uploadImageToStorage(File imageFile) async {
    final fileName = DateTime.now().millisecondsSinceEpoch.toString();
    final ref = FirebaseStorage.instance
        .ref()
        .child('product_images')
        .child('$fileName.jpg');

    await ref.putFile(imageFile);
    return await ref.getDownloadURL();
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

  Future<void> updateProduct() async {
    if (!_formKey.currentState!.validate()) return;

    if (currentImageUrls.isEmpty && selectedNewImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one product image')),
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
      final stock = int.parse(stockController.text.trim());

      final sizes = sizesController.text
          .split(',')
          .map((size) => size.trim())
          .where((size) => size.isNotEmpty)
          .toList();

      final uploadedNewUrls = await uploadImagesToStorage(selectedNewImages);

      final allImageUrls = [
        ...currentImageUrls,
        ...uploadedNewUrls,
      ];

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
        'stock': stock,
        'sizes': sizes,
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
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update product')),
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
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: AppColors.secondaryText,
        fontSize: 14,
      ),
      filled: true,
      fillColor: AppColors.field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: AppColors.deepAccent,
          width: 1.2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Widget buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryText,
        ),
      ),
    );
  }

  Widget buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
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
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: image,
        ),
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                color: Colors.white,
                size: 16,
              ),
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
              color: AppColors.field,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 32,
                  color: AppColors.deepAccent,
                ),
                SizedBox(height: 8),
                Text(
                  'Tap to add more images',
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 14,
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
                            width: 110,
                            height: 145,
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
                              decoration: BoxDecoration(
                                color: isMain ? Colors.black : Colors.black54,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isMain ? 'Main' : 'Make main',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
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
                        width: 110,
                        height: 145,
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
                      const Text(
                        'EDIT PRODUCT',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Update your product details and images.',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.secondaryText,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      buildSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            buildLabel('Product Images'),
                            buildImagePicker(),
                            const SizedBox(height: 18),
                            buildLabel('Product Title'),
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
                            const SizedBox(height: 18),
                            buildLabel('Stock'),
                            TextFormField(
                              controller: stockController,
                              keyboardType: TextInputType.number,
                              decoration: buildInputDecoration('Example: 10'),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Stock is required';
                                }
                                if (int.tryParse(value.trim()) == null) {
                                  return 'Enter a valid stock number';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            buildLabel('Sizes'),
                            TextFormField(
                              controller: sizesController,
                              decoration: buildInputDecoration(
                                'Example: S,M,L',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Sizes are required';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : updateProduct,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppColors.softAccent,
                            disabledForegroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
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
                            'Save Changes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
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