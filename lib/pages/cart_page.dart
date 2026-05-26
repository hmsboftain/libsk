import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/cart_item.dart';
import 'checkout_page.dart';
import 'login_page.dart';
import '../widgets/theme.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _cartStream;

  @override
  void initState() {
    super.initState();
    _cartStream = FirestoreService.getCartItemsStream();
  }

  Future<void> increaseQuantity(CartItem item) async {
    await FirestoreService.updateCartItemQuantity(
      docId: item.id,
      quantity: item.quantity + 1,
    );
  }

  Future<void> decreaseQuantity(CartItem item) async {
    if (item.quantity > 1) {
      await FirestoreService.updateCartItemQuantity(
        docId: item.id,
        quantity: item.quantity - 1,
      );
    }
  }

  Future<void> deleteItem(CartItem item) async {
    await FirestoreService.deleteCartItem(item.id);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.itemRemovedFromCart),
        duration: const Duration(seconds: 1),
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
            const AppHeader(showBackButton: true, isCartPage: true),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _cartStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.deepAccent,
                        strokeWidth: 1.5,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        AppLocalizations.of(context)!.somethingWentWrong,
                        style: AppTextStyles.bodySmall,
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  final cartItems = docs.map((doc) {
                    return CartItem.fromFirestore(doc.id, doc.data());
                  }).toList();

                  double subtotal = 0;
                  for (var item in cartItems) {
                    subtotal += item.price * item.quantity;
                  }

                  return Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                Text(
                                  AppLocalizations.of(context)!.cart,
                                  style: AppTextStyles.headingLarge,
                                ),
                                const SizedBox(height: 18),
                                if (cartItems.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 40),
                                    child: Center(
                                      child: Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.yourCartIsEmpty,
                                        style: AppTextStyles.bodyMedium
                                            .copyWith(
                                              color: AppColors.secondaryText,
                                            ),
                                      ),
                                    ),
                                  )
                                else
                                  Column(
                                    children: cartItems.map((item) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 18,
                                        ),
                                        child: CartItemWidget(
                                          imageUrl: item.imageUrl,
                                          title: item.title,
                                          description: item.description,
                                          size: item.size,
                                          color: item.color,
                                          price: item.price,
                                          quantity: item.quantity,
                                          onIncrease: () async {
                                            await increaseQuantity(item);
                                          },
                                          onDecrease: () async {
                                            await decreaseQuantity(item);
                                          },
                                          onDelete: () async {
                                            await deleteItem(item);
                                          },
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                const SizedBox(height: 90),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                        decoration: const BoxDecoration(
                          color: AppColors.background,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Divider(
                              color: AppColors.border,
                              thickness: 0.5,
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Text(
                                  AppLocalizations.of(context)!.subtotal,
                                  style: AppTextStyles.labelLarge.copyWith(
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  "${subtotal.toStringAsFixed(0)} KWD",
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                AppLocalizations.of(
                                  context,
                                )!.shippingChargesAndDiscountCodesCalculatedAtCheckout,
                                style: AppTextStyles.bodySmall.copyWith(
                                  height: 1.3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              height: 70,
                              child: ElevatedButton.icon(
                                onPressed: cartItems.isEmpty
                                    ? null
                                    : () async {
                                        final user =
                                            FirebaseAuth.instance.currentUser;

                                        if (user == null) {
                                          final result = await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const LoginPage(),
                                            ),
                                          );

                                          if (result == true &&
                                              context.mounted) {
                                            await FirestoreService.mergeGuestCartToUser();

                                            if (!context.mounted) return;
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    const CheckoutPage(),
                                              ),
                                            );
                                          }
                                        } else {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const CheckoutPage(),
                                            ),
                                          );
                                        }
                                      },
                                icon: const Icon(
                                  Icons.shopping_bag_outlined,
                                  size: 28,
                                ),
                                label: Text(
                                  AppLocalizations.of(context)!.checkoutButton,
                                  style: AppTextStyles.button,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.deepAccent,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: AppColors.softAccent,
                                  disabledForegroundColor: Colors.white70,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
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
