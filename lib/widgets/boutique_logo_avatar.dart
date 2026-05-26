import 'package:flutter/material.dart';
import '../widgets/theme.dart';

class BoutiqueLogoAvatar extends StatelessWidget {
  final String imageUrl;
  final double size;
  final double padding;
  final VoidCallback? onTap;

  const BoutiqueLogoAvatar({
    super.key,
    required this.imageUrl,
    this.size = 90,
    this.padding = 4,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.imagePlaceholder,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: ClipOval(
          child: imageUrl.isNotEmpty
              ? Image.network(
                  imageUrl,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: AppColors.imagePlaceholder,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.storefront_outlined,
                        color: AppColors.deepAccent,
                        size: size * 0.30,
                      ),
                    );
                  },
                )
              : Container(
                  color: AppColors.imagePlaceholder,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.storefront_outlined,
                    color: AppColors.deepAccent,
                    size: size * 0.30,
                  ),
                ),
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: avatar);
    }

    return avatar;
  }
}
