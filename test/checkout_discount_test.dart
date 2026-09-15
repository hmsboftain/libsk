// Unit tests for checkoutDiscount in checkout_page.dart — the checkout's preview
// of the discount-code rule createOrder enforces (functions/discount_codes.js).
//
// The checkout recomputes the discount from the live cart on every build, so
// these pin the three things the customer sees: a boutique's code only on its
// own cart, a discount that follows the cart if it changes after the code is
// applied, and a discount that never eats into the delivery fee.

import 'package:flutter_test/flutter_test.dart';
import 'package:libsk/pages/checkout_page.dart';
import 'package:libsk/widgets/cart_item.dart';

CartItem item(String boutiqueId, double price, [int quantity = 1]) => CartItem(
  id: '$boutiqueId-$price',
  productId: 'p-$price',
  boutiqueId: boutiqueId,
  imageUrl: '',
  title: 't',
  description: '',
  size: 'M',
  price: price,
  quantity: quantity,
);

double discount(
  List<CartItem> items, {
  String type = 'percentage',
  double value = 10,
  String? codeBoutiqueId = 'A',
}) => checkoutDiscount(
  type: type,
  value: value,
  codeBoutiqueId: codeBoutiqueId,
  items: items,
);

void main() {
  group('scope', () {
    test("boutique A's code applies to a boutique A cart", () {
      expect(discount([item('A', 7.5, 2)], codeBoutiqueId: 'A'), 1.5);
    });

    test("boutique A's code is worth nothing on a boutique B cart", () {
      expect(discount([item('B', 10)], codeBoutiqueId: 'A'), 0);
    });

    test("boutique A's code is worth nothing on a mixed A+B cart", () {
      expect(discount([item('A', 10), item('B', 10)], codeBoutiqueId: 'A'), 0);
    });

    test('a code with no boutiqueId is worth nothing on any cart', () {
      for (final cart in [
        [item('A', 10)], [item('B', 10)], [item('A', 10), item('B', 10)],
      ]) {
        expect(discount(cart, value: 15, codeBoutiqueId: null), 0);
        expect(discount(cart, value: 15, codeBoutiqueId: ''), 0);
      }
    });
  });

  group('never touches delivery', () {
    test('a flat code larger than the items is capped at the item subtotal', () {
      expect(discount([item('A', 10)], type: 'flat', value: 50), 10);
    });

    test('the discount never exceeds the subtotal, so the total never dips below delivery', () {
      const delivery = 2.0;
      for (final subtotal in [0.5, 1.0, 7.5, 13.0]) {
        for (final (type, value) in [
          ('percentage', 10.0), ('percentage', 100.0), ('percentage', 250.0),
          ('flat', 0.25), ('flat', 5.0), ('flat', 1000.0),
        ]) {
          final d = discount([item('A', subtotal)], type: type, value: value);
          expect(d, inInclusiveRange(0, subtotal));
          expect(subtotal + delivery - d, greaterThanOrEqualTo(delivery - 1e-9));
        }
      }
    });
  });

  group('follows the cart', () {
    test('if the cart shrinks after a code is applied, the discount shrinks with it', () {
      // 5.000 flat applied on a 10.000 cart; the cart then drops to one 3.000 item.
      expect(discount([item('A', 10)], type: 'flat', value: 5), 5);
      expect(discount([item('A', 3)], type: 'flat', value: 5), 3); // not a stale 5
      // A percentage code re-prices on the new subtotal.
      expect(discount([item('A', 20)], value: 10), 2);
      expect(discount([item('A', 12.5)], value: 10), 1.25);
    });

    test('an empty cart has no discount', () {
      expect(discount([], codeBoutiqueId: 'A'), 0);
    });
  });

  group('no regression', () {
    test('single-boutique carts price exactly as the previous checkout preview', () {
      // The previous preview: percentage of the discountable subtotal to 3 dp,
      // or min(value, discountable) — identical for a single-boutique cart.
      double previous(double subtotal, String type, double value) =>
          type == 'percentage'
              ? double.parse(((subtotal * value) / 100).toStringAsFixed(3))
              : (value < subtotal ? value : subtotal);
      for (final cart in [
        [item('A', 7.5)], [item('A', 12.345, 3)], [item('A', 8.75, 2), item('A', 11.25)],
      ]) {
        final subtotal = cart.fold<double>(0, (s, i) => s + i.price * i.quantity);
        for (final (type, value) in [
          ('percentage', 5.0), ('percentage', 12.5), ('percentage', 33.0),
          ('flat', 0.5), ('flat', 2.5), ('flat', 7.777),
        ]) {
          expect(
            discount(cart, type: type, value: value, codeBoutiqueId: 'A'),
            previous(subtotal, type, value),
          );
        }
      }
    });
  });
}
