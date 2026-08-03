import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../core/constants/countries.dart';
import '../navigation/app_header.dart';
import '../services/currency_service.dart';
import '../services/firestore_service.dart';
import '../services/wasal_service.dart';
import '../widgets/theme.dart';

// ── Pure helpers ──────────────────────────────────────────────────────────────

InputDecoration _inputStyle(String hintText) {
  return InputDecoration(hintText: hintText);
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

  // ── Kuwait fields ──────────────────────────────────────────────────────────
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

  // ── International fields ───────────────────────────────────────────────────
  final addressLine1Controller = TextEditingController();
  final addressLine2Controller = TextEditingController();
  final cityController = TextEditingController();
  final zipController = TextEditingController();

  bool _isSaving = false;

  // ── Wasal delivery areas (Kuwait) ──────────────────────────────────────────
  // Governorate/area become dropdowns backed by Wasal's area tree so every
  // new address carries the IDs delivery pricing needs. If the tree can't be
  // loaded the form falls back to the legacy free-text fields — the address
  // still saves, it just can't get area-based delivery pricing.
  List<WasalGovernorate>? _wasalAreas;
  WasalGovernorate? _selectedGovernorate;
  WasalArea? _selectedNeighborhood;
  bool _areasLoadFailed = false;

  bool get _isKuwait => CurrencyService.instance.selectedCountryCode == 'KW';

  Future<void> _loadWasalAreas() async {
    try {
      final areas = await WasalService.instance.getAreas();
      if (!mounted) return;
      setState(() {
        _wasalAreas = areas;
        _areasLoadFailed = areas.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _areasLoadFailed = true);
    }
  }

  @override
  void initState() {
    super.initState();
    if (_isKuwait) _loadWasalAreas();
    final displayName =
        FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) {
      final parts = displayName.split(' ');
      firstNameController.text = parts.first;
      if (parts.length > 1) {
        lastNameController.text = parts.sublist(1).join(' ');
      }
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
    addressLine1Controller.dispose();
    addressLine2Controller.dispose();
    cityController.dispose();
    zipController.dispose();
    super.dispose();
  }

  Future<void> _saveAddress() async {
    // Re-entrancy guard: drop a rapid second tap before the disabled state
    // rebuilds, so the address can't be saved twice.
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      if (_isKuwait) {
        // Dropdown path: names come from the selected Wasal areas (English
        // stored for consistency; the UI localizes at display time). The
        // legacy free-text path keeps working when areas failed to load.
        final gov = _selectedGovernorate;
        final neigh = _selectedNeighborhood;
        await FirestoreService.addAddress(
          firstName: firstNameController.text.trim(),
          lastName: lastNameController.text.trim(),
          governorate: gov?.nameEn ?? governorateController.text.trim(),
          area: neigh?.nameEn ?? areaController.text.trim(),
          block: blockController.text.trim(),
          street: streetController.text.trim(),
          house: houseController.text.trim(),
          floor: floorController.text.trim(),
          apartment: apartmentController.text.trim(),
          phone: phoneController.text.trim(),
          wasalGovernorateId: gov?.id,
          wasalNeighborhoodId: neigh?.id,
        );
      } else {
        final country = countryByCode(
          CurrencyService.instance.selectedCountryCode,
        );
        await FirestoreService.addInternationalAddress(
          firstName: firstNameController.text.trim(),
          lastName: lastNameController.text.trim(),
          addressLine1: addressLine1Controller.text.trim(),
          addressLine2: addressLine2Controller.text.trim(),
          city: cityController.text.trim(),
          zipCode: zipController.text.trim(),
          countryCode: country.code,
          phone: phoneController.text.trim(),
        );
      }

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

  // ── Kuwait form fields ────────────────────────────────────────────────────

  Widget _buildKuwaitFields(AppLocalizations l10n) {
    final localeCode = Localizations.localeOf(context).languageCode;

    return Column(
      children: [
        // Governorate / Area — Wasal-backed dropdowns (free text as fallback)
        if (_areasLoadFailed)
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: governorateController,
                  textInputAction: TextInputAction.next,
                  decoration: _inputStyle(l10n.governorate),
                  validator: (v) => _requiredValidator(v, l10n.requiredField),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: areaController,
                  textInputAction: TextInputAction.next,
                  decoration: _inputStyle(l10n.area),
                  validator: (v) => _requiredValidator(v, l10n.requiredField),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<WasalGovernorate>(
                  initialValue: _selectedGovernorate,
                  isExpanded: true,
                  decoration: _inputStyle(l10n.governorate),
                  items: (_wasalAreas ?? const [])
                      .map(
                        (g) => DropdownMenuItem(
                          value: g,
                          child: Text(
                            g.nameFor(localeCode),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (g) => setState(() {
                    _selectedGovernorate = g;
                    _selectedNeighborhood = null;
                  }),
                  validator: (v) =>
                      v == null ? l10n.requiredField : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<WasalArea>(
                  // Recreate the field when the governorate changes —
                  // otherwise the FormField's internal state keeps a
                  // selection that no longer exists in the new items list.
                  key: ValueKey(_selectedGovernorate?.id),
                  initialValue: _selectedNeighborhood,
                  isExpanded: true,
                  decoration: _inputStyle(l10n.area),
                  items: (_selectedGovernorate?.neighborhoods ?? const [])
                      .map(
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text(
                            n.nameFor(localeCode),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (n) => setState(() => _selectedNeighborhood = n),
                  validator: (v) =>
                      v == null ? l10n.requiredField : null,
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
                textInputAction: TextInputAction.next,
                decoration: _inputStyle(l10n.block),
                validator: (v) => _requiredValidator(v, l10n.requiredField),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: streetController,
                textInputAction: TextInputAction.next,
                decoration: _inputStyle(l10n.street),
                validator: (v) => _requiredValidator(v, l10n.requiredField),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // House / Floor
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: houseController,
                textInputAction: TextInputAction.next,
                decoration: _inputStyle(l10n.houseBuilding),
                validator: (v) => _requiredValidator(v, l10n.requiredField),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: floorController,
                textInputAction: TextInputAction.next,
                decoration: _inputStyle(l10n.floorOptional),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // Apartment / Phone
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: apartmentController,
                textInputAction: TextInputAction.next,
                decoration: _inputStyle(l10n.apartmentOptional),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onEditingComplete: () => FocusScope.of(context).unfocus(),
                decoration: _inputStyle(l10n.phoneNumber),
                validator: (v) => _requiredValidator(v, l10n.requiredField),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── International form fields ─────────────────────────────────────────────

  Widget _buildInternationalFields(AppLocalizations l10n) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final country = countryByCode(CurrencyService.instance.selectedCountryCode);
    final countryName = isArabic ? country.nameAr : country.nameEn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Country indicator (read-only — change via profile page)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.field,
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Row(
            children: [
              Text(countryName, style: AppTextStyles.bodyMedium),
              const Spacer(),
              Text(
                country.currency,
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Address line 1
        TextFormField(
          controller: addressLine1Controller,
          textInputAction: TextInputAction.next,
          decoration: _inputStyle(l10n.addressLine1),
          validator: (v) => _requiredValidator(v, l10n.requiredField),
        ),
        const SizedBox(height: 16),

        // Address line 2
        TextFormField(
          controller: addressLine2Controller,
          textInputAction: TextInputAction.next,
          decoration: _inputStyle(l10n.addressLine2Optional),
        ),
        const SizedBox(height: 16),

        // City / Zip
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: cityController,
                textInputAction: TextInputAction.next,
                decoration: _inputStyle(l10n.city),
                validator: (v) => _requiredValidator(v, l10n.requiredField),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: zipController,
                textInputAction: TextInputAction.next,
                decoration: _inputStyle(l10n.zipCode),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Phone
        TextFormField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          onEditingComplete: () => FocusScope.of(context).unfocus(),
          decoration: _inputStyle(l10n.phoneNumber),
          validator: (v) => _requiredValidator(v, l10n.requiredField),
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
            const SizedBox(height: 8),
            Text(l10n.addDeliveryAddress, style: AppTextStyles.headingMedium),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22),
              child: Divider(),
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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

                      // First / Last name — always shown
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: firstNameController,
                              textInputAction: TextInputAction.next,
                              decoration: _inputStyle(l10n.firstName),
                              validator: (v) =>
                                  _requiredValidator(v, l10n.requiredField),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: lastNameController,
                              textInputAction: TextInputAction.next,
                              decoration: _inputStyle(l10n.lastName),
                              validator: (v) =>
                                  _requiredValidator(v, l10n.requiredField),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      // Country-specific fields
                      _isKuwait
                          ? _buildKuwaitFields(l10n)
                          : _buildInternationalFields(l10n),

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
      ),
    );
  }
}
