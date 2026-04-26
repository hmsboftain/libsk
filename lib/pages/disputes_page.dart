import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../navigation/app_header.dart';
import '../widgets/theme.dart';

class DisputesPage extends StatefulWidget {
  const DisputesPage({super.key});

  @override
  State<DisputesPage> createState() => _DisputesPageState();
}

class _DisputesPageState extends State<DisputesPage> {
  String _filterStatus = 'All';
  final List<String> _statusFilters = [
    'All',
    'Open',
    'Under Review',
    'Resolved',
    'Rejected',
  ];

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return const Color(0xFF9B4A4A);
      case 'under review':
        return const Color(0xFFB87D3B);
      case 'resolved':
        return const Color(0xFF3D6B45);
      case 'rejected':
        return AppColors.secondaryText;
      default:
        return AppColors.deepAccent;
    }
  }

  Color _statusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return const Color(0xFFF7E8E8);
      case 'under review':
        return const Color(0xFFF8F0E4);
      case 'resolved':
        return const Color(0xFFE8F2EA);
      case 'rejected':
        return AppColors.field;
      default:
        return AppColors.softAccent;
    }
  }

  Future<void> _updateDisputeStatus({
    required String disputeId,
    required String newStatus,
    required String paymentIntentId,
    required double orderTotal,
  }) async {
    // If resolving with refund
    if (newStatus == 'Resolved') {
      final confirm = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Resolve Dispute',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'How would you like to resolve this dispute?',
            style: TextStyle(color: AppColors.secondaryText, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.secondaryText),
              ),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'resolve_no_refund'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF3D6B45),
                side: const BorderSide(color: Color(0xFF3D6B45)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Resolve — No Refund'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'resolve_with_refund'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3D6B45),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Resolve + Refund'),
            ),
          ],
        ),
      );

      if (confirm == null) return;

      if (confirm == 'resolve_with_refund') {
        if (paymentIntentId.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No payment intent found for this order'),
            ),
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
            const SnackBar(
              content: Text(
                'Dispute resolved and refund issued successfully',
              ),
            ),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to process refund: $e')),
          );
        }
        return;
      }

      // Resolve without refund
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
        const SnackBar(content: Text('Dispute resolved')),
      );
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
        SnackBar(content: Text('Dispute marked as $newStatus')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update dispute')),
      );
    }
  }

  Widget _buildStatusFilter() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _statusFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _statusFilters[index];
          final isSelected = _filterStatus == filter;

          return GestureDetector(
            onTap: () => setState(() => _filterStatus = filter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.deepAccent : AppColors.field,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.deepAccent : AppColors.border,
                ),
              ),
              child: Text(
                filter,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.secondaryText,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDisputeCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final disputeId = doc.id;

    final orderNumber = data['orderNumber']?.toString() ?? '-';
    final customerName = data['customerName']?.toString() ?? 'Unknown';
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

    final List<String> availableStatuses = [
      'Open',
      'Under Review',
      'Resolved',
      'Rejected',
    ].where((s) => s != status).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                child: Text(
                  'Order #$orderNumber',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _statusBgColor(status),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
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
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
            ),
          ),
          if (customerEmail.isNotEmpty)
            Text(
              customerEmail,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.secondaryText,
              ),
            ),
          const SizedBox(height: 10),

          // Category chip
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.softAccent.withValues(alpha:0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              category,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.deepAccent,
              ),
            ),
          ),

          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.secondaryText,
                height: 1.4,
              ),
            ),
          ],

          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Order total: ${orderTotal.toStringAsFixed(0)} KWD',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryText,
                ),
              ),
              const Spacer(),
              Text(
                dateString,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),

          if (refundIssued) ...[
            const SizedBox(height: 8),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F2EA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Color(0xFF3D6B45),
                    size: 14,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Refund issued',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF3D6B45),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Action buttons — only if not resolved or rejected
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
                  onTap: () => _updateDisputeStatus(
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
                          ? const Color(0xFFE8F2EA)
                          : isReject
                          ? const Color(0xFFF7E8E8)
                          : AppColors.field,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isResolve
                            ? const Color(0xFF3D6B45)
                            : isReject
                            ? const Color(0xFF9B4A4A)
                            : AppColors.border,
                      ),
                    ),
                    child: Text(
                      s,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isResolve
                            ? const Color(0xFF3D6B45)
                            : isReject
                            ? const Color(0xFF9B4A4A)
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('disputes')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'Failed to load disputes',
                        style: TextStyle(color: AppColors.secondaryText),
                      ),
                    );
                  }

                  final allDocs = snapshot.data?.docs ?? [];
                  final filtered = _filterStatus == 'All'
                      ? allDocs
                      : allDocs
                      .where(
                        (doc) => doc.data()['status'] == _filterStatus,
                  )
                      .toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Row(
                          children: [
                            const Text(
                              'DISPUTES',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryText,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${filtered.length} ${filtered.length == 1 ? 'dispute' : 'disputes'}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildStatusFilter(),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                          child: Text(
                            'No disputes found',
                            style: TextStyle(
                              color: AppColors.secondaryText,
                            ),
                          ),
                        )
                            : ListView.builder(
                          padding:
                          const EdgeInsets.fromLTRB(20, 8, 20, 30),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) =>
                              _buildDisputeCard(filtered[index]),
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