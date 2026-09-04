import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/utils/image_sizing.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../widgets/cart_item.dart';
import '../widgets/order_item.dart';
import '../widgets/theme.dart';
import '../core/constants/countries.dart';
import '../services/currency_service.dart';
import '../services/wasal_service.dart';

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

/// Customer-facing courier status — where the driver physically is with the
/// package, as pushed by Wasal webhooks (same mapping as the owner view).
String _localizedWasalStatus(String status, AppLocalizations l10n) {
  switch (status) {
    case 'pending':
      return l10n.wasalStatusPending;
    case 'assigned':
      return l10n.wasalStatusAssigned;
    case 'on_way_to_merchant':
      return l10n.wasalStatusOnWayToMerchant;
    case 'picked_up':
      return l10n.wasalStatusPickedUp;
    case 'in_transit':
      return l10n.wasalStatusInTransit;
    case 'delivered':
      return l10n.wasalStatusDelivered;
    case 'failed':
      return l10n.wasalStatusFailed;
    case 'returned':
      return l10n.wasalStatusReturned;
    case 'cancelled':
      return l10n.wasalStatusCancelled;
    default:
      return status;
  }
}

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
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () => FocusScope.of(ctx).unfocus(),
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
    // Re-entrancy guard: drop a rapid second tap on the dialog's submit before
    // it dismisses, so the dispute can't be filed twice.
    if (_isSubmittingDispute) return;
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
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
        child: Column(
          children: [
            const AppHeader(showBackButton: true),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                        l10n.statusLabel(widget.order.status),
                        style: AppTextStyles.labelLarge,
                      ),
                    ),
                    // ── Live delivery tracking (Wasal) ────────────────
                    // Timeline + driver-location map, driven by the
                    // getWasalTracking callable. Falls back to the last-known
                    // courier status carried on the order when the callable is
                    // unavailable, so the customer always sees something.
                    _DeliveryTrackingSection(
                      orderId: widget.order.id,
                      initialStatus: widget.order.wasalStatus,
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
                      memCacheWidth: gridTileCacheWidth,
                      maxWidthDiskCache: maxImageDiskCacheWidth,
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
                    l10n.colourLabel(item.color),
                    style: AppTextStyles.bodyMedium,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  l10n.quantityLabel(item.quantity.toString()),
                  style: AppTextStyles.bodyMedium,
                ),
                if (item.specialRequest.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.specialRequest,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.deepAccent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.specialRequest,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.secondaryText,
                      height: 1.35,
                    ),
                  ),
                ],
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

// ── Live delivery tracking ────────────────────────────────────────────────────

/// Poll interval while a delivery is still moving. Kept deliberately modest —
/// the Wasal key is rate-limited (600 req / 15 min, shared across all traffic)
/// and getWasalTracking caches for 15s server-side, so this only needs to be
/// responsive, not tight.
const _kTrackingPollInterval = Duration(seconds: 30);

/// The main forward path every delivery walks. `on_hold` (a temporary pause)
/// and the negative terminals (failed / returned / cancelled) are rendered as a
/// distinct final row when they are the current status, rather than as steps.
const _kMainDeliverySteps = [
  'pending',
  'assigned',
  'on_way_to_merchant',
  'picked_up',
  'in_transit',
  'delivered',
];

/// Fetches tracking for the order, renders the timeline + driver map, and polls
/// while any delivery is still in flight. Polling stops on all-terminal, screen
/// dismissal, and app backgrounding (see [didChangeAppLifecycleState]).
class _DeliveryTrackingSection extends StatefulWidget {
  final String orderId;
  final String initialStatus;

  const _DeliveryTrackingSection({
    required this.orderId,
    required this.initialStatus,
  });

  @override
  State<_DeliveryTrackingSection> createState() =>
      _DeliveryTrackingSectionState();
}

class _DeliveryTrackingSectionState extends State<_DeliveryTrackingSection>
    with WidgetsBindingObserver {
  List<WasalDeliveryTracking>? _deliveries;
  bool _fetching = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetch();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Stop polling in the background; resume (with an immediate refresh) on
    // return — no point burning the shared Wasal budget while unseen.
    if (state == AppLifecycleState.resumed) {
      _fetch();
    } else {
      _pollTimer?.cancel();
    }
  }

  bool get _hasActiveDelivery =>
      _deliveries?.any((d) => !d.isTerminal) ?? false;

  void _maybeSchedulePoll() {
    _pollTimer?.cancel();
    // Keep polling only while at least one delivery is still in flight.
    if (!_hasActiveDelivery) return;
    _pollTimer = Timer(_kTrackingPollInterval, _fetch);
  }

  Future<void> _fetch() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final deliveries =
          await WasalService.instance.getTracking(orderId: widget.orderId);
      if (!mounted) return;
      setState(() => _deliveries = deliveries);
    } catch (_) {
      // Keep any previously loaded data and fall back to the last-known status;
      // a transient failure shouldn't blank out the tracking panel.
    } finally {
      _fetching = false;
      if (mounted) _maybeSchedulePoll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final deliveries = _deliveries;

    // No successfully-loaded deliveries (still loading, none dispatched, or the
    // callable failed) → fall back to the last-known courier status if we have
    // one, otherwise render nothing.
    if (deliveries == null || deliveries.isEmpty) {
      if (widget.initialStatus.isEmpty) return const SizedBox.shrink();
      return _fallbackStatusRow(l10n, widget.initialStatus);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        Text(l10n.deliveryTrackingTitle, style: AppTextStyles.headingMedium),
        const SizedBox(height: 16),
        for (var i = 0; i < deliveries.length; i++) ...[
          // For multi-boutique orders, label each delivery by its Wasal number.
          if (deliveries.length > 1 &&
              deliveries[i].wasalOrderNumber.isNotEmpty) ...[
            Text(deliveries[i].wasalOrderNumber, style: AppTextStyles.labelSmall),
            const SizedBox(height: 8),
          ],
          _StatusTimeline(delivery: deliveries[i], l10n: l10n),
          const SizedBox(height: 14),
          _DriverMapArea(delivery: deliveries[i], l10n: l10n),
          if (i != deliveries.length - 1) ...[
            const SizedBox(height: 20),
            const Divider(color: AppColors.border, thickness: 0.5),
            const SizedBox(height: 20),
          ],
        ],
      ],
    );
  }

  Widget _fallbackStatusRow(AppLocalizations l10n, String status) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const Icon(Icons.local_shipping_outlined,
              size: 16, color: AppColors.deepAccent),
          const SizedBox(width: 8),
          Text(
            _localizedWasalStatus(status, l10n),
            style:
                AppTextStyles.bodyMedium.copyWith(color: AppColors.deepAccent),
          ),
        ],
      ),
    );
  }
}

enum _StepState { done, current, future }

class _StatusTimeline extends StatelessWidget {
  final WasalDeliveryTracking delivery;
  final AppLocalizations l10n;

  const _StatusTimeline({required this.delivery, required this.l10n});

  @override
  Widget build(BuildContext context) {
    // When did each status happen? (last occurrence wins) + which were reached.
    final timestamps = <String, DateTime>{};
    final reached = <String>{};
    for (final e in delivery.statusHistory) {
      reached.add(e.status);
      if (e.timestamp != null) timestamps[e.status] = e.timestamp!;
    }
    final current = delivery.status;
    if (current.isNotEmpty) reached.add(current);

    final currentMainIndex = _kMainDeliverySteps.indexOf(current);
    // on_hold / failed / returned / cancelled — off the main forward path.
    final isOffPath = currentMainIndex == -1 && current.isNotEmpty;

    final rows = <Widget>[];
    for (var i = 0; i < _kMainDeliverySteps.length; i++) {
      final step = _kMainDeliverySteps[i];
      final _StepState state;
      if (currentMainIndex >= 0) {
        state = i < currentMainIndex
            ? _StepState.done
            : i == currentMainIndex
                ? _StepState.current
                : _StepState.future;
      } else {
        // Off the main path — light up steps we have evidence of; rest pending.
        state = reached.contains(step) ? _StepState.done : _StepState.future;
      }
      rows.add(_TimelineRow(
        label: _localizedWasalStatus(step, l10n),
        timestamp: timestamps[step],
        state: state,
        isLast: i == _kMainDeliverySteps.length - 1 && !isOffPath,
      ));
    }

    if (isOffPath) {
      rows.add(_TimelineRow(
        label: _localizedWasalStatus(current, l10n),
        timestamp: timestamps[current],
        state: _StepState.current,
        isLast: true,
        icon: _offPathIcon(current),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  IconData _offPathIcon(String status) {
    switch (status) {
      case 'on_hold':
        return Icons.pause_circle_outline;
      case 'failed':
        return Icons.error_outline;
      case 'returned':
        return Icons.assignment_return_outlined;
      case 'cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.radio_button_unchecked;
    }
  }
}

class _TimelineRow extends StatelessWidget {
  final String label;
  final DateTime? timestamp;
  final _StepState state;
  final bool isLast;
  final IconData? icon;

  const _TimelineRow({
    required this.label,
    required this.timestamp,
    required this.state,
    required this.isLast,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final reached = state != _StepState.future;
    final markerColor = reached ? AppColors.deepAccent : AppColors.softAccent;
    final textColor =
        reached ? AppColors.primaryText : AppColors.secondaryText;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Marker column: dot (or status icon) + connector line to the next row.
          Column(
            children: [
              icon != null
                  ? Icon(icon, size: 18, color: markerColor)
                  : Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: reached
                            ? AppColors.deepAccent
                            : Colors.transparent,
                        border: Border.all(color: markerColor, width: 1.5),
                      ),
                    ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: AppColors.border,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: textColor,
                    fontWeight: state == _StepState.current
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                if (timestamp != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _formatTimestamp(timestamp!),
                      style: AppTextStyles.labelSmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTimestamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.day}/${t.month}/${t.year} ${two(t.hour)}:${two(t.minute)}';
}

/// The driver-location map (or a graceful "unavailable" state). Shown only when
/// the delivery is active; a null location never renders a blank map.
class _DriverMapArea extends StatelessWidget {
  final WasalDeliveryTracking delivery;
  final AppLocalizations l10n;

  const _DriverMapArea({required this.delivery, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final loc = delivery.agentLocation;

    // Live location → real map with a driver pin.
    if (loc != null) {
      final point = LatLng(loc.lat, loc.lng);
      return Container(
        height: 200,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: ClipRect(
          child: FlutterMap(
            options: MapOptions(initialCenter: point, initialZoom: 14),
            children: [
              // OpenStreetMap raster tiles: a light-use default that needs no
              // API key and no native platform setup, so tracking ships and is
              // testable immediately. If delivery volume grows, swap this
              // TileLayer + MarkerLayer for google_maps_flutter, which needs a
              // BILLED Google Maps key plus native config in
              // android/app/src/main/AndroidManifest.xml and
              // ios/Runner/AppDelegate.swift. (OSM's public tile server is fine
              // for low volume but is not intended for heavy commercial use.)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.libsk',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: point,
                    width: 44,
                    height: 44,
                    child: const Icon(
                      Icons.local_shipping,
                      color: AppColors.deepAccent,
                      size: 32,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Active delivery but no location yet (driver offline, or a sandbox test
    // driver with no coordinates) → clear "unavailable" state, never a blank map.
    if (delivery.isActiveDelivery) {
      return Container(
        height: 96,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.field,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off_outlined,
                size: 22, color: AppColors.secondaryText),
            const SizedBox(height: 6),
            Text(
              l10n.deliveryDriverLocationUnavailable,
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Pre-assignment or terminal → no map at all.
    return const SizedBox.shrink();
  }
}
