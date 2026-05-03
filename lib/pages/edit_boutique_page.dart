import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import 'package:image_cropper/image_cropper.dart';
import '../widgets/theme.dart';

class EditBoutiquePage extends StatefulWidget {
  final Map<String, dynamic> boutiqueData;

  const EditBoutiquePage({
    super.key,
    required this.boutiqueData,
  });

  @override
  State<EditBoutiquePage> createState() => _EditBoutiquePageState();
}

class _EditBoutiquePageState extends State<EditBoutiquePage> {
  Future<File?> cropLogoImage(String imagePath) async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: imagePath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      maxWidth: 800,
      maxHeight: 800,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Logo',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
          initAspectRatio: CropAspectRatioPreset.square,
          hideBottomControls: false,
          statusBarLight: false,
          backgroundColor: Colors.black,
        ),
        IOSUiSettings(
          title: 'Crop Logo',
          aspectRatioLockEnabled: true,
        ),
      ],
    );

    if (croppedFile == null) return null;
    return File(croppedFile.path);
  }

  Future<void> deleteOldImage(String? imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) return;

    try {
      await FirebaseStorage.instance.refFromURL(imageUrl).delete();
    } catch (e) {
      debugPrint('Failed to delete old image: $e');
    }
  }

  Future<File?> cropBannerImage(String imagePath) async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: imagePath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90,
      maxWidth: 1600,
      maxHeight: 900,
      aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Banner',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
          initAspectRatio: CropAspectRatioPreset.ratio16x9,
          hideBottomControls: false,
          statusBarLight: false,
          backgroundColor: Colors.black,
        ),
        IOSUiSettings(
          title: 'Crop Banner',
          aspectRatioLockEnabled: true,
        ),
      ],
    );

    if (croppedFile == null) return null;
    return File(croppedFile.path);
  }

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController nameController;
  late final TextEditingController descriptionController;

  bool isLoading = false;

  File? selectedLogoImage;
  File? selectedBannerImage;

  String? currentLogoUrl;
  String? currentBannerUrl;

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(
      text: widget.boutiqueData['name']?.toString() ?? '',
    );

    descriptionController = TextEditingController(
      text: widget.boutiqueData['description']?.toString() ?? '',
    );

    currentLogoUrl = widget.boutiqueData['logoPath']?.toString();
    currentBannerUrl = widget.boutiqueData['bannerPath']?.toString();
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> pickLogoImage() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (image == null) return;

      final croppedImage = await cropLogoImage(image.path);
      if (croppedImage == null) return;

      if (!mounted) return;
      setState(() {
        selectedLogoImage = croppedImage;
      });
    } catch (e) {
      debugPrint('pickLogoImage error: $e');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick logo image: $e')),
      );
    }
  }

  Future<void> pickBannerImage() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1600,
        maxHeight: 1200,
      );

      if (image == null) return;

      final croppedImage = await cropBannerImage(image.path);
      if (croppedImage == null) return;

      if (!mounted) return;
      setState(() {
        selectedBannerImage = croppedImage;
      });
    } catch (e) {
      debugPrint('pickBannerImage error: $e');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick banner image: $e')),
      );
    }
  }

  Future<String> uploadImageToStorage({
    required File imageFile,
    required String folderName,
  }) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

    final ref = FirebaseStorage.instance.ref().child(folderName).child(fileName);

    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
    );

    await ref.putFile(imageFile, metadata);
    return await ref.getDownloadURL();
  }

  Future<void> saveBoutiqueChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
    });

    try {
      String? logoUrl = currentLogoUrl;
      String? bannerUrl = currentBannerUrl;

      final oldLogoUrl = currentLogoUrl;
      final oldBannerUrl = currentBannerUrl;

      if (selectedLogoImage != null) {
        logoUrl = await uploadImageToStorage(
          imageFile: selectedLogoImage!,
          folderName: 'boutique_logos',
        );
      }

      if (selectedBannerImage != null) {
        bannerUrl = await uploadImageToStorage(
          imageFile: selectedBannerImage!,
          folderName: 'boutique_banners',
        );
      }

      await FirestoreService.updateCurrentOwnerBoutique(
        name: nameController.text.trim(),
        description: descriptionController.text.trim(),
        logoPath: logoUrl,
        bannerPath: bannerUrl,
      );

      if (selectedLogoImage != null && oldLogoUrl != logoUrl) {
        await deleteOldImage(oldLogoUrl);
      }

      if (selectedBannerImage != null && oldBannerUrl != bannerUrl) {
        await deleteOldImage(oldBannerUrl);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Boutique updated successfully')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update boutique')),
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

  Widget buildImagePicker({
    required VoidCallback onTap,
    required File? selectedImage,
    required String? currentImageUrl,
    required String emptyText,
    required String errorText,
    required double height,
    required bool isCircle,
  }) {
    Widget imageContent;

    if (selectedImage != null) {
      imageContent = Image.file(
        selectedImage,
        fit: BoxFit.cover,
        width: double.infinity,
        height: height,
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Text(
              errorText,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 14,
              ),
            ),
          );
        },
      );
    } else if (currentImageUrl != null && currentImageUrl.isNotEmpty) {
      imageContent = Image.network(
        currentImageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: height,
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Text(
              errorText,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 14,
              ),
            ),
          );
        },
      );
    } else {
      imageContent = Center(
        child: Text(
          emptyText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.secondaryText,
            fontSize: 14,
          ),
        ),
      );
    }

    if (isCircle) {
      return GestureDetector(
        onTap: onTap,
        child: Center(
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.field,
              border: Border.all(color: AppColors.border),
            ),
            child: ClipOval(
              child: imageContent,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.field,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: imageContent,
        ),
      ),
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
                        'EDIT BOUTIQUE',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Update your boutique details and images.',
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
                            buildLabel('Boutique Name'),
                            TextFormField(
                              controller: nameController,
                              decoration: buildInputDecoration(
                                'Enter boutique name',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Boutique name is required';
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
                                'Enter boutique description',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Description is required';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            buildLabel('Logo Image'),
                            buildImagePicker(
                              onTap: pickLogoImage,
                              selectedImage: selectedLogoImage,
                              currentImageUrl: currentLogoUrl,
                              emptyText: 'Tap to upload logo image',
                              errorText: 'Logo could not load',
                              height: 140,
                              isCircle: true,
                            ),
                            const SizedBox(height: 18),
                            buildLabel('Banner Image'),
                            buildImagePicker(
                              onTap: pickBannerImage,
                              selectedImage: selectedBannerImage,
                              currentImageUrl: currentBannerUrl,
                              emptyText: 'Tap to upload banner image',
                              errorText: 'Banner could not load',
                              height: 180,
                              isCircle: false,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : saveBoutiqueChanges,
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