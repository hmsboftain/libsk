import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController titleController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final TextEditingController stockController = TextEditingController();
  final TextEditingController sizesController = TextEditingController();

  bool isLoading = false;
  File? selectedImage;

  static const backgroundColor = AppColors.background;
  static const cardColor = AppColors.card;
  static const fieldColor = AppColors.field;
  static const borderColor = AppColors.border;
  static const primaryText = AppColors.primaryText;
  static const secondaryText = AppColors.secondaryText;
  static const softAccent = AppColors.softAccent;
  static const deepAccent = AppColors.deepAccent;

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

      setState(() {
        selectedImage = File(image.path);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.failedToPickImage,
          ),
        ),
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

  Future<void> saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    if (selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.pleaseSelectImage,
          ),
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final title = titleController.text.trim();
      final description = descriptionController.text.trim();
      final price = double.parse(priceController.text.trim());
      final stock = int.parse(stockController.text.trim());

      final sizes = sizesController.text
          .split(',')
          .map((size) => size.trim())
          .where((size) => size.isNotEmpty)
          .toList();

      final imageUrl = await uploadImageToStorage(selectedImage!);

      await FirestoreService.addProductForCurrentOwner(
        title: title,
        description: description,
        price: price,
        imageUrl: imageUrl,
        stock: stock,
        sizes: sizes,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.productAddedSuccessfully,
          ),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.failedToAddProduct,
          ),
        ),
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
                      Text(
                        AppLocalizations.of(context)!.addProduct,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: primaryText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context)!.createNewProductForBoutique,
                        style: const TextStyle(
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
                            buildLabel(AppLocalizations.of(context)!.productImage),
                            GestureDetector(
                              onTap: pickImage,
                              child: Container(
                                width: double.infinity,
                                height: 180,
                                decoration: BoxDecoration(
                                  color: fieldColor,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: borderColor),
                                ),
                                child: selectedImage != null
                                    ? ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.file(
                                    selectedImage!,
                                    fit: BoxFit.cover,
                                  ),
                                )
                                    : Column(
                                  mainAxisAlignment:
                                  MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.add_photo_alternate_outlined,
                                      size: 34,
                                      color: deepAccent,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      AppLocalizations.of(context)!
                                          .tapToUploadImage,
                                      style: const TextStyle(
                                        color: secondaryText,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            buildLabel(AppLocalizations.of(context)!.productTitle),
                            TextFormField(
                              controller: titleController,
                              decoration: buildInputDecoration(
                                AppLocalizations.of(context)!.enterProductTitle,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return AppLocalizations.of(context)!
                                      .titleRequired;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            buildLabel(AppLocalizations.of(context)!.description),
                            TextFormField(
                              controller: descriptionController,
                              maxLines: 4,
                              decoration: buildInputDecoration(
                                AppLocalizations.of(context)!
                                    .enterProductDescription,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return AppLocalizations.of(context)!
                                      .descriptionRequired;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            buildLabel(AppLocalizations.of(context)!.price),
                            TextFormField(
                              controller: priceController,
                              keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: buildInputDecoration(
                                AppLocalizations.of(context)!.priceExample,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return AppLocalizations.of(context)!
                                      .priceRequired;
                                }
                                if (double.tryParse(value.trim()) == null) {
                                  return AppLocalizations.of(context)!
                                      .enterValidPrice;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            buildLabel(AppLocalizations.of(context)!.stock),
                            TextFormField(
                              controller: stockController,
                              keyboardType: TextInputType.number,
                              decoration: buildInputDecoration(
                                AppLocalizations.of(context)!.stockExample,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return AppLocalizations.of(context)!
                                      .stockRequired;
                                }
                                if (int.tryParse(value.trim()) == null) {
                                  return AppLocalizations.of(context)!
                                      .enterValidStockNumber;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            buildLabel(AppLocalizations.of(context)!.sizes),
                            TextFormField(
                              controller: sizesController,
                              decoration: buildInputDecoration(
                                AppLocalizations.of(context)!.sizesExample,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return AppLocalizations.of(context)!
                                      .sizesRequired;
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
                          onPressed: isLoading ? null : saveProduct,
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
                              : Text(
                            AppLocalizations.of(context)!.saveProduct,
                            style: const TextStyle(
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