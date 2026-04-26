import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import 'global_order_details_page.dart';
import '../widgets/theme.dart';

class GlobalOrdersPage extends StatefulWidget {
  const GlobalOrdersPage({super.key});

  @override
  State<GlobalOrdersPage> createState() => _GlobalOrdersPageState();
}

class _GlobalOrdersPageState extends State<GlobalOrdersPage> {
  final TextEditingController searchController = TextEditingController();
  bool showSearch = false;
  String searchQuery = '';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  String _buildOrderNumber(Map<String, dynamic> data) {
    final value = data['orderNumber']?.toString().trim() ?? '';
    return value.isNotEmpty ? value : 'Unknown Order';
  }

  String _buildCustomerName(Map<String, dynamic> data) {
    final value = data['customerName']?.toString().trim() ?? '';
    return value.isNotEmpty ? value : 'Unknown Customer';
  }

  String _buildCustomerEmail(Map<String, dynamic> data) {
    final value = data['customerEmail']?.toString().trim() ?? '';
    return value.isNotEmpty ? value : 'No email';
  }

  String _buildStatus(Map<String, dynamic> data) {
    final value = data['status']?.toString().trim() ?? '';
    return value.isNotEmpty ? value : 'Unknown';
  }

  String _buildDate(Map<String, dynamic> data) {
    final value = data['date']?.toString().trim() ?? '';
    return value.isNotEmpty ? value : 'No date';
  }

  String _buildTotal(Map<String, dynamic> data) {
    final value = data['total'] ?? 0;

    if (value is num) {
      return '${value.toStringAsFixed(0)} KWD';
    }

    final parsed = double.tryParse(value.toString()) ?? 0;
    return '${parsed.toStringAsFixed(0)} KWD';
  }

  String _buildItemCount(Map<String, dynamic> data) {
    final value = data['itemCount'] ?? 0;

    if (value is int) return value.toString();
    return int.tryParse(value.toString())?.toString() ?? '0';
  }

  bool _matchesSearch(Map<String, dynamic> data) {
    if (searchQuery.trim().isEmpty) return true;

    final query = searchQuery.toLowerCase();

    final orderNumber = _buildOrderNumber(data).toLowerCase();
    final customerName = _buildCustomerName(data).toLowerCase();
    final customerEmail = _buildCustomerEmail(data).toLowerCase();

    return orderNumber.contains(query) ||
        customerName.contains(query) ||
        customerEmail.contains(query);
  }

  void _toggleSearch() {
    setState(() {
      if (showSearch) {
        showSearch = false;
        searchQuery = '';
        searchController.clear();
      } else {
        showSearch = true;
      }
    });
  }

  Widget buildOrderCard({
    required BuildContext context,
    required String orderId,
    required Map<String, dynamic> data,
    required String orderNumber,
    required String customerName,
    required String customerEmail,
    required String status,
    required String total,
    required String date,
    required String itemCount,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GlobalOrderDetailsPage(
              orderData: data,
              orderId: orderId,
            ),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                    ),
                  ),
                ),
                Text(
                  total,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              customerName,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              customerEmail,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Status: $status',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Date: $date',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Items: $itemCount',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: TextField(
        controller: searchController,
        onChanged: (value) {
          setState(() {
            searchQuery = value.trim();
          });
        },
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                searchController.clear();
                searchQuery = '';
              });
            },
          )
              : null,
          filled: true,
          fillColor: AppColors.field,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.black),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirestoreService.getGlobalOrdersStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'Failed to load orders',
                        style: TextStyle(color: AppColors.secondaryText),
                      ),
                    );
                  }

                  final allDocs = snapshot.data?.docs ?? [];
                  final orderDocs = allDocs.where((doc) {
                    return _matchesSearch(doc.data());
                  }).toList();

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'GLOBAL ORDERS',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryText,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _toggleSearch,
                              icon: Icon(
                                showSearch ? Icons.close : Icons.search,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${orderDocs.length} global orders',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.secondaryText,
                          ),
                        ),
                        if (showSearch) _buildSearchField(),
                        const SizedBox(height: 20),
                        if (orderDocs.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              searchQuery.isEmpty
                                  ? 'No orders found.'
                                  : 'No matching orders found.',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          )
                        else
                          ...orderDocs.map((doc) {
                            final data = doc.data();

                            return buildOrderCard(
                              context: context,
                              orderId: doc.id,
                              data: data,
                              orderNumber: _buildOrderNumber(data),
                              customerName: _buildCustomerName(data),
                              customerEmail: _buildCustomerEmail(data),
                              status: _buildStatus(data),
                              total: _buildTotal(data),
                              date: _buildDate(data),
                              itemCount: _buildItemCount(data),
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