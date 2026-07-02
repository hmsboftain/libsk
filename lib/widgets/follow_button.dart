import 'package:flutter/material.dart';
import '../core/services/analytics_service.dart';
import '../services/follow_service.dart';
import 'theme.dart';

class FollowButton extends StatelessWidget {
  final String boutiqueId;
  final String boutiqueName;

  /// When provided, the button is fully controlled by the shared
  /// [FollowController] — no per-widget Firestore listener (audit finding 4.1,
  /// used by the feed where many cards are on screen at once). When null it
  /// falls back to its own live `isFollowing` stream, which is fine for one-off
  /// placements like the storefront header.
  final FollowController? controller;

  const FollowButton({
    super.key,
    required this.boutiqueId,
    this.boutiqueName = '',
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller != null) {
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) => _button(
          following: controller.isFollowing(boutiqueId),
          onTap: () => controller.toggle(boutiqueId, boutiqueName),
        ),
      );
    }

    // Legacy single-listener mode for one-off placements (e.g. storefront).
    final service = FollowService();
    return StreamBuilder<bool>(
      stream: service.isFollowing(boutiqueId),
      builder: (context, snapshot) {
        final following = snapshot.data ?? false;
        return _button(
          following: following,
          onTap: () {
            if (following) {
              service.unfollow(boutiqueId);
              AnalyticsService.instance.logBoutiqueUnfollow(boutiqueId);
            } else {
              service.follow(boutiqueId);
              AnalyticsService.instance.logBoutiqueFollow(
                boutiqueId,
                boutiqueName,
              );
            }
          },
        );
      },
    );
  }

  Widget _button({required bool following, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
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
  }
}
