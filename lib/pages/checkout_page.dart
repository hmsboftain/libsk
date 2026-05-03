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

class _CheckoutPageState extends State<CheckoutPage> {
  String deliveryMethod = "Same Day Delivery";
  String paymentMethod = "Card";
  double deliveryCost = 5;
  bool isPlacingOrder = false;

  Future<Map<String, String>> _createPaymentIntent({
    required List<CartItem> cartItems,
    required double deliveryCost,
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
      'currency': 'usd',
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

  Future<void> _placeOrder({
    required List<CartItem> cartItems,
    required double total,
    required bool hasAddress,
  }) async {
    final loc = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (cartItems.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(loc.yourCartIsEmpty),
        ),
      );
      return;
    }

    if (!hasAddress) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(loc.pleaseAddADeliveryAddress),
        ),
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
      );

      final List<Map<String, dynamic>> orderItems = cartItems.map((item) {
        return {
          'productId': item.productId,
          'boutiqueId': item.boutiqueId,
          'title': item.title,
          'imageUrl': item.imageUrl,
          'description': item.description,
          'size': item.size,
          'price': item.price,
          'quantity': item.quantity,
        };
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
          builder: (context) => OrderConfirmationPage(
            orderNumber: orderNumber,
          ),
        ),
      );
    } on StripeException catch (e) {
      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.error.localizedMessage ?? loc.paymentCancelled,
          ),
        ),
      );
    } catch (e) {
      debugPrint("PLACE ORDER ERROR: $e");

      if (!mounted) return;

      final message = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : 'Something went wrong. Please try again.';

      messenger.showSnackBar(
        SnackBar(content: Text(message)),
      );
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
              style: const TextStyle(fontSize: 16, color: Colors.black54),
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
          stream: FirestoreService.getCartItemsStream(),
          builder: (context, cartSnapshot) {
            if (cartSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.black),
              );
            }

            if (cartSnapshot.hasError) {
              return Center(
                child: Text(
                  "${AppLocalizations.of(context)!.couldNotLoadCart}: ${cartSnapshot.error}",
                  style: const TextStyle(fontSize: 16, color: Colors.black54),
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
              stream: FirestoreService.getSavedAddressesStream(),
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
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Divider(),
                            const SizedBox(height: 18),
                            Text(
                              AppLocalizations.of(context)!.accountDetails,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
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
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fullName,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    email,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              AppLocalizations.of(context)!.deliveryAddress,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (addressSnapshot.connectionState ==
                                ConnectionState.waiting)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (addressSnapshot.hasError)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  "${AppLocalizations.of(context)!.couldNotLoadSavedAddresses}: ${addressSnapshot.error}",
                                  style: const TextStyle(
                                    color: Colors.black54,
                                  ),
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
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10),
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
                                        AppLocalizations.of(context)!
                                            .regularDelivery,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: "Same Day Delivery",
                                      child: Text(
                                        AppLocalizations.of(context)!
                                            .sameDayDelivery,
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
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10),
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
                            const Divider(),
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
                            const Divider(),
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
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Icon(
                          Icons.shopping_bag_outlined,
                          size: 28,
                        ),
                        label: Text(
                          isPlacingOrder
                              ? AppLocalizations.of(context)!.placingOrder
                              : AppLocalizations.of(context)!.placeOrder,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.black54,
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

  Widget addressButton({required bool hasAddress}) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AddAddressPage(),
          ),
        );

        if (mounted) setState(() {});
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text(
              hasAddress
                  ? AppLocalizations.of(context)!.changeDeliveryAddress
                  : AppLocalizations.of(context)!.addDeliveryAddress,
              style: const TextStyle(fontSize: 15),
            ),
            const Spacer(),
            const Icon(Icons.add),
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
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          "${AppLocalizations.of(context)!.block} ${address["block"]} "
              "${AppLocalizations.of(context)!.street} ${address["street"]} "
              "${AppLocalizations.of(context)!.house} ${address["house"]}",
        ),
        Text("${address["area"]} ${address["governorate"]}"),
        Text(address["phone"] ?? ""),
      ],
    );
  }

  Widget buildTotalRow(String title, String value, {bool bold = false}) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}