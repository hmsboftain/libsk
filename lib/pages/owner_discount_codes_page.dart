import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';
import '../core/constants/countries.dart';
import '../services/currency_service.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

const _border = OutlineInputBorder(
  borderRadius: BorderRadius.zero,
  borderSide: BorderSide(color: AppColors.border, width: 0.5),
);

InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: AppColors.field,
    hintStyle: AppTextStyles.bodyMedium.copyWith(
      color: AppColors.secondaryText,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: _border,
    enabledBorder: _border,
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: AppColors.deepAccent, width: 1),
    ),
  );
}

String _formatDate(Timestamp? ts) {
  if (ts == null) return 'No expiry';
  final d = ts.toDate();
  return '${d.day}/${d.month}/${d.year}';
}

class OwnerDiscountCodesPage extends StatefulWidget {
  final String boutiqueId;
  final String boutiqueName;

  const OwnerDiscountCodesPage({
    super.key,
    required this.boutiqueId,
    required this.boutiqueName,
  });

  @override
  State<OwnerDiscountCodesPage> createState() => _OwnerDiscountCodesPageState();
}

class _OwnerDiscountCodesPageState extends State<OwnerDiscountCodesPage> {
  final _db = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                // No orderBy — sort client-side to avoid composite index requirement
                stream: _db
                    .collection('discount_codes')
                    .where('boutiqueId', isEqualTo: widget.boutiqueId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                        strokeWidth: 1.5,
                      ),
                    );
                  }

                  // Sort newest first client-side
                  final docs = (snapshot.data?.docs ?? [])
                    ..sort((a, b) {
                      final aT = a.data()['createdAt'];
                      final bT = b.data()['createdAt'];
                      if (aT is Timestamp && bT is Timestamp) {
                        return bT.compareTo(aT);
                      }
                      return 0;
                    });

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Discount Codes',
                                    style: AppTextStyles.headingMedium,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.boutiqueName,
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _showCreateSheet(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.deepAccent,
                                  border: Border.all(
                                    color: AppColors.deepAccent,
                                    width: 0.5,
                                  ),
                                ),
                                child: Text(
                                  '+ New Code',
                                  style: AppTextStyles.labelLarge.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Divider(color: AppColors.border, thickness: 0.5),
                      ),
                      Expanded(
                        child: docs.isEmpty
                            ? Center(
                                child: Text(
                                  'No discount codes yet.\nTap + New Code to create one.',
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  30,
                                ),
                                itemCount: docs.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final doc = docs[index];
                                  return _CodeCard(
                                    doc: doc,
                                    onToggle: () => _toggleActive(doc),
                                    onDelete: () =>
                                        _confirmDelete(context, doc),
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Future<void> _toggleActive(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final current = doc.data()['isActive'] == true;
    await doc.reference.update({'isActive': !current});
  }

  Future<void> _confirmDelete(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final code = doc.data()['code']?.toString() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text('Delete $code?', style: AppTextStyles.headingSmall),
        content: Text(
          'This cannot be undone.',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.secondaryText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: AppTextStyles.labelLarge),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.deepAccent,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) await doc.reference.delete();
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => _CreateCodeSheet(
        boutiqueId: widget.boutiqueId,
        boutiqueName: widget.boutiqueName,
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _CodeCard({
    required this.doc,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final code = data['code']?.toString() ?? '';
    final type = data['type']?.toString() ?? 'percentage';
    final value = (data['value'] as num?)?.toDouble() ?? 0;
    final isActive = data['isActive'] == true;
    final usageCount = (data['usageCount'] as num?)?.toInt() ?? 0;
    final usageLimit = data['usageLimit'];
    final singleUse = data['singleUse'] == true;
    final expiresAt = data['expiresAt'] as Timestamp?;
    final description = data['description']?.toString() ?? '';

    final valueLabel = type == 'percentage'
        ? '${value.toStringAsFixed(0)}% off'
        : '${_fmt(value)} off';
    final usageLabel = usageLimit != null
        ? '$usageCount / $usageLimit uses'
        : '$usageCount uses';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.deepAccent
                      : AppColors.secondaryText,
                ),
                child: Text(
                  code,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Text(
                  valueLabel,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primaryText,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onToggle,
                child: Text(
                  isActive ? 'Active' : 'Inactive',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: isActive
                        ? AppColors.deepAccent
                        : AppColors.secondaryText,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: onDelete,
                child: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppColors.deepAccent,
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _pill(Icons.bar_chart_outlined, usageLabel),
              _pill(
                Icons.calendar_today_outlined,
                'Expires: ${_formatDate(expiresAt)}',
              ),
              if (singleUse) _pill(Icons.person_outline, 'Single use per user'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.secondaryText),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.secondaryText,
          ),
        ),
      ],
    );
  }
}

class _CreateCodeSheet extends StatefulWidget {
  final String boutiqueId;
  final String boutiqueName;

  const _CreateCodeSheet({
    required this.boutiqueId,
    required this.boutiqueName,
  });

  @override
  State<_CreateCodeSheet> createState() => _CreateCodeSheetState();
}

class _CreateCodeSheetState extends State<_CreateCodeSheet> {
  final _codeController = TextEditingController();
  final _valueController = TextEditingController();
  final _limitController = TextEditingController();
  final _descController = TextEditingController();

  String _type = 'percentage';
  bool _singleUse = true;
  bool _hasExpiry = false;
  bool _hasUsageLimit = false;
  DateTime? _expiryDate;
  bool _isSaving = false;

  @override
  void dispose() {
    _codeController.dispose();
    _valueController.dispose();
    _limitController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppColors.deepAccent,
            onSurface: AppColors.primaryText,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _save() async {
    // Re-entrancy guard: drop a rapid second tap before the disabled state
    // rebuilds, so the discount code can't be created twice.
    if (_isSaving) return;
    final code = _codeController.text.trim().toUpperCase();
    final valueText = _valueController.text.trim();

    if (code.isEmpty) {
      _snack('Enter a code.');
      return;
    }
    if (valueText.isEmpty || double.tryParse(valueText) == null) {
      _snack('Enter a valid discount value.');
      return;
    }
    if (_type == 'percentage') {
      final v = double.parse(valueText);
      if (v <= 0 || v > 100) {
        _snack('Percentage must be between 1 and 100.');
        return;
      }
    }
    if (_hasExpiry && _expiryDate == null) {
      _snack('Select an expiry date.');
      return;
    }
    if (_hasUsageLimit) {
      final l = int.tryParse(_limitController.text.trim());
      if (l == null || l <= 0) {
        _snack('Enter a valid usage limit.');
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final existing = await FirebaseFirestore.instance
          .collection('discount_codes')
          .where('code', isEqualTo: code)
          .where('boutiqueId', isEqualTo: widget.boutiqueId)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        _snack('You already have a code with that name.');
        return;
      }

      await FirebaseFirestore.instance.collection('discount_codes').add({
        'code': code,
        'type': _type,
        'value': double.parse(valueText),
        'isActive': true,
        'singleUse': _singleUse,
        'usageCount': 0,
        'usageLimit': _hasUsageLimit
            ? int.parse(_limitController.text.trim())
            : null,
        'description': _descController.text.trim(),
        'expiresAt': _hasExpiry && _expiryDate != null
            ? Timestamp.fromDate(_expiryDate!)
            : null,
        'boutiqueId': widget.boutiqueId,
        'boutiqueName': widget.boutiqueName,
        'createdBy': FirebaseAuth.instance.currentUser?.uid ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      debugPrint('CREATE DISCOUNT CODE ERROR: $e');
      _snack('Failed to create code. Try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('New Discount Code', style: AppTextStyles.headingSmall),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: AppColors.border, thickness: 0.5),
            const SizedBox(height: 16),
            Text('Code', style: AppTextStyles.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration('e.g. SUMMER20'),
            ),
            const SizedBox(height: 16),
            Text('Discount type', style: AppTextStyles.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                _typeChip('percentage', 'Percentage %'),
                const SizedBox(width: 10),
                _typeChip('flat', 'Flat (KWD)'),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _type == 'percentage'
                  ? 'Percentage off (1–100)'
                  : 'Amount off (KWD)',
              style: AppTextStyles.labelLarge,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _valueController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              onEditingComplete: () => FocusScope.of(context).unfocus(),
              decoration: _inputDecoration(
                _type == 'percentage' ? 'e.g. 15' : 'e.g. 2.500',
              ),
            ),
            const SizedBox(height: 16),
            Text('Description (optional)', style: AppTextStyles.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _descController,
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration('e.g. Summer sale'),
            ),
            const SizedBox(height: 16),
            _switchRow(
              'Single use per customer',
              'Each customer can only use this once.',
              _singleUse,
              (v) => setState(() => _singleUse = v),
            ),
            const SizedBox(height: 12),
            _switchRow(
              'Total usage limit',
              'Auto-deactivates after N uses.',
              _hasUsageLimit,
              (v) => setState(() => _hasUsageLimit = v),
            ),
            if (_hasUsageLimit) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _limitController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onEditingComplete: () => FocusScope.of(context).unfocus(),
                decoration: _inputDecoration('e.g. 50'),
              ),
            ],
            const SizedBox(height: 12),
            _switchRow(
              'Set expiry date',
              'Code stops working after this date.',
              _hasExpiry,
              (v) {
                setState(() {
                  _hasExpiry = v;
                  if (!v) _expiryDate = null;
                });
              },
            ),
            if (_hasExpiry) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _pickExpiryDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.field,
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Text(
                    _expiryDate == null
                        ? 'Tap to pick a date'
                        : '${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: _expiryDate == null
                          ? AppColors.secondaryText
                          : AppColors.primaryText,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.deepAccent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white,
                        ),
                      )
                    : Text('Create Code', style: AppTextStyles.button),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(String value, String label) {
    final selected = _type == value;
    return GestureDetector(
      onTap: () => setState(() => _type = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.deepAccent : Colors.transparent,
          border: Border.all(
            color: selected ? AppColors.deepAccent : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelLarge.copyWith(
            color: selected ? Colors.white : AppColors.primaryText,
          ),
        ),
      ),
    );
  }

  Widget _switchRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.labelLarge),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.deepAccent,
          activeTrackColor: AppColors.softAccent,
        ),
      ],
    );
  }
}
