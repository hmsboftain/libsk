import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../widgets/error_state_widget.dart';
import '../core/constants/countries.dart';
import '../core/services/analytics_service.dart';
import '../core/services/performance_service.dart';
import '../navigation/app_header.dart';
import '../services/currency_service.dart';
import 'add_address_page.dart';
import 'saved_addresses_page.dart';
import 'payzah_payment_page.dart';
import '../widgets/cart_item.dart';
import '../services/firestore_service.dart';
import '../services/wasal_service.dart';
import '../widgets/theme.dart';

// ── Branded snackbar ──────────────────────────────────────────────────────────

SnackBar _brandedErrorSnackBar(String message) {
  return SnackBar(
    backgroundColor: AppColors.primaryText,
    content: Text(
      message,
      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.background),
    ),
  );
}

// ── Page ──────────────────────────────────────────────────────────────────────

class CheckoutPage extends StatefulWidget {
  /// Each checkout is scoped to a single boutique's cart.
  final String boutiqueId;
  final String boutiqueName;

  const CheckoutPage({
    super.key,
    required this.boutiqueId,
    this.boutiqueName = '',
  });

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

/// Resolution state of the delivery fee for the chosen address. The pay button
/// is enabled ONLY in [resolved]; every other state means we can't quote a real
/// Wasal fee yet, so checkout is blocked (no flat fallback is ever charged).
enum _DeliveryFeeState { noAddress, noArea, loading, error, resolved }

class _CheckoutPageState extends State<CheckoutPage> {
  // ── Delivery / payment ─────────────────────────────────────────────────────
  String deliveryMethod = 'Regular Delivery';
  String paymentMethod = 'Card';
  // 0 until a real fee is known — a resolved Wasal area fee, or 0 for MTO.
  // There is deliberately no flat legacy fallback on the client.
  double deliveryCost = 0;

  // ── Made-to-order (auto-detected) ──────────────────────────────────────────
  bool _hasMtoItems = false;
  String _longestMtoTimeframe = '';

  // ── Discount code ──────────────────────────────────────────────────────────
  // ── Wasal area-based delivery fee ──────────────────────────────────────────
  // Live quote for the customer's delivery area (per boutique pickup). Non-null
  // only once the area fee has resolved; the pay button gates on it. Keyed by
  // the address doc it was quoted for so address changes refetch.
  double? _wasalAreaFee;
  String? _wasalFeeAddressKey;
  // Area IDs of the address currently being quoted, kept so the error state's
  // "tap to retry" can re-issue the same lookup.
  String? _feeGovId;
  String? _feeNbId;
  // True when the last fee lookup for an area-bearing address came back empty
  // (network/API failure, timeout, or no configured price) → error state.
  bool _wasalFeeError = false;

  String? _discountCodeId;
  double _discountAmount = 0;
  String? _appliedCode;
  String? _discountBoutiqueName;
  bool _isValidatingCode = false;
  final _codeController = TextEditingController();

  // ── Collapsible UI state ────────────────────────────────────────────────────
  bool _showOrderSummary = false;
  bool _showPromoInput = false;

  // ── Loading ────────────────────────────────────────────────────────────────
  bool isPlacingOrder = false;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _cartStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _addressesStream;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('checkout');
    _cartStream = FirestoreService.getCartItemsStream(widget.boutiqueId);
    _addressesStream = FirestoreService.getSavedAddressesStream();

    final isKuwait = CurrencyService.instance.selectedCountryCode == 'KW';
    deliveryMethod = isKuwait ? 'Same Day Delivery' : 'Regular Delivery';
    // deliveryCost stays 0 until a real Wasal fee resolves (or MTO forces 0).
    // KNET is the default rail for Kuwait customers; cards elsewhere.
    paymentMethod = isKuwait ? 'KNET' : 'Card';
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // ── Currency helper ────────────────────────────────────────────────────────

  String _fmt(double kwd) {
    final service = CurrencyService.instance;
    final country = countryByCode(service.selectedCountryCode);
    return service.format(kwd, country.currencySymbol, country.currency);
  }

  // ── Wasal live delivery fee ────────────────────────────────────────────────
  // The order ships from the newest saved address (createOrder uses the same
  // orderBy-createdAt-desc rule), so the fee is quoted for that address. Runs
  // once per address change; an area-less address or a failed lookup blocks
  // checkout rather than falling back to a flat fee.
  void _maybeFetchWasalFee(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> addressDocs,
  ) {
    if (addressDocs.isEmpty) return;
    final latest = addressDocs.first;
    if (_wasalFeeAddressKey == latest.id) return; // already evaluated this address
    _wasalFeeAddressKey = latest.id;

    final data = latest.data();
    _feeGovId = data['wasalGovernorateId']?.toString() ?? '';
    _feeNbId = data['wasalNeighborhoodId']?.toString() ?? '';

    if (_feeGovId!.isEmpty || _feeNbId!.isEmpty) {
      // No Wasal area on this address → we can't quote area pricing. Drop any
      // stale quote; the UI prompts the customer to add their area.
      if (mounted) {
        setState(() {
          _wasalAreaFee = null;
          _wasalFeeError = false;
        });
      }
      return;
    }

    _fetchWasalFee();
  }

  // Fetches (or re-fetches, on retry) the area fee for the current address.
  // getDeliveryFee never throws — it returns null on failure/timeout/no-price —
  // so a null result becomes the error state, not a silent flat fee.
  void _fetchWasalFee() {
    final gov = _feeGovId, nb = _feeNbId;
    if (gov == null || nb == null || gov.isEmpty || nb.isEmpty) return;
    // Enter the loading state: no fee in hand, no error yet.
    if (mounted) {
      setState(() {
        _wasalAreaFee = null;
        _wasalFeeError = false;
      });
    }
    WasalService.instance
        .getDeliveryFee(governorateId: gov, neighborhoodId: nb)
        .then((fee) {
          if (!mounted) return;
          setState(() {
            if (fee == null) {
              _wasalFeeError = true;
            } else {
              _wasalFeeError = false;
              _wasalAreaFee = fee;
              if (deliveryMethod != 'Made to Order') deliveryCost = fee;
            }
          });
        });
  }

  // Which delivery-fee state the chosen address is in. Drives both the delivery
  // section UI and the pay button's enabled state — the button is live only in
  // [resolved].
  _DeliveryFeeState _deliveryFeeState(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> addressDocs,
  ) {
    if (addressDocs.isEmpty) return _DeliveryFeeState.noAddress;
    // MTO ships free (deliveryCost 0) and needs no area quote.
    if (_hasMtoItems) return _DeliveryFeeState.resolved;
    final data = addressDocs.first.data();
    final gov = data['wasalGovernorateId']?.toString() ?? '';
    final nb = data['wasalNeighborhoodId']?.toString() ?? '';
    if (gov.isEmpty || nb.isEmpty) return _DeliveryFeeState.noArea;
    if (_wasalFeeError) return _DeliveryFeeState.error;
    if (_wasalAreaFee == null) return _DeliveryFeeState.loading;
    return _DeliveryFeeState.resolved;
  }

  // Inline info/error notice shown in the delivery slot (area missing, or the
  // fee lookup failed). Tapping runs [onTap] — the add-area form, or a retry.
  Widget _deliveryNotice({
    required String message,
    required VoidCallback onTap,
    IconData icon = Icons.info_outline,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.selectedSoft,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.deepAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.deepAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Delivery slot while the area fee lookup is in flight.
  Widget _deliveryLoadingRow() {
    return const Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: AppColors.deepAccent,
          ),
        ),
      ],
    );
  }

  // ── Auto-detect MTO from cart items ────────────────────────────────────────
  // Called on every rebuild. Reads product docs to get the longest timeframe.

  void _autoDetectMto(List<CartItem> cartItems) {
    final hasMto = cartItems.any((i) => i.madeToOrder);

    if (hasMto != _hasMtoItems) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _hasMtoItems = hasMto;
          if (hasMto) {
            // Force delivery method to MTO, free delivery
            deliveryMethod = 'Made to Order';
            deliveryCost = 0;
          } else if (deliveryMethod == 'Made to Order') {
            // MTO items removed — reset to default
            final isKuwait =
                CurrencyService.instance.selectedCountryCode == 'KW';
            deliveryMethod = isKuwait
                ? 'Same Day Delivery'
                : 'Regular Delivery';
            // Restore the resolved area fee if we have one; otherwise 0 and the
            // delivery-fee state machine re-blocks checkout until it resolves.
            deliveryCost = _wasalAreaFee ?? 0;
          }
        });

        // Fetch longest timeframe from products
        if (hasMto) _fetchLongestTimeframe(cartItems);
      });
    }
  }

  Future<void> _fetchLongestTimeframe(List<CartItem> cartItems) async {
    String longest = '';
    for (final item in cartItems) {
      if (!item.madeToOrder) continue;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('boutiques')
            .doc(item.boutiqueId)
            .collection('products')
            .doc(item.productId)
            .get();
        final tf = doc.data()?['deliveryTimeframe']?.toString().trim() ?? '';
        if (tf.isNotEmpty && tf.length > longest.length) longest = tf;
      } catch (_) {}
    }
    if (mounted && longest != _longestMtoTimeframe) {
      setState(() => _longestMtoTimeframe = longest);
    }
  }

  // ── Discount code ──────────────────────────────────────────────────────────

  Future<void> _applyDiscountCode(
    double subtotal,
    List<CartItem> cartItems,
  ) async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    final boutiqueIds = cartItems.map((i) => i.boutiqueId).toSet().toList();
    setState(() => _isValidatingCode = true);
    try {
      final data = await FirestoreService.validateDiscountCode(
        code: code,
        subtotal: subtotal,
        boutiqueIds: boutiqueIds,
      );
      // Scope the previewed discount to the owning boutique's items so the
      // preview matches the server-side charge (createOrder is authoritative).
      // Platform-wide codes (no boutiqueId) apply to the whole cart.
      final codeBoutiqueId = data['boutiqueId']?.toString();
      final codeType = data['type']?.toString();
      final codeValue = (data['value'] as num?)?.toDouble() ?? 0;
      final discountable = (codeBoutiqueId == null || codeBoutiqueId.isEmpty)
          ? subtotal
          : cartItems
                .where((i) => i.boutiqueId == codeBoutiqueId)
                .fold<double>(0, (s, i) => s + i.price * i.quantity);
      final amount = codeType == 'percentage'
          ? double.parse(((discountable * codeValue) / 100).toStringAsFixed(3))
          : (codeValue < discountable ? codeValue : discountable);
      final boutiqueName = data['boutiqueName']?.toString();
      setState(() {
        _discountCodeId = data['codeId']?.toString();
        _discountAmount = amount;
        _appliedCode = data['code']?.toString();
        _discountBoutiqueName =
            (boutiqueName != null && boutiqueName.isNotEmpty)
            ? boutiqueName
            : null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_appliedCode ?? code} — ${_fmt(_discountAmount)} off',
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _discountCodeId = null;
        _discountAmount = 0;
        _appliedCode = null;
        _discountBoutiqueName = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        _brandedErrorSnackBar(
          e.message ?? AppLocalizations.of(context)!.somethingWentWrong,
        ),
      );
    } finally {
      if (mounted) setState(() => _isValidatingCode = false);
    }
  }

  void _removeDiscountCode() {
    setState(() {
      _discountCodeId = null;
      _discountAmount = 0;
      _appliedCode = null;
      _discountBoutiqueName = null;
      _codeController.clear();
    });
  }

  // ── Place order ────────────────────────────────────────────────────────────
  //
  // Payzah direct flow: the order is created FIRST (server-verified prices,
  // status "Pending Payment"), then PayzahPaymentPage initializes the payment
  // and hands off to KNET / card. The cart is cleared and the purchase logged
  // only after the payment is verified CAPTURED server-side.

  Future<void> _placeOrder({
    required List<CartItem> cartItems,
    required double total,
    required bool hasAddress,
  }) async {
    // Re-entrancy guard: a rapid second tap that lands before the button's
    // disabled state has rebuilt is dropped here, so createOrder can't fire
    // twice and mint a duplicate order/charge.
    if (isPlacingOrder) return;

    final loc = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (cartItems.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(loc.yourCartIsEmpty)));
      return;
    }
    if (!hasAddress) {
      messenger.showSnackBar(
        SnackBar(content: Text(loc.pleaseAddADeliveryAddress)),
      );
      return;
    }

    setState(() => isPlacingOrder = true);

    final checkoutTrace = PerformanceService.instance.traceCheckoutFlow();
    await checkoutTrace.start();

    try {
      int totalItems = 0;
      double checkedSubtotal = 0;

      for (final item in cartItems) {
        totalItems += item.quantity;
        checkedSubtotal += item.price * item.quantity;

        final productDoc = await FirebaseFirestore.instance
            .collection('boutiques')
            .doc(item.boutiqueId)
            .collection('products')
            .doc(item.productId)
            .get();

        if (!productDoc.exists) {
          throw Exception(loc.productNoLongerAvailable(item.title));
        }

        final stockValue = productDoc.data()?['stock'] ?? 0;
        final int currentStock = stockValue is int
            ? stockValue
            : int.tryParse(stockValue.toString()) ?? 0;

        if (currentStock < item.quantity) {
          throw Exception(loc.productNotEnoughStock(item.title));
        }
      }

      final finalDiscount = _discountAmount > checkedSubtotal
          ? 0.0
          : _discountAmount;
      final checkedTotal = checkedSubtotal + deliveryCost - finalDiscount;

      final List<Map<String, dynamic>> orderItems = cartItems.map((item) {
        final map = <String, dynamic>{
          'productId': item.productId,
          'boutiqueId': item.boutiqueId,
          'title': item.title,
          'imageUrl': item.imageUrl,
          'description': item.description,
          'size': item.size,
          'price': item.price,
          'quantity': item.quantity,
        };
        final color = item.color.trim();
        if (color.isNotEmpty) map['color'] = color;
        final request = item.specialRequest.trim();
        if (request.isNotEmpty) map['specialRequest'] = request;
        return map;
      }).toList();

      final orderTrace = PerformanceService.instance.traceCreateOrder();
      await orderTrace.start();
      final CreateOrderResult order;
      try {
        order = await FirestoreService.createOrder(
          items: orderItems,
          itemCount: totalItems,
          total: checkedTotal,
          deliveryMethod: deliveryMethod,
          paymentMethod: paymentMethod,
          discountCodeId: finalDiscount > 0 ? _discountCodeId : null,
          discountAmount: finalDiscount > 0 ? finalDiscount : null,
          // Pass null — the server already has the product's timeframe
          estimatedDays: null,
        );
      } finally {
        await orderTrace.stop();
      }

      if (!mounted) return;
      final isArabic = Localizations.localeOf(context).languageCode == 'ar';
      navigator.push(
        MaterialPageRoute(
          builder: (context) => PayzahPaymentPage(
            attemptId: order.paymentAttemptId,
            orderNumber: order.orderNumber,
            boutiqueId: widget.boutiqueId,
            boutiqueName: widget.boutiqueName,
            total: checkedTotal,
            isArabic: isArabic,
            paymentMethod: paymentMethod,
          ),
        ),
      );
    } catch (e) {
      debugPrint('PLACE ORDER ERROR: $e');
      if (!mounted) return;
      final raw = e is FirebaseFunctionsException
          ? (e.message ?? e.code)
          : e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : AppLocalizations.of(context)!.somethingWentWrong;
      messenger.showSnackBar(_brandedErrorSnackBar(raw));
    } finally {
      await checkoutTrace.stop();
      if (mounted) setState(() => isPlacingOrder = false);
    }
  }

  // ── Pickers ──────────────────────────────────────────────────────────────

  void _selectDeliveryMethod(bool isKuwait) {
    final l10n = AppLocalizations.of(context)!;
    // The sheet is only meaningful once a real area fee has resolved — both
    // methods are priced at that fee, never a flat fallback.
    final fee = _wasalAreaFee;
    if (fee == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (sheetContext) {
        Widget option(String value, String label, double cost) {
          return ListTile(
            title: Text(
              '$label · ${_fmt(cost)}',
              style: AppTextStyles.bodyMedium,
            ),
            trailing: deliveryMethod == value
                ? const Icon(Icons.check, color: AppColors.deepAccent, size: 18)
                : null,
            onTap: () {
              setState(() {
                deliveryMethod = value;
                deliveryCost = cost;
              });
              Navigator.pop(sheetContext);
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(l10n.deliveryMethod, style: AppTextStyles.labelLarge),
                ),
              ),
              const Divider(color: AppColors.border, thickness: 0.5, height: 0.5),
              // Area-based Wasal fee (resolved); the sheet never opens otherwise.
              option('Regular Delivery', l10n.regularDelivery, fee),
              if (isKuwait)
                option('Same Day Delivery', l10n.sameDayDelivery, fee),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _selectPaymentMethod() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(l10n.paymentMethod, style: AppTextStyles.labelLarge),
                ),
              ),
              const Divider(color: AppColors.border, thickness: 0.5, height: 0.5),
              ListTile(
                leading: const Icon(
                  Icons.account_balance,
                  size: 20,
                  color: AppColors.secondaryText,
                ),
                title: Text(l10n.knet, style: AppTextStyles.bodyMedium),
                trailing: paymentMethod == 'KNET'
                    ? const Icon(Icons.check, color: AppColors.deepAccent, size: 18)
                    : null,
                onTap: () {
                  setState(() => paymentMethod = 'KNET');
                  Navigator.pop(sheetContext);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.credit_card,
                  size: 20,
                  color: AppColors.secondaryText,
                ),
                title: Text(l10n.card, style: AppTextStyles.bodyMedium),
                trailing: paymentMethod == 'Card'
                    ? const Icon(Icons.check, color: AppColors.deepAccent, size: 18)
                    : null,
                onTap: () {
                  setState(() => paymentMethod = 'Card');
                  Navigator.pop(sheetContext);
                },
              ),
              // Apple Pay goes through Payzah's Transit page, which needs
              // SFSafariViewController — iOS only by definition.
              if (Platform.isIOS)
                ListTile(
                  leading: const Icon(
                    Icons.apple,
                    size: 20,
                    color: AppColors.secondaryText,
                  ),
                  title: Text(l10n.applePay, style: AppTextStyles.bodyMedium),
                  trailing: paymentMethod == 'Apple Pay'
                      ? const Icon(Icons.check,
                          color: AppColors.deepAccent, size: 18)
                      : null,
                  onTap: () {
                    setState(() => paymentMethod = 'Apple Pay');
                    Navigator.pop(sheetContext);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: SafeArea(
            child: Center(
              child: Text(
                AppLocalizations.of(context)!.pleaseLogInToContinueToCheckout,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.secondaryText,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final isKuwait = CurrencyService.instance.selectedCountryCode == 'KW';
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _cartStream,
            builder: (context, cartSnapshot) {
              if (cartSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.deepAccent,
                    strokeWidth: 1.5,
                  ),
                );
              }
              if (cartSnapshot.hasError) {
                return ErrorStateWidget.inline(
                  title: l10n.couldNotLoadCart,
                  message: l10n.pullDownToRetry,
                  onRetry: () => setState(() {}),
                  type: ErrorType.network,
                );
              }

              final cartDocs = cartSnapshot.data?.docs ?? [];
              final cartItems = cartDocs
                  .map((doc) => CartItem.fromFirestore(doc.id, doc.data()))
                  .toList();

              // Auto-detect MTO — sets delivery method automatically
              _autoDetectMto(cartItems);

              double subtotal = 0;
              int totalUnits = 0;
              for (final item in cartItems) {
                subtotal += item.price * item.quantity;
                totalUnits += item.quantity;
              }
              final double total = subtotal + deliveryCost - _discountAmount;

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _addressesStream,
                builder: (context, addressSnapshot) {
                  final addressDocs = addressSnapshot.data?.docs ?? [];
                  final hasAddress = addressDocs.isNotEmpty;
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _maybeFetchWasalFee(addressDocs),
                  );
                  // Single source of truth for the delivery section + pay button.
                  final feeState = _deliveryFeeState(addressDocs);
                  final canPlaceOrder =
                      feeState == _DeliveryFeeState.resolved;

                  return Column(
                    children: [
                      const AppHeader(showBackButton: true),
                      Expanded(
                        child: SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 10),
                              Center(
                                child: Text(
                                  l10n.checkout,
                                  style: AppTextStyles.headingLarge,
                                ),
                              ),
                              const SizedBox(height: 22),

                              // ── Delivery address ──────────────────────
                              _sectionLabel(l10n.deliveryAddress),
                              const SizedBox(height: 10),
                              _addressRow(addressSnapshot, addressDocs, hasAddress),
                              _sectionGap(),

                              // ── Delivery method ───────────────────────
                              _sectionLabel(l10n.deliveryMethod),
                              const SizedBox(height: 10),
                              _deliveryRow(isKuwait, feeState),
                              _sectionGap(),

                              // ── Payment method ────────────────────────
                              _sectionLabel(l10n.paymentMethod),
                              const SizedBox(height: 10),
                              _compactRow(
                                value: paymentMethod == 'KNET'
                                    ? l10n.knet
                                    : paymentMethod == 'Apple Pay'
                                        ? l10n.applePay
                                        : l10n.card,
                                onTap: _selectPaymentMethod,
                              ),
                              _sectionGap(),

                              // ── Order summary (collapsible) ───────────
                              _orderSummarySection(
                                cartItems,
                                subtotal,
                                total,
                                totalUnits,
                              ),
                              _sectionGap(),

                              // ── Promo code ────────────────────────────
                              _promoSection(subtotal, cartItems),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),

                      // ── Sticky pay bar ────────────────────────────────
                      _stickyBar(
                        cartItems,
                        total,
                        hasAddress,
                        canPlaceOrder: canPlaceOrder,
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Section primitives ─────────────────────────────────────────────────────

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTextStyles.capsLabel.copyWith(color: AppColors.secondaryText),
    );
  }

  // 0.5px hairline border between sections — the only divider style used.
  Widget _sectionGap() {
    return const Column(
      children: [
        SizedBox(height: 18),
        Divider(color: AppColors.border, thickness: 0.5, height: 0.5),
        SizedBox(height: 18),
      ],
    );
  }

  Widget _compactRow({
    String? title,
    required String value,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  value,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.secondaryText,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.chevron_right,
              color: AppColors.secondaryText,
              size: 22,
            ),
        ],
      ),
    );
  }

  // ── Delivery address row ────────────────────────────────────────────────────

  Widget _addressRow(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> addressSnapshot,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> addressDocs,
    bool hasAddress,
  ) {
    final l10n = AppLocalizations.of(context)!;

    if (addressSnapshot.connectionState == ConnectionState.waiting) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.deepAccent,
            strokeWidth: 1.5,
          ),
        ),
      );
    }
    if (addressSnapshot.hasError) {
      return Text(
        l10n.couldNotLoadSavedAddresses,
        style: AppTextStyles.bodySmall,
      );
    }

    // No saved address yet → jump straight to the add-address form.
    Future<void> openEditor() async {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AddAddressPage()),
      );
      if (mounted) setState(() {});
    }

    // Has saved addresses → open the list to pick one (with its own "Add New
    // Address" button). Picking bumps that address to newest, which is the
    // address createOrder ships to and re-quotes the Wasal fee for; the live
    // addresses stream then re-emits and _maybeFetchWasalFee re-runs for it.
    Future<void> openAddressPicker() async {
      final selectedId = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => const SavedAddressesPage(selectable: true),
        ),
      );
      if (!mounted) return;
      if (selectedId != null) {
        try {
          await FirestoreService.markAddressSelected(selectedId);
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(_brandedErrorSnackBar(l10n.somethingWentWrong));
        }
      }
      if (mounted) setState(() {});
    }

    if (!hasAddress) {
      return _compactRow(
        value: l10n.addDeliveryAddress,
        onTap: openEditor,
      );
    }

    final addr = addressDocs.first.data();
    final name = '${addr["firstName"] ?? ''} ${addr["lastName"] ?? ''}'.trim();
    final line = _addressLineSummary(addr);
    final phone = addr['phone']?.toString() ?? '';

    return _compactRow(
      title: name.isNotEmpty ? name : l10n.deliveryAddress,
      value: line,
      subtitle: phone,
      onTap: openAddressPicker,
    );
  }

  String _addressLineSummary(Map<String, dynamic> address) {
    final l10n = AppLocalizations.of(context)!;
    final type = address['type']?.toString() ?? 'kuwait';

    if (type == 'international') {
      return [
        address['addressLine1']?.toString() ?? '',
        address['addressLine2']?.toString() ?? '',
        address['city']?.toString() ?? '',
        address['zipCode']?.toString() ?? '',
      ].where((s) => s.isNotEmpty).join(', ');
    }

    return [
      '${l10n.block} ${address["block"] ?? ''}'.trim(),
      '${l10n.street} ${address["street"] ?? ''}'.trim(),
      '${l10n.house} ${address["house"] ?? ''}'.trim(),
      address['area']?.toString() ?? '',
      address['governorate']?.toString() ?? '',
    ].where((s) => s.trim().isNotEmpty).join(', ');
  }

  // ── Delivery method row ─────────────────────────────────────────────────────

  Widget _deliveryRow(bool isKuwait, _DeliveryFeeState state) {
    final l10n = AppLocalizations.of(context)!;

    if (_hasMtoItems) {
      // Non-interactive — MTO forces a free, timeframe-based delivery.
      return _compactRow(
        title: l10n.madeToOrder,
        value: _longestMtoTimeframe.isNotEmpty
            ? _longestMtoTimeframe
            : l10n.madeToOrderSubtitle,
      );
    }

    switch (state) {
      // No delivery address yet → the fee isn't known (createOrder and the
      // Wasal quote both derive it from the chosen address).
      case _DeliveryFeeState.noAddress:
        return _compactRow(value: l10n.deliveryCostAfterAddress);
      // Address has no Wasal area → prompt to add it (unlocks area pricing).
      case _DeliveryFeeState.noArea:
        return _deliveryNotice(
          message: l10n.deliverySelectAreaHint,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddAddressPage()),
          ),
        );
      // Area fee lookup in flight.
      case _DeliveryFeeState.loading:
        return _deliveryLoadingRow();
      // Lookup failed/timed out/no price → tap to retry, no flat fallback.
      case _DeliveryFeeState.error:
        return _deliveryNotice(
          message: l10n.deliveryFeeUnavailable,
          onTap: _fetchWasalFee,
          icon: Icons.refresh,
        );
      // Real fee in hand → show it; Kuwait can switch delivery method.
      case _DeliveryFeeState.resolved:
        final methodLabel = deliveryMethod == 'Same Day Delivery'
            ? l10n.sameDayDelivery
            : l10n.regularDelivery;
        return _compactRow(
          value: '$methodLabel · ${_fmt(deliveryCost)}',
          onTap: isKuwait ? () => _selectDeliveryMethod(isKuwait) : null,
        );
    }
  }

  // ── Order summary (collapsible) ─────────────────────────────────────────────

  Widget _orderSummarySection(
    List<CartItem> cartItems,
    double subtotal,
    double total,
    int totalUnits,
  ) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(l10n.orderSummary),
        const SizedBox(height: 10),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              setState(() => _showOrderSummary = !_showOrderSummary),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${l10n.itemCount(totalUnits)} · ${_fmt(total)}',
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                _showOrderSummary
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: AppColors.secondaryText,
              ),
            ],
          ),
        ),
        if (_showOrderSummary) ...[
          const SizedBox(height: 14),
          ...cartItems.map(_lineItem),
          const SizedBox(height: 6),
          const Divider(color: AppColors.border, thickness: 0.5, height: 0.5),
          const SizedBox(height: 12),
          _buildTotalRow(l10n.subtotal, _fmt(subtotal)),
          const SizedBox(height: 8),
          _buildTotalRow(
            l10n.delivery,
            _hasMtoItems ? l10n.madeToOrder : _fmt(deliveryCost),
          ),
          if (_discountAmount > 0) ...[
            const SizedBox(height: 8),
            _buildTotalRow(l10n.discountLabel, '- ${_fmt(_discountAmount)}'),
          ],
          const SizedBox(height: 12),
          _buildTotalRow(l10n.total, _fmt(total), bold: true),
        ],
      ],
    );
  }

  Widget _lineItem(CartItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              item.quantity > 1 ? '${item.title} ×${item.quantity}' : item.title,
              style: AppTextStyles.bodyMedium,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _fmt(item.price * item.quantity),
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  // ── Promo code ──────────────────────────────────────────────────────────────

  Widget _promoSection(double subtotal, List<CartItem> cartItems) {
    final l10n = AppLocalizations.of(context)!;

    // Applied state — show the code with a remove control.
    if (_appliedCode != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$_appliedCode — ${_fmt(_discountAmount)} off',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.deepAccent,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _removeDiscountCode,
                behavior: HitTestBehavior.opaque,
                child: const Icon(
                  Icons.close,
                  size: 18,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
          if (_discountBoutiqueName != null &&
              cartItems.map((i) => i.boutiqueId).toSet().length > 1) ...[
            const SizedBox(height: 4),
            Text(
              l10n.appliedToBoutiqueItemsOnly(_discountBoutiqueName!),
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ],
      );
    }

    // Collapsed — render as a text link until tapped.
    if (!_showPromoInput) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showPromoInput = true),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 16, color: AppColors.deepAccent),
            const SizedBox(width: 6),
            Text(
              l10n.addPromoCode,
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.deepAccent,
              ),
            ),
          ],
        ),
      );
    }

    // Revealed input.
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            autofocus: true,
            onEditingComplete: () => FocusScope.of(context).unfocus(),
            decoration: InputDecoration(
              hintText: l10n.enterPromoCode,
              filled: true,
              fillColor: AppColors.field,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: AppColors.border, width: 0.5),
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: AppColors.border, width: 0.5),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: AppColors.deepAccent, width: 1),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: _isValidatingCode
                ? null
                : () => _applyDiscountCode(subtotal, cartItems),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepAccent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.softAccent,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: _isValidatingCode
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.white,
                    ),
                  )
                : Text(l10n.apply, style: AppTextStyles.button),
          ),
        ),
      ],
    );
  }

  // ── Sticky pay bar ──────────────────────────────────────────────────────────

  Widget _stickyBar(
    List<CartItem> cartItems,
    double total,
    bool hasAddress, {
    required bool canPlaceOrder,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 13,
                color: AppColors.secondaryText,
              ),
              const SizedBox(width: 6),
              Text(l10n.secureCheckout, style: AppTextStyles.labelSmall),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              // Live only once a real delivery fee has resolved (or MTO): no
              // flat fallback is ever charged.
              onPressed: (isPlacingOrder || !canPlaceOrder)
                  ? null
                  : () => _placeOrder(
                      cartItems: cartItems,
                      total: total,
                      hasAddress: hasAddress,
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepAccent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.softAccent,
                disabledForegroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              child: isPlacingOrder
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(l10n.payAmount(_fmt(total)), style: AppTextStyles.button),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String title, String value, {bool bold = false}) {
    return Row(
      children: [
        Text(
          title,
          style: bold
              ? AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w500)
              : AppTextStyles.bodyMedium,
        ),
        const Spacer(),
        Text(
          value,
          style: bold
              ? AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w500)
              : AppTextStyles.bodyMedium,
        ),
      ],
    );
  }
}
