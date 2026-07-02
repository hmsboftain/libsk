import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';
import 'category_products_page.dart';

// Localized display label for a category. Existing categories stay in English
// (their Firestore keys), while the new launch categories carry translations.
String _labelForCategory(String? key, String label, AppLocalizations l10n) {
  switch (key) {
    case 'Swimwear':
      return l10n.categorySwimwear;
    case 'Accessories':
      return l10n.categoryAccessories;
    default:
      return label;
  }
}

class CategoryBrowsePage extends StatelessWidget {
  const CategoryBrowsePage({super.key});

  static const List<Map<String, String?>> categories = [
    {'label': 'All', 'key': null},
    {'label': 'Abaya', 'key': 'Abaya'},
    {'label': 'Accessories', 'key': 'Accessories'},
    {'label': 'Blazers', 'key': 'Blazers'},
    {'label': 'Blouses & Shirts', 'key': 'Blouses & Shirts'},
    {'label': 'Casual Wear', 'key': 'Casual Wear'},
    {'label': 'Coats', 'key': 'Coats'},
    {'label': 'Dresses', 'key': 'Dresses'},
    {'label': "Dra'a", 'key': "Dra'a"},
    {'label': 'Gowns', 'key': 'Gowns'},
    {'label': 'Jackets', 'key': 'Jackets'},
    {'label': 'Jumpsuits', 'key': 'Jumpsuits'},
    {'label': 'Office Attire', 'key': 'Office Attire'},
    {'label': 'Pants', 'key': 'Pants'},
    {'label': 'Shoes', 'key': 'Shoes'},
    {'label': 'Skirts', 'key': 'Skirts'},
    {'label': 'Swimwear', 'key': 'Swimwear'},
    {'label': 'Tops', 'key': 'Tops'},
  ];

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppHeader(),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Title ──────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                      child: Text(
                        l10n.browse,
                        style: AppTextStyles.displayMedium,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        l10n.shopByCategoryAcrossAllBoutiques,
                        style: AppTextStyles.bodySmall,
                      ),
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(color: AppColors.border, thickness: 0.5),
                    ),

                    const SizedBox(height: 16),

                    // ── Category grid ───────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: categories.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1.05,
                            ),
                        itemBuilder: (context, index) {
                          final cat = categories[index];
                          final key = cat['key'];
                          return _CategoryTile(
                            label: _labelForCategory(key, cat['label']!, l10n),
                            categoryKey: key,
                            allProductsLabel: l10n.allProducts,
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 30),
                  ],
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

class _CategoryTile extends StatelessWidget {
  final String label;
  final String? categoryKey;
  final String allProductsLabel;

  const _CategoryTile({
    required this.label,
    required this.categoryKey,
    required this.allProductsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isAll = categoryKey == null;
    // "All" reads as the emphasized chip (filled Taupe); every other category
    // is an outline chip with just its label centered.
    final Color bg = isAll ? AppColors.deepAccent : Colors.transparent;
    final Color borderColor = isAll ? AppColors.deepAccent : AppColors.border;
    final Color contentColor = isAll ? Colors.white : AppColors.primaryText;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CategoryProductsPage(
              category: categoryKey,
              displayLabel: isAll ? allProductsLabel : label,
            ),
          ),
        );
      },
      child: Container(
        // Chip style: 0.5px border, no radius, ~12px / 10px padding.
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: borderColor, width: 0.5),
        ),
        alignment: Alignment.center,
        child: Text(
          isAll ? allProductsLabel : label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.labelSmall.copyWith(
            color: contentColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
