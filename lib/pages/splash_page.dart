import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../navigation/main_navigation_bar.dart';
import '../services/firestore_service.dart';
import '../services/verification_service.dart';
import '../widgets/theme.dart';
import 'email_verification_page.dart';

/// Branded splash shown for the first ~800ms while we finish boot tasks.
///
/// Drives a four-step progress meter:
///   1. Firebase ready (already done before we get here)
///   2. Guest cart prepared
///   3. Permissions requested
///   4. Complete — fade into MainNavigationPage
///
/// Uses only existing design tokens (background / deepAccent / border).
class SplashPage extends StatefulWidget {
  final Function(Locale) onLanguageChange;

  const SplashPage({super.key, required this.onLanguageChange});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _logoController;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;

  // 0.0 → 1.0; each completed boot step bumps it by 0.25.
  double _progress = 0.25; // Firebase already ready when we arrive here.
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    final curved = CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeOut,
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _logoScale = Tween<double>(begin: 0.85, end: 1.0).animate(curved);
    _logoController.forward();

    _runBootSequence();
  }

  @override
  void dispose() {
    _logoController.dispose();
    super.dispose();
  }

  /// Routes a signed-in-but-unverified user to the code screen before the app
  /// opens. Abandoning drops the session — browsing continues as a guest, which
  /// is the app's normal signed-out state, rather than a live gated account.
  Future<void> _resolveVerificationGate() async {
    try {
      final status = await VerificationService.checkCurrentUser();
      if (!status.needsEmail || !mounted) return;

      final verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const EmailVerificationPage()),
      );
      if (verified != true) {
        await FirebaseAuth.instance.signOut();
      }
    } catch (_) {
      // Never strand boot on a verification failure — an offline launch falls
      // through to the app, and the gate re-runs on the next start.
    }
  }

  Future<void> _runBootSequence() async {
    // Step 2 — guest cart prep (idempotent; safe even if main() already ran it).
    try {
      await FirestoreService.prepareGuestCartId();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _progress = 0.5);

    // Step 3 — permissions request (same surface area as the old PermissionGatePage).
    try {
      await Permission.photos.request();
      await Permission.location.request();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _progress = 0.75);

    // Step 3.5 — resume an interrupted signup.
    //
    // The Auth session survives a restart, so a user who created an account and
    // then closed the app before entering their code would otherwise boot
    // straight into an app their account isn't cleared for. Send them back to
    // the code screen instead. Grandfathered and social accounts report clear
    // here and never see this.
    await _resolveVerificationGate();
    if (!mounted) return;

    // Brief settle so the user actually sees the progress bar fill.
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() => _progress = 1.0);

    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) =>
            MainNavigationPage(onLanguageChange: widget.onLanguageChange),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: AnimatedBuilder(
                animation: _logoController,
                builder: (_, __) => Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: Image.asset(
                      'assets/libsk_logo.png',
                      height: 90,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: _progress),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                builder: (_, value, __) => SizedBox(
                  height: 1.5,
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 1.5,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.deepAccent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
