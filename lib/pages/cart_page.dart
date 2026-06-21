import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../widgets/error_state_widget.dart';
import '../navigation/app_header.dart';
import '../services/firestore_service.dart';
import '../widgets/cart_item.dart';
import '../widgets/theme.dart';
import 'checkout_page.dart';
import 'login_page.dart';
import 'boutiques_page.dart';
import '../core/constants/countries.dart';
import '../services/currency_service.dart';

String _fmt(double kwd) {
  final service = CurrencyService.instance;
  final country = countryByCode(service.selectedCountryCode);
  return service.format(kwd, country.currencySymbol, country.currency);
}

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

  Future<void> _increaseQuantity(CartItem item) async {
    await FirestoreService.updateCartItemQuantity(
      docId: item.id,
      quantity: item.quantity + 1,
    );
  }

  Future<void> _decreaseQuantity(CartItem item) async {
    if (item.quantity > 1) {
      await FirestoreService.updateCartItemQuantity(
        docId: item.id,
        quantity: item.quantity - 1,
      );
    }
  }

  Future<void> _deleteItem(CartItem item) async {
    await FirestoreService.deleteCartItem(item.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.itemRemovedFromCart),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _handleCheckout() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (result == true && context.mounted) {
        await FirestoreService.mergeGuestCartToUser();
        if (!context.mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CheckoutPage()),
        );
      }
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CheckoutPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

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
                    return ErrorStateWidget.inline(
                      title: l10n.somethingWentWrong,
                      message: l10n.pullDownToRetry,
                      onRetry: () => setState(() {}),
                      type: ErrorType.network,
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];
                  final cartItems = docs
                      .map((doc) => CartItem.fromFirestore(doc.id, doc.data()))
                      .toList();

                  final subtotal = cartItems.fold<double>(
                    0.0,
                    (total, item) => total + item.price * item.quantity,
                  );

                  if (cartItems.isEmpty) {
                    return _buildEmptyCart(l10n);
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
                                  l10n.cart,
                                  style: AppTextStyles.headingLarge,
                                ),
                                const SizedBox(height: 18),
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
                                        onIncrease: () =>
                                            _increaseQuantity(item),
                                        onDecrease: () =>
                                            _decreaseQuantity(item),
                                        onDelete: () => _deleteItem(item),
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
                        color: AppColors.background,
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
                                  l10n.subtotal,
                                  style: AppTextStyles.labelLarge.copyWith(
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _fmt(subtotal),
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
                                l10n.shippingChargesAndDiscountCodesCalculatedAtCheckout,
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
                                    : _handleCheckout,
                                icon: const Icon(
                                  Icons.shopping_bag_outlined,
                                  size: 28,
                                ),
                                label: Text(
                                  l10n.checkoutButton,
                                  style: AppTextStyles.button,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.deepAccent,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: AppColors.softAccent,
                                  disabledForegroundColor: Colors.white70,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.zero,
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

  Widget _buildEmptyCart(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.shopping_bag_outlined,
              size: 56,
              color: AppColors.softAccent,
            ),
            const SizedBox(height: 20),
            Text(
              l10n.yourCartIsEmpty,
              style: AppTextStyles.headingSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.cartEmptySubtitle,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.secondaryText,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BoutiquesPage()),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
              child: Text(l10n.browseBoutiques, style: AppTextStyles.button),
            ),
          ],
        ),
      ),
    );
  }
}
