import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'cart_item.dart';
import '../widgets/theme.dart';

class OrderItem {
  final String id;
  final String orderNumber;
  final String date;
  final int itemCount;
  final double total;
  final String status;
  final List<CartItem> orderedItems;
  final DateTime? createdAt;
  final String paymentIntentId;

  OrderItem({
    required this.id,
    required this.orderNumber,
    required this.date,
    required this.itemCount,
    required this.total,
    required this.status,
    required this.orderedItems,
    this.createdAt,
    this.paymentIntentId = '',
  });

  String get displayDate {
    if (createdAt == null) {
      return date;
    }

    return '${createdAt!.day}/${createdAt!.month}/${createdAt!.year}';
  }

  factory OrderItem.fromFirestore(String id, Map<String, dynamic> data) {
    final itemsData = (data['items'] as List<dynamic>? ?? []);

    final List<CartItem> orderedItems = itemsData.map((item) {
      final itemMap = Map<String, dynamic>.from(item as Map);

      final priceValue = itemMap['price'] ?? 0;
      final double price = priceValue is num
          ? priceValue.toDouble()
          : double.tryParse(priceValue.toString()) ?? 0;

      final quantityValue = itemMap['quantity'] ?? 1;
      final int quantity = quantityValue is int
          ? quantityValue
          : int.tryParse(quantityValue.toString()) ?? 1;

      return CartItem(
        id: '',
        productId: itemMap['productId'] ?? '',
        boutiqueId: itemMap['boutiqueId'] ?? '',
        imageUrl: itemMap['imageUrl'] ?? '',
        title: itemMap['title'] ?? '',
        description: itemMap['description'] ?? '',
        size: itemMap['size'] ?? '',
        color: itemMap['color']?.toString() ?? '',
        price: price,
        quantity: quantity,
      );
    }).toList();

    final totalValue = data['total'] ?? 0;
    final double total = totalValue is num
        ? totalValue.toDouble()
        : double.tryParse(totalValue.toString()) ?? 0;

    final itemCountValue = data['itemCount'] ?? 0;
    final int itemCount = itemCountValue is int
        ? itemCountValue
        : int.tryParse(itemCountValue.toString()) ?? 0;

    DateTime? createdAt;
    final createdAtValue = data['createdAt'];
    if (createdAtValue is Timestamp) {
      createdAt = createdAtValue.toDate();
    }

    return OrderItem(
      id: id,
      orderNumber: data['orderNumber'] ?? '',
      date: data['date'] ?? '',
      itemCount: itemCount,
      total: total,
      status: data['status'] ?? '',
      orderedItems: orderedItems,
      createdAt: createdAt,
      paymentIntentId: data['paymentIntentId']?.toString() ?? '',
    );
  }
}

class OrderItemWidget extends StatelessWidget {
  final String orderNumber;
  final String date;
  final int itemCount;
  final double total;
  final String status;
  final VoidCallback? onTap;

  const OrderItemWidget({
    super.key,
    required this.orderNumber,
    required this.date,
    required this.itemCount,
    required this.total,
    required this.status,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final safeDate = date.trim().isEmpty ? 'Date unavailable' : date;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.shopping_bag_outlined,
              color: AppColors.deepAccent,
              size: 26,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order #$orderNumber',
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    safeDate,
                    style: AppTextStyles.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$itemCount item${itemCount == 1 ? '' : 's'}',
                    style: AppTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${total.toStringAsFixed(0)} KWD',
                    style: AppTextStyles.labelLarge,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.field,
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: Text(
                status,
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
