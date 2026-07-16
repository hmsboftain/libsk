// Tests for the home_banner tap target in rotating_hero_banner.dart.
//
// Two things must hold, and they are the whole point of the change:
//   1. a PAID banner (has boutiqueId) opens the advertising boutique, and
//   2. an EDITORIAL banner (no boutiqueId) stays completely inert — the admin
//      tool publishes banners with no boutique, and those have nowhere to go.
//
// These pump the REAL HeroBannerTapTarget, so they assert rendered behaviour
// rather than the shape of the source.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsk/widgets/rotating_hero_banner.dart';

void main() {
  group('bannerBoutiqueId — paid vs editorial discriminator', () {
    test('a paid promo banner exposes its boutique', () {
      // What applyPromoRendering publishes for a home_banner booking.
      expect(
        bannerBoutiqueId({
          'imageUrl': 'https://x/y.jpg',
          'isActive': true,
          'boutiqueId': 'katleir',
          'promoBookingId': 'bk1',
        }),
        'katleir',
      );
    });

    test('an editorial banner has no boutique', () {
      // The exact field set of the editorial banners live in prod (verified
      // against hero_banners on 2026-07-16): the boutiqueId key is ABSENT, not
      // empty. Both existing banners must keep rendering inert after this change.
      expect(
        bannerBoutiqueId({
          'createdAt': null,
          'ctaText': 'Shop',
          'imageUrl': 'https://x/y.jpg',
          'isActive': true,
          'order': 0,
          'subtitle': 'New in',
          'title': 'Summer',
        }),
        isNull,
      );
    });

    test('blank and whitespace-only boutiqueId count as editorial, not a link to nowhere', () {
      expect(bannerBoutiqueId({'boutiqueId': ''}), isNull);
      expect(bannerBoutiqueId({'boutiqueId': '   '}), isNull);
    });

    test('a non-string boutiqueId is coerced rather than crashing the home page', () {
      expect(bannerBoutiqueId({'boutiqueId': 123}), '123');
    });
  });

  group('bannerHasExpired — defence in depth behind revokePromoRendering', () {
    final past = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1)));
    final future = Timestamp.fromDate(DateTime.now().add(const Duration(days: 1)));

    test('a paid banner past its window is refused even while isActive is true', () {
      // The exact failure this guards: revokePromoRendering lagged or failed, so
      // isActive is still true and the boutique keeps the priciest slot for free.
      expect(
        bannerHasExpired({
          'isActive': true,
          'boutiqueId': 'katleir',
          'expiresAt': past,
        }),
        isTrue,
      );
    });

    test('a paid banner inside its window still renders', () {
      expect(bannerHasExpired({'boutiqueId': 'katleir', 'expiresAt': future}), isFalse);
    });

    test('an editorial banner has no expiresAt and never expires', () {
      // Curation, not a booking — it runs until an admin turns it off. Both
      // banners live in prod today are exactly this shape.
      expect(bannerHasExpired({'imageUrl': 'https://x/y.jpg', 'isActive': true}), isFalse);
    });

    test('a malformed expiresAt does not blank the home page', () {
      // Anything non-Timestamp is ignored rather than thrown on: a bad value must
      // not take down the hero slot.
      expect(bannerHasExpired({'expiresAt': 'not-a-timestamp'}), isFalse);
      expect(bannerHasExpired({'expiresAt': 12345}), isFalse);
      expect(bannerHasExpired({'expiresAt': null}), isFalse);
    });
  });

  group('HeroBannerTapTarget', () {
    testWidgets('an editorial banner has NO tap target in the tree', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: HeroBannerTapTarget(
          boutiqueId: null,
          child: Text('banner'),
        ),
      ));

      expect(find.text('banner'), findsOneWidget);
      // Not merely a no-op handler — genuinely no gesture detector, so a shopper
      // never taps a banner and gets nothing.
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('a paid banner is wrapped in a tap target', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: HeroBannerTapTarget(
          boutiqueId: 'katleir',
          child: Text('banner'),
        ),
      ));

      expect(find.text('banner'), findsOneWidget);
      expect(find.byType(GestureDetector), findsOneWidget);
    });

    testWidgets('tapping an editorial banner navigates nowhere', (tester) async {
      final observer = _RecordingObserver();
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [observer],
        home: const HeroBannerTapTarget(
          boutiqueId: null,
          child: Text('banner'),
        ),
      ));
      observer.pushes.clear(); // drop the initial home route

      await tester.tap(find.text('banner'));
      await tester.pump();

      expect(observer.pushes, isEmpty);
    });

    testWidgets('tapping a paid banner pushes a route', (tester) async {
      final observer = _RecordingObserver();
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [observer],
        home: const HeroBannerTapTarget(
          boutiqueId: 'katleir',
          child: Text('banner'),
        ),
      ));
      observer.pushes.clear();

      await tester.tap(find.text('banner'));
      // Deliberately not pumpAndSettle: one frame is enough to prove the push.
      await tester.pump();

      expect(observer.pushes, hasLength(1));

      // The pushed destination is BoutiqueStorefrontPage, which opens a Firestore
      // stream as it builds and therefore throws without an initialised Firebase.
      // The unit under test is the tap target — that it PUSHES — so the
      // destination's own dependency is consumed here rather than left to fail
      // the test. Its absence would mean nothing was pushed at all.
      expect(tester.takeException(), isA<FirebaseException>());
    });

    testWidgets('the child renders identically whether or not it is tappable', (tester) async {
      for (final id in [null, 'katleir']) {
        await tester.pumpWidget(MaterialApp(
          home: HeroBannerTapTarget(
            boutiqueId: id,
            child: const Text('banner'),
          ),
        ));
        expect(find.text('banner'), findsOneWidget);
      }
    });
  });
}

class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes.add(route);
    super.didPush(route, previousRoute);
  }
}
