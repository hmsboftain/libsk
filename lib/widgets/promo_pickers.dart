import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';

import '../core/constants/app_categories.dart';
import '../core/utils/image_sizing.dart';
import '../services/firestore_service.dart';
import 'theme.dart';

/// A product the owner chose to promote, reduced to what the booking flow shows.
class PromoProductRef {
  final String id;
  final String title;
  final String imageUrl;
  final double price;

  const PromoProductRef({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.price,
  });
}

/// Full-page picker over the boutique's OWN products (never manual id entry).
/// Enforces [minSelection]..[maxSelection]; with [categoryFilter] set it shows
/// only products in that category (used by top_of_category). Pops a
/// `List<PromoProductRef>` on confirm, or null on back.
class PromoProductPickerPage extends StatefulWidget {
  final String boutiqueId;
  final String title;
  final int minSelection;
  final int maxSelection;
  final String? categoryFilter;

  /// Products already chosen — seeded with their FULL refs (not just ids) so
  /// reopening the picker to adjust a selection preserves each product's title/
  /// image/price instead of returning a blank placeholder.
  final List<PromoProductRef> initialSelected;

  const PromoProductPickerPage({
    super.key,
    required this.boutiqueId,
    required this.title,
    this.minSelection = 1,
    this.maxSelection = 1,
    this.categoryFilter,
    this.initialSelected = const [],
  });

  @override
  State<PromoProductPickerPage> createState() => _PromoProductPickerPageState();
}

class _PromoProductPickerPageState extends State<PromoProductPickerPage> {
  final Map<String, PromoProductRef> _selected = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    for (final ref in widget.initialSelected) {
      _selected[ref.id] = ref;
    }
  }

  void _toggle(PromoProductRef ref) {
    setState(() {
      if (_selected.containsKey(ref.id)) {
        // Already picked → tapping again removes it (the Map also guarantees the
        // same product can never be added twice).
        _selected.remove(ref.id);
      } else if (widget.maxSelection == 1) {
        _selected
          ..clear()
          ..[ref.id] = ref;
      } else if (_selected.length < widget.maxSelection) {
        _selected[ref.id] = ref;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canConfirm = _selected.length >= widget.minSelection &&
        _selected.length <= widget.maxSelection;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.primaryText,
        title: Text(widget.title, style: AppTextStyles.labelLarge),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: l10n.promoSearchProducts,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.field,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirestoreService.getOwnerProductsStream(widget.boutiqueId),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data?.docs ?? [];
                  final items = docs.where((d) {
                    final data = d.data();
                    if (widget.categoryFilter != null) {
                      final cats = (data['category'] as List?)
                              ?.map((e) => e.toString())
                              .toList() ??
                          const [];
                      if (!cats.contains(widget.categoryFilter)) return false;
                    }
                    if (_query.isEmpty) return true;
                    return (data['title']?.toString().toLowerCase() ?? '')
                        .contains(_query);
                  }).toList();

                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          l10n.promoNoProducts,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.62,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final data = items[i].data();
                      final ref = PromoProductRef(
                        id: items[i].id,
                        title: data['title']?.toString() ?? '',
                        imageUrl: data['imageUrl']?.toString() ?? '',
                        price: (data['price'] as num?)?.toDouble() ?? 0,
                      );
                      final isSelected = _selected.containsKey(ref.id);
                      // At the limit, unselected products are disabled so it's
                      // clear you must remove one before adding another.
                      final atMax = _selected.length >= widget.maxSelection;
                      final disabled = !isSelected && widget.maxSelection > 1 && atMax;
                      return _ProductTile(
                        ref: ref,
                        selected: isSelected,
                        disabled: disabled,
                        onTap: disabled ? null : () => _toggle(ref),
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: canConfirm
                        ? () => Navigator.of(context).pop(_selected.values.toList())
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.deepAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.softAccent,
                      disabledForegroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    child: Text(
                      widget.maxSelection == 1
                          ? l10n.promoSelectProduct
                          : l10n.promoSelectCount(_selected.length),
                      style: AppTextStyles.button,
                    ),
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

class _ProductTile extends StatelessWidget {
  final PromoProductRef ref;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const _ProductTile({
    required this.ref,
    required this.selected,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(
              color: selected ? AppColors.deepAccent : AppColors.border,
              width: selected ? 1.5 : 0.5,
            ),
          ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: AppColors.imagePlaceholder,
                      child: ref.imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: ref.imageUrl,
                              memCacheWidth: gridTileCacheWidth,
                              maxWidthDiskCache: maxImageDiskCacheWidth,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Center(
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: AppColors.softAccent,
                                ),
                              ),
                            )
                          : const Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: AppColors.softAccent,
                              ),
                            ),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: AppColors.deepAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Text(
                ref.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Text(
                ref.price.toStringAsFixed(3),
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.secondaryText,
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

/// Picks exactly one category from the canonical list. Pops the category name
/// (String) or null. Kept trivial because top_of_category products are then
/// filtered to the chosen category by [PromoProductPickerPage].
class PromoCategoryPickerPage extends StatelessWidget {
  final String title;
  final String? selected;

  const PromoCategoryPickerPage({super.key, required this.title, this.selected});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.primaryText,
        title: Text(title, style: AppTextStyles.labelLarge),
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: AppCategories.all.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: AppColors.border),
          itemBuilder: (context, i) {
            final cat = AppCategories.all[i];
            return ListTile(
              title: Text(cat, style: AppTextStyles.bodyMedium),
              trailing: cat == selected
                  ? const Icon(Icons.check, color: AppColors.deepAccent, size: 20)
                  : null,
              onTap: () => Navigator.of(context).pop(cat),
            );
          },
        ),
      ),
    );
  }
}
