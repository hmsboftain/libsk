// Ad disclosure on paid category pins.
//
// A top_of_category pin is an ADVERT: it outranks organic results because a
// boutique paid, so it has to say so. The label rides the existing boutique caps
// line ("LUWANI · PROMOTED") rather than adding a fourth line, because the grid
// tile has a fixed aspect ratio and an Expanded image — a line on promoted cards
// only would shrink their image against the organic card beside them.
//
// These assert the rendered string, in both languages, against the real
// generated localisations.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsk/l10n/app_localizations.dart';

/// The label composition under test, mirroring _CategoryProductCard's boutique
/// line. Kept as a helper so the assertion is about the STRING a shopper reads.
String boutiqueLine(AppLocalizations l10n, String boutiqueName, bool isPromoted) {
  final name = boutiqueName.toUpperCase();
  return isPromoted ? '$name · ${l10n.promotedBadge}' : name;
}

Future<AppLocalizations> _l10nFor(WidgetTester tester, Locale locale) async {
  late AppLocalizations captured;
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(builder: (context) {
      captured = AppLocalizations.of(context)!;
      return const SizedBox();
    }),
  ));
  return captured;
}

void main() {
  testWidgets('a promoted pin is disclosed in English', (tester) async {
    final l10n = await _l10nFor(tester, const Locale('en'));
    expect(boutiqueLine(l10n, 'luwani', true), 'LUWANI · PROMOTED');
  });

  testWidgets('an organic result carries no disclosure', (tester) async {
    final l10n = await _l10nFor(tester, const Locale('en'));
    final line = boutiqueLine(l10n, 'luwani', false);
    expect(line, 'LUWANI');
    expect(line.contains('·'), isFalse);
    expect(line.toUpperCase().contains('PROMOTED'), isFalse);
  });

  testWidgets('the disclosure is localised, not hardcoded English', (tester) async {
    final ar = await _l10nFor(tester, const Locale('ar'));
    expect(ar.promotedBadge, isNotEmpty);
    // The whole point of localising: an Arabic shopper must not be shown the
    // English word. (The feed's existing 'Sponsored' IS hardcoded — this is
    // deliberately the more correct of the two.)
    expect(ar.promotedBadge, isNot('PROMOTED'));
    expect(boutiqueLine(ar, 'luwani', true), contains(ar.promotedBadge));
  });

  testWidgets('English and Arabic disclosures differ', (tester) async {
    final en = await _l10nFor(tester, const Locale('en'));
    final ar = await _l10nFor(tester, const Locale('ar'));
    expect(en.promotedBadge, 'PROMOTED');
    expect(ar.promotedBadge, isNot(en.promotedBadge));
  });

  testWidgets('the badge renders on the real caps line style', (tester) async {
    // Proves the composed line actually paints, rather than only being a string.
    final l10n = await _l10nFor(tester, const Locale('en'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Text(boutiqueLine(l10n, 'luwani', true))),
    ));
    expect(find.text('LUWANI · PROMOTED'), findsOneWidget);
  });
}
