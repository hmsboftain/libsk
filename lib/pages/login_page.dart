import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';
import 'forgot_password_page.dart';
import 'owner_dashboard_page.dart';
import 'sign_up_page.dart';
import 'super_admin_dashboard_page.dart';

// ── Pure helpers ──────────────────────────────────────────────────────────────

InputDecoration _loginInputDecoration({
  required String hint,
  Widget? suffixIcon,
}) {
  const border = OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: AppColors.border, width: 0.5),
  );
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: AppColors.field,
    border: border,
    enabledBorder: border,
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: AppColors.deepAccent, width: 1),
    ),
    suffixIcon: suffixIcon,
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _googleSignIn = GoogleSignIn();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      await FirestoreService.updateCurrentUserLastLogin();
      await FirestoreService.setCurrentUserOnline();
      await FirestoreService.prepareGuestCartId();

      // Check roles in parallel
      final results = await Future.wait([
        FirestoreService.isCurrentUserSuperAdmin(),
        FirestoreService.isCurrentUserApprovedOwner(),
      ]);
      final isSuperAdmin = results[0];
      final isOwner = results[1];

      if (!mounted) return;

      if (isSuperAdmin) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SuperAdminDashboardPage()),
        );
      } else if (isOwner) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const OwnerDashboardPage()),
        );
      } else {
        Navigator.pop(context, true);
      }
    } on FirebaseAuthException catch (e) {
      final l10n = AppLocalizations.of(context)!;
      String message = l10n.loginFailed;
      if (e.code == 'user-not-found')
        message = l10n.noAccountFoundForThisEmail;
      else if (e.code == 'wrong-password')
        message = l10n.incorrectPassword;
      else if (e.code == 'invalid-email')
        message = l10n.invalidEmailAddress;
      else if (e.code == 'invalid-credential')
        message = l10n.incorrectEmailOrPassword;
      else if (e.message != null)
        message = e.message!;

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.somethingWentWrong),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        ),
      );

      final user = userCredential.user;
      if (user != null) {
        final nameParts = (user.displayName ?? '').split(' ');
        await FirestoreService.createUserProfile(
          uid: user.uid,
          firstName: nameParts.isNotEmpty ? nameParts.first : '',
          lastName: nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '',
          email: user.email ?? '',
          phone: '',
        );
      }

      await FirestoreService.mergeGuestCartToUser();
      await FirestoreService.updateCurrentUserLastLogin();
      await FirestoreService.setCurrentUserOnline();

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.somethingWentWrong),
        ),
      );
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 30),
                Image.asset(
                  'assets/libsk_logo.png',
                  height: 90,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 70),
                Text(l10n.welcomeBack, style: AppTextStyles.headingLarge),
                const SizedBox(height: 40),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.emailAddress,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _loginInputDecoration(hint: l10n.emailExample),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty)
                      return l10n.emailRequired;
                    if (!v.contains('@') || !v.contains('.')) {
                      return l10n.enterValidEmail;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.password,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: passwordController,
                  obscureText: _obscurePassword,
                  decoration: _loginInputDecoration(
                    hint: l10n.passwordHidden,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return l10n.passwordRequired;
                    }
                    if (v.length < 6) return l10n.minimumSixCharacters;
                    return null;
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ForgotPasswordPage(),
                      ),
                    ),
                    child: Text(
                      l10n.forgotPassword,
                      style: AppTextStyles.labelLarge,
                    ),
                  ),
                ),
                const SizedBox(height: 26),

                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _signInUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.deepAccent,
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(l10n.signIn, style: AppTextStyles.button),
                  ),
                ),
                const SizedBox(height: 26),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.dontHaveAnAccount,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.secondaryText,
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SignUpPage()),
                        );
                        if (result == true && mounted) {
                          Navigator.pop(context, true);
                        }
                      },
                      child: Text(l10n.signUp, style: AppTextStyles.labelLarge),
                    ),
                  ],
                ),
                const SizedBox(height: 50),

                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Text(
                        l10n.or,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 24),

                GestureDetector(
                  onTap: _isGoogleLoading ? null : _signInWithGoogle,
                  child: Container(
                    width: double.infinity,
                    height: 54,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      border: Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: _isGoogleLoading
                        ? const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppColors.deepAccent,
                              ),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.g_mobiledata,
                                size: 28,
                                color: AppColors.primaryText,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.continueWithGoogle,
                                style: AppTextStyles.labelLarge,
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
