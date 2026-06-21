import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../widgets/error_state_widget.dart';
import '../core/constants/countries.dart';
import '../navigation/app_header.dart';
import '../services/currency_service.dart';
import 'add_address_page.dart';
import 'order_confirmation_page.dart';
import '../widgets/cart_item.dart';
import '../services/firestore_service.dart';
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
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  // ── Delivery / payment ─────────────────────────────────────────────────────
  String deliveryMethod = 'Regular Delivery';
  String paymentMethod = 'Card';
  double deliveryCost = 3;

  // ── Made-to-order (auto-detected) ──────────────────────────────────────────
  bool _hasMtoItems = false;
  String _longestMtoTimeframe = '';

  // ── Discount code ──────────────────────────────────────────────────────────
  String? _discountCodeId;
  double _discountAmount = 0;
  String? _appliedCode;
  String? _discountBoutiqueName;
  bool _isValidatingCode = false;
  final _codeController = TextEditingController();

  // ── Loading ────────────────────────────────────────────────────────────────
  bool isPlacingOrder = false;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _cartStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _addressesStream;

  @override
  void initState() {
    super.initState();
    _cartStream = FirestoreService.getCartItemsStream();
    _addressesStream = FirestoreService.getSavedAddressesStream();

    final isKuwait = CurrencyService.instance.selectedCountryCode == 'KW';
    deliveryMethod = isKuwait ? 'Same Day Delivery' : 'Regular Delivery';
    deliveryCost = isKuwait ? 5 : 3;
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
            deliveryCost = isKuwait ? 5 : 3;
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

  // ── Payment ────────────────────────────────────────────────────────────────

  Future<Map<String, String>> _createPaymentIntent({
    required List<CartItem> cartItems,
    required double deliveryCost,
  }) async {
    final l10n = AppLocalizations.of(context)!;

    final items = cartItems
        .map(
          (item) => {
            'productId': item.productId,
            'boutiqueId': item.boutiqueId,
            'title': item.title,
            'price': item.price,
            'quantity': item.quantity,
          },
        )
        .toList();

    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = functions.httpsCallable('createPaymentIntent');

    final result = await callable.call({
      'items': items,
      'deliveryCost': deliveryCost,
      'currency': 'usd',
    });

    final data = Map<String, dynamic>.from(result.data as Map);
    final clientSecret = data['clientSecret']?.toString();
    final paymentIntentId = data['paymentIntentId']?.toString();

    if (clientSecret == null || clientSecret.isEmpty) {
      throw Exception(l10n.paymentSetupFailed);
    }

    return {
      'clientSecret': clientSecret,
      'paymentIntentId': paymentIntentId ?? '',
    };
  }

  Future<String> _startStripeCheckout({
    required List<CartItem> cartItems,
    required double deliveryCost,
  }) async {
    final result = await _createPaymentIntent(
      cartItems: cartItems,
      deliveryCost: deliveryCost,
    );

    final clientSecret = result['clientSecret']!;
    final paymentIntentId = result['paymentIntentId']!;

    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'LIBSK',
      ),
    );

    await Stripe.instance.presentPaymentSheet();
    return paymentIntentId;
  }

  // ── Place order ────────────────────────────────────────────────────────────

  Future<void> _placeOrder({
    required List<CartItem> cartItems,
    required double total,
    required bool hasAddress,
  }) async {
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

      final paymentIntentId = await _startStripeCheckout(
        cartItems: cartItems,
        deliveryCost: deliveryCost,
      );

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
        return map;
      }).toList();

      final orderNumber = await FirestoreService.createOrder(
        items: orderItems,
        itemCount: totalItems,
        total: checkedTotal,
        deliveryMethod: deliveryMethod,
        paymentMethod: paymentMethod,
        paymentIntentId: paymentIntentId,
        discountCodeId: finalDiscount > 0 ? _discountCodeId : null,
        discountAmount: finalDiscount > 0 ? finalDiscount : null,
        // Pass null — the server already has the product's timeframe
        estimatedDays: null,
      );

      for (final item in cartItems) {
        await FirestoreService.deleteCartItem(item.id);
      }

      if (!mounted) return;
      navigator.push(
        MaterialPageRoute(
          builder: (context) => OrderConfirmationPage(orderNumber: orderNumber),
        ),
      );
    } on StripeException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        _brandedErrorSnackBar(
          e.error.localizedMessage ??
              AppLocalizations.of(context)!.paymentCancelled,
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
      if (mounted) setState(() => isPlacingOrder = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: Text(
              AppLocalizations.of(context)!.pleaseLogInToContinueToCheckout,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.secondaryText,
              ),
            ),
          ),
        ),
      );
    }

    final fullName =
        user.displayName != null && user.displayName!.trim().isNotEmpty
        ? user.displayName!
        : AppLocalizations.of(context)!.user;
    final email = user.email ?? AppLocalizations.of(context)!.noEmail;
    final isKuwait = CurrencyService.instance.selectedCountryCode == 'KW';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
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
                title: AppLocalizations.of(context)!.couldNotLoadCart,
                message: AppLocalizations.of(context)!.pullDownToRetry,
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
            for (final item in cartItems) {
              subtotal += item.price * item.quantity;
            }
            final double total = subtotal + deliveryCost - _discountAmount;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _addressesStream,
              builder: (context, addressSnapshot) {
                final addressDocs = addressSnapshot.data?.docs ?? [];
                final hasAddress = addressDocs.isNotEmpty;

                return Column(
                  children: [
                    const AppHeader(showBackButton: true),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            Center(
                              child: Text(
                                AppLocalizations.of(context)!.checkout,
                                style: AppTextStyles.headingLarge,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Divider(
                              color: AppColors.border,
                              thickness: 0.5,
                            ),
                            const SizedBox(height: 18),

                            // ── Account details ──────────────────────
                            Text(
                              AppLocalizations.of(context)!.accountDetails,
                              style: AppTextStyles.capsLabel.copyWith(
                                color: AppColors.secondaryText,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.field,
                                border: Border.all(
                                  color: AppColors.border,
                                  width: 0.5,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fullName,
                                    style: AppTextStyles.bodyLarge.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(email, style: AppTextStyles.bodySmall),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),

                            // ── Delivery address ─────────────────────
                            Text(
                              AppLocalizations.of(context)!.deliveryAddress,
                              style: AppTextStyles.capsLabel.copyWith(
                                color: AppColors.secondaryText,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (addressSnapshot.connectionState ==
                                ConnectionState.waiting)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.deepAccent,
                                    strokeWidth: 1.5,
                                  ),
                                ),
                              )
                            else if (addressSnapshot.hasError)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  '${AppLocalizations.of(context)!.couldNotLoadSavedAddresses}: ${addressSnapshot.error}',
                                  style: AppTextStyles.bodySmall,
                                ),
                              )
                            else
                              Column(
                                children: [
                                  if (hasAddress) ...[
                                    _addressInfo(addressDocs.first.data()),
                                    const SizedBox(height: 16),
                                  ],
                                  _addressButton(hasAddress: hasAddress),
                                ],
                              ),
                            const SizedBox(height: 28),

                            // ── Delivery method ──────────────────────
                            Text(
                              AppLocalizations.of(context)!.deliveryMethod,
                              style: AppTextStyles.capsLabel.copyWith(
                                color: AppColors.secondaryText,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // If cart has MTO items — show banner, no dropdown
                            if (_hasMtoItems) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.field,
                                  border: Border.all(
                                    color: AppColors.border,
                                    width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Icon(
                                        Icons.access_time_rounded,
                                        size: 20,
                                        color: AppColors.deepAccent,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            AppLocalizations.of(
                                              context,
                                            )!.madeToOrder,
                                            style: AppTextStyles.labelLarge
                                                .copyWith(
                                                  color: AppColors.deepAccent,
                                                ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            _longestMtoTimeframe.isNotEmpty
                                                ? _longestMtoTimeframe
                                                : AppLocalizations.of(
                                                    context,
                                                  )!.madeToOrderSubtitle,
                                            style: AppTextStyles.bodySmall
                                                .copyWith(
                                                  color:
                                                      AppColors.secondaryText,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              // Normal dropdown for regular items
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.field,
                                  border: Border.all(
                                    color: AppColors.border,
                                    width: 0.5,
                                  ),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: deliveryMethod,
                                    isExpanded: true,
                                    dropdownColor: AppColors.field,
                                    items: [
                                      DropdownMenuItem(
                                        value: 'Regular Delivery',
                                        child: Text(
                                          AppLocalizations.of(
                                            context,
                                          )!.regularDelivery,
                                        ),
                                      ),
                                      if (isKuwait)
                                        DropdownMenuItem(
                                          value: 'Same Day Delivery',
                                          child: Text(
                                            AppLocalizations.of(
                                              context,
                                            )!.sameDayDelivery,
                                          ),
                                        ),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() {
                                          deliveryMethod = value;
                                          deliveryCost =
                                              value == 'Same Day Delivery'
                                              ? 5
                                              : 3;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 28),

                            // ── Payment method ───────────────────────
                            Text(
                              AppLocalizations.of(context)!.paymentMethod,
                              style: AppTextStyles.capsLabel.copyWith(
                                color: AppColors.secondaryText,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.field,
                                border: Border.all(
                                  color: AppColors.border,
                                  width: 0.5,
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: paymentMethod,
                                  isExpanded: true,
                                  dropdownColor: AppColors.field,
                                  items: [
                                    DropdownMenuItem(
                                      value: 'Card',
                                      child: Text(
                                        AppLocalizations.of(context)!.card,
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => paymentMethod = value);
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),

                            // ── Discount code ────────────────────────
                            Text(
                              'Discount Code',
                              style: AppTextStyles.capsLabel.copyWith(
                                color: AppColors.secondaryText,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _codeController,
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    enabled: _appliedCode == null,
                                    decoration: InputDecoration(
                                      hintText: 'Enter code',
                                      filled: true,
                                      fillColor: AppColors.field,
                                      border: const OutlineInputBorder(
                                        borderRadius: BorderRadius.zero,
                                        borderSide: BorderSide(
                                          color: AppColors.border,
                                          width: 0.5,
                                        ),
                                      ),
                                      enabledBorder: const OutlineInputBorder(
                                        borderRadius: BorderRadius.zero,
                                        borderSide: BorderSide(
                                          color: AppColors.border,
                                          width: 0.5,
                                        ),
                                      ),
                                      focusedBorder: const OutlineInputBorder(
                                        borderRadius: BorderRadius.zero,
                                        borderSide: BorderSide(
                                          color: AppColors.deepAccent,
                                          width: 1,
                                        ),
                                      ),
                                      suffixIcon: _appliedCode != null
                                          ? IconButton(
                                              icon: const Icon(
                                                Icons.close,
                                                size: 18,
                                              ),
                                              onPressed: _removeDiscountCode,
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  height: 56,
                                  child: ElevatedButton(
                                    onPressed:
                                        (_isValidatingCode ||
                                            _appliedCode != null)
                                        ? null
                                        : () => _applyDiscountCode(
                                            subtotal,
                                            cartItems,
                                          ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.deepAccent,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          AppColors.softAccent,
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
                                        : Text(
                                            _appliedCode != null
                                                ? 'Applied'
                                                : 'Apply',
                                            style: AppTextStyles.button,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                            if (_appliedCode != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                '$_appliedCode — ${_fmt(_discountAmount)} off',
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.deepAccent,
                                ),
                              ),
                              if (_discountBoutiqueName != null &&
                                  cartItems
                                          .map((i) => i.boutiqueId)
                                          .toSet()
                                          .length >
                                      1) ...[
                                const SizedBox(height: 4),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.appliedToBoutiqueItemsOnly(
                                    _discountBoutiqueName!,
                                  ),
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                              ],
                            ],

                            const SizedBox(height: 40),
                            const Divider(
                              color: AppColors.border,
                              thickness: 0.5,
                            ),
                            const SizedBox(height: 20),

                            // ── Totals ───────────────────────────────
                            _buildTotalRow(
                              AppLocalizations.of(context)!.subtotal,
                              _fmt(subtotal),
                            ),
                            const SizedBox(height: 8),
                            _buildTotalRow(
                              AppLocalizations.of(context)!.delivery,
                              _hasMtoItems
                                  ? AppLocalizations.of(context)!.madeToOrder
                                  : _fmt(deliveryCost),
                            ),
                            if (_discountAmount > 0) ...[
                              const SizedBox(height: 8),
                              _buildTotalRow(
                                'Discount',
                                '- ${_fmt(_discountAmount)}',
                              ),
                            ],
                            const SizedBox(height: 12),
                            const Divider(
                              color: AppColors.border,
                              thickness: 0.5,
                            ),
                            const SizedBox(height: 12),
                            _buildTotalRow(
                              AppLocalizations.of(context)!.total,
                              _fmt(total),
                              bold: true,
                            ),
                            const SizedBox(height: 30),
                          ],
                        ),
                      ),
                    ),

                    // ── Trust signals ────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          size: 14,
                          color: AppColors.secondaryText,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          AppLocalizations.of(context)!.secureCheckout,
                          style: AppTextStyles.labelSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _paymentPill(
                          icon: Icons.credit_card,
                          label: AppLocalizations.of(context)!.card,
                        ),
                        const SizedBox(width: 8),
                        _paymentPill(
                          label: AppLocalizations.of(context)!.knet,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Place order button ───────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 70,
                      child: ElevatedButton.icon(
                        onPressed: isPlacingOrder
                            ? null
                            : () => _placeOrder(
                                cartItems: cartItems,
                                total: total,
                                hasAddress: hasAddress,
                              ),
                        icon: isPlacingOrder
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.shopping_bag_outlined, size: 28),
                        label: Text(
                          isPlacingOrder
                              ? AppLocalizations.of(context)!.placingOrder
                              : AppLocalizations.of(context)!.placeOrder,
                          style: AppTextStyles.button,
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
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ── Widget helpers ─────────────────────────────────────────────────────────

  Widget _addressButton({required bool hasAddress}) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AddAddressPage()),
        );
        if (mounted) setState(() {});
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.field,
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Text(
              hasAddress
                  ? AppLocalizations.of(context)!.changeDeliveryAddress
                  : AppLocalizations.of(context)!.addDeliveryAddress,
              style: AppTextStyles.bodyMedium,
            ),
            const Spacer(),
            const Icon(Icons.add, color: AppColors.primaryText),
          ],
        ),
      ),
    );
  }

  Widget _addressInfo(Map<String, dynamic> address) {
    final type = address['type']?.toString() ?? 'kuwait';

    if (type == 'international') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${address["firstName"]} ${address["lastName"]}',
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          if ((address['addressLine1']?.toString() ?? '').isNotEmpty)
            Text(
              address['addressLine1'].toString(),
              style: AppTextStyles.bodyMedium,
            ),
          if ((address['addressLine2']?.toString() ?? '').isNotEmpty)
            Text(
              address['addressLine2'].toString(),
              style: AppTextStyles.bodyMedium,
            ),
          Text(
            [
              address['city']?.toString() ?? '',
              address['zipCode']?.toString() ?? '',
            ].where((s) => s.isNotEmpty).join(', '),
            style: AppTextStyles.bodyMedium,
          ),
          Text(
            address['phone']?.toString() ?? '',
            style: AppTextStyles.bodyMedium,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${address["firstName"]} ${address["lastName"]}',
          style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          '${AppLocalizations.of(context)!.block} ${address["block"]} '
          '${AppLocalizations.of(context)!.street} ${address["street"]} '
          '${AppLocalizations.of(context)!.house} ${address["house"]}',
          style: AppTextStyles.bodyMedium,
        ),
        Text(
          '${address["area"]} ${address["governorate"]}',
          style: AppTextStyles.bodyMedium,
        ),
        Text(
          address['phone']?.toString() ?? '',
          style: AppTextStyles.bodyMedium,
        ),
      ],
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

  Widget _paymentPill({IconData? icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.field,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: AppColors.secondaryText),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              letterSpacing: 0.5,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}
