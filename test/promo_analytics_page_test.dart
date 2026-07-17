// Tests for the presentation logic behind the boutique's ad-performance page.
//
// These numbers are what an owner uses to decide whether to buy the slot again,
// so the edge cases matter more than the happy path: a rate with no clicks, a
// day the ad ran but nobody tapped, a booking that never went live at all.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsk/pages/promo_booking_analytics_page.dart';

void main() {
  group('filsToKwd', () {
    test('converts the server\'s integral fils to KWD', () {
      expect(filsToKwd(12500), 12.5);
      expect(filsToKwd(0), 0);
      expect(filsToKwd(1), 0.001);
    });
  });

  group('conversionRate', () {
    test('is orders per click', () {
      expect(conversionRate(clicks: 10, orders: 2), 0.2);
      expect(conversionRate(clicks: 4, orders: 4), 1.0);
    });

    test('is undefined — not zero — when nobody has clicked', () {
      // Showing "0%" here would read as "this ad converts terribly" when the
      // truth is "nobody has tapped it yet". The page renders an em-dash.
      expect(conversionRate(clicks: 0, orders: 0), isNull);
    });

    test('can exceed 100% when one click drives several orders', () {
      // Legitimate: a shopper taps once and buys twice inside the 48h window.
      // Not clamped — clamping would hide a genuinely great ad.
      expect(conversionRate(clicks: 1, orders: 2), 2.0);
    });
  });

  group('netKwd — did the ad pay for itself?', () {
    test('positive when attributed revenue beats the ad spend', () {
      expect(netKwd(attributedRevenueFils: 30000, adSpendKwd: 16), 14.0);
    });

    test('negative when it did not', () {
      expect(netKwd(attributedRevenueFils: 5000, adSpendKwd: 16), -11.0);
    });

    test('exactly break-even is not negative', () {
      expect(netKwd(attributedRevenueFils: 16000, adSpendKwd: 16), 0.0);
    });

    test('no attributed revenue means the whole spend is a loss', () {
      expect(netKwd(attributedRevenueFils: 0, adSpendKwd: 16), -16.0);
    });
  });

  group('clicksByDaySeries', () {
    // Kuwait midnight == 21:00 UTC the previous day — how bookings are cut.
    DateTime kuwaitMidnightUtc(int y, int m, int d) =>
        DateTime.utc(y, m, d).subtract(const Duration(hours: 3));

    test('one entry per booked day, in order', () {
      final s = clicksByDaySeries(
        clicksByDay: {'2026-07-16': 3, '2026-07-17': 5},
        dayStart: kuwaitMidnightUtc(2026, 7, 16),
        dayEnd: kuwaitMidnightUtc(2026, 7, 18),
      );
      expect(s.map((d) => d.day), ['2026-07-16', '2026-07-17']);
      expect(s.map((d) => d.clicks), [3, 5]);
    });

    test('a day the ad ran but nobody clicked appears as an explicit zero', () {
      // The gap is the information. Omitting it would make a quiet Thursday
      // indistinguishable from a Thursday the booking never covered.
      final s = clicksByDaySeries(
        clicksByDay: {'2026-07-16': 3},
        dayStart: kuwaitMidnightUtc(2026, 7, 16),
        dayEnd: kuwaitMidnightUtc(2026, 7, 19),
      );
      expect(s.map((d) => d.clicks), [3, 0, 0]);
      expect(s, hasLength(3));
    });

    test('dayEnd is exclusive, matching the booking window', () {
      final s = clicksByDaySeries(
        clicksByDay: const {},
        dayStart: kuwaitMidnightUtc(2026, 7, 16),
        dayEnd: kuwaitMidnightUtc(2026, 7, 17),
      );
      expect(s, hasLength(1));
      expect(s.single.day, '2026-07-16');
    });

    test('a full seven-day booking yields seven bars', () {
      final s = clicksByDaySeries(
        clicksByDay: const {},
        dayStart: kuwaitMidnightUtc(2026, 7, 19),
        dayEnd: kuwaitMidnightUtc(2026, 7, 26),
      );
      expect(s, hasLength(7));
      expect(s.first.day, '2026-07-19');
      expect(s.last.day, '2026-07-25');
    });

    test('no clicksByDay map at all is all zeroes, not a crash', () {
      // Real case: bookings that ran BEFORE per-day counts shipped have clicks
      // but no clicksByDay. The page must not blow up on them.
      final s = clicksByDaySeries(
        clicksByDay: null,
        dayStart: kuwaitMidnightUtc(2026, 7, 16),
        dayEnd: kuwaitMidnightUtc(2026, 7, 18),
      );
      expect(s.map((d) => d.clicks), [0, 0]);
    });

    test('unknown keys in the map are ignored, not appended', () {
      // Only days the booking actually covers are charted.
      final s = clicksByDaySeries(
        clicksByDay: {'2026-07-16': 3, '2099-01-01': 99},
        dayStart: kuwaitMidnightUtc(2026, 7, 16),
        dayEnd: kuwaitMidnightUtc(2026, 7, 17),
      );
      expect(s, hasLength(1));
      expect(s.single.clicks, 3);
    });

    test('a non-numeric count degrades to zero', () {
      final s = clicksByDaySeries(
        clicksByDay: {'2026-07-16': 'garbage'},
        dayStart: kuwaitMidnightUtc(2026, 7, 16),
        dayEnd: kuwaitMidnightUtc(2026, 7, 17),
      );
      expect(s.single.clicks, 0);
    });

    test('a malformed window cannot spin forever', () {
      // dayEnd before dayStart yields nothing rather than looping.
      final s = clicksByDaySeries(
        clicksByDay: const {},
        dayStart: kuwaitMidnightUtc(2026, 7, 18),
        dayEnd: kuwaitMidnightUtc(2026, 7, 16),
      );
      expect(s, isEmpty);
    });
  });

  group('against the real live booking', () {
    // Copied from promo_bookings/TfXwVHqusEEPXJwSgc6r as it stands in prod on
    // 2026-07-17, after the on-device click test: a 4-day featured_product
    // booking, one real click. If the server's rollup shape ever drifts, this
    // fails here rather than silently rendering an empty dashboard to an owner
    // who actually did get clicks.
    final booking = <String, dynamic>{
      'renderingApplied': true,
      'status': 'active',
      'priceKwd': 16,
      'numDays': 4,
      'dayStart': Timestamp.fromDate(DateTime.utc(2026, 7, 14, 21)),
      'dayEnd': Timestamp.fromDate(DateTime.utc(2026, 7, 18, 21)),
      'stats': {
        'clicks': 1,
        'attributedOrders': 0,
        'attributedRevenueFils': 0,
        'clicksByDay': {'2026-07-17': 1},
      },
    };

    test('the live booking is recognised as having run', () {
      expect(bookingHasRun(booking), isTrue);
    });

    test('its 4 booked days chart as 4 bars, on Kuwait days', () {
      final stats = booking['stats'] as Map<String, dynamic>;
      final s = clicksByDaySeries(
        clicksByDay: stats['clicksByDay'] as Map<String, dynamic>,
        dayStart: (booking['dayStart'] as Timestamp).toDate(),
        dayEnd: (booking['dayEnd'] as Timestamp).toDate(),
      );
      expect(s.map((d) => d.day),
          ['2026-07-15', '2026-07-16', '2026-07-17', '2026-07-18']);
      // The real click landed on the 17th; the other booked days are honest zeroes.
      expect(s.map((d) => d.clicks), [0, 0, 1, 0]);
    });

    test('one click and no orders reads as 0% conversion, not undefined', () {
      final stats = booking['stats'] as Map<String, dynamic>;
      expect(
        conversionRate(
          clicks: stats['clicks'] as int,
          orders: stats['attributedOrders'] as int,
        ),
        0.0,
      );
    });

    test('with nothing attributed, the ad is down its full 16 KWD', () {
      final stats = booking['stats'] as Map<String, dynamic>;
      expect(
        netKwd(
          attributedRevenueFils: stats['attributedRevenueFils'] as int,
          adSpendKwd: (booking['priceKwd'] as num).toDouble(),
        ),
        -16.0,
      );
    });
  });

  group('bookingHasRun — "never ran" must not read as "failed"', () {
    test('a booking the server put on screen has run', () {
      expect(bookingHasRun({'renderingApplied': true}), isTrue);
    });

    test('a booking awaiting payment or review has not', () {
      // No clicks by construction — it was never visible to anyone.
      expect(bookingHasRun({'renderingApplied': false}), isFalse);
      expect(bookingHasRun({'status': 'pending_payment'}), isFalse);
      expect(bookingHasRun(const {}), isFalse);
    });
  });

  group('bookingIsRunning', () {
    final now = DateTime.utc(2026, 7, 17, 12);

    test('rendered and still inside its window', () {
      expect(
        bookingIsRunning({
          'renderingApplied': true,
          'dayEnd': Timestamp.fromDate(DateTime.utc(2026, 7, 18, 21)),
        }, now),
        isTrue,
      );
    });

    test('rendered but finished', () {
      expect(
        bookingIsRunning({
          'renderingApplied': true,
          'dayEnd': Timestamp.fromDate(DateTime.utc(2026, 7, 16, 21)),
        }, now),
        isFalse,
      );
    });

    test('never rendered is never running, whatever the window says', () {
      expect(
        bookingIsRunning({
          'renderingApplied': false,
          'dayEnd': Timestamp.fromDate(DateTime.utc(2026, 7, 18, 21)),
        }, now),
        isFalse,
      );
    });

    test('feed bookings fall back to weekEnd', () {
      expect(
        bookingIsRunning({
          'renderingApplied': true,
          'weekEnd': Timestamp.fromDate(DateTime.utc(2026, 7, 18, 21)),
        }, now),
        isTrue,
      );
    });

    test('a missing window is not running rather than throwing', () {
      expect(bookingIsRunning({'renderingApplied': true}, now), isFalse);
    });
  });
}
