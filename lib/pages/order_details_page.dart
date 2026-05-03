import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../widgets/order_item.dart';
import '../widgets/theme.dart';
import 'package:cloud_functions/cloud_functions.dart';

class OrderDetailsPage extends StatefulWidget {
  final OrderItem order;

  const OrderDetailsPage({
    super.key,
    required this.order,
  });

  @override
  State<OrderDetailsPage> createState() => _OrderDetailsPageState();
}

class _OrderDetailsPageState extends State<OrderDetailsPage> {
  bool _isSubmittingDispute = false;
  bool _disputeAlreadySubmitted = false;

  final List<String> _disputeCategories = [
    'Item Damaged',
    'Wrong Item Sent',
    'Item Never Arrived',
    'Not As Described',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _checkExistingDispute();
  }

  Future<void> _checkExistingDispute() async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('disputes')
          .where('orderId', isEqualTo: widget.order.id)
          .limit(1)
          .get();

      if (!mounted) return;
      if (query.docs.isNotEmpty) {
        setState(() => _disputeAlreadySubmitted = true);
      }
    } catch (_) {}
  }

  bool get _canDispute {
    if (widget.order.status.toLowerCase() != 'delivered') return false;
    if (_disputeAlreadySubmitted) return false;
    if (widget.order.createdAt == null) return true;
    final daysSince =
        DateTime.now().difference(widget.order.createdAt!).inDays;
    return daysSince <= 7;
  }

  Future<void> _showDisputeDialog() async {
    String? selectedCategory;
    final descController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.background,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Submit Dispute',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'What is the issue with your order?',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 16),
                ..._disputeCategories.map((category) {
                  final isSelected = selectedCategory == category;
                  return GestureDetector(
                    onTap: () =>
                        setDialogState(() => selectedCategory = category),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.softAccent.withValues(alpha:0.4)
                            : AppColors.field,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.deepAccent
                              : AppColors.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              category,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? AppColors.deepAccent
                                    : AppColors.primaryText,
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check,
                                color: AppColors.deepAccent, size: 18),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                const Text(
                  'Additional details (optional)',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Describe the issue...',
                    hintStyle: const TextStyle(
                        color: AppColors.secondaryText, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.field,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                      const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                      const BorderSide(color: AppColors.deepAccent),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.secondaryText)),
            ),
            ElevatedButton(
              onPressed: selectedCategory == null
                  ? null
                  : () async {
                Navigator.pop(ctx);
                await _submitDispute(
                  category: selectedCategory!,
                  description: descController.text.trim(),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitDispute({
    required String category,
    required String description,
  }) async {
    setState(() => _isSubmittingDispute = true);

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('submitDispute');

      await callable.call({
        'orderId': widget.order.id,
        'category': category,
        'description': description,
      });

      if (!mounted) return;

      setState(() => _disputeAlreadySubmitted = true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dispute submitted. Our team will review it within 24 hours.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Failed to submit dispute'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit dispute')),
      );
    } finally {
      if (mounted) setState(() => _isSubmittingDispute = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double subtotal = 0;
    for (var item in widget.order.orderedItems) {
      subtotal += item.price * item.quantity;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      "${AppLocalizations.of(context)!.orderLabel} #${widget.order.orderNumber}",
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 18),
                    Text(
                      "${AppLocalizations.of(context)!.dateLabel} ${widget.order.displayDate}",
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.field,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        "${AppLocalizations.of(context)!.statusLabel} ${widget.order.status}",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppLocalizations.of(context)!.itemsOrdered,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...widget.order.orderedItems.map((item) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.field,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: item.imageUrl.isNotEmpty
                                  ? Image.network(
                                item.imageUrl,
                                width: 70,
                                height: 85,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (context, error, stackTrace) {
                                  return Container(
                                    width: 70,
                                    height: 85,
                                    color: AppColors.imagePlaceholder,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons
                                          .image_not_supported_outlined,
                                      color: Colors.black54,
                                    ),
                                  );
                                },
                              )
                                  : Container(
                                width: 70,
                                height: 85,
                                color: AppColors.imagePlaceholder,
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.image_not_supported_outlined,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    item.description,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "${AppLocalizations.of(context)!.size} ${item.size}",
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${AppLocalizations.of(context)!.quantityLabel} ${item.quantity}",
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              "${item.price.toStringAsFixed(0)} KWD",
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          AppLocalizations.of(context)!.subtotalNormal,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          "${subtotal.toStringAsFixed(0)} KWD",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          AppLocalizations.of(context)!.total,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          "${widget.order.total.toStringAsFixed(0)} KWD",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),

                    // Dispute section
                    if (widget.order.status.toLowerCase() == 'delivered') ...[
                      const SizedBox(height: 30),
                      const Divider(),
                      const SizedBox(height: 16),
                      if (_disputeAlreadySubmitted)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F0E4),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: const Color(0xFFB87D3B)
                            ),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.info_outline,
                                  color: Color(0xFFB87D3B), size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'A dispute has already been submitted for this order.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFFB87D3B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (_canDispute)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isSubmittingDispute
                                ? null
                                : _showDisputeDialog,
                            icon: _isSubmittingDispute
                                ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.deepAccent,
                              ),
                            )
                                : const Icon(Icons.flag_outlined,
                                color: AppColors.deepAccent),
                            label: const Text(
                              'Dispute Order',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.deepAccent,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding:
                              const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(
                                  color: AppColors.deepAccent),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.field,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Text(
                            'The 7-day dispute window for this order has passed.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.secondaryText,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}