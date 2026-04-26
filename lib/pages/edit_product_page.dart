import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
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
  Future<File?> cropProductImage(String imagePath) async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: imagePath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Product Image',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
          initAspectRatio: CropAspectRatioPreset.square,
        ),
        IOSUiSettings(
          title: 'Crop Product Image',
          aspectRatioLockEnabled: true,
        ),
      ],
    );

    if (croppedFile == null) return null;
    return File(croppedFile.path);
  }

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController titleController;
  late final TextEditingController descriptionController;
  late final TextEditingController priceController;
  late final TextEditingController stockController;
  late final TextEditingController sizesController;

  bool isLoading = false;
  File? selectedImage;
  String? currentImageUrl;

  static const backgroundColor = AppColors.background;
  static const cardColor = AppColors.card;
  static const fieldColor = AppColors.field;
  static const borderColor = AppColors.border;
  static const primaryText = AppColors.primaryText;
  static const secondaryText = AppColors.secondaryText;
  static const softAccent = AppColors.softAccent;
  static const deepAccent = AppColors.deepAccent;

  @override
  void initState() {
    super.initState();

    final sizes = widget.productData['sizes'];
    currentImageUrl = widget.productData['imageUrl']?.toString();

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

  Future<void> pickImage() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image == null) return;

      final croppedImage = await cropProductImage(image.path);
      if (croppedImage == null) return;

      setState(() {
        selectedImage = croppedImage;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to pick image')),
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

  Future<void> updateProduct() async {
    if (!_formKey.currentState!.validate()) return;

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

      String imageUrl = currentImageUrl ?? '';

      if (selectedImage != null) {
        imageUrl = await uploadImageToStorage(selectedImage!);
      }

      await FirebaseFirestore.instance
          .collection('boutiques')
          .doc(boutiqueId)
          .collection('products')
          .doc(widget.productId)
          .update({
        'title': title,
        'description': description,
        'price': price,
        'imageUrl': imageUrl,
        'stock': stock,
        'sizes': sizes,
      });

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

  InputDecoration buildInputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: secondaryText,
        fontSize: 14,
      ),
      filled: true,
      fillColor: fieldColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: deepAccent,
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
          color: primaryText,
        ),
      ),
    );
  }

  Widget buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }

  Widget buildImagePicker() {
    Widget child;

    if (selectedImage != null) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          selectedImage!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 180,
        ),
      );
    } else if (currentImageUrl != null && currentImageUrl!.isNotEmpty) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          currentImageUrl!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 180,
          errorBuilder: (context, error, stackTrace) {
            return const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 34,
                  color: deepAccent,
                ),
                SizedBox(height: 10),
                Text(
                  'Tap to change image',
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 14,
                  ),
                ),
              ],
            );
          },
        ),
      );
    } else {
      child = const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 34,
            color: deepAccent,
          ),
          SizedBox(height: 10),
          Text(
            'Tap to upload image',
            style: TextStyle(
              color: secondaryText,
              fontSize: 14,
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: pickImage,
      child: Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          color: fieldColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
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
                          color: primaryText,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Update your product details.',
                        style: TextStyle(
                          fontSize: 14,
                          color: secondaryText,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      buildSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            buildLabel('Product Image'),
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
                            disabledBackgroundColor: softAccent,
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