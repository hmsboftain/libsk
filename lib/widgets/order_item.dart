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
          color: AppColors.field,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                color: Colors.black,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Order #$orderNumber",
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    safeDate,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "$itemCount item${itemCount == 1 ? "" : "s"}",
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "${total.toStringAsFixed(0)} KWD",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.black12),
              ),
              child: Text(
                status,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}