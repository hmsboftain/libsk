import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../core/constants/countries.dart';
import '../navigation/app_header.dart';
import '../services/currency_service.dart';
import '../widgets/theme.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

// ── Dispute filter enum ───────────────────────────────────────────────────────

enum _DisputeFilter { all, open, underReview, resolved, rejected }

String _filterLabel(_DisputeFilter filter, AppLocalizations l10n) {
  switch (filter) {
    case _DisputeFilter.all:
      return l10n.filterAll;
    case _DisputeFilter.open:
      return l10n.disputeStatusOpen;
    case _DisputeFilter.underReview:
      return l10n.disputeStatusUnderReview;
    case _DisputeFilter.resolved:
      return l10n.disputeStatusResolved;
    case _DisputeFilter.rejected:
      return l10n.disputeStatusRejected;
  }
}

bool _matchesFilter(String dataStatus, _DisputeFilter filter) {
  switch (filter) {
    case _DisputeFilter.all:
      return true;
    case _DisputeFilter.open:
      return dataStatus == 'Open';
    case _DisputeFilter.underReview:
      return dataStatus == 'Under Review';
    case _DisputeFilter.resolved:
      return dataStatus == 'Resolved';
    case _DisputeFilter.rejected:
      return dataStatus == 'Rejected';
  }
}

// ── Pure helpers ──────────────────────────────────────────────────────────────

Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'open':
      return AppColors.deepAccent;
    case 'under review':
      return AppColors.primaryText;
    case 'resolved':
      return AppColors.primaryText;
    case 'rejected':
      return AppColors.secondaryText;
    default:
      return AppColors.deepAccent;
  }
}

Color _statusBgColor(String status) {
  switch (status.toLowerCase()) {
    case 'open':
      return AppColors.selectedSoft;
    case 'under review':
      return AppColors.field;
    case 'resolved':
      return AppColors.selectedSoft;
    case 'rejected':
      return AppColors.disabledField;
    default:
      return AppColors.softAccent;
  }
}

String _localizeDisputeStatus(String status, AppLocalizations l10n) {
  switch (status) {
    case 'Open':
      return l10n.disputeStatusOpen;
    case 'Under Review':
      return l10n.disputeStatusUnderReview;
    case 'Resolved':
      return l10n.disputeStatusResolved;
    case 'Rejected':
      return l10n.disputeStatusRejected;
    default:
      return status;
  }
}

// ── Page ──────────────────────────────────────────────────────────────────────

class DisputesPage extends StatefulWidget {
  const DisputesPage({super.key});

  @override
  State<DisputesPage> createState() => _DisputesPageState();
}

class _DisputesPageState extends State<DisputesPage> {
  _DisputeFilter _selectedFilter = _DisputeFilter.all;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _disputesStream;

  @override
  void initState() {
    super.initState();
    _disputesStream = FirebaseFirestore.instance
        .collection('disputes')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _updateDisputeStatus({
    required String disputeId,
    required String newStatus,
    required String paymentIntentId,
    required double orderTotal,
  }) async {
    final l10n = AppLocalizations.of(context)!;

    if (newStatus == 'Resolved') {
      final confirm = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.background,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: AppColors.border, width: 0.5),
          ),
          title: Text(l10n.resolveDispute, style: AppTextStyles.headingSmall),
          content: Text(
            l10n.resolveDisputeQuestion,
            style: AppTextStyles.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                l10n.cancel,
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.secondaryText,
                ),
              ),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'resolve_no_refund'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.deepAccent,
                side: const BorderSide(
                  color: AppColors.deepAccent,
                  width: 0.5,
                ),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              child: Text(l10n.resolveNoRefund),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'resolve_with_refund'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              child: Text(l10n.resolveWithRefund, style: AppTextStyles.button),
            ),
          ],
        ),
      );

      if (confirm == null) return;

      if (confirm == 'resolve_with_refund') {
        if (paymentIntentId.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.noPaymentIntentFound)),
          );
          return;
        }

        try {
          final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable('processRefund');
          await callable.call({'paymentIntentId': paymentIntentId});

          await FirebaseFirestore.instance
              .collection('disputes')
              .doc(disputeId)
              .update({
            'status': 'Resolved',
            'refundIssued': true,
            'resolvedAt': FieldValue.serverTimestamp(),
          });

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.disputeResolvedWithRefund)),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.failedToProcessRefund)),
          );
        }
        return;
      }

      // Resolve without refund — wrapped in try/catch
      try {
        await FirebaseFirestore.instance
            .collection('disputes')
            .doc(disputeId)
            .update({
          'status': 'Resolved',
          'refundIssued': false,
          'resolvedAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.disputeResolved)),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToUpdateDispute)),
        );
      }
      return;
    }

    // All other status updates
    try {
      await FirebaseFirestore.instance
          .collection('disputes')
          .doc(disputeId)
          .update({'status': newStatus});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.disputeMarkedAs(_localizeDisputeStatus(newStatus, l10n)),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.failedToUpdateDispute)),
      );
    }
  }

  Widget _buildStatusFilter(AppLocalizations l10n) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _DisputeFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _DisputeFilter.values[index];
          final isSelected = _selectedFilter == filter;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = filter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.deepAccent : AppColors.field,
                border: Border.all(
                  color:
                      isSelected ? AppColors.deepAccent : AppColors.border,
                  width: 0.5,
                ),
              ),
              child: Text(
                _filterLabel(filter, l10n),
                style: AppTextStyles.labelSmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color:
                      isSelected ? Colors.white : AppColors.secondaryText,
                ),
              ),
            ),
          );
        },
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
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _disputesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                        strokeWidth: 1.5,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        l10n.failedToLoadDisputes,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.secondaryText,
                        ),
                      ),
                    );
                  }

                  final allDocs = snapshot.data?.docs ?? [];
                  final filtered = allDocs
                      .where((doc) => _matchesFilter(
                            doc.data()['status']?.toString() ?? '',
                            _selectedFilter,
                          ))
                      .toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Row(
                          children: [
                            Text(
                              l10n.disputes,
                              style: AppTextStyles.displayMedium,
                            ),
                            const Spacer(),
                            Text(
                              l10n.disputesCount(filtered.length),
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildStatusFilter(l10n),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  l10n.noDisputesFound,
                                  style: AppTextStyles.bodyMedium,
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  8,
                                  20,
                                  30,
                                ),
                                itemCount: filtered.length,
                                itemBuilder: (context, index) => _DisputeCard(
                                  doc: filtered[index],
                                  onStatusUpdate: _updateDisputeStatus,
                                ),
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
    );
  }
}

// ── Dispute card widget ───────────────────────────────────────────────────────

class _DisputeCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Future<void> Function({
    required String disputeId,
    required String newStatus,
    required String paymentIntentId,
    required double orderTotal,
  }) onStatusUpdate;

  const _DisputeCard({required this.doc, required this.onStatusUpdate});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final data = doc.data();
    final disputeId = doc.id;

    final orderNumber = data['orderNumber']?.toString() ?? '-';
    final customerName = data['customerName']?.toString() ?? l10n.unknown;
    final customerEmail = data['customerEmail']?.toString() ?? '';
    final category = data['category']?.toString() ?? '-';
    final description = data['description']?.toString() ?? '';
    final status = data['status']?.toString() ?? 'Open';
    final paymentIntentId = data['paymentIntentId']?.toString() ?? '';
    final refundIssued = data['refundIssued'] == true;

    final orderTotalValue = data['orderTotal'] ?? 0;
    final double orderTotal = orderTotalValue is num
        ? orderTotalValue.toDouble()
        : double.tryParse(orderTotalValue.toString()) ?? 0;

    final createdAt = data['createdAt'];
    String dateString = '-';
    if (createdAt is Timestamp) {
      final date = createdAt.toDate();
      dateString = '${date.day}/${date.month}/${date.year}';
    }

    final availableStatuses = ['Open', 'Under Review', 'Resolved', 'Rejected']
        .where((s) => s != status)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.orderNumber(orderNumber),
                  style: AppTextStyles.bodyLarge
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _statusBgColor(status),
                  border: Border.all(
                    color: _statusColor(status).withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  _localizeDisputeStatus(status, l10n),
                  style: AppTextStyles.capsLabel.copyWith(
                    fontWeight: FontWeight.w600,
                    color: _statusColor(status),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Customer
          Text(
            customerName,
            style:
                AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          if (customerEmail.isNotEmpty)
            Text(customerEmail, style: AppTextStyles.bodySmall),
          const SizedBox(height: 10),

          // Category chip
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.softAccent.withValues(alpha: 0.3),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Text(
              category,
              style: AppTextStyles.labelSmall.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.deepAccent,
              ),
            ),
          ),

          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              description,
              style: AppTextStyles.bodySmall.copyWith(height: 1.4),
            ),
          ],

          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                _fmt(orderTotal),
                style: AppTextStyles.bodySmall,
              ),
              const Spacer(),
              Text(dateString, style: AppTextStyles.bodySmall),
            ],
          ),

          if (refundIssued) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.selectedSoft,
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.deepAccent,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.refundIssued,
                    style: AppTextStyles.labelSmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.deepAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Action buttons — only shown when not terminal status
          if (status != 'Resolved' && status != 'Rejected') ...[
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: availableStatuses.map((s) {
                final isResolve = s == 'Resolved';
                final isReject = s == 'Rejected';
                return GestureDetector(
                  onTap: () => onStatusUpdate(
                    disputeId: disputeId,
                    newStatus: s,
                    paymentIntentId: paymentIntentId,
                    orderTotal: orderTotal,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isResolve
                          ? AppColors.selectedSoft
                          : isReject
                              ? AppColors.disabledField
                              : AppColors.field,
                      border: Border.all(
                        color: AppColors.border,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      _localizeDisputeStatus(s, l10n),
                      style: AppTextStyles.labelLarge.copyWith(
                        color: isResolve || isReject
                            ? AppColors.deepAccent
                            : AppColors.secondaryText,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}