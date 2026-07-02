import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import '../widgets/theme.dart';

// ── Pure helpers ──────────────────────────────────────────────────────────────

Future<void> _deleteOldImage(String? imageUrl) async {
  if (imageUrl == null || imageUrl.isEmpty) return;
  await StorageService.deleteImageByUrl(imageUrl);
}

Future<File?> _cropImage(
  String imagePath, {
  required int maxWidth,
  required int maxHeight,
  required CropAspectRatio aspectRatio,
  required CropAspectRatioPreset preset,
  required String toolbarTitle,
}) async {
  final cropped = await ImageCropper().cropImage(
    sourcePath: imagePath,
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 90,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    aspectRatio: aspectRatio,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: toolbarTitle,
        toolbarColor: Colors.black,
        toolbarWidgetColor: Colors.white,
        lockAspectRatio: true,
        initAspectRatio: preset,
        hideBottomControls: false,
        statusBarLight: false,
        backgroundColor: Colors.black,
      ),
      IOSUiSettings(title: toolbarTitle, aspectRatioLockEnabled: true),
    ],
  );
  if (cropped == null) return null;
  return File(cropped.path);
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

InputDecoration _inputDecoration(String hintText) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: AppTextStyles.bodyMedium.copyWith(
      color: AppColors.secondaryText,
    ),
  );
}

Widget _buildImagePicker({
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
      errorBuilder: (_, __, ___) => Center(
        child: Text(
          errorText,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.secondaryText,
          ),
        ),
      ),
    );
  } else if (currentImageUrl != null && currentImageUrl.isNotEmpty) {
    imageContent = Image.network(
      currentImageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: height,
      errorBuilder: (_, __, ___) => Center(
        child: Text(
          errorText,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.secondaryText,
          ),
        ),
      ),
    );
  } else {
    imageContent = Center(
      child: Text(
        emptyText,
        textAlign: TextAlign.center,
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.secondaryText,
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
            color: AppColors.imagePlaceholder,
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: ClipOval(child: imageContent),
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
        color: AppColors.imagePlaceholder,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: imageContent,
    ),
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

class EditBoutiquePage extends StatefulWidget {
  final Map<String, dynamic> boutiqueData;

  const EditBoutiquePage({super.key, required this.boutiqueData});

  @override
  State<EditBoutiquePage> createState() => _EditBoutiquePageState();
}

class _EditBoutiquePageState extends State<EditBoutiquePage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController nameController;
  late final TextEditingController descriptionController;

  bool _isLoading = false;

  File? _selectedLogoImage;
  File? _selectedBannerImage;

  String? _currentLogoUrl;
  String? _currentBannerUrl;

  // Per-boutique setting — whether the live stock count is shown on product
  // pages. Defaults to true when the field is absent on older boutique docs.
  bool _showStockCount = true;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(
      text: widget.boutiqueData['name']?.toString() ?? '',
    );
    descriptionController = TextEditingController(
      text: widget.boutiqueData['description']?.toString() ?? '',
    );
    _currentLogoUrl = widget.boutiqueData['logoPath']?.toString();
    _currentBannerUrl = widget.boutiqueData['bannerPath']?.toString();
    final stockSetting = widget.boutiqueData['showStockCount'];
    if (stockSetting is bool) _showStockCount = stockSetting;
  }

  @override
  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  // ── Image picking ─────────────────────────────────────────────────────────

  Future<void> _pickLogoImage() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (image == null) return;

      final cropped = await _cropImage(
        image.path,
        maxWidth: 800,
        maxHeight: 800,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        preset: CropAspectRatioPreset.square,
        toolbarTitle: l10n.cropLogo,
      );
      if (cropped == null || !mounted) return;

      setState(() => _selectedLogoImage = cropped);
    } catch (e) {
      debugPrint('pickLogoImage error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.failedToPickLogoImage)));
    }
  }

  Future<void> _pickBannerImage() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1600,
        maxHeight: 1200,
      );
      if (image == null) return;

      final cropped = await _cropImage(
        image.path,
        maxWidth: 1600,
        maxHeight: 900,
        aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
        preset: CropAspectRatioPreset.ratio16x9,
        toolbarTitle: l10n.cropBanner,
      );
      if (cropped == null || !mounted) return;

      setState(() => _selectedBannerImage = cropped);
    } catch (e) {
      debugPrint('pickBannerImage error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.failedToPickBannerImage)));
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _saveBoutiqueChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Track newly uploaded URLs so we can clean them up if Firestore fails
    String? newLogoUrl;
    String? newBannerUrl;

    try {
      String? logoUrl = _currentLogoUrl;
      String? bannerUrl = _currentBannerUrl;

      final boutiqueId = await FirestoreService.getCurrentOwnerBoutiqueId();
      if (boutiqueId == null) throw Exception('No boutique found');

      if (_selectedLogoImage != null) {
        newLogoUrl = await StorageService.uploadImage(
          _selectedLogoImage!,
          'boutique_logos/$boutiqueId',
        );
        logoUrl = newLogoUrl;
      }

      if (_selectedBannerImage != null) {
        newBannerUrl = await StorageService.uploadImage(
          _selectedBannerImage!,
          'boutique_banners/$boutiqueId',
        );
        bannerUrl = newBannerUrl;
      }

      await FirestoreService.updateCurrentOwnerBoutique(
        name: nameController.text.trim(),
        description: descriptionController.text.trim(),
        logoPath: logoUrl,
        bannerPath: bannerUrl,
        showStockCount: _showStockCount,
      );

      // Firestore write confirmed — safe to delete old Storage files
      if (newLogoUrl != null) await _deleteOldImage(_currentLogoUrl);
      if (newBannerUrl != null) await _deleteOldImage(_currentBannerUrl);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.boutiqueUpdatedSuccessfully,
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      // Firestore write failed — delete any newly uploaded files to avoid orphans
      if (newLogoUrl != null) {
        await StorageService.deleteImageByUrl(
          newLogoUrl,
        ).catchError((err) => debugPrint('Logo cleanup error: $err'));
      }
      if (newBannerUrl != null) {
        await StorageService.deleteImageByUrl(
          newBannerUrl,
        ).catchError((err) => debugPrint('Banner cleanup error: $err'));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.failedToUpdateBoutique),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.editBoutique,
                        style: AppTextStyles.headingMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.editBoutiqueDescription,
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
                            _buildLabel(l10n.boutiqueName),
                            TextFormField(
                              controller: nameController,
                              textInputAction: TextInputAction.next,
                              decoration: _inputDecoration(
                                l10n.enterBoutiqueName,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return l10n.boutiqueNameRequired;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            _buildLabel(l10n.description),
                            TextFormField(
                              controller: descriptionController,
                              maxLines: 4,
                              textInputAction: TextInputAction.done,
                              onEditingComplete: () =>
                                  FocusScope.of(context).unfocus(),
                              decoration: _inputDecoration(
                                l10n.enterBoutiqueDescription,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return l10n.descriptionRequired;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            _buildLabel(l10n.logoImage),
                            _buildImagePicker(
                              onTap: _pickLogoImage,
                              selectedImage: _selectedLogoImage,
                              currentImageUrl: _currentLogoUrl,
                              emptyText: l10n.tapToUploadLogo,
                              errorText: l10n.logoCouldNotLoad,
                              height: 140,
                              isCircle: true,
                            ),
                            const SizedBox(height: 18),
                            _buildLabel(l10n.bannerImage),
                            _buildImagePicker(
                              onTap: _pickBannerImage,
                              selectedImage: _selectedBannerImage,
                              currentImageUrl: _currentBannerUrl,
                              emptyText: l10n.tapToUploadBanner,
                              errorText: l10n.bannerCouldNotLoad,
                              height: 180,
                              isCircle: false,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      // ── Storefront settings ──────────────────────────
                      _buildSectionCard(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.showStockCount,
                                    style: AppTextStyles.labelLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.showStockCountSubtitle,
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.secondaryText,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Switch(
                              value: _showStockCount,
                              activeTrackColor: AppColors.deepAccent,
                              onChanged: (v) =>
                                  setState(() => _showStockCount = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _saveBoutiqueChanges,
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
      ),
    );
  }
}
