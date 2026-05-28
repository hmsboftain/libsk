import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

// ── Pure helpers ──────────────────────────────────────────────────────────────

InputDecoration _inputStyle(String hintText) {
  return InputDecoration(
    hintText: hintText,
    filled: true,
    fillColor: AppColors.field,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: AppColors.border, width: 0.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: AppColors.border, width: 0.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: AppColors.deepAccent, width: 1),
    ),
  );
}

String? _requiredValidator(String? value, String errorMessage) {
  if (value == null || value.trim().isEmpty) return errorMessage;
  return null;
}

// ── Page ──────────────────────────────────────────────────────────────────────

class AddAddressPage extends StatefulWidget {
  const AddAddressPage({super.key});

  @override
  State<AddAddressPage> createState() => _AddAddressPageState();
}

class _AddAddressPageState extends State<AddAddressPage> {
  final _formKey = GlobalKey<FormState>();

  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final governorateController = TextEditingController();
  final areaController = TextEditingController();
  final blockController = TextEditingController();
  final streetController = TextEditingController();
  final houseController = TextEditingController();
  final floorController = TextEditingController();
  final apartmentController = TextEditingController();
  final phoneController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final displayName =
        FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) {
      final parts = displayName.split(' ');
      firstNameController.text = parts.first;
      if (parts.length > 1)
        lastNameController.text = parts.sublist(1).join(' ');
    }
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    governorateController.dispose();
    areaController.dispose();
    blockController.dispose();
    streetController.dispose();
    houseController.dispose();
    floorController.dispose();
    apartmentController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      await FirestoreService.addAddress(
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        governorate: governorateController.text.trim(),
        area: areaController.text.trim(),
        block: blockController.text.trim(),
        street: streetController.text.trim(),
        house: houseController.text.trim(),
        floor: floorController.text.trim(),
        apartment: apartmentController.text.trim(),
        phone: phoneController.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.failedToSaveAddress),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
            const SizedBox(height: 8),
            Text(l10n.addDeliveryAddress, style: AppTextStyles.headingMedium),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22),
              child: Divider(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 18),
                      Text(
                        l10n.deliveryAddress,
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 22),

                      // First / Last name
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: firstNameController,
                              decoration: _inputStyle(l10n.firstName),
                              validator: (v) =>
                                  _requiredValidator(v, l10n.requiredField),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: lastNameController,
                              decoration: _inputStyle(l10n.lastName),
                              validator: (v) =>
                                  _requiredValidator(v, l10n.requiredField),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      // Governorate / Area
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: governorateController,
                              decoration: _inputStyle(l10n.governorate),
                              validator: (v) =>
                                  _requiredValidator(v, l10n.requiredField),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: areaController,
                              decoration: _inputStyle(l10n.area),
                              validator: (v) =>
                                  _requiredValidator(v, l10n.requiredField),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      // Block / Street
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: blockController,
                              decoration: _inputStyle(l10n.block),
                              validator: (v) =>
                                  _requiredValidator(v, l10n.requiredField),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: streetController,
                              decoration: _inputStyle(l10n.street),
                              validator: (v) =>
                                  _requiredValidator(v, l10n.requiredField),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      // House / Floor (optional)
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: houseController,
                              decoration: _inputStyle(l10n.houseBuilding),
                              validator: (v) =>
                                  _requiredValidator(v, l10n.requiredField),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: floorController,
                              decoration: _inputStyle(l10n.floorOptional),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      // Apartment (optional) / Phone
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: apartmentController,
                              decoration: _inputStyle(l10n.apartmentOptional),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: _inputStyle(l10n.phoneNumber),
                              validator: (v) =>
                                  _requiredValidator(v, l10n.requiredField),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),

            SizedBox(
              width: double.infinity,
              height: 70,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveAddress,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepAccent,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        l10n.addNow,
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
