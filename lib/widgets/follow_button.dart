import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../core/services/analytics_service.dart';
import '../pages/login_page.dart';
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
        builder: (context, _) {
          final following = controller.isFollowing(boutiqueId);
          return _button(
            following: following,
            onTap: () => _onTap(
              context,
              controller: controller,
              following: following,
            ),
          );
        },
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
          onTap: () =>
              _onTap(context, service: service, following: following),
        );
      },
    );
  }

  /// Handles a tap in either mode. Following is per-account, so a guest is sent
  /// to sign in first and the follow only proceeds on success — this is what
  /// stops the feed from showing a phantom "Following" (an optimistic flip whose
  /// write silently no-ops for a signed-out user) while the storefront, reading
  /// live from Firestore, correctly shows "Follow". Any write failure is rolled
  /// back and surfaced instead of being swallowed.
  Future<void> _onTap(
    BuildContext context, {
    FollowController? controller,
    FollowService? service,
    required bool following,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      final loggedIn = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (loggedIn != true || !context.mounted) return;
    }

    try {
      if (controller != null) {
        // Analytics is logged inside the controller's optimistic toggle.
        await controller.toggle(boutiqueId, boutiqueName);
      } else if (service != null) {
        if (following) {
          await service.unfollow(boutiqueId);
          AnalyticsService.instance.logBoutiqueUnfollow(boutiqueId);
        } else {
          await service.follow(boutiqueId);
          AnalyticsService.instance.logBoutiqueFollow(boutiqueId, boutiqueName);
        }
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.somethingWentWrong),
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
