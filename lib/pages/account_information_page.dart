import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:libsk/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';

class AccountInformationPage extends StatefulWidget {
  const AccountInformationPage({super.key});

  @override
  State<AccountInformationPage> createState() =>
      _AccountInformationPageState();
}

class _AccountInformationPageState extends State<AccountInformationPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController fullNameController;
  late TextEditingController emailController;
  late TextEditingController phoneController;

  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    loadUserData();
  }

  Future<void> loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;

    fullNameController = TextEditingController(
      text: user?.displayName ?? '',
    );
    emailController = TextEditingController(
      text: user?.email ?? '',
    );
    phoneController = TextEditingController();

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
    setState(() {
      isLoading = false;
    });
  }

  Future<void> _onRefresh() async {
    setState(() {
      isLoading = true;
    });
    await loadUserData();
  }

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Future<void> saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      isSaving = true;
    });

    try {
      final fullName = fullNameController.text.trim();
      final phone = phoneController.text.trim();

      await user.updateDisplayName(fullName);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'fullName': fullName,
        'email': user.email ?? '',
        'phone': phone,
      }, SetOptions(merge: true));

      await user.reload();

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
          content: Text(
            AppLocalizations.of(context)!.somethingWentWrong,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Widget buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        color: Colors.black54,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration buildInputDecoration({
    required String hintText,
    bool isDisabled = false,
  }) {
    return InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: isDisabled ? AppColors.disabledField : AppColors.field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.black),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.accountInformation,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: isLoading
                  ? const Center(
                child: CircularProgressIndicator(),
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
                        buildLabel(AppLocalizations.of(context)!.username),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: fullNameController,
                          decoration: buildInputDecoration(
                            hintText:
                            AppLocalizations.of(context)!.enterUsername,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return AppLocalizations.of(context)!
                                  .requiredField;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        buildLabel(AppLocalizations.of(context)!.email),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: emailController,
                          readOnly: true,
                          enabled: false,
                          decoration: buildInputDecoration(
                            hintText:
                            AppLocalizations.of(context)!.enterEmail,
                            isDisabled: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          AppLocalizations.of(context)!.emailNotEditable,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 24),
                        buildLabel(AppLocalizations.of(context)!.phoneNumber),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: buildInputDecoration(
                            hintText: AppLocalizations.of(context)!
                                .enterPhoneNumber,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return AppLocalizations.of(context)!
                                  .requiredField;
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
                  backgroundColor: Colors.black,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: isSaving
                    ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
                    : Text(
                  AppLocalizations.of(context)!.saveChanges,
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}