import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../core/utils/image_sizing.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../widgets/error_state_widget.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../services/wasal_service.dart';
import '../widgets/skeleton_loaders.dart';
import '../widgets/theme.dart';
import '../core/constants/countries.dart';
import '../services/currency_service.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

// ── Pure helpers ──────────────────────────────────────────────────────────────

/// Human-readable courier (Wasal) status, distinct from the LIBSK order
/// status — this is where the driver physically is with the package.
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

String _localizedStatus(String status, AppLocalizations l10n) {
  switch (status.toLowerCase()) {
    case 'placed':
      return l10n.statusPlaced;
    case 'confirmed':
      return l10n.statusConfirmed;
    case 'on the way':
      return l10n.statusOnTheWay;
    case 'delivered':
      return l10n.statusDelivered;
    case 'cancelled':
      return l10n.statusCancelled;
    default:
      return status;
  }
}

String _localizedFilter(String filter, AppLocalizations l10n) {
  if (filter == 'All') return l10n.statusAll;
  return _localizedStatus(filter, l10n);
}

Widget _orderStatusBadge(String status, AppLocalizations l10n) {
  Color background;
  Color textColor;

  switch (status.toLowerCase()) {
    case 'confirmed':
      background = AppColors.field;
      textColor = AppColors.primaryText;
      break;
    case 'on the way':
      background = AppColors.selectedSoft;
      textColor = AppColors.deepAccent;
      break;
    case 'delivered':
      background = AppColors.selectedSoft;
      textColor = AppColors.primaryText;
      break;
    case 'cancelled':
      background = AppColors.disabledField;
      textColor = AppColors.deepAccent;
      break;
    default:
      background = AppColors.field;
      textColor = AppColors.secondaryText;
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: background,
      border: Border.all(color: AppColors.border, width: 0.5),
    ),
    child: Text(
      _localizedStatus(status, l10n),
      style: AppTextStyles.bodySmall.copyWith(
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
    ),
  );
}

// ── Filter options ────────────────────────────────────────────────────────────

const _statusFilters = [
  'All',
  'Placed',
  'Confirmed',
  'On the Way',
  'Delivered',
  'Cancelled',
];

// ── Page ──────────────────────────────────────────────────────────────────────

class OwnerOrdersPage extends StatefulWidget {
  const OwnerOrdersPage({super.key});

  @override
  State<OwnerOrdersPage> createState() => _OwnerOrdersPageState();
}

class _OwnerOrdersPageState extends State<OwnerOrdersPage> {
  String? _boutiqueId;
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _loadBoutiqueId();
  }

  Future<void> _loadBoutiqueId() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _boutiqueId = null;
    });

    try {
      final id = await FirestoreService.getCurrentOwnerBoutiqueId();
      if (!mounted) return;
      if (id == null) {
        setState(() {
          _errorMessage = AppLocalizations.of(context)!.noBoutiqueFound;
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _boutiqueId = id;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppLocalizations.of(
          context,
        )!.failedToLoadBoutiqueOrders;
        _isLoading = false;
      });
    }
  }

  Future<void> _onRefresh() => _loadBoutiqueId();

  Future<void> _updateOrderStatus({
    required String boutiqueOrderId,
    required String sourceUserOrderId,
    required String customerUid,
    required String newStatus,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      // The customer order + global_orders docs are admin-only to write, so the
      // change goes through the updateOrderStatus Cloud Function, which verifies
      // boutique ownership server-side and updates all three docs atomically.
      // customerUid / sourceUserOrderId are resolved on the server from the
      // boutique order, so only the boutique order id + new status are sent.
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('updateOrderStatus');
      await callable.call({
        'boutiqueOrderId': boutiqueOrderId,
        'status': newStatus,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.orderStatusUpdated),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.failedToUpdateOrderStatus)));
    }
  }

  /// "Ready for Pickup": the owner has packed this sub-order — the
  /// markReadyForPickup Cloud Function creates the Wasal delivery order from
  /// this boutique's branch and a driver is dispatched to collect it.
  Future<void> _dispatchDelivery(String boutiqueOrderId) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await WasalService.instance.markReadyForPickup(
        boutiqueOrderId: boutiqueOrderId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.deliveryRequested),
          duration: const Duration(seconds: 2),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? l10n.deliveryDispatchFailed)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.deliveryDispatchFailed)));
    }
  }

  Widget _buildFilterChips() {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: _statusFilters.map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedFilter = filter),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.deepAccent : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? AppColors.deepAccent : AppColors.border,
                    width: 0.5,
                  ),
                ),
                child: Text(
                  _localizedFilter(filter, l10n),
                  style: AppTextStyles.labelLarge.copyWith(
                    fontSize: 12,
                    color: isSelected ? Colors.white : AppColors.secondaryText,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilter(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (_selectedFilter == 'All') return docs;
    return docs.where((doc) {
      final status = doc.data()['status']?.toString() ?? '';
      return status.toLowerCase() == _selectedFilter.toLowerCase();
    }).toList();
  }

  Widget _buildOrdersList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.getOwnerOrdersStream(_boutiqueId!),
      builder: (context, snapshot) {
        final l10n = AppLocalizations.of(context)!;

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.symmetric(vertical: 12),
              child: OrdersListSkeleton(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Expanded(
            child: ErrorStateWidget.inline(
              title: l10n.failedToLoadOrders,
              message: l10n.pullDownToRetry,
              onRetry: () => setState(() {}),
              type: ErrorType.network,
            ),
          );
        }

        final allDocs = snapshot.data?.docs ?? [];
        final docs = _applyFilter(allDocs);

        if (allDocs.isEmpty) {
          return Expanded(
            child: RefreshIndicator(
              color: AppColors.deepAccent,
              onRefresh: _onRefresh,
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: 400,
                  child: Center(
                    child: Text(
                      l10n.noOrdersYet,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        if (docs.isEmpty) {
          return Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.noStatusOrders(_localizedFilter(_selectedFilter, l10n)),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
            ),
          );
        }

        return Expanded(
          child: RefreshIndicator(
            color: AppColors.deepAccent,
            onRefresh: _onRefresh,
            child: ListView.builder(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              itemCount: docs.length,
              itemBuilder: (context, index) => _OrderCard(
                doc: docs[index],
                onStatusUpdate: _updateOrderStatus,
                onDispatchDelivery: _dispatchDelivery,
              ),
            ),
          ),
        );
      },
    );
  }

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
            if (!_isLoading &&
                _errorMessage == null &&
                _boutiqueId != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.myOrders,
                    style: AppTextStyles.headingMedium.copyWith(
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _buildFilterChips(),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                        strokeWidth: 1.5,
                      ),
                    )
                  : _errorMessage != null
                  ? RefreshIndicator(
                      color: AppColors.deepAccent,
                      onRefresh: _onRefresh,
                      child: ListView(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _errorMessage!,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.secondaryText,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(children: [_buildOrdersList()]),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ── Order card widget ─────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Future<void> Function({
    required String boutiqueOrderId,
    required String sourceUserOrderId,
    required String customerUid,
    required String newStatus,
  })
  onStatusUpdate;
  final Future<void> Function(String boutiqueOrderId) onDispatchDelivery;

  const _OrderCard({
    required this.doc,
    required this.onStatusUpdate,
    required this.onDispatchDelivery,
  });

  Future<void> _cancelOrder(
    BuildContext context,
    String boutiqueOrderId,
    String sourceUserOrderId,
    String customerUid,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: AppColors.border, width: 0.5),
        ),
        title: Text(l10n.cancelOrder, style: AppTextStyles.headingSmall),
        content: Text(
          l10n.cancelOrderConfirmation,
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.back,
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: Text(l10n.cancelOrder, style: AppTextStyles.button),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await onStatusUpdate(
        boutiqueOrderId: boutiqueOrderId,
        sourceUserOrderId: sourceUserOrderId,
        customerUid: customerUid,
        newStatus: 'Cancelled',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final data = doc.data();
    final boutiqueOrderId = doc.id;

    final orderNumber = data['orderNumber']?.toString() ?? '-';
    final date = data['date']?.toString() ?? '-';
    final status = data['status']?.toString() ?? 'Placed';
    final customerName = data['customerName']?.toString() ?? l10n.customer;
    final customerEmail = data['customerEmail']?.toString() ?? '';
    final customerUid = data['customerUid']?.toString() ?? '';
    final sourceUserOrderId = data['sourceUserOrderId']?.toString() ?? '';
    final deliveryMethod = data['deliveryMethod']?.toString() ?? '-';
    final paymentMethod = data['paymentMethod']?.toString() ?? '-';
    final itemCountValue = data['itemCount'] ?? 0;
    final itemCount = itemCountValue is int
        ? itemCountValue
        : int.tryParse(itemCountValue.toString()) ?? 0;

    final totalValue = data['total'] ?? 0;
    final double total = totalValue is num
        ? totalValue.toDouble()
        : double.tryParse(totalValue.toString()) ?? 0;

    final address = data['address'] as Map<String, dynamic>?;
    final items = data['items'] as List<dynamic>? ?? [];

    final addressText = address == null
        ? l10n.noAddressAvailable
        : '${address['area'] ?? ''}, ${address['governorate'] ?? ''}\n'
              '${l10n.addressBlock} ${address['block'] ?? ''} '
              '${l10n.addressStreet} ${address['street'] ?? ''} '
              '${l10n.addressHouse} ${address['house'] ?? ''}';

    final isPlaced = status.toLowerCase() == 'placed';

    // Courier (Wasal) state. A delivery can be re-requested only after a
    // previous one ended without delivering (cancelled / failed / returned) —
    // the server enforces the same rule authoritatively.
    final wasalStatus = data['wasalStatus']?.toString() ?? '';
    final canDispatch =
        status.toLowerCase() == 'confirmed' &&
        (wasalStatus.isEmpty ||
            const ['cancelled', 'failed', 'returned'].contains(wasalStatus));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
              Expanded(
                child: Text(
                  l10n.orderNumber(orderNumber),
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _orderStatusBadge(status, l10n),
            ],
          ),
          const SizedBox(height: 8),
          Text(l10n.orderDate(date), style: AppTextStyles.bodySmall),
          const SizedBox(height: 14),
          Text(l10n.customer, style: AppTextStyles.labelLarge),
          const SizedBox(height: 6),
          Text(customerName, style: AppTextStyles.bodyMedium),
          if (customerEmail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(customerEmail, style: AppTextStyles.bodySmall),
          ],
          const SizedBox(height: 14),
          Text(l10n.delivery, style: AppTextStyles.labelLarge),
          const SizedBox(height: 6),
          Text(deliveryMethod, style: AppTextStyles.bodyMedium),
          if (wasalStatus.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${l10n.courierStatusLabel}: '
              '${_localizedWasalStatus(wasalStatus, l10n)}',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.deepAccent,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(l10n.payment, style: AppTextStyles.labelLarge),
          const SizedBox(height: 6),
          Text(paymentMethod, style: AppTextStyles.bodyMedium),
          const SizedBox(height: 14),
          Text(l10n.address, style: AppTextStyles.labelLarge),
          const SizedBox(height: 6),
          Text(
            addressText,
            style: AppTextStyles.bodySmall.copyWith(height: 1.4),
          ),
          const SizedBox(height: 16),
          Text(l10n.items, style: AppTextStyles.labelLarge),
          const SizedBox(height: 10),
          ...items.map(
            (item) => _OrderItemRow(item: Map<String, dynamic>.from(item)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(l10n.itemsCount(itemCount), style: AppTextStyles.bodySmall),
              const Spacer(),
              Text(_fmt(total), style: AppTextStyles.labelLarge),
            ],
          ),
          if (isPlaced) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _cancelOrder(
                      context,
                      boutiqueOrderId,
                      sourceUserOrderId,
                      customerUid,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.deepAccent,
                      side: const BorderSide(
                        color: AppColors.deepAccent,
                        width: 0.5,
                      ),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      l10n.cancelOrder,
                      style: AppTextStyles.labelLarge,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => onStatusUpdate(
                      boutiqueOrderId: boutiqueOrderId,
                      sourceUserOrderId: sourceUserOrderId,
                      customerUid: customerUid,
                      newStatus: 'Confirmed',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.deepAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(l10n.confirmOrder, style: AppTextStyles.button),
                  ),
                ),
              ],
            ),
          ],
          if (canDispatch) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            // B1: this button disables itself for the duration of the call so a
            // double-tap can't fire two dispatch requests from the client. The
            // server also claims the dispatch atomically as the authoritative
            // guard, but this stops the second request before it leaves.
            _ReadyForPickupButton(
              label: l10n.readyForPickup,
              onDispatch: () => onDispatchDelivery(boutiqueOrderId),
            ),
          ],
        ],
      ),
    );
  }
}

// ── "Ready for Pickup" dispatch button ────────────────────────────────────────
// Owns its own in-flight state so it can't be tapped twice while the
// markReadyForPickup call is running (B1, client-side half).

class _ReadyForPickupButton extends StatefulWidget {
  final String label;
  final Future<void> Function() onDispatch;

  const _ReadyForPickupButton({required this.label, required this.onDispatch});

  @override
  State<_ReadyForPickupButton> createState() => _ReadyForPickupButtonState();
}

class _ReadyForPickupButtonState extends State<_ReadyForPickupButton> {
  bool _dispatching = false;

  Future<void> _onPressed() async {
    if (_dispatching) return;
    setState(() => _dispatching = true);
    try {
      await widget.onDispatch();
    } finally {
      if (mounted) setState(() => _dispatching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _dispatching ? null : _onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.deepAccent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.deepAccent,
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: _dispatching
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(widget.label, style: AppTextStyles.button),
      ),
    );
  }
}

// ── Order item row widget ─────────────────────────────────────────────────────

class _OrderItemRow extends StatelessWidget {
  final Map<String, dynamic> item;

  const _OrderItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final imageUrl = item['imageUrl']?.toString() ?? '';
    final title = item['title']?.toString() ?? l10n.untitledProduct;
    final size = item['size']?.toString() ?? '-';
    final quantity = item['quantity']?.toString() ?? '1';
    final specialRequest = item['specialRequest']?.toString().trim() ?? '';
    final priceValue = item['price'] ?? 0;

    final double price = priceValue is num
        ? priceValue.toDouble()
        : double.tryParse(priceValue.toString()) ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.field,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.imagePlaceholder,
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    memCacheWidth: gridTileCacheWidth,
                    maxWidthDiskCache: maxImageDiskCacheWidth,
                    width: 64,
                    height: 80,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: AppColors.softAccent,
                        size: 24,
                      ),
                    ),
                  )
                : const Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: AppColors.softAccent,
                      size: 24,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(l10n.sizeLabel(size), style: AppTextStyles.bodySmall),
                const SizedBox(height: 4),
                Text(
                  l10n.quantityLabel(quantity),
                  style: AppTextStyles.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(_fmt(price), style: AppTextStyles.labelLarge),
                if (specialRequest.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.specialRequest,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.deepAccent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    specialRequest,
                    style: AppTextStyles.bodySmall.copyWith(height: 1.35),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
