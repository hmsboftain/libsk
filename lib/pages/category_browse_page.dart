import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';
import 'category_products_page.dart';

class CategoryBrowsePage extends StatelessWidget {
  const CategoryBrowsePage({super.key});

  static const List<Map<String, String?>> categories = [
    {'label': 'All', 'key': null},
    {'label': 'Abaya', 'key': 'Abaya'},
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
    {'label': 'Tops', 'key': 'Tops'},
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppHeader(),
            Expanded(
              child: SingleChildScrollView(
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
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1.4,
                            ),
                        itemBuilder: (context, index) {
                          final cat = categories[index];
                          return _CategoryTile(
                            label: cat['label']!,
                            categoryKey: cat['key'],
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
    );
  }
}

class _CategoryTile extends StatefulWidget {
  final String label;
  final String? categoryKey;
  final String allProductsLabel;

  const _CategoryTile({
    required this.label,
    required this.categoryKey,
    required this.allProductsLabel,
  });

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile> {
  // categoryKey -> thumbnail URL ('' = no thumbnail). Static so it survives
  // page re-opens and is shared across tiles: one .get() per category per app
  // session, replacing a per-tile real-time listener.
  static final Map<String, String> _thumbCache = {};

  String _bgImageUrl = '';

  @override
  void initState() {
    super.initState();
    final key = widget.categoryKey;
    if (key != null) _loadThumb(key);
  }

  Future<void> _loadThumb(String key) async {
    final cached = _thumbCache[key];
    if (cached != null) {
      _bgImageUrl = cached;
      return; // already resolved this session — no read, no setState needed
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collectionGroup('products')
          .where('category', arrayContains: key)
          .limit(1)
          .get();
      var url = '';
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        final imageUrlsData = data['imageUrls'];
        if (imageUrlsData is List && imageUrlsData.isNotEmpty) {
          url = imageUrlsData.first.toString();
        } else {
          url = data['imageUrl']?.toString() ?? '';
        }
      }
      _thumbCache[key] = url;
      if (!mounted) return;
      setState(() => _bgImageUrl = url);
    } catch (_) {
      // Leave the placeholder background on error.
    }
  }

  @override
  Widget build(BuildContext context) {
    // "All" tile — no Firestore query needed
    if (widget.categoryKey == null) {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CategoryProductsPage(
                category: null,
                displayLabel: widget.allProductsLabel,
              ),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.deepAccent,
            border: Border.all(color: AppColors.deepAccent, width: 0.5),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.deepAccent, AppColors.softAccent],
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Text(
                  'All',
                  style: AppTextStyles.headingSmall.copyWith(
                    color: Colors.white,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CategoryProductsPage(
              category: widget.categoryKey,
              displayLabel: widget.label,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.imagePlaceholder,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_bgImageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: _bgImageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox(),
              ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black45],
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Text(
                widget.label,
                style: AppTextStyles.headingSmall.copyWith(
                  color: Colors.white,
                  fontStyle: FontStyle.italic,
                  shadows: [
                    const Shadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, 1),
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
