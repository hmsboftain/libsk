// Tests for the client half of promo click tracking.
//
// promoStampFor is the paid/free gate on the CLIENT: the admin homepage tool
// sets exactly the same rendering flags (isFeaturedOnHome and friends) as a paid
// booking, so a stamp is the only thing separating an advert from free editorial
// curation. Getting this wrong bills a boutique for clicks it never bought, or
// credits one booking with another's — so the null cases matter as much as the
// hits.
//
// Mirrors the stamp written by applyPromoRendering in functions/index.js.

import 'package:flutter_test/flutter_test.dart';
import 'package:libsk/core/services/promo_click_service.dart';

/// A stamp exactly as applyPromoRendering writes it.
Map<String, dynamic> stamp(
  String placementType,
  String bookingId, {
  String boutiqueId = 'luwani',
  String? category,
}) => {
      'placementType': placementType,
      'bookingId': bookingId,
      'boutiqueId': boutiqueId,
      if (category != null) 'category': category,
    };

void main() {
  group('promoStampFor — paid vs free', () {
    test('parses the stamp shape live in production', () {
      // Copied verbatim from boutiques/katleir/products/PbVsLU68dWEiMcxIUScL as
      // written by the deployed activator on 2026-07-16. If the server ever
      // changes the stamp shape, this fails rather than silently logging no
      // clicks — the failure mode that would otherwise look like "the ad got no
      // engagement".
      final live = [
        {
          'placementType': 'featured_product',
          'bookingId': 'TfXwVHqusEEPXJwSgc6r',
          'boutiqueId': 'katleir',
        },
      ];
      final s = promoStampFor(live, PromoPlacement.featuredProduct);
      expect(s, isNotNull);
      expect(s!.bookingId, 'TfXwVHqusEEPXJwSgc6r');
      expect(s.boutiqueId, 'katleir');
      expect(s.category, isNull);
    });

    test('finds the booking that paid for this placement', () {
      final s = promoStampFor(
        [stamp(PromoPlacement.featuredProduct, 'bk1')],
        PromoPlacement.featuredProduct,
      );
      expect(s, isNotNull);
      expect(s!.bookingId, 'bk1');
      expect(s.boutiqueId, 'luwani');
    });

    test('an editorial pick has no stamp, so nothing is billed', () {
      // The exact shape of an admin-featured product: flags set, no stamp.
      expect(promoStampFor(null, PromoPlacement.featuredProduct), isNull);
      expect(promoStampFor([], PromoPlacement.featuredProduct), isNull);
    });

    test('a stamp for a DIFFERENT placement does not match', () {
      // Product is feed-sponsored but NOT featured — a tap on the home featured
      // row must not be billed to the feed booking.
      final s = promoStampFor(
        [stamp(PromoPlacement.feedSponsored, 'bkFeed')],
        PromoPlacement.featuredProduct,
      );
      expect(s, isNull);
    });

    test('one product promoted by two placements resolves each to its own booking', () {
      // Entirely legitimate: a boutique buys featured_product AND feed_sponsored
      // for the same item. Each surface must credit its own booking.
      final stamps = [
        stamp(PromoPlacement.featuredProduct, 'bkFeatured'),
        stamp(PromoPlacement.feedSponsored, 'bkFeed'),
      ];
      expect(
        promoStampFor(stamps, PromoPlacement.featuredProduct)!.bookingId,
        'bkFeatured',
      );
      expect(
        promoStampFor(stamps, PromoPlacement.feedSponsored)!.bookingId,
        'bkFeed',
      );
    });
  });

  group('promoStampFor — top_of_category is per category', () {
    final stamps = [
      stamp(PromoPlacement.topOfCategory, 'bkDresses', category: 'Dresses'),
      stamp(PromoPlacement.topOfCategory, 'bkTops', category: 'Tops'),
    ];

    test('a click in a category credits the booking that bought THAT category', () {
      // The reason the stamp is an array rather than a map keyed by placement:
      // one product pinned in two categories by two bookings would collide.
      expect(
        promoStampFor(stamps, PromoPlacement.topOfCategory, category: 'Dresses')!
            .bookingId,
        'bkDresses',
      );
      expect(
        promoStampFor(stamps, PromoPlacement.topOfCategory, category: 'Tops')!
            .bookingId,
        'bkTops',
      );
    });

    test('a category nobody pinned matches nothing', () {
      expect(
        promoStampFor(stamps, PromoPlacement.topOfCategory, category: 'Shoes'),
        isNull,
      );
    });

    test('categories with punctuation resolve (Dra\'a, Blouses & Shirts)', () {
      // These are real AppCategories values and are why the stamp is not a
      // Firestore field path.
      final punct = [
        stamp(PromoPlacement.topOfCategory, 'bk1', category: 'Blouses & Shirts'),
        stamp(PromoPlacement.topOfCategory, 'bk2', category: "Dra'a"),
      ];
      expect(
        promoStampFor(punct, PromoPlacement.topOfCategory,
                category: 'Blouses & Shirts')!
            .bookingId,
        'bk1',
      );
      expect(
        promoStampFor(punct, PromoPlacement.topOfCategory, category: "Dra'a")!
            .bookingId,
        'bk2',
      );
    });

    test('the matched category is carried through for the server to re-verify', () {
      final s = promoStampFor(stamps, PromoPlacement.topOfCategory,
          category: 'Dresses');
      expect(s!.category, 'Dresses');
    });
  });

  group('promoStampFor — malformed data never breaks a tap', () {
    test('junk entries are skipped, not thrown on', () {
      final s = promoStampFor(
        ['not-a-map', 42, null, stamp(PromoPlacement.featuredProduct, 'bk1')],
        PromoPlacement.featuredProduct,
      );
      expect(s!.bookingId, 'bk1');
    });

    test('a stamp with no bookingId is ignored', () {
      final s = promoStampFor(
        [
          {'placementType': PromoPlacement.featuredProduct, 'boutiqueId': 'x'},
        ],
        PromoPlacement.featuredProduct,
      );
      expect(s, isNull);
    });

    test('an empty bookingId is ignored', () {
      final s = promoStampFor(
        [stamp(PromoPlacement.featuredProduct, '')],
        PromoPlacement.featuredProduct,
      );
      expect(s, isNull);
    });
  });

  group('promoAttributionOf', () {
    test('reads the stamp array off a document', () {
      final data = {
        'title': 'Butter Dress',
        'promoAttribution': [stamp(PromoPlacement.featuredProduct, 'bk1')],
      };
      expect(promoAttributionOf(data), hasLength(1));
    });

    test('an unstamped or malformed document yields null, not a crash', () {
      expect(promoAttributionOf({'title': 'x'}), isNull);
      expect(promoAttributionOf(null), isNull);
      expect(promoAttributionOf({'promoAttribution': 'garbage'}), isNull);
    });
  });

  group('PromoClickService payloads', () {
    late List<Map<String, dynamic>> sent;

    setUp(() {
      sent = [];
      PromoClickService.debugOnClick = sent.add;
    });
    tearDown(() => PromoClickService.debugOnClick = null);

    test('a stamped click sends what the server needs to re-verify it', () async {
      await PromoClickService.instance.logStamped(
        promoStampFor(
          [stamp(PromoPlacement.topOfCategory, 'bk1', category: 'Dresses')],
          PromoPlacement.topOfCategory,
          category: 'Dresses',
        ),
        subjectId: 'p1',
      );
      expect(sent, hasLength(1));
      expect(sent.single['bookingId'], 'bk1');
      expect(sent.single['placementType'], PromoPlacement.topOfCategory);
      expect(sent.single['subjectId'], 'p1');
      expect(sent.single['category'], 'Dresses');
    });

    test('a null stamp (editorial) sends nothing at all', () async {
      await PromoClickService.instance.logStamped(null, subjectId: 'p1');
      expect(sent, isEmpty);
    });

    test('category is omitted for placements that are not category-scoped', () async {
      await PromoClickService.instance.logStamped(
        promoStampFor(
          [stamp(PromoPlacement.featuredProduct, 'bk1')],
          PromoPlacement.featuredProduct,
        ),
        subjectId: 'p1',
      );
      expect(sent.single.containsKey('category'), isFalse);
    });

    test('an empty bookingId or subjectId is never sent', () async {
      await PromoClickService.instance
          .logClick(bookingId: '', placementType: 'featured_product', subjectId: 'p1');
      await PromoClickService.instance
          .logClick(bookingId: 'bk1', placementType: 'featured_product', subjectId: '');
      expect(sent, isEmpty);
    });

    test('a paid banner logs against its boutique, keyed by promoBookingId', () async {
      await PromoClickService.instance.logBannerClick({
        'imageUrl': 'https://x/y.jpg',
        'boutiqueId': 'katleir',
        'promoBookingId': 'bkBanner',
      });
      expect(sent.single['bookingId'], 'bkBanner');
      expect(sent.single['placementType'], PromoPlacement.homeBanner);
      // home_banner is boutique-scoped: the subject is the boutique itself.
      expect(sent.single['subjectId'], 'katleir');
    });

    test('an editorial banner logs nothing', () async {
      // The real prod shape — no boutiqueId, no promoBookingId.
      await PromoClickService.instance.logBannerClick({
        'imageUrl': 'https://x/y.jpg',
        'title': 'Summer',
        'isActive': true,
        'order': 0,
      });
      expect(sent, isEmpty);
    });

    test('a banner with a boutique but no booking logs nothing', () async {
      await PromoClickService.instance
          .logBannerClick({'boutiqueId': 'katleir'});
      expect(sent, isEmpty);
    });
  });
}
