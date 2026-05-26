import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/algolia_config.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';
import 'product_page.dart';
import 'boutique_storefront_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _queryController = TextEditingController();
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
    } catch (e) {
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
                          hintText: 'Search products, boutiques...',
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
                        ? 'PRODUCTS (${_productResults.length})'
                        : 'PRODUCTS',
                  ),
                  Tab(
                    text: _hasSearched
                        ? 'BOUTIQUES (${_boutiqueResults.length})'
                        : 'BOUTIQUES',
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
                      message: 'Search for products or boutiques',
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildProductResults(),
                        _buildBoutiqueResults(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

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

  Widget _buildProductResults() {
    if (_productResults.isEmpty) {
      return _emptyState(
        icon: Icons.search_off_outlined,
        message: 'No products found',
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
      itemBuilder: (context, index) {
        final hit = _productResults[index];
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
        final displayImageUrl = imageUrls.isNotEmpty
            ? imageUrls.first
            : imageUrl;
        final priceVal = hit['price'] ?? 0;
        final double price = priceVal is num
            ? priceVal.toDouble()
            : double.tryParse(priceVal.toString()) ?? 0;
        final stockVal = hit['stock'] ?? 0;
        final int stock = stockVal is int
            ? stockVal
            : int.tryParse(stockVal.toString()) ?? 0;
        final sizesData = hit['sizes'];
        final List<String> sizes = sizesData is List
            ? sizesData.map((e) => e.toString()).toList()
            : [];

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
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.imagePlaceholder,
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: displayImageUrl.isNotEmpty
                      ? Image.network(
                          displayImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
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
              Text(
                'KD ${price.toStringAsFixed(0)}',
                style: AppTextStyles.labelLarge,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBoutiqueResults() {
    if (_boutiqueResults.isEmpty) {
      return _emptyState(
        icon: Icons.storefront_outlined,
        message: 'No boutiques found',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
      itemCount: _boutiqueResults.length,
      itemBuilder: (context, index) {
        final hit = _boutiqueResults[index];
        final boutiqueId =
            hit['boutiqueId']?.toString() ?? hit['objectID']?.toString() ?? '';
        final name = hit['name']?.toString() ?? '';
        final description = hit['description']?.toString() ?? '';
        final logoPath = hit['logoPath']?.toString() ?? '';

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
                      ? Image.network(
                          logoPath,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'B',
                              style: AppTextStyles.headingMedium,
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'B',
                            style: AppTextStyles.headingMedium,
                          ),
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
      },
    );
  }
}
