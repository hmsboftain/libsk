import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../services/storage_service.dart';
import '../widgets/theme.dart';

class HeroBannerManagementPage extends StatefulWidget {
  const HeroBannerManagementPage({super.key});

  @override
  State<HeroBannerManagementPage> createState() =>
      _HeroBannerManagementPageState();
}

class _HeroBannerManagementPageState extends State<HeroBannerManagementPage> {
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _ctaController = TextEditingController();
  File? _selectedImage;
  bool _isUploading = false;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _bannersStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _activeBannersStream;

  @override
  void initState() {
    super.initState();
    _bannersStream = FirebaseFirestore.instance
        .collection('hero_banners')
        .orderBy('order')
        .snapshots();
    _activeBannersStream = FirebaseFirestore.instance
        .collection('hero_banners')
        .where('isActive', isEqualTo: true)
        .orderBy('order')
        .snapshots();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _ctaController.dispose();
    super.dispose();
  }

  Future<void> _pickAndCropImage() async {
    final l10n = AppLocalizations.of(context)!;
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file == null) return;

    // Crop to 16:9 ratio (matches home banner height: 300 on full width)
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: file.path,
      aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: l10n.cropBanner,
          toolbarColor: const Color(0xFF8E877D),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFF8E877D),
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: l10n.cropBanner,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
        ),
      ],
    );

    if (croppedFile == null) return;
    if (!mounted) return;
    setState(() => _selectedImage = File(croppedFile.path));
  }

  Future<void> _uploadBanner() async {
    final l10n = AppLocalizations.of(context)!;
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.selectBannerImage)),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final imageUrl = await StorageService.uploadImage(
        _selectedImage!,
        'hero_banners',
      );

      final existing = await FirebaseFirestore.instance
          .collection('hero_banners')
          .orderBy('order', descending: true)
          .limit(1)
          .get();

      final nextOrder = existing.docs.isEmpty
          ? 0
          : ((existing.docs.first.data()['order'] ?? 0) as int) + 1;

      await FirebaseFirestore.instance.collection('hero_banners').add({
        'imageUrl': imageUrl,
        'title': _titleController.text.trim(),
        'subtitle': _subtitleController.text.trim(),
        'ctaText': _ctaController.text.trim(),
        'isActive': true,
        'order': nextOrder,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _titleController.clear();
      _subtitleController.clear();
      _ctaController.clear();
      setState(() => _selectedImage = null);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.bannerUploadedSuccessfully)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${l10n.uploadFailed}: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _deleteBanner(String docId, String imageUrl) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: const RoundedRectangleBorder(),
        title: Text(l10n.deleteBanner, style: AppTextStyles.headingSmall),
        content: Text(
          l10n.confirmDeleteBanner,
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.cancel,
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: Text(l10n.deleteAccountButton, style: AppTextStyles.button),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('hero_banners')
          .doc(docId)
          .delete();
      await StorageService.deleteImageByUrl(imageUrl);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.bannerRemoved)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${l10n.error}: $e')));
    }
  }

  Future<void> _toggleActive(String docId, bool current) async {
    await FirebaseFirestore.instance
        .collection('hero_banners')
        .doc(docId)
        .update({'isActive': !current});
  }

  InputDecoration _inputDec(String hint) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: AppColors.border, width: 0.5),
    );
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppColors.field,
      hintStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.secondaryText,
      ),
      border: border,
      enabledBorder: border,
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: AppColors.deepAccent, width: 1),
      ),
    );
  }

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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.heroBanners, style: AppTextStyles.displayMedium),
                    const SizedBox(height: 4),
                    Text(
                      l10n.manageHomepageBanners,
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(height: 20),

                    // ── Live preview ────────────────────────────────
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _activeBannersStream,
                      builder: (context, snapshot) {
                        final banners = snapshot.data?.docs ?? [];

                        if (banners.isEmpty) {
                          return Container(
                            height: 180,
                            width: double.infinity,
                            color: AppColors.imagePlaceholder,
                            alignment: Alignment.center,
                            child: Text(
                              l10n.noActiveBanners,
                              style: AppTextStyles.bodySmall,
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.livePreview,
                              style: AppTextStyles.capsLabel,
                            ),
                            const SizedBox(height: 8),
                            _AutoRotatingBanner(banners: banners),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // ── All banners list ────────────────────────────
                    Text(l10n.allBanners, style: AppTextStyles.capsLabel),
                    const SizedBox(height: 10),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _bannersStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(
                                color: AppColors.deepAccent,
                                strokeWidth: 1.5,
                              ),
                            ),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];

                        if (docs.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.field,
                              border: Border.all(
                                color: AppColors.border,
                                width: 0.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                l10n.noBannersAddedYet,
                                style: AppTextStyles.bodySmall,
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: docs.map((doc) {
                            final data = doc.data();
                            final imageUrl = data['imageUrl']?.toString() ?? '';
                            final title = data['title']?.toString() ?? '';
                            final isActive = data['isActive'] == true;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                border: Border.all(
                                  color: AppColors.border,
                                  width: 0.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 80,
                                    height: 60,
                                    color: AppColors.imagePlaceholder,
                                    child: imageUrl.isNotEmpty
                                        ? Image.network(
                                            imageUrl,
                                            fit: BoxFit.cover,
                                          )
                                        : const Icon(
                                            Icons.image_outlined,
                                            color: AppColors.softAccent,
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title.isNotEmpty
                                              ? title
                                              : l10n.untitled,
                                          style: AppTextStyles.labelLarge,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          color: isActive
                                              ? AppColors.deepAccent
                                              : AppColors.softAccent,
                                          child: Text(
                                            isActive
                                                ? l10n.activeCaps
                                                : l10n.hiddenCaps,
                                            style: AppTextStyles.capsLabel
                                                .copyWith(
                                                  fontSize: 9,
                                                  color: Colors.white,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          isActive
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          size: 18,
                                          color: AppColors.secondaryText,
                                        ),
                                        onPressed: () =>
                                            _toggleActive(doc.id, isActive),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18,
                                          color: AppColors.deepAccent,
                                        ),
                                        onPressed: () =>
                                            _deleteBanner(doc.id, imageUrl),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // ── Add new banner ──────────────────────────────
                    Text(l10n.addNewBanner, style: AppTextStyles.capsLabel),
                    const SizedBox(height: 6),

                    // Guideline info box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.field,
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 16,
                            color: AppColors.deepAccent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.bannerImageGuideline,
                              style: AppTextStyles.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Image picker with crop
                          GestureDetector(
                            onTap: _pickAndCropImage,
                            child: Container(
                              width: double.infinity,
                              // 16:9 preview container
                              height:
                                  (MediaQuery.of(context).size.width - 64) *
                                  9 /
                                  16,
                              decoration: BoxDecoration(
                                color: AppColors.imagePlaceholder,
                                border: Border.all(
                                  color: AppColors.border,
                                  width: 0.5,
                                ),
                              ),
                              child: _selectedImage != null
                                  ? Stack(
                                      children: [
                                        Image.file(
                                          _selectedImage!,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                        ),
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: GestureDetector(
                                            onTap: _pickAndCropImage,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 5,
                                                  ),
                                              color: AppColors.deepAccent,
                                              child: Text(
                                                l10n.changeCaps,
                                                style: AppTextStyles.capsLabel
                                                    .copyWith(
                                                      color: Colors.white,
                                                      fontSize: 9,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.add_photo_alternate_outlined,
                                          size: 30,
                                          color: AppColors.deepAccent,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          l10n.tapToSelectCropBannerImage,
                                          style: AppTextStyles.bodySmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          l10n.willBeCroppedToRatio,
                                          style: AppTextStyles.bodySmall
                                              .copyWith(
                                                color: AppColors.softAccent,
                                                fontSize: 10,
                                              ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),

                          const SizedBox(height: 14),
                          TextField(
                            controller: _titleController,
                            decoration: _inputDec(l10n.bannerTitleOptional),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _subtitleController,
                            decoration: _inputDec(l10n.subtitleOptional),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _ctaController,
                            decoration: _inputDec(''),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isUploading ? null : _uploadBanner,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.deepAccent,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                              ),
                              child: _isUploading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      l10n.uploadBannerButton,
                                      style: AppTextStyles.button,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Auto-rotating banner preview ─────────────────────────────────────────────
class _AutoRotatingBanner extends StatefulWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> banners;
  const _AutoRotatingBanner({required this.banners});

  @override
  State<_AutoRotatingBanner> createState() => _AutoRotatingBannerState();
}

class _AutoRotatingBannerState extends State<_AutoRotatingBanner> {
  final PageController _controller = PageController();
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _startRotation();
  }

  void _startRotation() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted) return false;
      if (widget.banners.isEmpty) return true;
      final next = (_current + 1) % widget.banners.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
      return true;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Preview matches exact home page ratio: full width, 300px tall
    final previewWidth = MediaQuery.of(context).size.width - 32;
    final previewHeight = previewWidth * 9 / 16;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: previewHeight,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.banners.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, index) {
              final data = widget.banners[index].data();
              final imageUrl = data['imageUrl']?.toString() ?? '';
              final title = data['title']?.toString().trim() ?? '';
              final subtitle = data['subtitle']?.toString().trim() ?? '';
              final cta = data['ctaText']?.toString().trim() ?? '';
              final showOverlay =
                  title.isNotEmpty || subtitle.isNotEmpty || cta.isNotEmpty;

              return Stack(
                fit: StackFit.expand,
                children: [
                  imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : Container(color: AppColors.imagePlaceholder),
                  if (showOverlay) ...[
                    Container(color: Colors.black.withValues(alpha: 0.1)),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title.isNotEmpty)
                            Text(
                              title,
                              style: AppTextStyles.headingSmall.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          if (cta.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              cta.toUpperCase(),
                              style: AppTextStyles.capsLabel.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.exactHomePreview,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.softAccent,
            fontSize: 10,
          ),
        ),
        if (widget.banners.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.banners.length, (i) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _current == i ? 18 : 8,
                height: 8,
                color: _current == i ? AppColors.deepAccent : AppColors.border,
              );
            }),
          ),
        ],
      ],
    );
  }
}
