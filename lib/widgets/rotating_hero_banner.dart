import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/utils/image_sizing.dart';
import '../pages/boutique_storefront_page.dart';
import 'theme.dart';
import '../core/services/promo_click_service.dart';

/// Is this banner a PAID home_banner placement, or free editorial curation?
///
/// The two live side by side in `hero_banners`: applyPromoRendering publishes a
/// paid banner carrying `boutiqueId` (+ `promoBookingId`), while the admin tool
/// (hero_banner_management_page) writes image/title/subtitle/cta and no boutique
/// at all. Only a paid banner has somewhere to go, so `boutiqueId` is both the
/// destination and the paid/free discriminator — an editorial banner stays inert
/// exactly as before.
String? bannerBoutiqueId(Map<String, dynamic> data) {
  final id = data['boutiqueId']?.toString().trim() ?? '';
  return id.isEmpty ? null : id;
}

/// Has a paid banner's booked window already closed?
///
/// Defence in depth, not the primary mechanism: revokePromoRendering flips
/// `isActive` to false when a booking expires, and that stays the real control.
/// But if that scheduled job ever lags or fails, an expired banner would keep
/// running for free in the most expensive slot on the home page. `expiresAt` is
/// written by applyPromoRendering at publish time, so the client can refuse to
/// render a lapsed banner on its own.
///
/// Editorial banners carry no `expiresAt` and therefore never expire — they are
/// curation, not a booking, and run until an admin turns them off.
bool bannerHasExpired(Map<String, dynamic> data) {
  final expiresAt = data['expiresAt'];
  if (expiresAt is! Timestamp) return false;
  return expiresAt.toDate().isBefore(DateTime.now());
}

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
        .where((doc) => doc.data()['isActive'] == true && !bannerHasExpired(doc.data()))
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
                  final boutiqueId = bannerBoutiqueId(data);

                  return HeroBannerTapTarget(
                    boutiqueId: boutiqueId,
                    bannerData: data,
                    child: Stack(
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
                    ),
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

/// Wraps a banner in a tap target ONLY when it has somewhere to go.
///
/// A paid home_banner opens the advertising boutique's storefront. An editorial
/// banner has no boutiqueId, so it renders exactly as it always has, with no
/// GestureDetector in the tree at all — not a no-op handler, but genuinely
/// inert, so a shopper never taps a banner and gets nothing.
class HeroBannerTapTarget extends StatelessWidget {
  final String? boutiqueId;
  final Widget child;

  /// The raw banner document, used to log the promo click. Omitted in tests that
  /// only care about tap behaviour; a banner with no promoBookingId logs nothing.
  final Map<String, dynamic>? bannerData;

  const HeroBannerTapTarget({
    super.key,
    required this.boutiqueId,
    required this.child,
    this.bannerData,
  });

  @override
  Widget build(BuildContext context) {
    final id = boutiqueId;
    if (id == null) return child;
    return GestureDetector(
      onTap: () {
        // home_banner is the one placement whose provenance is a scalar
        // (promoBookingId on the hero_banners doc) rather than a stamp array.
        // Not awaited — the storefront opens regardless.
        final data = bannerData;
        if (data != null) PromoClickService.instance.logBannerClick(data);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BoutiqueStorefrontPage(boutiqueId: id)),
        );
      },
      child: child,
    );
  }
}
