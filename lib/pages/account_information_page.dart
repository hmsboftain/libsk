import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:libsk/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';

// ── Pure helpers ──────────────────────────────────────────────────────────────

Widget _buildLabel(String text) {
  return Text(text, style: AppTextStyles.capsLabel);
}

InputDecoration _buildInputDecoration({
  required String hintText,
  bool isDisabled = false,
}) {
  return InputDecoration(
    hintText: hintText,
    filled: true,
    fillColor: isDisabled ? AppColors.disabledField : AppColors.field,
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

class AccountInformationPage extends StatefulWidget {
  const AccountInformationPage({super.key});

  @override
  State<AccountInformationPage> createState() => _AccountInformationPageState();
}

class _AccountInformationPageState extends State<AccountInformationPage> {
  final _formKey = GlobalKey<FormState>();

  final fullNameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();

  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    loadUserData();
  }

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  // Pull user data from both Auth and Firestore
  Future<void> loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;

    fullNameController.text = user?.displayName ?? '';
    emailController.text = user?.email ?? '';
    phoneController.text = '';

    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = doc.data();
      if (data != null) {
        fullNameController.text =
            data['fullName']?.toString() ?? fullNameController.text;
        phoneController.text = data['phone']?.toString() ?? '';
      }
    }

    if (!mounted) return;
    setState(() => isLoading = false);
  }

  Future<void> _onRefresh() => loadUserData();

  Future<void> saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => isSaving = true);

    try {
      final fullName = fullNameController.text.trim();
      final phone = phoneController.text.trim();

      await user.updateDisplayName(fullName);

      // merge so we don't overwrite other fields like role or createdAt
      // email is intentionally excluded — it's read-only and never changes here
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fullName': fullName,
        'phone': phone,
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.accountUpdated),
          duration: const Duration(seconds: 1),
        ),
      );

      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message ?? AppLocalizations.of(context)!.failedToUpdateAccount,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.somethingWentWrong),
        ),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
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
            Text(l10n.accountInformation, style: AppTextStyles.headingLarge),
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 0.5),
            Expanded(
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                        strokeWidth: 1.5,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _onRefresh,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 24),
                              _buildLabel(l10n.username),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: fullNameController,
                                decoration: _buildInputDecoration(
                                  hintText: l10n.enterUsername,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return l10n.requiredField;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              _buildLabel(l10n.email),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: emailController,
                                enabled: false,
                                decoration: _buildInputDecoration(
                                  hintText: l10n.enterEmail,
                                  isDisabled: true,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                l10n.emailNotEditable,
                                style: AppTextStyles.bodySmall,
                              ),
                              const SizedBox(height: 24),
                              _buildLabel(l10n.phoneNumber),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: _buildInputDecoration(
                                  hintText: l10n.enterPhoneNumber,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return l10n.requiredField;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 30),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
            SizedBox(
              width: double.infinity,
              height: 70,
              child: ElevatedButton(
                onPressed: isSaving ? null : saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepAccent,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: isSaving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        l10n.saveChanges,
                        style: AppTextStyles.button.copyWith(fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
