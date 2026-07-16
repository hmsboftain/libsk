import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import '../widgets/error_state_widget.dart';
import '../navigation/app_header.dart';
import '../core/services/analytics_service.dart';
import '../services/firestore_service.dart';
import '../widgets/cart_item.dart';
import '../widgets/boutique_logo_avatar.dart';
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

/// Lightweight view of a per-boutique cart summary doc (carts/{boutiqueId}).
class _CartSummary {
  final String boutiqueId;
  final String boutiqueName;
  final String boutiqueLogoUrl;
  final int itemCount;

  const _CartSummary({
    required this.boutiqueId,
    required this.boutiqueName,
    required this.boutiqueLogoUrl,
    required this.itemCount,
  });

  factory _CartSummary.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return _CartSummary(
      boutiqueId: doc.id,
      boutiqueName: (data['boutiqueName'] ?? '').toString(),
      boutiqueLogoUrl: (data['boutiqueLogoUrl'] ?? '').toString(),
      itemCount: (data['itemCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _cartsStream;
  String? _selectedBoutiqueId;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('cart');
    _cartsStream = FirestoreService.getCartsStream();
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
              const AppHeader(showBackButton: true, isCartPage: true),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _cartsStream,
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

                    final carts = (snapshot.data?.docs ?? [])
                        .map(_CartSummary.fromDoc)
                        .toList();

                    if (carts.isEmpty) {
                      return _buildEmptyCart(l10n);
                    }

                    // Resolve the active boutique — keep the current selection
                    // if it still has a cart, otherwise fall back to the most
                    // recently updated one.
                    final ids = carts.map((c) => c.boutiqueId).toSet();
                    final selectedId =
                        (_selectedBoutiqueId != null &&
                            ids.contains(_selectedBoutiqueId))
                        ? _selectedBoutiqueId!
                        : carts.first.boutiqueId;
                    final selected = carts.firstWhere(
                      (c) => c.boutiqueId == selectedId,
                    );

                    return Column(
                      children: [
                        if (carts.length > 1)
                          _boutiqueSwitcher(carts, selectedId),
                        Expanded(
                          child: _BoutiqueCartView(
                            key: ValueKey(selected.boutiqueId),
                            boutiqueId: selected.boutiqueId,
                            boutiqueName: selected.boutiqueName,
                            boutiqueLogoUrl: selected.boutiqueLogoUrl,
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
      ),
    );
  }

  // ── Boutique switcher ───────────────────────────────────────────────────────

  Widget _boutiqueSwitcher(List<_CartSummary> carts, String selectedId) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: carts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cart = carts[i];
          final isSelected = cart.boutiqueId == selectedId;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                setState(() => _selectedBoutiqueId = cart.boutiqueId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.deepAccent : AppColors.field,
                border: Border.all(
                  color: isSelected ? AppColors.deepAccent : AppColors.border,
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BoutiqueLogoAvatar(
                    imageUrl: cart.boutiqueLogoUrl,
                    size: 26,
                    padding: 2,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    cart.boutiqueName.isNotEmpty
                        ? cart.boutiqueName
                        : AppLocalizations.of(context)!.boutique,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: isSelected
                          ? AppColors.background
                          : AppColors.primaryText,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${cart.itemCount})',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: isSelected
                          ? AppColors.background
                          : AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Empty state ─────────────────────────────────────────────────────────────

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

/// The scrollable items + subtotal + checkout for a single boutique's cart.
/// Keyed by boutiqueId so switching boutiques rebuilds cleanly, while quantity
/// changes within a boutique reuse the same stream subscription.
class _BoutiqueCartView extends StatefulWidget {
  final String boutiqueId;
  final String boutiqueName;
  final String boutiqueLogoUrl;

  const _BoutiqueCartView({
    super.key,
    required this.boutiqueId,
    required this.boutiqueName,
    required this.boutiqueLogoUrl,
  });

  @override
  State<_BoutiqueCartView> createState() => _BoutiqueCartViewState();
}

class _BoutiqueCartViewState extends State<_BoutiqueCartView> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _itemsStream;

  @override
  void initState() {
    super.initState();
    _itemsStream = FirestoreService.getCartItemsStream(widget.boutiqueId);
  }

  Future<void> _increaseQuantity(CartItem item) async {
    await FirestoreService.updateCartItemQuantity(
      boutiqueId: widget.boutiqueId,
      docId: item.id,
      quantity: item.quantity + 1,
    );
  }

  Future<void> _decreaseQuantity(CartItem item) async {
    if (item.quantity > 1) {
      await FirestoreService.updateCartItemQuantity(
        boutiqueId: widget.boutiqueId,
        docId: item.id,
        quantity: item.quantity - 1,
      );
    }
  }

  Future<void> _deleteItem(CartItem item) async {
    await FirestoreService.deleteCartItem(
      boutiqueId: widget.boutiqueId,
      docId: item.id,
    );
    AnalyticsService.instance.logRemoveFromCart(item.productId);
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
    Widget checkout() => CheckoutPage(
      boutiqueId: widget.boutiqueId,
      boutiqueName: widget.boutiqueName,
    );

    if (user == null) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (result == true && mounted) {
        await FirestoreService.mergeGuestCartToUser();
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => checkout()),
        );
      }
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => checkout()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _itemsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: AppColors.deepAccent,
              strokeWidth: 1.5,
            ),
          );
        }

        final cartItems = (snapshot.data?.docs ?? [])
            .map((doc) => CartItem.fromFirestore(doc.id, doc.data()))
            .toList();

        // The parent carts stream removes this view once the boutique cart is
        // emptied; guard against a transient empty frame.
        if (cartItems.isEmpty) {
          return const SizedBox.shrink();
        }

        final subtotal = cartItems.fold<double>(
          0.0,
          (total, item) => total + item.price * item.quantity,
        );

        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(l10n.cart, style: AppTextStyles.headingLarge),
                      const SizedBox(height: 12),
                      // Which boutique this cart belongs to.
                      Row(
                        children: [
                          BoutiqueLogoAvatar(
                            imageUrl: widget.boutiqueLogoUrl,
                            size: 28,
                            padding: 2,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              widget.boutiqueName.isNotEmpty
                                  ? widget.boutiqueName
                                  : l10n.boutique,
                              style: AppTextStyles.labelLarge,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Column(
                        children: cartItems.map((item) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: CartItemWidget(
                              imageUrl: item.imageUrl,
                              title: item.title,
                              description: item.description,
                              size: item.size,
                              color: item.color,
                              price: item.price,
                              quantity: item.quantity,
                              specialRequest: item.specialRequest,
                              onIncrease: () => _increaseQuantity(item),
                              onDecrease: () => _decreaseQuantity(item),
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
                  const Divider(color: AppColors.border, thickness: 0.5),
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
                      style: AppTextStyles.bodySmall.copyWith(height: 1.3),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 70,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        AnalyticsService.instance.logBeginCheckout(
                          subtotal,
                          cartItems.fold<int>(0, (n, i) => n + i.quantity),
                        );
                        _handleCheckout();
                      },
                      icon: const Icon(Icons.shopping_bag_outlined, size: 28),
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
    );
  }
}
