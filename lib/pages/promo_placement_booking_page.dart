import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:libsk/l10n/app_localizations.dart';

import '../models/promo_availability.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import '../widgets/promo_pickers.dart';
import '../widgets/promo_week_picker.dart';
import '../widgets/theme.dart';
import 'promo_credit_booked_page.dart';
import 'promo_payzah_payment_page.dart';

/// Books one promo placement for the upcoming week: day-range picker (or post
/// count for feed), the matching target picker, a live price, and payment.
///
/// PRICE INTEGRITY: every price shown — the rate line, the running total, the
/// "extend to full week" saving, the pay button — is a LOOKUP into the
/// server-computed [PromoPlacement.priceByDays] / priceByPosts tables. This
/// screen never multiplies or sums a rate; the number on the button therefore
/// always equals what createPromoBooking charges (which returns the price it
/// actually used, shown next on the payment page).
class PromoPlacementBookingPage extends StatefulWidget {
  final String boutiqueId;
  final String placementType;
  final String placementLabel;
  final PromoPlacement placement;
  final DateTime weekStart;
  final List<int> globalRemainingPerDay;

  /// Live, spendable promo credit (KWD) for this boutique. > 0 shows the "Use
  /// promo credit" checkbox; the server re-verifies and re-splits at booking.
  final double promoCreditBalance;

  const PromoPlacementBookingPage({
    super.key,
    required this.boutiqueId,
    required this.placementType,
    required this.placementLabel,
    required this.placement,
    required this.weekStart,
    required this.globalRemainingPerDay,
    required this.promoCreditBalance,
  });

  @override
  State<PromoPlacementBookingPage> createState() =>
      _PromoPlacementBookingPageState();
}

class _PromoPlacementBookingPageState extends State<PromoPlacementBookingPage> {
  int? _startDay;
  int? _numDays;

  PromoProductRef? _product; // featured_product
  final List<PromoProductRef> _feedPosts = []; // feed_sponsored (1–2)
  String? _category; // top_of_category
  final List<PromoProductRef> _catProducts = []; // top_of_category (1–2)

  File? _bannerFile; // home_banner
  String? _bannerUrl;
  bool _uploadingBanner = false;

  String _method = 'KNET';
  bool _booking = false;
  bool _useCredit = false;

  bool get _isFeed => widget.placementType == 'feed_sponsored';
  bool get _isCategory => widget.placementType == 'top_of_category';
  bool get _isFeaturedProduct => widget.placementType == 'featured_product';
  bool get _isBanner => widget.placementType == 'home_banner';

  int get _catItemCount => _catProducts.length;

  // ── Server-price lookups (never computed here) ──────────────────────────────

  double? get _displayPrice {
    if (_isFeed) {
      return _feedPosts.isEmpty ? null : widget.placement.priceForPosts(_feedPosts.length);
    }
    final n = _numDays;
    return n == null ? null : widget.placement.priceForDays(n);
  }

  bool get _showFullWeekNudge {
    final n = _numDays;
    return !_isFeed && n != null && widget.placement.fullWeekIsCheaperThan(n);
  }

  // ── Promo-credit split (preview only; the server re-splits authoritatively) ──

  bool get _hasCredit => widget.promoCreditBalance > 0;

  /// Credit that would apply to the current price = min(balance, price). Null
  /// until a price is known (a day range / post count is picked).
  double? get _creditApplied {
    if (!_useCredit || !_hasCredit) return null;
    final price = _displayPrice;
    if (price == null) return null;
    return price < widget.promoCreditBalance ? price : widget.promoCreditBalance;
  }

  /// The remainder to charge via Payzah = price − credit (never negative). Falls
  /// back to the full price when credit isn't used.
  double? get _remainderToPay {
    final price = _displayPrice;
    if (price == null) return null;
    final r = price - (_creditApplied ?? 0);
    return r < 0 ? 0 : r;
  }

  /// True when credit covers the whole price (within half a fil) — no payment
  /// step. The final decision is the server's `creditOnly`; this only drives the
  /// button label and whether the payment-method picker is shown.
  bool get _fullyCovered {
    final r = _remainderToPay;
    return _useCredit && _hasCredit && r != null && r <= 0.0005;
  }

  // ── Day picker availability ────────────────────────────────────────────────

  bool _dayOpen(int day) {
    if (_isCategory) {
      final cat = _category;
      if (cat == null || _catItemCount == 0) return false;
      return widget.placement.categoryDayOpen(
        cat,
        day,
        _catItemCount,
        globalRemainingPerDay: widget.globalRemainingPerDay,
      );
    }
    return widget.placement.normalDayOpen(
      day,
      globalRemainingPerDay: widget.globalRemainingPerDay,
    );
  }

  int? _remainingFor(int day) {
    if (_isCategory) {
      final cat = _category;
      if (cat == null) return null;
      return widget.placement.categoryRemainingItems(cat, day);
    }
    if (day < widget.placement.remainingPerDay.length) {
      return widget.placement.remainingPerDay[day];
    }
    return null;
  }

  // ── Target editing ──────────────────────────────────────────────────────────

  Future<void> _pickFeaturedProduct() async {
    final result = await Navigator.of(context).push<List<PromoProductRef>>(
      MaterialPageRoute(
        builder: (_) => PromoProductPickerPage(
          boutiqueId: widget.boutiqueId,
          title: AppLocalizations.of(context)!.promoChooseProduct,
          minSelection: 1,
          maxSelection: 1,
          initialSelected: _product == null ? const [] : [_product!],
        ),
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _product = result.first);
    }
  }

  Future<void> _pickFeedPosts() async {
    final result = await Navigator.of(context).push<List<PromoProductRef>>(
      MaterialPageRoute(
        builder: (_) => PromoProductPickerPage(
          boutiqueId: widget.boutiqueId,
          title: AppLocalizations.of(context)!.promoChoosePosts,
          minSelection: 1,
          maxSelection: 2,
          initialSelected: List.of(_feedPosts),
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _feedPosts
          ..clear()
          ..addAll(result);
      });
    }
  }

  Future<void> _pickCategory() async {
    final cat = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PromoCategoryPickerPage(
          title: AppLocalizations.of(context)!.promoChooseCategory,
          selected: _category,
        ),
      ),
    );
    if (cat != null && cat != _category) {
      setState(() {
        _category = cat;
        _catProducts.clear(); // products are category-scoped — reset on change
        _startDay = null; // availability changes with category
        _numDays = null;
      });
    }
  }

  Future<void> _pickCategoryProducts() async {
    final cat = _category;
    if (cat == null) return;
    final result = await Navigator.of(context).push<List<PromoProductRef>>(
      MaterialPageRoute(
        builder: (_) => PromoProductPickerPage(
          boutiqueId: widget.boutiqueId,
          title: AppLocalizations.of(context)!.promoPinProducts,
          minSelection: 1,
          maxSelection: 2,
          categoryFilter: cat,
          initialSelected: List.of(_catProducts),
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _catProducts
          ..clear()
          ..addAll(result);
        // Item count may have changed → previously-open days might not fit.
        _startDay = null;
        _numDays = null;
      });
    }
  }

  Future<void> _pickBanner() async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final file = File(picked.path);

    // Type is checked on the source (cheap, valid pre-compression). Size is
    // enforced by uploadImage on the COMPRESSED bytes below — most phone photos
    // are >5 MB raw but well under it once compressed.
    if (StorageService.imageTypeError(file) != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.promoImageWrongType)));
      return;
    }

    setState(() {
      _bannerFile = file;
      _uploadingBanner = true;
      _bannerUrl = null;
    });
    try {
      final url = await StorageService.uploadImage(
        file,
        'promo_banners/${widget.boutiqueId}',
        enforceSizeLimit: true,
      );
      if (!mounted) return;
      setState(() {
        _bannerUrl = url;
        _uploadingBanner = false;
      });
    } on StorageImageException {
      // Still over 5 MB after compression — revert to the picker prompt.
      if (!mounted) return;
      setState(() {
        _uploadingBanner = false;
        _bannerFile = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.promoImageTooLarge)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingBanner = false;
        _bannerFile = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  // ── Booking readiness ────────────────────────────────────────────────────────

  bool get _targetReady {
    if (_isFeaturedProduct) return _product != null;
    if (_isBanner) return _bannerUrl != null && !_uploadingBanner;
    if (_isCategory) return _category != null && _catProducts.isNotEmpty;
    if (_isFeed) return _feedPosts.isNotEmpty;
    return true; // featured_boutique
  }

  bool get _canBook {
    if (!_targetReady) return false;
    if (_isFeed) return true;
    return _startDay != null && _numDays != null;
  }

  Future<void> _bookAndPay() async {
    final l10n = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    setState(() => _booking = true);
    try {
      final result = await FirestoreService.createPromoBooking(
        placementType: widget.placementType,
        paymentMethod: _method,
        startDay: _isFeed ? null : _startDay,
        numDays: _isFeed ? null : _numDays,
        productId: _isFeaturedProduct ? _product?.id : null,
        targetProductIds:
            _isFeed ? _feedPosts.map((p) => p.id).toList() : null,
        category: _isCategory ? _category : null,
        productIds: _isCategory ? _catProducts.map((p) => p.id).toList() : null,
        bannerImageUrl: _isBanner ? _bannerUrl : null,
        useCredit: _useCredit,
      );
      if (!mounted) return;
      setState(() => _booking = false);

      // Fully covered by credit: the server already booked it (active, or banner
      // awaiting review) with no payment attempt — skip the Payzah page, but
      // still show a full confirmation, since real credit was just spent.
      if (result.creditOnly || result.paymentAttemptId == null) {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => PromoCreditBookedPage(
              amountFromCredit: result.amountFromCredit,
            ),
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pop(true); // back to dashboard
        return;
      }

      final paid = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => PromoPayzahPaymentPage(
            attemptId: result.paymentAttemptId!,
            bookingId: result.bookingId,
            placementLabel: widget.placementLabel,
            priceKwd: result.amountToCharge, // only the remainder is charged
            isArabic: isArabic,
            paymentMethod: _method,
          ),
        ),
      );
      if (!mounted) return;
      if (paid == true) Navigator.of(context).pop(true); // back to dashboard
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _booking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? l10n.somethingWentWrong)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _booking = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final daily = widget.placement.priceForDays(1);
    final weekly = widget.placement.priceForDays(7);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.primaryText,
        title: Text(widget.placementLabel, style: AppTextStyles.labelLarge),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            if (!_isFeed && daily != null && weekly != null)
              Text(
                l10n.promoRateLine(
                  daily.toStringAsFixed(3),
                  weekly.toStringAsFixed(3),
                ),
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.secondaryText,
                ),
              ),

            // top_of_category chooses its target first — day availability
            // depends on the category and the number of pinned items.
            if (_isCategory) ...[
              const SizedBox(height: 20),
              _categorySection(l10n),
            ],

            if (!_isFeed) ...[
              const SizedBox(height: 20),
              _sectionLabel(l10n.promoPickYourDays),
              const SizedBox(height: 10),
              if (_isCategory && (_category == null || _catProducts.isEmpty))
                _hint(l10n.promoPickCategoryFirst)
              else ...[
                PromoWeekPicker(
                  weekStart: widget.weekStart,
                  isDayOpen: _dayOpen,
                  remainingFor: _remainingFor,
                  startDay: _startDay,
                  numDays: _numDays,
                  onChanged: (s, n) => setState(() {
                    _startDay = s;
                    _numDays = n;
                  }),
                ),
                const SizedBox(height: 8),
                _legend(l10n),
                if (_numDays != null) ...[
                  const SizedBox(height: 14),
                  _totalRow(l10n),
                  if (_showFullWeekNudge) ...[
                    const SizedBox(height: 8),
                    _fullWeekNudge(l10n),
                  ],
                ],
              ],
            ],

            if (_isFeed) ...[
              const SizedBox(height: 20),
              _feedSection(l10n),
            ],

            if (_isFeaturedProduct) ...[
              const SizedBox(height: 22),
              _sectionLabel(l10n.promoProductToFeature),
              const SizedBox(height: 10),
              _productChip(
                _product,
                onTap: _pickFeaturedProduct,
                placeholder: l10n.promoChooseProduct,
              ),
            ],

            if (_isBanner) ...[
              const SizedBox(height: 22),
              _sectionLabel(l10n.promoBannerImage),
              const SizedBox(height: 10),
              _bannerSection(l10n),
              const SizedBox(height: 8),
              _hint(l10n.promoBannerReviewNote),
            ],

            if (_hasCredit) ...[
              const SizedBox(height: 24),
              _creditSection(l10n),
            ],

            // A fully-credit-covered booking has nothing to charge, so the
            // gateway picker is hidden.
            if (!_fullyCovered) ...[
              const SizedBox(height: 24),
              _sectionLabel(l10n.paymentMethod),
              const SizedBox(height: 4),
              _methodTile('KNET', l10n.knet),
              _methodTile('Card', l10n.card),
              _methodTile('Apple Pay', l10n.applePay),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: (_canBook && !_booking) ? _bookAndPay : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepAccent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.softAccent,
                  disabledForegroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: _booking
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 1.5,
                        ),
                      )
                    : Text(_payButtonLabel(l10n), style: AppTextStyles.button),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section builders ─────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) =>
      Text(text, style: AppTextStyles.labelSmall);

  Widget _hint(String text) => Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
      );

  String _payButtonLabel(AppLocalizations l10n) {
    if (_fullyCovered) return l10n.promoConfirmBooking;
    final amount = _remainderToPay;
    return amount == null
        ? l10n.bookAndPay
        : l10n.promoBookAndPayAmount(amount.toStringAsFixed(3));
  }

  Widget _creditSection(AppLocalizations l10n) {
    final applied = _creditApplied;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _useCredit = !_useCredit),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  _useCredit ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 22,
                  color: _useCredit
                      ? AppColors.deepAccent
                      : AppColors.secondaryText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.promoUseCredit(
                        widget.promoCreditBalance.toStringAsFixed(3)),
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Live breakdown once a price is known: credit applied + remainder.
        if (applied != null) ...[
          const SizedBox(height: 10),
          _breakdownRow(
            l10n.promoCreditApplied,
            l10n.promoPriceKwd('−${applied.toStringAsFixed(3)}'),
          ),
          const SizedBox(height: 4),
          _breakdownRow(
            l10n.promoRemainingToPay,
            l10n.promoPriceKwd((_remainderToPay ?? 0).toStringAsFixed(3)),
          ),
        ],
      ],
    );
  }

  Widget _breakdownRow(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.secondaryText),
          ),
          Text(value, style: AppTextStyles.labelSmall),
        ],
      );

  Widget _totalRow(AppLocalizations l10n) {
    final price = _displayPrice;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(l10n.promoTotalLabel, style: AppTextStyles.labelSmall),
        Text(
          price == null ? '—' : l10n.promoPriceKwd(price.toStringAsFixed(3)),
          style: AppTextStyles.headingMedium,
        ),
      ],
    );
  }

  Widget _fullWeekNudge(AppLocalizations l10n) {
    final full = widget.placement.fullWeekPrice;
    final part = _numDays == null ? null : widget.placement.priceForDays(_numDays!);
    if (full == null || part == null) return const SizedBox.shrink();
    final saving = part - full; // both server prices → exact
    return InkWell(
      onTap: () => setState(() {
        _startDay = 0;
        _numDays = 7;
      }),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.field,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, size: 18, color: AppColors.deepAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.promoFullWeekNudge(
                  full.toStringAsFixed(3),
                  saving.toStringAsFixed(3),
                ),
                style: AppTextStyles.bodySmall,
              ),
            ),
            Text(
              l10n.promoExtendFullWeek,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.deepAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(AppLocalizations l10n) {
    Widget swatch(Color c, Color border) => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: c, border: Border.all(color: border)),
        );
    return Row(
      children: [
        swatch(AppColors.deepAccent, AppColors.deepAccent),
        const SizedBox(width: 5),
        Text(l10n.promoLegendPicked, style: _legendStyle),
        const SizedBox(width: 14),
        swatch(AppColors.card, AppColors.border),
        const SizedBox(width: 5),
        Text(l10n.promoLegendOpen, style: _legendStyle),
        const SizedBox(width: 14),
        swatch(AppColors.disabledField, AppColors.disabledField),
        const SizedBox(width: 5),
        Text(l10n.promoLegendFull, style: _legendStyle),
      ],
    );
  }

  TextStyle get _legendStyle =>
      AppTextStyles.labelSmall.copyWith(color: AppColors.secondaryText);

  Widget _categorySection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(l10n.promoCategory),
        const SizedBox(height: 10),
        _selectorTile(
          label: _category ?? l10n.promoChooseCategory,
          filled: _category != null,
          onTap: _pickCategory,
        ),
        if (_category != null) ...[
          const SizedBox(height: 14),
          _sectionLabel(l10n.promoPinProducts),
          const SizedBox(height: 10),
          if (_catProducts.isEmpty)
            _selectorTile(
              label: l10n.promoPinProducts,
              filled: false,
              onTap: _pickCategoryProducts,
            )
          else
            _multiProductChips(
              _catProducts,
              _pickCategoryProducts,
              // Item count drives day availability, so reset the day selection.
              onRemove: (r) => setState(() {
                _catProducts.remove(r);
                _startDay = null;
                _numDays = null;
              }),
            ),
        ],
      ],
    );
  }

  Widget _feedSection(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(l10n.promoPostsToSponsor),
        const SizedBox(height: 6),
        _hint(l10n.promoFeedWeekNote),
        const SizedBox(height: 10),
        if (_feedPosts.isEmpty)
          _selectorTile(
            label: l10n.promoChoosePosts,
            filled: false,
            onTap: _pickFeedPosts,
          )
        else
          _multiProductChips(
            _feedPosts,
            _pickFeedPosts,
            onRemove: (r) => setState(() => _feedPosts.remove(r)),
          ),
      ],
    );
  }

  Widget _bannerSection(AppLocalizations l10n) {
    return GestureDetector(
      onTap: _uploadingBanner ? null : _pickBanner,
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          color: AppColors.imagePlaceholder,
          border: Border.all(color: AppColors.border),
        ),
        child: _uploadingBanner
            ? const Center(child: CircularProgressIndicator())
            : _bannerFile != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(_bannerFile!, fit: BoxFit.cover),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          color: Colors.black54,
                          child: Text(
                            l10n.promoChange,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.add_photo_alternate_outlined,
                          color: AppColors.deepAccent,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.promoUploadBanner,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _selectorTile({
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: filled ? AppColors.primaryText : AppColors.secondaryText,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.secondaryText),
          ],
        ),
      ),
    );
  }

  Widget _productChip(
    PromoProductRef? ref, {
    required VoidCallback onTap,
    required String placeholder,
  }) {
    if (ref == null) {
      return _selectorTile(label: placeholder, filled: false, onTap: onTap);
    }
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            _thumb(ref.imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ref.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ref.price.toStringAsFixed(3),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              AppLocalizations.of(context)!.promoChange,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.deepAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _multiProductChips(
    List<PromoProductRef> refs,
    VoidCallback onEdit, {
    required void Function(PromoProductRef) onRemove,
  }) {
    return Column(
      children: [
        for (final r in refs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 4, 10),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  _thumb(r.imageUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: AppColors.secondaryText,
                    visualDensity: VisualDensity.compact,
                    tooltip: AppLocalizations.of(context)!.promoRemove,
                    onPressed: () => onRemove(r),
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: onEdit,
            child: Text(
              AppLocalizations.of(context)!.promoChangeSelection,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.deepAccent,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _thumb(String url) => Container(
        width: 42,
        height: 52,
        color: AppColors.imagePlaceholder,
        child: url.isEmpty
            ? const Icon(Icons.image_not_supported_outlined,
                color: AppColors.softAccent, size: 18)
            : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
      );

  Widget _methodTile(String value, String label) {
    final selected = _method == value;
    return InkWell(
      onTap: () => setState(() => _method = value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? AppColors.deepAccent : AppColors.secondaryText,
            ),
            const SizedBox(width: 12),
            Text(label, style: AppTextStyles.bodyMedium),
          ],
        ),
      ),
    );
  }
}
