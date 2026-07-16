import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:libsk/l10n/app_localizations.dart';

import '../services/firestore_service.dart';
import '../widgets/theme.dart';

/// Super-admin review queue for home-banner creatives. Banners are paid but held
/// at `paid_pending_review` until approved here; approval lets the scheduled
/// activator publish the banner when its booked day-window opens.
class PromoBannerApprovalPage extends StatelessWidget {
  const PromoBannerApprovalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.primaryText,
        title: Text(l10n.promoBannerApprovals, style: AppTextStyles.labelLarge),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.getPendingPromoBannersStream(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    l10n.promoNoPendingBanners,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              itemCount: docs.length,
              itemBuilder: (context, i) =>
                  _BannerReviewCard(id: docs[i].id, data: docs[i].data()),
            );
          },
        ),
      ),
    );
  }
}

class _BannerReviewCard extends StatefulWidget {
  final String id;
  final Map<String, dynamic> data;
  const _BannerReviewCard({required this.id, required this.data});

  @override
  State<_BannerReviewCard> createState() => _BannerReviewCardState();
}

class _BannerReviewCardState extends State<_BannerReviewCard> {
  bool _busy = false;

  Future<void> _approve() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      await FirestoreService.approvePromoBanner(widget.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.promoBannerApproved)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _reject() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text(l10n.promoReject, style: AppTextStyles.headingSmall),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: l10n.promoRejectReasonHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.promoReject,
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      await FirestoreService.rejectPromoBanner(
        widget.id,
        reason: controller.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.promoBannerRejected)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final boutiqueName = widget.data['boutiqueName']?.toString() ?? '';
    final imageUrl = widget.data['bannerImageUrl']?.toString() ?? '';
    final price = (widget.data['priceKwd'] as num?)?.toDouble();

    final dayStart = widget.data['dayStart'];
    final dayEnd = widget.data['dayEnd'];
    String window = '';
    if (dayStart is Timestamp && dayEnd is Timestamp) {
      final start = dayStart.toDate();
      final lastDay = dayEnd.toDate().subtract(const Duration(days: 1));
      window =
          '${DateFormat('EEE d', locale).format(start)} – ${DateFormat('EEE d MMM', locale).format(lastDay)}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: AppColors.imagePlaceholder,
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover)
                  : const Center(
                      child: Icon(Icons.image_not_supported_outlined,
                          color: AppColors.softAccent),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(boutiqueName, style: AppTextStyles.bodyLarge),
                const SizedBox(height: 4),
                if (window.isNotEmpty)
                  Text(window,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.secondaryText)),
                if (price != null)
                  Text(
                    l10n.promoPriceKwd(price.toStringAsFixed(3)),
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.secondaryText),
                  ),
                const SizedBox(height: 14),
                if (_busy)
                  const Center(child: CircularProgressIndicator())
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _reject,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.secondaryText,
                            side: BorderSide(color: AppColors.border),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                          child: Text(l10n.promoReject),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _approve,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.deepAccent,
                            foregroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                          child: Text(l10n.promoApprove),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
