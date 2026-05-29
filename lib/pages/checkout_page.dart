import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import 'add_address_page.dart';
import 'order_confirmation_page.dart';
import '../widgets/cart_item.dart';
import '../services/firestore_service.dart';
import '../widgets/theme.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

// Branded snackbar used for action failures on checkout — ink-on-cream so it
// matches the rest of the design system rather than the default material dark
// pill.
SnackBar _brandedErrorSnackBar(String message) {
  return SnackBar(
    backgroundColor: AppColors.primaryText,
    content: Text(
      message,
      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.background),
    ),
  );
}

class _CheckoutPageState extends State<CheckoutPage> {
  String deliveryMethod = "Same Day Delivery";
  String paymentMethod = "Card";
  double deliveryCost = 5;
  bool isPlacingOrder = false;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _cartStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _addressesStream;

  @override
  void initState() {
    super.initState();
    _cartStream = FirestoreService.getCartItemsStream();
    _addressesStream = FirestoreService.getSavedAddressesStream();
  }

  Future<Map<String, String>> _createPaymentIntent({
    required List<CartItem> cartItems,
    required double deliveryCost,
    required String deliveryMethod,
  }) async {
    final items = cartItems.map((item) {
      return {
        'productId': item.productId,
        'boutiqueId': item.boutiqueId,
        'title': item.title,
        'price': item.price,
        'quantity': item.quantity,
      };
    }).toList();

    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = functions.httpsCallable('createPaymentIntent');

    final result = await callable.call({
      'items': items,
      'deliveryCost': deliveryCost,
      'deliveryMethod': deliveryMethod,
      'currency': 'kwd',
    });

    final data = Map<String, dynamic>.from(result.data as Map);
    final clientSecret = data['clientSecret']?.toString();
    final paymentIntentId = data['paymentIntentId']?.toString();

    if (clientSecret == null || clientSecret.isEmpty) {
      throw Exception('Missing client secret');
    }

    return {
      'clientSecret': clientSecret,
      'paymentIntentId': paymentIntentId ?? '',
    };
  }

  Future<String> _startStripeCheckout({
    required List<CartItem> cartItems,
    required double deliveryCost,
    required String deliveryMethod,
  }) async {
    final result = await _createPaymentIntent(
      cartItems: cartItems,
      deliveryCost: deliveryCost,
      deliveryMethod: deliveryMethod,
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
          throw Exception('${item.title} is no longer available');
        }

        final productData = productDoc.data();
        final stockValue = productData?['stock'] ?? 0;

        final int currentStock = stockValue is int
            ? stockValue
            : int.tryParse(stockValue.toString()) ?? 0;

        if (currentStock < item.quantity) {
          throw Exception('${item.title} does not have enough stock');
        }
      }

      final checkedTotal = checkedSubtotal + deliveryCost;

      final paymentIntentId = await _startStripeCheckout(
        cartItems: cartItems,
        deliveryCost: deliveryCost,
        deliveryMethod: deliveryMethod,
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
        if (color.isNotEmpty) {
          map['color'] = color;
        }
        return map;
      }).toList();

      final orderNumber = await FirestoreService.createOrder(
        items: orderItems,
        itemCount: totalItems,
        total: checkedTotal,
        deliveryMethod: deliveryMethod,
        paymentMethod: paymentMethod,
        paymentIntentId: paymentIntentId,
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
        _brandedErrorSnackBar(e.error.localizedMessage ?? loc.paymentCancelled),
      );
    } catch (e) {
      debugPrint("PLACE ORDER ERROR: $e");

      if (!mounted) return;

      // Surface the actual Cloud Function / Firestore message when present so
      // the user understands why placing the order failed (e.g. rate limit,
      // stock unavailable). Fall back to a generic line otherwise.
      final raw = e is FirebaseFunctionsException
          ? (e.message ?? e.code)
          : e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : 'Something went wrong. Please try again.';

      messenger.showSnackBar(_brandedErrorSnackBar(raw));
    } finally {
      if (mounted) {
        setState(() => isPlacingOrder = false);
      }
    }
  }

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
              return Center(
                child: Text(
                  "${AppLocalizations.of(context)!.couldNotLoadCart}: ${cartSnapshot.error}",
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.secondaryText,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            }

            final cartDocs = cartSnapshot.data?.docs ?? [];

            final cartItems = cartDocs.map((doc) {
              return CartItem.fromFirestore(doc.id, doc.data());
            }).toList();

            double subtotal = 0;
            for (final item in cartItems) {
              subtotal += item.price * item.quantity;
            }

            final double total = subtotal + deliveryCost;

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
                                  "${AppLocalizations.of(context)!.couldNotLoadSavedAddresses}: ${addressSnapshot.error}",
                                  style: AppTextStyles.bodySmall,
                                ),
                              )
                            else
                              Column(
                                children: [
                                  if (hasAddress) ...[
                                    addressInfo(addressDocs.first.data()),
                                    const SizedBox(height: 16),
                                  ],
                                  addressButton(hasAddress: hasAddress),
                                ],
                              ),
                            const SizedBox(height: 28),
                            Text(
                              AppLocalizations.of(context)!.deliveryMethod,
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
                                  value: deliveryMethod,
                                  isExpanded: true,
                                  dropdownColor: AppColors.field,
                                  items: [
                                    DropdownMenuItem(
                                      value: "Regular Delivery",
                                      child: Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.regularDelivery,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: "Same Day Delivery",
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
                                            value == "Regular Delivery" ? 3 : 5;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
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
                                      value: "Card",
                                      child: Text(
                                        AppLocalizations.of(context)!.card,
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        paymentMethod = value;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 40),
                            const Divider(
                              color: AppColors.border,
                              thickness: 0.5,
                            ),
                            const SizedBox(height: 20),
                            buildTotalRow(
                              AppLocalizations.of(context)!.subtotal,
                              "${subtotal.toStringAsFixed(0)} KWD",
                            ),
                            const SizedBox(height: 8),
                            buildTotalRow(
                              AppLocalizations.of(context)!.delivery,
                              "${deliveryCost.toStringAsFixed(0)} KWD",
                            ),
                            const SizedBox(height: 12),
                            const Divider(
                              color: AppColors.border,
                              thickness: 0.5,
                            ),
                            const SizedBox(height: 12),
                            buildTotalRow(
                              AppLocalizations.of(context)!.total,
                              "${total.toStringAsFixed(0)} KWD",
                              bold: true,
                            ),
                            const SizedBox(height: 30),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      height: 70,
                      child: ElevatedButton.icon(
                        onPressed: isPlacingOrder
                            ? null
                            : () {
                                _placeOrder(
                                  cartItems: cartItems,
                                  total: total,
                                  hasAddress: hasAddress,
                                );
                              },
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
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

  Widget addressButton({required bool hasAddress}) {
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

  Widget addressInfo(Map<String, dynamic> address) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "${address["firstName"]} ${address["lastName"]}",
          style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          "${AppLocalizations.of(context)!.block} ${address["block"]} "
          "${AppLocalizations.of(context)!.street} ${address["street"]} "
          "${AppLocalizations.of(context)!.house} ${address["house"]}",
          style: AppTextStyles.bodyMedium,
        ),
        Text(
          "${address["area"]} ${address["governorate"]}",
          style: AppTextStyles.bodyMedium,
        ),
        Text(address["phone"] ?? "", style: AppTextStyles.bodyMedium),
      ],
    );
  }

  Widget buildTotalRow(String title, String value, {bool bold = false}) {
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
