import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import 'change_password_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/theme.dart';

class EditPersonalInformationPage extends StatefulWidget {
  const EditPersonalInformationPage({super.key});

  @override
  State<EditPersonalInformationPage> createState() =>
      _EditPersonalInformationPageState();
}

class _EditPersonalInformationPageState
    extends State<EditPersonalInformationPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController fullNameController;
  late TextEditingController emailController;

  bool isLoading = false;

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;

    fullNameController = TextEditingController(
      text: user?.displayName ?? "",
    );
    emailController = TextEditingController(
      text: user?.email ?? "",
    );
  }

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    super.dispose();
  }

  Future<void> saveChanges() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      isLoading = true;
    });

    try {
      final fullName = fullNameController.text.trim();

      await user.updateDisplayName(fullName);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'fullName': fullName,
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.accountUpdated),
          duration: const Duration(seconds: 1),
        ),
      );

      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? l10n.failedToUpdateAccount),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.somethingWentWrong)),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> openChangePasswordPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ChangePasswordPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            const SizedBox(height: 12),
            Text(
              l10n.editPersonalInformation,
              style: AppTextStyles.headingLarge,
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 0.5),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      Text(
                        l10n.fullNameLabel,
                        style: AppTextStyles.capsLabel,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: fullNameController,
                        decoration: InputDecoration(
                          hintText: "",
                          filled: true,
                          fillColor: AppColors.field,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                              width: 0.5,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                              width: 0.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(
                              color: AppColors.deepAccent,
                              width: 1,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return l10n.requiredField;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l10n.emailAddressLabel,
                        style: AppTextStyles.capsLabel,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: emailController,
                        readOnly: true,
                        enabled: false,
                        decoration: InputDecoration(
                          hintText: "",
                          filled: true,
                          fillColor: AppColors.disabledField,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.emailNotEditable,
                        style: AppTextStyles.bodySmall,
                      ),
                      const SizedBox(height: 30),
                      Text(
                        l10n.securitySection,
                        style: AppTextStyles.capsLabel,
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.lock_outline,
                          color: AppColors.primaryText,
                        ),
                        title: Text(
                          l10n.changePassword,
                          style: AppTextStyles.bodyLarge,
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: AppColors.secondaryText,
                        ),
                        onTap: openChangePasswordPage,
                      ),
                      const Divider(),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 70,
              child: ElevatedButton(
                onPressed: isLoading ? null : saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepAccent,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Colors.white,
                  ),
                )
                    : const Text(
                  "SAVE CHANGES",
                  style: AppTextStyles.button,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}