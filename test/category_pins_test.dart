// Unit tests for the paid category-pin merge in category_products_page.dart.
//
// mergePinnedFirst is what makes a top_of_category booking actually deliver what
// the boutique paid for: the pinned product on top, exactly once, whatever the
// shopper has sorted by. Generic over the key function, so these run against the
// REAL implementation with plain strings — no Firestore, no widget pumping.

import 'package:flutter_test/flutter_test.dart';
import 'package:libsk/pages/category_products_page.dart';

String key(String s) => s;

void main() {
  group('mergePinnedFirst', () {
    test('pinned products lead the list', () {
      final out = mergePinnedFirst(['p1'], ['a', 'b', 'c'], key);
      expect(out, ['p1', 'a', 'b', 'c']);
    });

    test('a pinned product already in the organic list is not duplicated', () {
      // The pin query and the category query both match the same product — it
      // must render once, at the top, not twice.
      final out = mergePinnedFirst(['b'], ['a', 'b', 'c'], key);
      expect(out, ['b', 'a', 'c']);
      expect(out.where((e) => e == 'b').length, 1);
    });

    test('no pins leaves the organic list untouched', () {
      final organic = ['a', 'b', 'c'];
      expect(mergePinnedFirst(<String>[], organic, key), organic);
    });

    test('pins with an empty organic list still render', () {
      expect(mergePinnedFirst(['p1', 'p2'], <String>[], key), ['p1', 'p2']);
    });

    test('several pins keep their relative order ahead of organic', () {
      final out = mergePinnedFirst(['p1', 'p2'], ['a', 'p2', 'b', 'p1'], key);
      expect(out, ['p1', 'p2', 'a', 'b']);
    });

    test('everything pinned collapses the organic list away', () {
      final out = mergePinnedFirst(['a', 'b'], ['a', 'b'], key);
      expect(out, ['a', 'b']);
    });

    test('both lists empty is empty, not an error', () {
      expect(mergePinnedFirst(<String>[], <String>[], key), isEmpty);
    });

    test('dedupe is by key, not identity — distinct objects, same doc path', () {
      // Mirrors the real call, where the pin query and the category query return
      // different snapshot instances for the SAME document.
      final pinned = [_Doc('boutiques/b1/products/p1')];
      final organic = [_Doc('boutiques/b1/products/p1'), _Doc('boutiques/b1/products/p2')];
      final out = mergePinnedFirst(pinned, organic, (d) => d.path);
      expect(out.length, 2);
      expect(out.first, same(pinned.first));
      expect(out.map((d) => d.path), ['boutiques/b1/products/p1', 'boutiques/b1/products/p2']);
    });

    test('same product id under different boutiques is NOT deduped', () {
      // Document ids are only unique within a boutique's subcollection, so the
      // key must be the full path — otherwise a collision would hide a rival
      // boutique's product from the category.
      final pinned = [_Doc('boutiques/b1/products/same')];
      final organic = [_Doc('boutiques/b2/products/same')];
      final out = mergePinnedFirst(pinned, organic, (d) => d.path);
      expect(out.length, 2, reason: 'different boutiques, different products');
    });

    test('the merged order is stable across repeated calls', () {
      final a = mergePinnedFirst(['p1', 'p2'], ['a', 'b'], key);
      final b = mergePinnedFirst(['p1', 'p2'], ['a', 'b'], key);
      expect(a, b);
    });
  });
}

class _Doc {
  final String path;
  _Doc(this.path);
}
