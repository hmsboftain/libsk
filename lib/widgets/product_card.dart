import 'package:flutter/material.dart';
import '../widgets/theme.dart';

Widget buildProductCard({
  required String imageUrl,
  required String title,
  String? brand,
  required String price,
  VoidCallback? onTap,
  bool isLiked = false,
  VoidCallback? onLikeTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: SizedBox(
      width: 170,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: imageUrl.isNotEmpty
                    ? Image.network(
                  imageUrl,
                  height: 210,
                  width: 170,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 210,
                      width: 170,
                      color: AppColors.field,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.image_not_supported_outlined,
                        size: 30,
                        color: Colors.black54,
                      ),
                    );
                  },
                )
                    : Container(
                  height: 210,
                  width: 170,
                  color: AppColors.field,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.image_not_supported_outlined,
                    size: 30,
                    color: Colors.black54,
                  ),
                ),
              ),
              if (onLikeTap != null)
                Positioned(
                  top: 10,
                  right: 10,
                  child: GestureDetector(
                    onTap: onLikeTap,
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.card,
                      child: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.red : Colors.black,
                        size: 18,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          if (brand != null)
            Text(
              brand,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            price,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );
}