import 'package:cached_network_image/cached_network_image.dart';
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
              Container(
                width: 170,
                height: 212,
                decoration: BoxDecoration(
                  color: AppColors.imagePlaceholder,
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 170,
                        height: 212,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Container(color: AppColors.imagePlaceholder),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 24,
                            color: AppColors.softAccent,
                          ),
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          size: 24,
                          color: AppColors.softAccent,
                        ),
                      ),
              ),
              if (onLikeTap != null)
                Positioned(
                  top: 10,
                  right: 10,
                  child: GestureDetector(
                    onTap: onLikeTap,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.background.withValues(alpha: 0.9),
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked
                            ? AppColors.deepAccent
                            : AppColors.secondaryText,
                        size: 16,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: AppTextStyles.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          if (brand != null)
            Text(
              brand,
              style: AppTextStyles.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 5),
          Text(price, style: AppTextStyles.labelLarge),
        ],
      ),
    ),
  );
}
