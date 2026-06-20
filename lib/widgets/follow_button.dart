import 'package:flutter/material.dart';
import '../services/follow_service.dart';
import 'theme.dart';

class FollowButton extends StatelessWidget {
  final String boutiqueId;
  const FollowButton({super.key, required this.boutiqueId});

  @override
  Widget build(BuildContext context) {
    final service = FollowService();

    return StreamBuilder<bool>(
      stream: service.isFollowing(boutiqueId),
      builder: (context, snapshot) {
        final following = snapshot.data ?? false;

        return GestureDetector(
          onTap: () => following
              ? service.unfollow(boutiqueId)
              : service.follow(boutiqueId),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: following ? AppColors.field : AppColors.deepAccent,
              border: Border.all(
                color: following ? AppColors.border : AppColors.deepAccent,
                width: 0.5,
              ),
            ),
            child: Text(
              following ? 'Following' : 'Follow',
              style: AppTextStyles.labelSmall.copyWith(
                fontWeight: FontWeight.w500,
                color: following ? AppColors.secondaryText : Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }
}
