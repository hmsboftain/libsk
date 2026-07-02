import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/utils/image_sizing.dart';
import 'theme.dart';

/// Drop-in replacement for the static banner on home_page.dart
/// Usage: const RotatingHeroBanner()
class RotatingHeroBanner extends StatefulWidget {
  const RotatingHeroBanner({super.key});

  @override
  State<RotatingHeroBanner> createState() => _RotatingHeroBannerState();
}

class _RotatingHeroBannerState extends State<RotatingHeroBanner> {
  final PageController _controller = PageController();
  int _current = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startRotation(int count) {
    if (count <= 1) return;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted) return false;
      final next = (_current + 1) % count;
      await _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
      if (mounted) setState(() => _current = next);
      return true;
    });
  }

  bool _rotationStarted = false;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _activeBanners(
    QuerySnapshot<Map<String, dynamic>>? snapshot,
  ) {
    if (snapshot == null) return [];
    return snapshot.docs
        .where((doc) => doc.data()['isActive'] == true)
        .toList()
      ..sort((a, b) {
        final orderA = (a.data()['order'] as num?)?.toInt() ?? 0;
        final orderB = (b.data()['order'] as num?)?.toInt() ?? 0;
        return orderA.compareTo(orderB);
      });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('hero_banners')
          .orderBy('order')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _emptyPlaceholder();
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _emptyPlaceholder();
        }

        final banners = _activeBanners(snapshot.data);

        if (banners.isEmpty) {
          return _emptyPlaceholder();
        }

        if (!_rotationStarted && banners.length > 1) {
          _rotationStarted = true;
          _startRotation(banners.length);
        }

        return Column(
          children: [
            SizedBox(
              height: 300,
              child: PageView.builder(
                controller: _controller,
                itemCount: banners.length,
                onPageChanged: (i) => setState(() => _current = i),
                itemBuilder: (context, index) {
                  final data = banners[index].data();
                  final imageUrl = data['imageUrl']?.toString() ?? '';
                  final title = data['title']?.toString().trim() ?? '';
                  final subtitle = data['subtitle']?.toString().trim() ?? '';
                  final cta = data['ctaText']?.toString().trim() ?? '';
                  final showOverlay =
                      title.isNotEmpty || subtitle.isNotEmpty || cta.isNotEmpty;

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageUrl.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: double.infinity,
                          height: 300,
                          fit: BoxFit.cover,
                          memCacheWidth: fullBleedCacheWidth(context),
                          maxWidthDiskCache: maxImageDiskCacheWidth,
                          errorWidget: (_, __, ___) => _emptyPlaceholder(),
                        )
                      else
                        _emptyPlaceholder(),
                      if (showOverlay) ...[
                        Container(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (title.isNotEmpty) ...[
                                Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.displayLarge.copyWith(
                                    fontSize: 28,
                                    height: 1.2,
                                  ),
                                ),
                                if (subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    subtitle,
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                ],
                              ],
                              if (cta.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                    vertical: 12,
                                  ),
                                  color: AppColors.deepAccent,
                                  child: Text(
                                    cta.toUpperCase(),
                                    style: AppTextStyles.capsLabel.copyWith(
                                      color: Colors.white,
                                      letterSpacing: 0.2,
                                    ),
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
            if (banners.length > 1) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(banners.length, (i) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _current == i ? 18 : 8,
                    height: 8,
                    color: _current == i
                        ? AppColors.deepAccent
                        : AppColors.border,
                  );
                }),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _emptyPlaceholder() {
    return Container(
      height: 300,
      width: double.infinity,
      color: AppColors.imagePlaceholder,
    );
  }
}
