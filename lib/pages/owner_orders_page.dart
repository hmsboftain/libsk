import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

class OwnerOrdersPage extends StatefulWidget {
  const OwnerOrdersPage({super.key});

  @override
  State<OwnerOrdersPage> createState() => _OwnerOrdersPageState();
}

class _OwnerOrdersPageState extends State<OwnerOrdersPage> {
  String? boutiqueId;
  bool isLoading = true;
  String? errorMessage;

  static const backgroundColor = AppColors.background;
  static const cardColor = AppColors.card;
  static const fieldColor = AppColors.field;
  static const borderColor = AppColors.border;
  static const primaryText = AppColors.primaryText;
  static const secondaryText = AppColors.secondaryText;
  static const deepAccent = AppColors.deepAccent;

  @override
  void initState() {
    super.initState();
    loadBoutiqueId();
  }

  Future<void> loadBoutiqueId() async {
    try {
      final id = await FirestoreService.getCurrentOwnerBoutiqueId();
      if (!mounted) return;
      if (id == null) {
        setState(() {
          errorMessage = 'No boutique found for this owner.';
          isLoading = false;
        });
        return;
      }
      setState(() {
        boutiqueId = id;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Failed to load boutique orders.';
        isLoading = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
      boutiqueId = null;
    });
    await loadBoutiqueId();
  }

  Future<void> _updateOrderStatus({
    required String boutiqueOrderId,
    required String sourceUserOrderId,
    required String customerUid,
    required String newStatus,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('boutiques')
          .doc(boutiqueId)
          .collection('orders')
          .doc(boutiqueOrderId)
          .update({'status': newStatus});

      if (customerUid.isNotEmpty && sourceUserOrderId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(customerUid)
            .collection('orders')
            .doc(sourceUserOrderId)
            .update({'status': newStatus});
      }

      if (sourceUserOrderId.isNotEmpty) {
        final globalQuery = await FirebaseFirestore.instance
            .collection('global_orders')
            .where('sourceUserOrderId', isEqualTo: sourceUserOrderId)
            .get();

        for (final doc in globalQuery.docs) {
          await doc.reference.update({'status': newStatus});
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order $newStatus successfully'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update order status')),
      );
    }
  }

  Widget buildOrderStatus(String status) {
    Color background;
    Color textColor;

    switch (status.toLowerCase()) {
      case 'confirmed':
        background = const Color(0xFFE8F0F8);
        textColor = const Color(0xFF5B8DB8);
        break;
      case 'on the way':
        background = const Color(0xFFF8F0E4);
        textColor = const Color(0xFFB87D3B);
        break;
      case 'delivered':
        background = const Color(0xFFE8F2EA);
        textColor = const Color(0xFF3D6B45);
        break;
      case 'cancelled':
        background = const Color(0xFFF7E8E8);
        textColor = const Color(0xFF9B4A4A);
        break;
      default:
        background = fieldColor;
        textColor = secondaryText;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget buildOrderItem(Map<String, dynamic> item) {
    final imageUrl = item['imageUrl']?.toString() ?? '';
    final title = item['title']?.toString() ?? 'Untitled Product';
    final size = item['size']?.toString() ?? '-';
    final quantity = item['quantity']?.toString() ?? '1';
    final priceValue = item['price'] ?? 0;

    final double price = priceValue is num
        ? priceValue.toDouble()
        : double.tryParse(priceValue.toString()) ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fieldColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: imageUrl.isNotEmpty
                ? Image.network(
              imageUrl,
              width: 62,
              height: 74,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 62,
                  height: 74,
                  color: AppColors.card,
                  child: const Icon(
                    Icons.image_not_supported_outlined,
                    color: deepAccent,
                  ),
                );
              },
            )
                : Container(
              width: 62,
              height: 74,
              color: AppColors.card,
              child: const Icon(
                Icons.image_not_supported_outlined,
                color: deepAccent,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: primaryText,
                  ),
                ),
                const SizedBox(height: 6),
                Text('Size: $size',
                    style:
                    const TextStyle(fontSize: 12, color: secondaryText)),
                const SizedBox(height: 4),
                Text('Quantity: $quantity',
                    style:
                    const TextStyle(fontSize: 12, color: secondaryText)),
                const SizedBox(height: 6),
                Text(
                  '${price.toStringAsFixed(0)} KWD',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: primaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildOrderCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final boutiqueOrderId = doc.id;

    final orderNumber = data['orderNumber']?.toString() ?? '-';
    final date = data['date']?.toString() ?? '-';
    final status = data['status']?.toString() ?? 'Placed';
    final customerName = data['customerName']?.toString() ?? 'Customer';
    final customerEmail = data['customerEmail']?.toString() ?? '';
    final customerUid = data['customerUid']?.toString() ?? '';
    final sourceUserOrderId = data['sourceUserOrderId']?.toString() ?? '';
    final deliveryMethod = data['deliveryMethod']?.toString() ?? '-';
    final paymentMethod = data['paymentMethod']?.toString() ?? '-';
    final itemCount = data['itemCount']?.toString() ?? '0';

    final totalValue = data['total'] ?? 0;
    final double total = totalValue is num
        ? totalValue.toDouble()
        : double.tryParse(totalValue.toString()) ?? 0;

    final address = data['address'] as Map<String, dynamic>?;
    final items = data['items'] as List<dynamic>? ?? [];

    final addressText = address == null
        ? 'No address available'
        : '${address['area'] ?? ''}, ${address['governorate'] ?? ''}\n'
        'Block ${address['block'] ?? ''} Street ${address['street'] ?? ''} House ${address['house'] ?? ''}';

    final isPlaced = status.toLowerCase() == 'placed';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Order #$orderNumber',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: primaryText,
                  ),
                ),
              ),
              buildOrderStatus(status),
            ],
          ),
          const SizedBox(height: 8),
          Text('Date: $date',
              style: const TextStyle(fontSize: 13, color: secondaryText)),
          const SizedBox(height: 14),
          const Text('Customer',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: primaryText)),
          const SizedBox(height: 6),
          Text(customerName,
              style: const TextStyle(fontSize: 14, color: primaryText)),
          if (customerEmail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(customerEmail,
                style: const TextStyle(fontSize: 13, color: secondaryText)),
          ],
          const SizedBox(height: 14),
          const Text('Delivery',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: primaryText)),
          const SizedBox(height: 6),
          Text(deliveryMethod,
              style: const TextStyle(fontSize: 14, color: primaryText)),
          const SizedBox(height: 14),
          const Text('Payment',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: primaryText)),
          const SizedBox(height: 6),
          Text(paymentMethod,
              style: const TextStyle(fontSize: 14, color: primaryText)),
          const SizedBox(height: 14),
          const Text('Address',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: primaryText)),
          const SizedBox(height: 6),
          Text(addressText,
              style: const TextStyle(
                  fontSize: 13, color: secondaryText, height: 1.4)),
          const SizedBox(height: 16),
          const Text('Items',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: primaryText)),
          const SizedBox(height: 10),
          ...items.map((item) {
            return buildOrderItem(Map<String, dynamic>.from(item));
          }),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('$itemCount item(s)',
                  style:
                  const TextStyle(fontSize: 13, color: secondaryText)),
              const Spacer(),
              Text(
                'Total: ${total.toStringAsFixed(0)} KWD',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: primaryText,
                ),
              ),
            ],
          ),

          // Confirm / Cancel — only when Placed
          if (isPlaced) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: backgroundColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          title: const Text('Cancel Order',
                              style:
                              TextStyle(fontWeight: FontWeight.w700)),
                          content: const Text(
                            'Are you sure you want to cancel this order? This cannot be undone.',
                            style: TextStyle(
                                color: secondaryText, height: 1.4),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Back',
                                  style:
                                  TextStyle(color: secondaryText)),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                const Color(0xFF9B4A4A),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(12)),
                              ),
                              child: const Text('Cancel Order'),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        await _updateOrderStatus(
                          boutiqueOrderId: boutiqueOrderId,
                          sourceUserOrderId: sourceUserOrderId,
                          customerUid: customerUid,
                          newStatus: 'Cancelled',
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF9B4A4A),
                      side: const BorderSide(color: Color(0xFF9B4A4A)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding:
                      const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel Order',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await _updateOrderStatus(
                        boutiqueOrderId: boutiqueOrderId,
                        sourceUserOrderId: sourceUserOrderId,
                        customerUid: customerUid,
                        newStatus: 'Confirmed',
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3D6B45),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding:
                      const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Confirm Order',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOrdersList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.getOwnerOrdersStream(boutiqueId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: deepAccent),
          );
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text('Failed to load orders',
                style: TextStyle(color: secondaryText)),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: const SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: 400,
                child: Center(
                  child: Text('No orders yet',
                      style:
                      TextStyle(fontSize: 16, color: secondaryText)),
                ),
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _onRefresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              return buildOrderCard(docs[index]);
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: isLoading
                  ? const Center(
                  child: CircularProgressIndicator(color: deepAccent))
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Text(
                      'MY ORDERS',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: primaryText,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  Expanded(
                    child: errorMessage != null
                        ? RefreshIndicator(
                      onRefresh: _onRefresh,
                      child: ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(
                                  fontSize: 15,
                                  color: secondaryText),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    )
                        : _buildOrdersList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}