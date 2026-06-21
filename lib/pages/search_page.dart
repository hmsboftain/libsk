import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:libsk/l10n/app_localizations.dart';

import '../config/algolia_config.dart';
import '../navigation/app_header.dart';
import '../widgets/product_badges.dart';
import '../widgets/theme.dart';
import 'boutique_storefront_page.dart';
import 'product_page.dart';

// ── Pure helpers ──────────────────────────────────────────────────────────────

Widget _emptyState({required IconData icon, required String message}) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 44, color: AppColors.softAccent),
        const SizedBox(height: 12),
        Text(
          message,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.secondaryText,
          ),
        ),
      ],
    ),
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _queryController = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _productResults = [];
  List<Map<String, dynamic>> _boutiqueResults = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _queryController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _productResults = [];
        _boutiqueResults = [];
        _hasSearched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (!AlgoliaConfig.isConfigured) {
      if (!mounted) return;
      setState(() {
        _productResults = [];
        _boutiqueResults = [];
        _hasSearched = true;
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _algoliaSearch('products', query),
        _algoliaSearch('boutiques', query),
      ]);
      if (!mounted) return;
      setState(() {
        _productResults = results[0];
        _boutiqueResults = results[1];
        _hasSearched = true;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _algoliaSearch(
    String index,
    String query,
  ) async {
    final url =
        'https://${AlgoliaConfig.appId}-dsn.algolia.net/1/indexes/$index/query';
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'X-Algolia-Application-Id': AlgoliaConfig.appId,
        'X-Algolia-API-Key': AlgoliaConfig.searchKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'query': query, 'hitsPerPage': 30}),
    );
    if (response.statusCode != 200) return [];
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final hits = data['hits'] as List<dynamic>? ?? [];
    return hits.map((h) => Map<String, dynamic>.from(h as Map)).toList();
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

            // ── Search bar ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.field,
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        Icons.search,
                        size: 20,
                        color: AppColors.softAccent,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _queryController,
                        autofocus: true,
                        onChanged: _onQueryChanged,
                        style: AppTextStyles.bodyMedium,
                        decoration: InputDecoration(
                          hintText: l10n.searchHint,
                          hintStyle: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.secondaryText,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    if (_queryController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _queryController.clear();
                          _onQueryChanged('');
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Icon(
                            Icons.close,
                            size: 18,
                            color: AppColors.softAccent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Tabs ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TabBar(
                controller: _tabController,
                labelStyle: AppTextStyles.capsLabel.copyWith(fontSize: 11),
                unselectedLabelStyle: AppTextStyles.capsLabel.copyWith(
                  fontSize: 11,
                ),
                labelColor: AppColors.primaryText,
                unselectedLabelColor: AppColors.softAccent,
                indicatorColor: AppColors.deepAccent,
                indicatorWeight: 1.5,
                dividerColor: AppColors.border,
                tabs: [
                  Tab(
                    text: _hasSearched
                        ? l10n.productsTabWithCount(_productResults.length)
                        : l10n.productsTab,
                  ),
                  Tab(
                    text: _hasSearched
                        ? l10n.boutiquesTabWithCount(_boutiqueResults.length)
                        : l10n.boutiquesTab,
                  ),
                ],
              ),
            ),

            // ── Results ───────────────────────────────────────────
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                        strokeWidth: 1.5,
                      ),
                    )
                  : !_hasSearched
                  ? _emptyState(
                      icon: Icons.search_outlined,
                      message: l10n.searchForProductsOrBoutiques,
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildProductResults(l10n),
                        _buildBoutiqueResults(l10n),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductResults(AppLocalizations l10n) {
    if (_productResults.isEmpty) {
      return _emptyState(
        icon: Icons.search_off_outlined,
        message: l10n.noProductsFound,
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
      itemCount: _productResults.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.58,
      ),
      itemBuilder: (context, index) =>
          _SearchProductCard(hit: _productResults[index]),
    );
  }

  Widget _buildBoutiqueResults(AppLocalizations l10n) {
    if (_boutiqueResults.isEmpty) {
      return _emptyState(
        icon: Icons.storefront_outlined,
        message: l10n.noBoutiquesFound,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
      itemCount: _boutiqueResults.length,
      itemBuilder: (context, index) =>
          _SearchBoutiqueCard(hit: _boutiqueResults[index]),
    );
  }
}

// ── Search product card widget ────────────────────────────────────────────────

class _SearchProductCard extends StatelessWidget {
  final Map<String, dynamic> hit;

  const _SearchProductCard({required this.hit});

  @override
  Widget build(BuildContext context) {
    final productId =
        hit['productId']?.toString() ?? hit['objectID']?.toString() ?? '';
    final boutiqueId = hit['boutiqueId']?.toString() ?? '';
    final title = hit['title']?.toString() ?? '';
    final description = hit['description']?.toString() ?? '';
    final boutiqueName = hit['boutiqueName']?.toString() ?? '';
    final imageUrl = hit['imageUrl']?.toString() ?? '';
    final imageUrlsData = hit['imageUrls'];
    final List<String> imageUrls = imageUrlsData is List
        ? imageUrlsData.map((e) => e.toString()).toList()
        : imageUrl.isNotEmpty
        ? [imageUrl]
        : [];
    final displayImageUrl = imageUrls.isNotEmpty ? imageUrls.first : imageUrl;
    final priceVal = hit['price'] ?? 0;
    final double price = priceVal is num
        ? priceVal.toDouble()
        : double.tryParse(priceVal.toString()) ?? 0;
    final stockVal = hit['stock'] ?? 0;
    final int stock = stockVal is int
        ? stockVal
        : int.tryParse(stockVal.toString()) ?? 0;
    final saleVal = hit['salePrice'];
    final double? salePrice = saleVal is num
        ? saleVal.toDouble()
        : double.tryParse(saleVal?.toString() ?? '');
    final soldOut = stock <= 0 || hit['isOutOfStock'] == true;
    final sizesData = hit['sizes'];
    final sizes = sizesData is List
        ? sizesData.map((e) => e.toString()).toList()
        : <String>[];

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductPage(
            productId: productId,
            boutiqueId: boutiqueId,
            imageUrl: displayImageUrl,
            imageUrls: imageUrls,
            title: title,
            price: price,
            description: description,
            sizes: sizes,
            stock: stock,
            boutiqueName: boutiqueName,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.imagePlaceholder,
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: displayImageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: displayImageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              size: 24,
                              color: AppColors.softAccent,
                            ),
                          ),
                        )
                      : const Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 24,
                            color: AppColors.softAccent,
                          ),
                        ),
                ),
                if (soldOut)
                  OutOfStockOverlay(
                    label: AppLocalizations.of(context)!.outOfStock,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            boutiqueName.toUpperCase(),
            style: AppTextStyles.capsLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: AppTextStyles.headingSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 5),
          ProductPriceText(
            price: price,
            salePrice: salePrice,
            saleBadgeLabel: AppLocalizations.of(context)!.saleBadge,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Search boutique card widget ───────────────────────────────────────────────

class _SearchBoutiqueCard extends StatelessWidget {
  final Map<String, dynamic> hit;

  const _SearchBoutiqueCard({required this.hit});

  @override
  Widget build(BuildContext context) {
    final boutiqueId =
        hit['boutiqueId']?.toString() ?? hit['objectID']?.toString() ?? '';
    final name = hit['name']?.toString() ?? '';
    final description = hit['description']?.toString() ?? '';
    final logoPath = hit['logoPath']?.toString() ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'B';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BoutiqueStorefrontPage(boutiqueId: boutiqueId),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              color: AppColors.imagePlaceholder,
              child: logoPath.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: logoPath,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Center(
                        child: Text(
                          initial,
                          style: AppTextStyles.headingMedium,
                        ),
                      ),
                    )
                  : Center(
                      child: Text(initial, style: AppTextStyles.headingMedium),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppTextStyles.bodyLarge),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: AppTextStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 12,
              color: AppColors.softAccent,
            ),
          ],
        ),
      ),
    );
  }
}
