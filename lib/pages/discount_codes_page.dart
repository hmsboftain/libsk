import 'package:cloud_firestore/cloud_firestore.dart';
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

String _formatDate(Timestamp? ts) {
  if (ts == null) return 'No expiry';
  final d = ts.toDate();
  return '${d.day}/${d.month}/${d.year}';
}

/// Superadmin oversight of every boutique's discount codes: review them, pause
/// or resume one, or delete it. Codes are created ONLY by boutique owners (see
/// OwnerDiscountCodesPage) — every code belongs to exactly one boutique, so
/// there is no way to create a code here.
class DiscountCodesPage extends StatefulWidget {
  const DiscountCodesPage({super.key});

  @override
  State<DiscountCodesPage> createState() => _DiscountCodesPageState();
}

class _DiscountCodesPageState extends State<DiscountCodesPage> {
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
                // Super admin sees ALL codes — no filter
                stream: _db.collection('discount_codes').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                        strokeWidth: 1.5,
                      ),
                    );
                  }

                  // Sort client-side — newest first
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
                            Text(
                              'Discount Codes',
                              style: AppTextStyles.headingMedium,
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
                                  'No discount codes yet.\nBoutiques create their own from their dashboard.',
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
    final boutiqueName = data['boutiqueName']?.toString() ?? '';

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
          if (boutiqueName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              boutiqueName,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: 4),
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
