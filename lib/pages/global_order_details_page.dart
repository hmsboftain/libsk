import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';

class GlobalOrderDetailsPage extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final String orderId;

  const GlobalOrderDetailsPage({
    super.key,
    required this.orderData,
    required this.orderId,
  });

  @override
  State<GlobalOrderDetailsPage> createState() => _GlobalOrderDetailsPageState();
}

class _GlobalOrderDetailsPageState extends State<GlobalOrderDetailsPage> {
  static const backgroundColor = AppColors.background;
  static const cardColor = AppColors.card;
  static const borderColor = AppColors.border;
  static const primaryText = AppColors.primaryText;
  static const secondaryText = AppColors.secondaryText;
  static const deepAccent = AppColors.deepAccent;

  late String _currentStatus;
  bool _isUpdating = false;

  final List<String> _statusOptions = [
    'Placed',
    'Confirmed',
    'On the Way',
    'Delivered',
    'Cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.orderData['status']?.toString() ?? 'Placed';
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _isUpdating = true);

    try {
      // Update in global_orders
      await FirebaseFirestore.instance
          .collection('global_orders')
          .doc(widget.orderId)
          .update({'status': newStatus});

      // Update in user's orders collection
      final customerUid = widget.orderData['customerUid']?.toString() ?? '';
      final sourceUserOrderId = widget.orderData['sourceUserOrderId']?.toString() ?? '';

      if (customerUid.isNotEmpty && sourceUserOrderId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(customerUid)
            .collection('orders')
            .doc(sourceUserOrderId)
            .update({'status': newStatus});
      }

      // Update in boutique orders
      final items = widget.orderData['items'];
      if (items is List) {
        final boutiqueIds = <String>{};
        for (final item in items) {
          final boutiqueId = item['boutiqueId']?.toString() ?? '';
          if (boutiqueId.isNotEmpty) boutiqueIds.add(boutiqueId);
        }

        for (final boutiqueId in boutiqueIds) {
          final boutiqueOrders = await FirebaseFirestore.instance
              .collection('boutiques')
              .doc(boutiqueId)
              .collection('orders')
              .where('sourceUserOrderId', isEqualTo: sourceUserOrderId)
              .get();

          for (final doc in boutiqueOrders.docs) {
            await doc.reference.update({'status': newStatus});
          }
        }
      }

      if (!mounted) return;
      setState(() => _currentStatus = newStatus);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order status updated to $newStatus'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update status')),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'placed':
        return AppColors.deepAccent;
      case 'confirmed':
        return const Color(0xFF5B8DB8);
      case 'on the way':
        return const Color(0xFFB87D3B);
      case 'delivered':
        return const Color(0xFF3D6B45);
      case 'cancelled':
        return const Color(0xFF9B4A4A);
      default:
        return AppColors.secondaryText;
    }
  }

  Color _statusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'placed':
        return AppColors.softAccent.withOpacity(0.35);
      case 'confirmed':
        return const Color(0xFFE8F0F8);
      case 'on the way':
        return const Color(0xFFF8F0E4);
      case 'delivered':
        return const Color(0xFFE8F2EA);
      case 'cancelled':
        return const Color(0xFFF7E8E8);
      default:
        return AppColors.field;
    }
  }

  String _buildTextValue(dynamic value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isNotEmpty ? text : fallback;
  }

  String _buildTotal(dynamic value) {
    if (value is num) return '${value.toStringAsFixed(0)} KWD';
    final parsed = double.tryParse(value.toString()) ?? 0;
    return '${parsed.toStringAsFixed(0)} KWD';
  }

  String _buildItemCount(dynamic value) {
    if (value is int) return value.toString();
    return int.tryParse(value.toString())?.toString() ?? '0';
  }

  Widget buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: primaryText,
      ),
    );
  }

  Widget buildInfoBox({required String label, required String value}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: secondaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              color: primaryText,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildItemCard(Map<String, dynamic> item) {
    final title = _buildTextValue(item['title'], 'Untitled Product');
    final description = _buildTextValue(item['description'], 'No description');
    final size = _buildTextValue(item['size'], 'No size');
    final imageUrl = _buildTextValue(item['imageUrl'], '');
    final boutiqueId = _buildTextValue(item['boutiqueId'], 'Unknown Boutique');

    final quantityValue = item['quantity'] ?? 0;
    final priceValue = item['price'] ?? 0;

    final int quantity = quantityValue is int
        ? quantityValue
        : int.tryParse(quantityValue.toString()) ?? 0;

    final double price = priceValue is num
        ? priceValue.toDouble()
        : double.tryParse(priceValue.toString()) ?? 0;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 76,
            height: 92,
            decoration: BoxDecoration(
              color: AppColors.field,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: imageUrl.isNotEmpty
                  ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.image_not_supported_outlined,
                  color: deepAccent,
                  size: 28,
                ),
              )
                  : const Icon(
                Icons.image_not_supported_outlined,
                color: deepAccent,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: primaryText)),
                const SizedBox(height: 6),
                Text(description,
                    style: const TextStyle(
                        fontSize: 13, color: secondaryText, height: 1.35)),
                const SizedBox(height: 8),
                Text('Size: $size',
                    style: const TextStyle(fontSize: 13, color: secondaryText)),
                const SizedBox(height: 4),
                Text('Quantity: $quantity',
                    style: const TextStyle(fontSize: 13, color: secondaryText)),
                const SizedBox(height: 4),
                Text('Price: ${price.toStringAsFixed(0)} KWD',
                    style: const TextStyle(fontSize: 13, color: secondaryText)),
                const SizedBox(height: 4),
                Text('Boutique ID: $boutiqueId',
                    style: const TextStyle(fontSize: 13, color: secondaryText)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orderNumber = _buildTextValue(widget.orderData['orderNumber'], 'Unknown Order');
    final customerName = _buildTextValue(widget.orderData['customerName'], 'Unknown Customer');
    final customerEmail = _buildTextValue(widget.orderData['customerEmail'], 'No email');
    final date = _buildTextValue(widget.orderData['date'], 'No date');
    final deliveryMethod = _buildTextValue(widget.orderData['deliveryMethod'], 'No delivery method');
    final paymentMethod = _buildTextValue(widget.orderData['paymentMethod'], 'No payment method');
    final itemCount = _buildItemCount(widget.orderData['itemCount']);
    final total = _buildTotal(widget.orderData['total']);

    final addressData = widget.orderData['address'] is Map<String, dynamic>
        ? widget.orderData['address'] as Map<String, dynamic>
        : <String, dynamic>{};

    final addressText = [
      _buildTextValue(addressData['firstName'], ''),
      _buildTextValue(addressData['lastName'], ''),
      _buildTextValue(addressData['governorate'], ''),
      _buildTextValue(addressData['area'], ''),
      _buildTextValue(addressData['block'], ''),
      _buildTextValue(addressData['street'], ''),
      _buildTextValue(addressData['house'], ''),
      _buildTextValue(addressData['floor'], ''),
      _buildTextValue(addressData['apartment'], ''),
      _buildTextValue(addressData['phone'], ''),
    ].where((v) => v.isNotEmpty).join('\n');

    final rawItems = widget.orderData['items'];
    final List<Map<String, dynamic>> items = rawItems is List
        ? rawItems.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
        : [];

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ORDER DETAILS',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: primaryText,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Status update card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ORDER STATUS',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: secondaryText,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Current status badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _statusBgColor(_currentStatus),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              _currentStatus,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _statusColor(_currentStatus),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Update status:',
                            style: TextStyle(
                              fontSize: 13,
                              color: secondaryText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _isUpdating
                              ? const Center(
                              child: CircularProgressIndicator(
                                  color: deepAccent))
                              : Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _statusOptions.map((status) {
                              final isSelected =
                                  _currentStatus == status;
                              return GestureDetector(
                                onTap: isSelected
                                    ? null
                                    : () => _updateStatus(status),
                                child: AnimatedContainer(
                                  duration:
                                  const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? _statusBgColor(status)
                                        : AppColors.field,
                                    borderRadius:
                                    BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected
                                          ? _statusColor(status)
                                          : AppColors.border,
                                    ),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? _statusColor(status)
                                          : AppColors.secondaryText,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    buildSectionTitle('Order Information'),
                    const SizedBox(height: 12),
                    buildInfoBox(label: 'Order Number', value: orderNumber),
                    buildInfoBox(label: 'Date', value: date),
                    buildInfoBox(label: 'Item Count', value: itemCount),
                    buildInfoBox(label: 'Total', value: total),

                    const SizedBox(height: 12),
                    buildSectionTitle('Customer Information'),
                    const SizedBox(height: 12),
                    buildInfoBox(label: 'Customer Name', value: customerName),
                    buildInfoBox(label: 'Customer Email', value: customerEmail),
                    buildInfoBox(label: 'Delivery Method', value: deliveryMethod),
                    buildInfoBox(label: 'Payment Method', value: paymentMethod),

                    const SizedBox(height: 12),
                    buildSectionTitle('Delivery Address'),
                    const SizedBox(height: 12),
                    buildInfoBox(
                      label: 'Address',
                      value: addressText.isEmpty ? 'No address saved' : addressText,
                    ),

                    const SizedBox(height: 12),
                    buildSectionTitle('Ordered Items'),
                    const SizedBox(height: 12),

                    if (items.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: borderColor),
                        ),
                        child: const Text(
                          'No items found.',
                          style: TextStyle(fontSize: 14, color: secondaryText),
                        ),
                      )
                    else
                      ...items.map(buildItemCard),
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