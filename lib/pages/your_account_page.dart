import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../navigation/main_navigation_bar.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';
import 'account_information_page.dart';
import 'change_password_page.dart';

class YourAccountPage extends StatefulWidget {
  const YourAccountPage({super.key});

  @override
  State<YourAccountPage> createState() => _YourAccountPageState();
}

class _YourAccountPageState extends State<YourAccountPage> {
  final _googleSignIn = GoogleSignIn();
  bool _isDeleting = false;

  Future<void> _deleteAccount() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: AppColors.border, width: 0.5),
        ),
        title: Text(l10n.deleteAccount, style: AppTextStyles.headingMedium),
        content: Text(
          l10n.deleteAccountConfirmation,
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.cancel,
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: Text(l10n.deleteButton, style: AppTextStyles.button),
          ),
        ],
      ),
    );

    if (!mounted || confirm != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final isGoogleUser = user.providerData.any(
      (info) => info.providerId == 'google.com',
    );

    try {
      setState(() => _isDeleting = true);

      if (isGoogleUser) {
        final googleUser = await _googleSignIn.signIn();
        if (!mounted || googleUser == null) return;
        final googleAuth = await googleUser.authentication;
        await user.reauthenticateWithCredential(
          GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          ),
        );
      } else {
        final passwordController = TextEditingController();

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.background,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: AppColors.border, width: 0.5),
            ),
            title: Text(
              l10n.confirmPasswordTitle,
              style: AppTextStyles.headingMedium,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.confirmPasswordDescription,
                  style: AppTextStyles.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () => FocusScope.of(ctx).unfocus(),
                  decoration: InputDecoration(hintText: l10n.password),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  l10n.cancel,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepAccent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: Text(l10n.confirmButton, style: AppTextStyles.button),
              ),
            ],
          ),
        );

        if (!mounted || confirmed != true) return;

        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(
            email: user.email!,
            password: passwordController.text.trim(),
          ),
        );
      }

      await FirestoreService.setCurrentUserOffline();
      await FirebaseAuth.instance.currentUser?.delete();

      if (!mounted) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => MainNavigationPage(onLanguageChange: (_) {}),
        ),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(e.message ?? l10n.somethingWentWrong)),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            const SizedBox(height: 12),
            Text(l10n.yourAccount, style: AppTextStyles.headingLarge),
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 0.5),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.badge_outlined),
                      title: Text(
                        l10n.accountInformation,
                        style: AppTextStyles.bodyLarge,
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: AppColors.secondaryText,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AccountInformationPage(),
                        ),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.lock_outline),
                      title: Text(
                        l10n.changePassword,
                        style: AppTextStyles.bodyLarge,
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: AppColors.secondaryText,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ChangePasswordPage(),
                        ),
                      ),
                    ),
                    const Divider(),
                    const SizedBox(height: 40),
                    _isDeleting
                        ? const CircularProgressIndicator(
                            color: AppColors.deepAccent,
                            strokeWidth: 1.5,
                          )
                        : SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: OutlinedButton(
                              onPressed: _deleteAccount,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.deepAccent,
                                side: const BorderSide(
                                  color: AppColors.deepAccent,
                                  width: 0.5,
                                ),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                              ),
                              child: Text(
                                l10n.deleteAccount,
                                style: AppTextStyles.labelLarge.copyWith(
                                  color: AppColors.deepAccent,
                                ),
                              ),
                            ),
                          ),
                  ],
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
