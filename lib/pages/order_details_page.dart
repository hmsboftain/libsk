import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../widgets/order_item.dart';
import '../widgets/theme.dart';
import 'package:cloud_functions/cloud_functions.dart';

class OrderDetailsPage extends StatefulWidget {
  final OrderItem order;

  const OrderDetailsPage({super.key, required this.order});

  @override
  State<OrderDetailsPage> createState() => _OrderDetailsPageState();
}

class _OrderDetailsPageState extends State<OrderDetailsPage> {
  bool _isSubmittingDispute = false;
  bool _disputeAlreadySubmitted = false;

  final List<String> _disputeCategories = [
    'Wrong Item',
    'Damaged Item',
    'Not Delivered',
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
    final daysSince = DateTime.now().difference(widget.order.createdAt!).inDays;
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
          shape: const RoundedRectangleBorder(),
          title: Text('Submit Dispute', style: AppTextStyles.headingSmall),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What is the issue with your order?',
                  style: AppTextStyles.bodySmall,
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
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.selectedSoft
                            : AppColors.field,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.deepAccent
                              : AppColors.border,
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              category,
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: isSelected
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                                color: isSelected
                                    ? AppColors.deepAccent
                                    : AppColors.primaryText,
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check,
                              color: AppColors.deepAccent,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Text(
                  'Additional details (optional)',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Describe the issue...',
                    hintStyle: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.secondaryText,
                    ),
                    filled: true,
                    fillColor: AppColors.field,
                    border: OutlineInputBorder(
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
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.secondaryText,
                ),
              ),
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
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('Submit', style: AppTextStyles.button),
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
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('submitDispute');

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
        SnackBar(content: Text(e.message ?? 'Failed to submit dispute')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to submit dispute')));
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
                      style: AppTextStyles.headingLarge,
                    ),
                    const SizedBox(height: 8),
                    const Divider(color: AppColors.border, thickness: 0.5),
                    const SizedBox(height: 18),
                    Text(
                      "${AppLocalizations.of(context)!.dateLabel} ${widget.order.displayDate}",
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.field,
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: Text(
                        "${AppLocalizations.of(context)!.statusLabel} ${widget.order.status}",
                        style: AppTextStyles.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppLocalizations.of(context)!.itemsOrdered,
                      style: AppTextStyles.headingMedium,
                    ),
                    const SizedBox(height: 16),
                    ...widget.order.orderedItems.map((item) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          border: Border.all(
                            color: AppColors.border,
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 70,
                              child: AspectRatio(
                                aspectRatio: 4 / 5,
                                child: item.imageUrl.isNotEmpty
                                    ? Image.network(
                                        item.imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            color: AppColors.imagePlaceholder,
                                            alignment: Alignment.center,
                                            child: const Icon(
                                              Icons
                                                  .image_not_supported_outlined,
                                              color: AppColors.secondaryText,
                                            ),
                                          );
                                        },
                                      )
                                    : Container(
                                        color: AppColors.imagePlaceholder,
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.image_not_supported_outlined,
                                          color: AppColors.secondaryText,
                                        ),
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
                                    style: AppTextStyles.labelLarge,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    item.description,
                                    style: AppTextStyles.bodySmall,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "${AppLocalizations.of(context)!.size} ${item.size}",
                                    style: AppTextStyles.bodyMedium,
                                  ),
                                  if (item.color.trim().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Colour: ${item.color}',
                                      style: AppTextStyles.bodyMedium,
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    "${AppLocalizations.of(context)!.quantityLabel} ${item.quantity}",
                                    style: AppTextStyles.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              "${item.price.toStringAsFixed(0)} KWD",
                              style: AppTextStyles.labelLarge,
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
                          style: AppTextStyles.bodyMedium,
                        ),
                        const Spacer(),
                        Text(
                          "${subtotal.toStringAsFixed(0)} KWD",
                          style: AppTextStyles.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          AppLocalizations.of(context)!.total,
                          style: AppTextStyles.headingSmall,
                        ),
                        const Spacer(),
                        Text(
                          "${widget.order.total.toStringAsFixed(0)} KWD",
                          style: AppTextStyles.headingSmall,
                        ),
                      ],
                    ),

                    // Dispute section
                    if (widget.order.status.toLowerCase() == 'delivered') ...[
                      const SizedBox(height: 30),
                      const Divider(color: AppColors.border, thickness: 0.5),
                      const SizedBox(height: 16),
                      if (_disputeAlreadySubmitted)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.selectedSoft,
                            border: Border.all(
                              color: AppColors.border,
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: AppColors.deepAccent,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'A dispute has already been submitted for this order.',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.deepAccent,
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
                                      strokeWidth: 1.5,
                                      color: AppColors.deepAccent,
                                    ),
                                  )
                                : const Icon(
                                    Icons.flag_outlined,
                                    color: AppColors.deepAccent,
                                  ),
                            label: Text(
                              'Dispute Order',
                              style: AppTextStyles.button.copyWith(
                                color: AppColors.deepAccent,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(
                                color: AppColors.deepAccent,
                                width: 0.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.field,
                            border: Border.all(
                              color: AppColors.border,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            'The 7-day dispute window for this order has passed.',
                            style: AppTextStyles.bodySmall,
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
