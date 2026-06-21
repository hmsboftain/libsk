import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:libsk/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/utils/validators.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

// ── Pure helpers ──────────────────────────────────────────────────────────────

int _getPasswordStrength(String password) {
  int score = 0;
  if (password.length >= 8) score++;
  if (password.contains(RegExp(r'[A-Z]'))) score++;
  if (password.contains(RegExp(r'[a-z]'))) score++;
  if (password.contains(RegExp(r'[0-9]'))) score++;
  return score;
}

String _strengthLabel(int strength, AppLocalizations l10n) {
  switch (strength) {
    case 0:
    case 1:
      return l10n.strengthWeak;
    case 2:
      return l10n.strengthFair;
    case 3:
      return l10n.strengthGood;
    case 4:
      return l10n.strengthStrong;
    default:
      return '';
  }
}

Color _strengthColor(int strength) {
  switch (strength) {
    case 0:
    case 1:
      return AppColors.secondaryText;
    case 2:
      return AppColors.softAccent;
    case 3:
      return AppColors.deepAccent;
    case 4:
      return AppColors.primaryText;
    default:
      return AppColors.border;
  }
}

Widget _criteriaChip(String label, bool met) {
  return AnimatedContainer(
    duration: const Duration(milliseconds: 250),
    margin: const EdgeInsets.only(right: 5),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: met ? AppColors.selectedSoft : AppColors.field,
      border: Border.all(
        color: met ? AppColors.deepAccent : AppColors.border,
        width: 0.5,
      ),
    ),
    child: Text(
      label,
      style: AppTextStyles.labelSmall.copyWith(
        fontWeight: FontWeight.w500,
        color: met ? AppColors.deepAccent : AppColors.secondaryText,
      ),
    ),
  );
}

Widget _buildStrengthMeter(String password, AppLocalizations l10n) {
  if (password.isEmpty) return const SizedBox.shrink();
  final strength = _getPasswordStrength(password);
  final color = _strengthColor(strength);
  final label = _strengthLabel(strength, l10n);

  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (index) {
            final filled = index < strength;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                margin: EdgeInsets.only(right: index < 3 ? 5 : 0),
                height: 5,
                decoration: BoxDecoration(
                  color: filled ? color : AppColors.border,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                label,
                key: ValueKey(label),
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _criteriaChip('8+ chars', password.length >= 8),
            _criteriaChip('A-Z', password.contains(RegExp(r'[A-Z]'))),
            _criteriaChip('a-z', password.contains(RegExp(r'[a-z]'))),
            _criteriaChip('0-9', password.contains(RegExp(r'[0-9]'))),
          ],
        ),
      ],
    ),
  );
}

Widget _buildInput({
  required String label,
  required TextEditingController controller,
  bool obscureText = false,
  Widget? suffixIcon,
  String? Function(String?)? validator,
  TextInputType? keyboardType,
  Widget? belowField,
  TextInputAction? textInputAction,
  VoidCallback? onEditingComplete,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: AppTextStyles.labelLarge.copyWith(
          color: AppColors.secondaryText,
        ),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onEditingComplete: onEditingComplete,
        decoration: InputDecoration(suffixIcon: suffixIcon),
        validator: validator,
      ),
      if (belowField != null) belowField,
    ],
  );
}

Future<void> _launchUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ── Page ──────────────────────────────────────────────────────────────────────

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  final _googleSignIn = GoogleSignIn();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String _currentPassword = '';

  @override
  void initState() {
    super.initState();
    passwordController.addListener(() {
      setState(() => _currentPassword = passwordController.text);
    });
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context)!;
    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();
    final phone = phoneController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    final preflight =
        Validators.maxLength(firstName, 50, 'First name') ??
        Validators.maxLength(lastName, 50, 'Last name') ??
        Validators.email(email) ??
        Validators.phone(phone) ??
        Validators.minLength(password, 8, 'Password');
    if (preflight != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(preflight)));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final fullName = '$firstName $lastName'.trim();
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      await credential.user?.updateDisplayName(fullName);
      await credential.user?.getIdToken(true);

      if (credential.user != null) {
        await FirestoreService.createUserProfile(
          uid: credential.user!.uid,
          firstName: firstName,
          lastName: lastName,
          email: email,
          phone: phone,
        );
      }

      await FirestoreService.mergeGuestCartToUser();

      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      String message = l10n.signUpFailed;
      if (e.code == 'email-already-in-use') {
        message = l10n.emailAlreadyInUse;
      } else if (e.code == 'invalid-email')
        message = l10n.invalidEmailAddress;
      else if (e.code == 'weak-password')
        message = l10n.passwordTooWeak;
      else if (e.message != null)
        message = e.message!;

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      debugPrint('SIGNUP ERROR: $e');
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
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final user = userCredential.user;

      if (user != null) {
        await user.getIdToken(true);
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
    } catch (e) {
      debugPrint('GOOGLE SIGN IN ERROR: $e');
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
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.primaryText),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                const SizedBox(height: 60),
                Text(l10n.signUp, style: AppTextStyles.headingLarge),
                const SizedBox(height: 36),

                // ── Name row ────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _buildInput(
                        label: l10n.firstName,
                        controller: firstNameController,
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return l10n.firstNameRequired;
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildInput(
                        label: l10n.lastName,
                        controller: lastNameController,
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return l10n.lastNameRequired;
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                _buildInput(
                  label: l10n.emailAddress,
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return l10n.emailRequired;
                    }
                    if (!v.contains('@') || !v.contains('.')) {
                      return l10n.enterValidEmail;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 22),

                _buildInput(
                  label: l10n.phoneNumber,
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () => FocusScope.of(context).unfocus(),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return l10n.phoneNumberRequired;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 22),

                _buildInput(
                  label: l10n.password,
                  controller: passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return l10n.passwordRequired;
                    }
                    if (v.length < 8) return l10n.passwordMinLength;
                    if (!v.contains(RegExp(r'[A-Z]'))) {
                      return l10n.passwordNeedsUppercase;
                    }
                    if (!v.contains(RegExp(r'[a-z]'))) {
                      return l10n.passwordNeedsLowercase;
                    }
                    if (!v.contains(RegExp(r'[0-9]'))) {
                      return l10n.passwordNeedsNumber;
                    }
                    return null;
                  },
                  belowField: _buildStrengthMeter(_currentPassword, l10n),
                ),
                const SizedBox(height: 22),

                _buildInput(
                  label: l10n.confirmPassword,
                  controller: confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () => FocusScope.of(context).unfocus(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return l10n.pleaseConfirmYourPassword;
                    }
                    if (v != passwordController.text) {
                      return l10n.passwordsDoNotMatch;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // ── Terms & Privacy ──────────────────────────────
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.secondaryText,
                    ),
                    children: [
                      TextSpan(text: l10n.byCreatingAccount),
                      TextSpan(
                        text: l10n.termsOfUse,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primaryText,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () =>
                              _launchUrl('https://libsk.com/terms.html'),
                      ),
                      TextSpan(text: ' ${l10n.and} '),
                      TextSpan(
                        text: l10n.privacyPolicy,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primaryText,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () =>
                              _launchUrl('https://libsk.com/privacy.html'),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createAccount,
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
                        : Text(l10n.createAccount, style: AppTextStyles.button),
                  ),
                ),
                const SizedBox(height: 36),

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
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
