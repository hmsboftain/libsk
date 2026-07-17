// Layout regression tests for the clicks-by-day sparkline.
//
// Reported from a real device: "bottom overflowed by 4.0 pixels" on the
// performance page. A RenderFlex overflow raises a FlutterError in widget tests,
// so pumping the real widget reproduces it rather than eyeballing arithmetic.
//
// The overflow is not cosmetic in origin: the bar height and the box height were
// two independent hard-coded numbers that had to happen to agree. They didn't,
// and any change to either — or a shopper's text-scale setting — would break it
// again. These tests pin the cases that must fit.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsk/l10n/app_localizations.dart';
import 'package:libsk/pages/promo_booking_analytics_page.dart';

/// Pump the sparkline in a realistically narrow column, like the ListView it
/// actually lives in, and return any layout exception.
///
/// The localisation delegates are not decoration: the sparkline formats its day
/// labels with DateFormat('E', locale), and it is GlobalMaterialLocalizations
/// that initialises intl's locale data. Without them the widget throws
/// LocaleDataException before it can even lay out — which is exactly what the
/// real app avoids by installing these same delegates.
Future<Object?> pumpSparkline(
  WidgetTester tester,
  List<DayCount> series, {
  double textScale = 1.0,
  double width = 350,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: PromoClicksSparkline(series: series, locale: 'en'),
            ),
          ),
        ),
      ),
    ),
  );
  return tester.takeException();
}

void main() {
  testWidgets('the reported case: a 4-day booking with one click does not overflow',
      (tester) async {
    // The live katleir booking exactly: 4 booked days, a single click on the
    // 17th. This is the layout that overflowed by 4px on device.
    final series = const [
      DayCount('2026-07-15', 0),
      DayCount('2026-07-16', 0),
      DayCount('2026-07-17', 1),
      DayCount('2026-07-18', 0),
    ];
    expect(await pumpSparkline(tester, series), isNull);
  });

  testWidgets('a full 7-day booking at the tallest bar does not overflow',
      (tester) async {
    // The worst case for height: a bar at full scale on every day.
    final series = [
      for (var i = 15; i < 22; i++) DayCount('2026-07-$i', 40),
    ];
    expect(await pumpSparkline(tester, series), isNull);
  });

  testWidgets('a single day at full height does not overflow', (tester) async {
    expect(await pumpSparkline(tester, const [DayCount('2026-07-17', 9)]), isNull);
  });

  testWidgets('an all-zero week does not overflow', (tester) async {
    final series = [
      for (var i = 15; i < 22; i++) DayCount('2026-07-$i', 0),
    ];
    expect(await pumpSparkline(tester, series), isNull);
  });

  testWidgets('large click counts (wide labels) do not overflow', (tester) async {
    final series = const [
      DayCount('2026-07-15', 1),
      DayCount('2026-07-16', 9999),
      DayCount('2026-07-17', 120),
    ];
    expect(await pumpSparkline(tester, series), isNull);
  });

  testWidgets('a narrow phone does not overflow', (tester) async {
    final series = [
      for (var i = 15; i < 22; i++) DayCount('2026-07-$i', 12),
    ];
    expect(await pumpSparkline(tester, series, width: 280), isNull);
  });

  testWidgets('bumped-up system text size does not overflow', (tester) async {
    // The original bug in general form: two text lines plus a fixed bar had to
    // fit a fixed box. Anything that grows the text reopens it.
    final series = const [
      DayCount('2026-07-15', 0),
      DayCount('2026-07-16', 3),
      DayCount('2026-07-17', 1),
      DayCount('2026-07-18', 0),
    ];
    expect(await pumpSparkline(tester, series, textScale: 1.3), isNull);
  });

  testWidgets('an empty series renders nothing rather than an empty box',
      (tester) async {
    expect(await pumpSparkline(tester, const []), isNull);
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('every booked day is still drawn and labelled', (tester) async {
    // Guard against "fixing" the overflow by dropping content.
    final series = const [
      DayCount('2026-07-15', 0),
      DayCount('2026-07-16', 2),
      DayCount('2026-07-17', 1),
      DayCount('2026-07-18', 0),
    ];
    await pumpSparkline(tester, series);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(2)); // the two quiet days still show
  });
}
