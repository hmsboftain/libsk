import 'package:flutter/material.dart';
import 'boutique_logo_avatar.dart';
import 'theme.dart';

class BoutiquesCard extends StatelessWidget {
  final String imageUrl;
  final String boutiqueName;
  final bool isLiked;
  final VoidCallback onLikeTap;
  final VoidCallback onTap;
  final bool showLikeButton;

  const BoutiquesCard({
    super.key,
    required this.imageUrl,
    required this.boutiqueName,
    required this.isLiked,
    required this.onLikeTap,
    required this.onTap,
    this.showLikeButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                BoutiqueLogoAvatar(
                  imageUrl: imageUrl,
                  size: 52,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    boutiqueName,
                    style: AppTextStyles.bodyLarge,
                  ),
                ),
                if (showLikeButton)
                  IconButton(
                    onPressed: onLikeTap,
                    icon: Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      color: isLiked
                          ? AppColors.deepAccent
                          : AppColors.secondaryText,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, thickness: 0.5, color: AppColors.border),
      ],
    );
  }
}
