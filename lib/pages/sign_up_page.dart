import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  // text controllers for each form field
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
  TextEditingController();

  final _formKey = GlobalKey<FormState>();

  // password visibility toggles
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;

  // loading states for email signup and google signin
  bool isLoading = false;
  bool isGoogleLoading = false;

  // tracks current password value for live strength meter
  String _currentPassword = '';

  @override
  void initState() {
    super.initState();
    passwordController.addListener(() {
      setState(() {
        _currentPassword = passwordController.text;
      });
    });
  }

  @override
  void dispose() {
    // clean up controllers when page is removed
    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  // returns 0–4 based on how many strength criteria are met
  int _getPasswordStrength(String password) {
    int score = 0;
    if (password.length >= 8) score++;
    if (password.contains(RegExp(r'[A-Z]'))) score++;
    if (password.contains(RegExp(r'[a-z]'))) score++;
    if (password.contains(RegExp(r'[0-9]'))) score++;
    return score;
  }

  // label shown next to the strength bars
  String _strengthLabel(int strength) {
    switch (strength) {
      case 0:
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Strong';
      default:
        return '';
    }
  }

  // color for each strength level
  Color _strengthColor(int strength) {
    switch (strength) {
      case 0:
      case 1:
        return const Color(0xFFE53935); // red
      case 2:
        return const Color(0xFFFB8C00); // orange
      case 3:
        return const Color(0xFFFDD835); // yellow
      case 4:
        return const Color(0xFF43A047); // green
      default:
        return Colors.transparent;
    }
  }

  // visual password strength meter — 4 bars that fill up as criteria are met
  Widget _buildStrengthMeter(String password) {
    if (password.isEmpty) return const SizedBox.shrink();

    final strength = _getPasswordStrength(password);
    final color = _strengthColor(strength);
    final label = _strengthLabel(strength);

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
                    color: filled ? color : Colors.black12,
                    borderRadius: BorderRadius.circular(10),
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
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  label,
                  key: ValueKey(label),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // criteria checklist pills
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

  // small pill showing whether a single criterion is met
  Widget _criteriaChip(String label, bool met) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: met ? const Color(0xFF43A047).withOpacity(0.12) : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: met ? const Color(0xFF43A047) : Colors.black12,
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: met ? const Color(0xFF43A047) : Colors.black38,
        ),
      ),
    );
  }

  // reusable labeled text field with optional validation and suffix icon
  Widget buildInput({
    required String label,
    required TextEditingController controller,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    Widget? belowField,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black54,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.field,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.black),
            ),
            suffixIcon: suffixIcon,
          ),
          validator: validator,
        ),
        if (belowField != null) belowField,
      ],
    );
  }

  // handles email/password account creation
  Future<void> createAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
    });

    try {
      final firstName = firstNameController.text.trim();
      final lastName = lastNameController.text.trim();
      final phone = phoneController.text.trim();
      final email = emailController.text.trim();
      final password = passwordController.text.trim();
      final fullName = '$firstName $lastName'.trim();

      // create firebase auth account
      final credential =
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // set display name on the auth user
      await credential.user?.updateDisplayName(fullName);

      // force token refresh so Firestore security rules can verify the new user
      await credential.user?.getIdToken(true);

      // create the user document in firestore
      if (credential.user != null) {
        await FirestoreService.createUserProfile(
          uid: credential.user!.uid,
          firstName: firstName,
          lastName: lastName,
          email: email,
          phone: phone,
        );
      }

      // move any guest cart items to the new account
      await FirestoreService.mergeGuestCartToUser();

      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      // map firebase error codes to user-friendly messages
      String message = AppLocalizations.of(context)!.signUpFailed;

      if (e.code == 'email-already-in-use') {
        message = AppLocalizations.of(context)!.emailAlreadyInUse;
      } else if (e.code == 'invalid-email') {
        message = AppLocalizations.of(context)!.invalidEmailAddress;
      } else if (e.code == 'weak-password') {
        message = AppLocalizations.of(context)!.passwordTooWeak;
      } else if (e.message != null) {
        message = e.message!;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      debugPrint("SIGNUP ERROR: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.somethingWentWrong),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // handles google sign in and profile creation if first time
  Future<void> signInWithGoogle() async {
    setState(() {
      isGoogleLoading = true;
    });

    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();

      // user cancelled the google sign in sheet
      if (googleUser == null) {
        return;
      }

      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential =
      await FirebaseAuth.instance.signInWithCredential(credential);

      // create or update firestore profile using google account info
      final user = userCredential.user;
      if (user != null) {
        // force token refresh so Firestore security rules can verify the user
        await user.getIdToken(true);

        final nameParts = (user.displayName ?? '').split(' ');
        final firstName = nameParts.isNotEmpty ? nameParts.first : '';
        final lastName =
        nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

        await FirestoreService.createUserProfile(
          uid: user.uid,
          firstName: firstName,
          lastName: lastName,
          email: user.email ?? '',
          phone: '',
        );
      }

      // merge guest cart and mark user as online
      await FirestoreService.mergeGuestCartToUser();
      await FirestoreService.updateCurrentUserLastLogin();
      await FirestoreService.setCurrentUserOnline();

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint("GOOGLE SIGN IN ERROR: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.somethingWentWrong),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isGoogleLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      // back arrow to return to previous page
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 30),

                // app logo
                Image.asset(
                  "assets/libsk_logo.png",
                  height: 90,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 60),

                Text(
                  AppLocalizations.of(context)!.signUp,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 36),

                // first and last name side by side
                Row(
                  children: [
                    Expanded(
                      child: buildInput(
                        label: AppLocalizations.of(context)!.firstName,
                        controller: firstNameController,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return AppLocalizations.of(context)!
                                .firstNameRequired;
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: buildInput(
                        label: AppLocalizations.of(context)!.lastName,
                        controller: lastNameController,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return AppLocalizations.of(context)!
                                .lastNameRequired;
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                buildInput(
                  label: AppLocalizations.of(context)!.emailAddress,
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppLocalizations.of(context)!.emailRequired;
                    }
                    if (!value.contains("@") || !value.contains(".")) {
                      return AppLocalizations.of(context)!.enterValidEmail;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 22),

                buildInput(
                  label: AppLocalizations.of(context)!.phoneNumber,
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppLocalizations.of(context)!.phoneNumberRequired;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 22),

                // password field with show/hide toggle + live strength meter
                buildInput(
                  label: AppLocalizations.of(context)!.password,
                  controller: passwordController,
                  obscureText: obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () {
                      setState(() {
                        obscurePassword = !obscurePassword;
                      });
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppLocalizations.of(context)!.passwordRequired;
                    }
                    if (value.length < 8) {
                      return 'Password must be at least 8 characters';
                    }
                    if (!value.contains(RegExp(r'[A-Z]'))) {
                      return 'Password must contain at least one uppercase letter';
                    }
                    if (!value.contains(RegExp(r'[a-z]'))) {
                      return 'Password must contain at least one lowercase letter';
                    }
                    if (!value.contains(RegExp(r'[0-9]'))) {
                      return 'Password must contain at least one number';
                    }
                    return null;
                  },
                  belowField: _buildStrengthMeter(_currentPassword),
                ),
                const SizedBox(height: 22),

                // confirm password field checks it matches the first
                buildInput(
                  label: AppLocalizations.of(context)!.confirmPassword,
                  controller: confirmPasswordController,
                  obscureText: obscureConfirmPassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () {
                      setState(() {
                        obscureConfirmPassword = !obscureConfirmPassword;
                      });
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppLocalizations.of(context)!
                          .pleaseConfirmYourPassword;
                    }
                    if (value != passwordController.text) {
                      return AppLocalizations.of(context)!.passwordsDoNotMatch;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // main create account button
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : createAccount,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: isLoading
                        ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                        : Text(
                      AppLocalizations.of(context)!.createAccount,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 36),

                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Text(
                        AppLocalizations.of(context)!.or,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 24),

                // google sign in button
                GestureDetector(
                  onTap: isGoogleLoading ? null : signInWithGoogle,
                  child: Container(
                    width: double.infinity,
                    height: 54,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      border: Border.all(color: Colors.black12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: isGoogleLoading
                        ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.black,
                        ),
                      ),
                    )
                        : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.g_mobiledata, size: 28),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!
                              .continueWithGoogle,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
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
      ),
    );
  }
}