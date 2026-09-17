// Guards against the two category lists drifting apart.
//
// AppCategories.all is the canonical list (add/edit product, promo category
// picker), but the Browse grid keeps its own copy in
// CategoryBrowsePage.categories. A category added to only one of them either
// can't be browsed or can't be assigned to a product, and nothing else would
// catch it — so these compare the REAL lists, no widget pumping.

import 'package:flutter_test/flutter_test.dart';
import 'package:libsk/core/constants/app_categories.dart';
import 'package:libsk/pages/category_browse_page.dart';

void main() {
  // Every Browse tile except "All", which has no key and filters nothing.
  final browseKeys = CategoryBrowsePage.categories
      .map((c) => c['key'])
      .whereType<String>()
      .toList();
  const canonical = AppCategories.all;

  group('Browse grid vs AppCategories.all', () {
    test('every canonical category has a Browse tile', () {
      final missing = canonical.toSet().difference(browseKeys.toSet());
      expect(missing, isEmpty,
          reason: 'In AppCategories.all but not in CategoryBrowsePage.categories');
    });

    test('every Browse tile is a canonical category', () {
      final extra = browseKeys.toSet().difference(canonical.toSet());
      expect(extra, isEmpty,
          reason: 'In CategoryBrowsePage.categories but not in AppCategories.all');
    });

    test('neither list repeats a category', () {
      expect(canonical.toSet().length, canonical.length);
      expect(browseKeys.toSet().length, browseKeys.length);
    });

    test('the only keyless tile is "All"', () {
      final keyless =
          CategoryBrowsePage.categories.where((c) => c['key'] == null).toList();
      expect(keyless.map((c) => c['label']), ['All']);
    });
  });
}
