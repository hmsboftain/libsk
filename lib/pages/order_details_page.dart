import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../widgets/cart_item.dart';
import '../widgets/order_item.dart';
import '../widgets/theme.dart';
import '../core/constants/countries.dart';
import '../services/currency_service.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

// ── Pure helpers ──────────────────────────────────────────────────────────────

double _calculateSubtotal(List<CartItem> items) {
  return items.fold(0.0, (total, item) => total + item.price * item.quantity);
}

// ── Page ──────────────────────────────────────────────────────────────────────

class OrderDetailsPage extends StatefulWidget {
  final OrderItem order;

  const OrderDetailsPage({super.key, required this.order});

  @override
  State<OrderDetailsPage> createState() => _OrderDetailsPageState();
}

class _OrderDetailsPageState extends State<OrderDetailsPage> {
  bool _isSubmittingDispute = false;
  bool _disputeAlreadySubmitted = false;

  // Declared as a field so it can be properly disposed
  final _descController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkExistingDispute();
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
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
    return DateTime.now().difference(widget.order.createdAt!).inDays <= 7;
  }

  Future<void> _showDisputeDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final disputeCategories = [
      l10n.disputeWrongItem,
      l10n.disputeDamagedItem,
      l10n.disputeNotDelivered,
      l10n.disputeOther,
    ];
    String? selectedCategory;
    _descController.clear();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.background,
          shape: const RoundedRectangleBorder(),
          title: Text(l10n.submitDispute, style: AppTextStyles.headingSmall),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.disputeIssueQuestion, style: AppTextStyles.bodySmall),
                const SizedBox(height: 16),
                ...disputeCategories.map((category) {
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
                  l10n.additionalDetailsOptional,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descController,
                  maxLines: 3,
                  decoration: const InputDecoration(),
                ),
              ],
            ),
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
            ElevatedButton(
              onPressed: selectedCategory == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _submitDispute(
                        category: selectedCategory!,
                        description: _descController.text.trim(),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              child: Text(l10n.submit, style: AppTextStyles.button),
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
    final l10n = AppLocalizations.of(context)!;
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
        SnackBar(
          content: Text(l10n.disputeSubmittedReviewSoon),
          duration: const Duration(seconds: 3),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? l10n.failedToSubmitDispute)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.failedToSubmitDispute)));
    } finally {
      if (mounted) setState(() => _isSubmittingDispute = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final subtotal = _calculateSubtotal(widget.order.orderedItems);

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
                      l10n.orderNumber(widget.order.orderNumber),
                      style: AppTextStyles.headingLarge,
                    ),
                    const SizedBox(height: 8),
                    const Divider(color: AppColors.border, thickness: 0.5),
                    const SizedBox(height: 18),
                    Text(
                      l10n.orderDate(widget.order.displayDate),
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
                        '${l10n.statusLabel} ${widget.order.status}',
                        style: AppTextStyles.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(l10n.itemsOrdered, style: AppTextStyles.headingMedium),
                    const SizedBox(height: 16),
                    ...widget.order.orderedItems.map(
                      (item) => _OrderItemRow(item: item, l10n: l10n),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text(l10n.subtotal, style: AppTextStyles.bodyMedium),
                        const Spacer(),
                        Text(_fmt(subtotal), style: AppTextStyles.bodyMedium),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(l10n.total, style: AppTextStyles.headingSmall),
                        const Spacer(),
                        Text(
                          _fmt(widget.order.total),
                          style: AppTextStyles.headingSmall,
                        ),
                      ],
                    ),

                    // ── Dispute section ───────────────────────────────
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
                                  l10n.disputeAlreadySubmitted,
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
                              l10n.disputeOrder,
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
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
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
                            l10n.disputeWindowPassed,
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

// ── Order item row widget ─────────────────────────────────────────────────────

class _OrderItemRow extends StatelessWidget {
  final CartItem item;
  final AppLocalizations l10n;

  const _OrderItemRow({required this.item, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: AspectRatio(
              aspectRatio: 4 / 5,
              child: item.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: item.imageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.imagePlaceholder,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.secondaryText,
                        ),
                      ),
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
                Text(item.title, style: AppTextStyles.labelLarge),
                const SizedBox(height: 6),
                Text(item.description, style: AppTextStyles.bodySmall),
                const SizedBox(height: 6),
                Text(
                  l10n.sizeLabel(item.size),
                  style: AppTextStyles.bodyMedium,
                ),
                if (item.color.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${l10n.colourLabel}: ${item.color}',
                    style: AppTextStyles.bodyMedium,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${l10n.quantityLabel} ${item.quantity}',
                  style: AppTextStyles.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(_fmt(item.price), style: AppTextStyles.labelLarge),
        ],
      ),
    );
  }
}
