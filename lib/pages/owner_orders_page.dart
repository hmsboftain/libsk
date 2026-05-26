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
        background = AppColors.field;
        textColor = AppColors.primaryText;
        break;
      case 'on the way':
        background = AppColors.selectedSoft;
        textColor = AppColors.deepAccent;
        break;
      case 'delivered':
        background = AppColors.selectedSoft;
        textColor = AppColors.primaryText;
        break;
      case 'cancelled':
        background = AppColors.disabledField;
        textColor = AppColors.deepAccent;
        break;
      default:
        background = AppColors.field;
        textColor = AppColors.secondaryText;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Text(
        status,
        style: AppTextStyles.bodySmall.copyWith(
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
        color: AppColors.field,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.imagePlaceholder,
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: imageUrl.isNotEmpty
                ? Image.network(
                    imageUrl,
                    width: 64,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.softAccent,
                          size: 24,
                        ),
                      );
                    },
                  )
                : const Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: AppColors.softAccent,
                      size: 24,
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
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text('Size: $size', style: AppTextStyles.bodySmall),
                const SizedBox(height: 4),
                Text('Quantity: $quantity', style: AppTextStyles.bodySmall),
                const SizedBox(height: 6),
                Text(
                  '${price.toStringAsFixed(0)} KWD',
                  style: AppTextStyles.labelLarge,
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
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Order #$orderNumber',
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              buildOrderStatus(status),
            ],
          ),
          const SizedBox(height: 8),
          Text('Date: $date', style: AppTextStyles.bodySmall),
          const SizedBox(height: 14),
          Text('Customer', style: AppTextStyles.labelLarge),
          const SizedBox(height: 6),
          Text(customerName, style: AppTextStyles.bodyMedium),
          if (customerEmail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(customerEmail, style: AppTextStyles.bodySmall),
          ],
          const SizedBox(height: 14),
          Text('Delivery', style: AppTextStyles.labelLarge),
          const SizedBox(height: 6),
          Text(deliveryMethod, style: AppTextStyles.bodyMedium),
          const SizedBox(height: 14),
          Text('Payment', style: AppTextStyles.labelLarge),
          const SizedBox(height: 6),
          Text(paymentMethod, style: AppTextStyles.bodyMedium),
          const SizedBox(height: 14),
          Text('Address', style: AppTextStyles.labelLarge),
          const SizedBox(height: 6),
          Text(
            addressText,
            style: AppTextStyles.bodySmall.copyWith(height: 1.4),
          ),
          const SizedBox(height: 16),
          Text('Items', style: AppTextStyles.labelLarge),
          const SizedBox(height: 10),
          ...items.map((item) {
            return buildOrderItem(Map<String, dynamic>.from(item));
          }),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('$itemCount item(s)', style: AppTextStyles.bodySmall),
              const Spacer(),
              Text(
                'Total: ${total.toStringAsFixed(0)} KWD',
                style: AppTextStyles.labelLarge,
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
                          backgroundColor: AppColors.background,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                            side: BorderSide(
                              color: AppColors.border,
                              width: 0.5,
                            ),
                          ),
                          title: const Text(
                            'Cancel Order',
                            style: AppTextStyles.headingSmall,
                          ),
                          content: const Text(
                            'Are you sure you want to cancel this order? This cannot be undone.',
                            style: AppTextStyles.bodyMedium,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(
                                'Back',
                                style: AppTextStyles.labelLarge.copyWith(
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.deepAccent,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'Cancel Order',
                                style: AppTextStyles.button,
                              ),
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
                      foregroundColor: AppColors.deepAccent,
                      side: const BorderSide(
                        color: AppColors.deepAccent,
                        width: 0.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Cancel Order',
                      style: AppTextStyles.labelLarge,
                    ),
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
                      backgroundColor: AppColors.deepAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Confirm Order',
                      style: AppTextStyles.button,
                    ),
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
            child: CircularProgressIndicator(
              color: AppColors.deepAccent,
              strokeWidth: 1.5,
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Failed to load orders',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return RefreshIndicator(
            color: AppColors.deepAccent,
            onRefresh: _onRefresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: 400,
                child: Center(
                  child: Text(
                    'No orders yet',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: AppColors.deepAccent,
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
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                        strokeWidth: 1.5,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                          child: Text(
                            'MY ORDERS',
                            style: AppTextStyles.headingMedium.copyWith(
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        Expanded(
                          child: errorMessage != null
                              ? RefreshIndicator(
                                  color: AppColors.deepAccent,
                                  onRefresh: _onRefresh,
                                  child: ListView(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Text(
                                          errorMessage!,
                                          style: AppTextStyles.bodyMedium
                                              .copyWith(
                                                color: AppColors.secondaryText,
                                              ),
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
