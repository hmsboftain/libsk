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
  final String color;
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
    this.color = '',
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
      color: data['color']?.toString() ?? '',
      price: (data['price'] ?? 0).toDouble(),
      quantity: data['quantity'] ?? 1,
    );
  }
}

class CartItemWidget extends StatelessWidget {
  static const double _imageWidth = 104;
  static const double _imageHeight = 130; // 4:5

  final String imageUrl;
  final String title;
  final String description;
  final String size;
  final String color;
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
    this.color = '',
    required this.price,
    required this.quantity,
    required this.onIncrease,
    required this.onDecrease,
    required this.onDelete,
  });

  Widget _productImage() {
    return Container(
      width: _imageWidth,
      height: _imageHeight,
      decoration: BoxDecoration(
        color: AppColors.imagePlaceholder,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              width: _imageWidth,
              height: _imageHeight,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Item', style: AppTextStyles.capsLabel),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _productImage(),
                const SizedBox(height: 8),
                Text('Size: $size', style: AppTextStyles.bodyMedium),
                if (color.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Colour: $color', style: AppTextStyles.bodyMedium),
                ],
              ],
            ),
            const SizedBox(width: 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.secondaryText,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _quantityButton(icon: Icons.remove, onTap: onDecrease),
                      const SizedBox(width: 10),
                      Text(
                        quantity.toString(),
                        style: AppTextStyles.labelLarge,
                      ),
                      const SizedBox(width: 10),
                      _quantityButton(icon: Icons.add, onTap: onIncrease),
                      const Spacer(),
                      GestureDetector(
                        onTap: onDelete,
                        child: const Icon(
                          Icons.delete_outline,
                          size: 24,
                          color: AppColors.deepAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${price.toStringAsFixed(0)} KWD',
                    style: AppTextStyles.headingSmall,
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
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Icon(icon, size: 18, color: AppColors.deepAccent),
      ),
    );
  }
}
