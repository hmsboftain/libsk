import 'package:flutter/material.dart';
import '../widgets/theme.dart';

class CartItem {
  final String id;
  final String productId;
  final String boutiqueId;
  final String imageUrl;
  final String title;
  final String description;
  final String size;
  final double price;
  final int quantity;

  CartItem({
    required this.id,
    required this.productId,
    required this.boutiqueId,
    required this.imageUrl,
    required this.title,
    required this.description,
    required this.size,
    required this.price,
    required this.quantity,
  });

  factory CartItem.fromFirestore(String id, Map<String, dynamic> data) {
    return CartItem(
      id: id,
      productId: data['productId'] ?? '',
      boutiqueId: data['boutiqueId'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      size: data['size'] ?? '',
      price: (data['price'] ?? 0).toDouble(),
      quantity: data['quantity'] ?? 1,
    );
  }
}

class CartItemWidget extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String description;
  final String size;
  final double price;
  final int quantity;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onDelete;

  const CartItemWidget({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.description,
    required this.size,
    required this.price,
    required this.quantity,
    required this.onIncrease,
    required this.onDecrease,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Item",
          style: TextStyle(
            fontSize: 13,
            color: Colors.black26,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: imageUrl.isNotEmpty
                      ? Image.network(
                    imageUrl,
                    width: 130,
                    height: 150,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 130,
                        height: 150,
                        color: AppColors.field,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          color: Colors.black54,
                          size: 28,
                        ),
                      );
                    },
                  )
                      : Container(
                    width: 130,
                    height: 150,
                    color: AppColors.field,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.image_not_supported_outlined,
                      color: Colors.black54,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Size: $size",
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _quantityButton(
                        icon: Icons.remove,
                        onTap: onDecrease,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        quantity.toString(),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _quantityButton(
                        icon: Icons.add,
                        onTap: onIncrease,
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: onDelete,
                        child: const Icon(
                          Icons.delete_outline,
                          size: 26,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    "${price.toStringAsFixed(0)} KWD",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _quantityButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black26),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 18,
          color: Colors.black54,
        ),
      ),
    );
  }
}