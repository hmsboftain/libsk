import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import 'global_order_details_page.dart';
import '../widgets/theme.dart';
import '../core/constants/countries.dart';
import '../services/currency_service.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

// ── Pure helpers ──────────────────────────────────────────────────────────────

String _parseOrderNumber(Map<String, dynamic> data, AppLocalizations l10n) {
  final v = data['orderNumber']?.toString().trim() ?? '';
  return v.isNotEmpty ? v : l10n.unknownOrder;
}

String _parseCustomerName(Map<String, dynamic> data, AppLocalizations l10n) {
  final v = data['customerName']?.toString().trim() ?? '';
  return v.isNotEmpty ? v : l10n.unknownCustomer;
}

String _parseCustomerEmail(Map<String, dynamic> data, AppLocalizations l10n) {
  final v = data['customerEmail']?.toString().trim() ?? '';
  return v.isNotEmpty ? v : l10n.noEmail;
}

String _parseStatus(Map<String, dynamic> data, AppLocalizations l10n) {
  final v = data['status']?.toString().trim() ?? '';
  return v.isNotEmpty ? _localizedStatus(v, l10n) : l10n.unknown;
}

String _parseDate(Map<String, dynamic> data, AppLocalizations l10n) {
  final v = data['date']?.toString().trim() ?? '';
  return v.isNotEmpty ? v : l10n.noDate;
}

String _parseTotal(Map<String, dynamic> data) {
  final v = data['total'] ?? 0;
  final amount = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
  return _fmt(amount);
}

String _parseItemCount(Map<String, dynamic> data) {
  final v = data['itemCount'] ?? 0;
  if (v is int) return v.toString();
  return int.tryParse(v.toString())?.toString() ?? '0';
}

// Search against raw Firestore values — not localized fallbacks
bool _matchesSearch(Map<String, dynamic> data, String query) {
  if (query.trim().isEmpty) return true;
  final q = query.toLowerCase();
  final orderNumber = data['orderNumber']?.toString().toLowerCase() ?? '';
  final customerName = data['customerName']?.toString().toLowerCase() ?? '';
  final customerEmail = data['customerEmail']?.toString().toLowerCase() ?? '';
  return orderNumber.contains(q) ||
      customerName.contains(q) ||
      customerEmail.contains(q);
}

String _localizedStatus(String status, AppLocalizations l10n) {
  switch (status.toLowerCase()) {
    case 'placed':
      return l10n.statusPlaced;
    case 'confirmed':
      return l10n.statusConfirmed;
    case 'on the way':
      return l10n.statusOnTheWay;
    case 'delivered':
      return l10n.statusDelivered;
    case 'cancelled':
      return l10n.statusCancelled;
    default:
      return status;
  }
}

// ── Page ──────────────────────────────────────────────────────────────────────

class GlobalOrdersPage extends StatefulWidget {
  const GlobalOrdersPage({super.key});

  @override
  State<GlobalOrdersPage> createState() => _GlobalOrdersPageState();
}

class _GlobalOrdersPageState extends State<GlobalOrdersPage> {
  final searchController = TextEditingController();
  bool _showSearch = false;
  String _searchQuery = '';

  late final Future<QuerySnapshot<Map<String, dynamic>>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _ordersFuture = FirestoreService.getGlobalOrdersOnce();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      if (_showSearch) {
        _showSearch = false;
        _searchQuery = '';
        searchController.clear();
      } else {
        _showSearch = true;
      }
    });
  }

  Widget _buildSearchField(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: TextField(
        controller: searchController,
        onChanged: (value) => setState(() => _searchQuery = value.trim()),
        decoration: InputDecoration(
          hintText: l10n.searchOrders,
          prefixIcon: const Icon(Icons.search, color: AppColors.deepAccent),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, color: AppColors.deepAccent),
                  onPressed: () => setState(() {
                    searchController.clear();
                    _searchQuery = '';
                  }),
                )
              : null,
          filled: true,
          fillColor: AppColors.field,
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.secondaryText,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppColors.border, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppColors.border, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide:
                const BorderSide(color: AppColors.deepAccent, width: 1),
          ),
        ),
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
              child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                future: _ordersFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        l10n.failedToLoadOrders,
                        style: AppTextStyles.bodyMedium,
                      ),
                    );
                  }

                  final allDocs = snapshot.data?.docs ?? [];
                  final orderDocs = allDocs
                      .where((doc) => _matchesSearch(doc.data(), _searchQuery))
                      .toList();

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.globalOrders,
                                style: AppTextStyles.displayMedium,
                              ),
                            ),
                            IconButton(
                              onPressed: _toggleSearch,
                              icon: Icon(
                                _showSearch ? Icons.close : Icons.search,
                                color: AppColors.primaryText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.globalOrdersCount(orderDocs.length),
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.secondaryText,
                          ),
                        ),
                        if (_showSearch) _buildSearchField(l10n),
                        const SizedBox(height: 20),
                        if (orderDocs.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              border: Border.all(
                                color: AppColors.border,
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              _searchQuery.isEmpty
                                  ? l10n.noOrdersFound
                                  : l10n.noMatchingOrdersFound,
                              style: AppTextStyles.bodyMedium,
                            ),
                          )
                        else
                          ...orderDocs.map((doc) {
                            final data = doc.data();
                            return _GlobalOrderCard(
                              orderId: doc.id,
                              data: data,
                            );
                          }),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Global order card widget ──────────────────────────────────────────────────

class _GlobalOrderCard extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> data;

  const _GlobalOrderCard({required this.orderId, required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final orderNumber = _parseOrderNumber(data, l10n);
    final customerName = _parseCustomerName(data, l10n);
    final customerEmail = _parseCustomerEmail(data, l10n);
    final status = _parseStatus(data, l10n);
    final total = _parseTotal(data);
    final date = _parseDate(data, l10n);
    final itemCount = _parseItemCount(data);

    return InkWell(
      borderRadius: BorderRadius.zero,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GlobalOrderDetailsPage(
            orderData: data,
            orderId: orderId,
          ),
        ),
      ),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.receipt_long_outlined,
                  color: AppColors.deepAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    orderNumber,
                    style: AppTextStyles.bodyLarge
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  total,
                  style: AppTextStyles.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              customerName,
              style:
                  AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(customerEmail, style: AppTextStyles.bodySmall),
            const SizedBox(height: 10),
            Text(l10n.statusLabel(status), style: AppTextStyles.bodySmall),
            const SizedBox(height: 4),
            Text(l10n.orderDate(date), style: AppTextStyles.bodySmall),
            const SizedBox(height: 4),
            Text(l10n.itemsLabel(itemCount), style: AppTextStyles.bodySmall),
          ],
        ),
      ),
    );
  }
}