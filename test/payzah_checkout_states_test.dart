import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsk/l10n/app_localizations.dart';
import 'package:libsk/widgets/payzah_checkout_states.dart';

Widget _host(PayzahCheckoutState state,
    {VoidCallback? onRetry,
    VoidCallback? onContinue,
    VoidCallback? onReturnToCart,
    Locale? locale}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: PayzahCheckoutStateView(
        state: state,
        onRetry: onRetry,
        onContinue: onContinue,
        onReturnToCart: onReturnToCart,
      ),
    ),
  );
}

void main() {
  testWidgets('loading state shows spinner and preparing copy', (tester) async {
    await tester.pumpWidget(_host(PayzahCheckoutState.loading));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Preparing your payment'), findsOneWidget);
  });

  testWidgets('redirecting state shows handoff copy', (tester) async {
    await tester.pumpWidget(_host(PayzahCheckoutState.redirecting));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Taking you to secure payment'), findsOneWidget);
    expect(
      find.text("You'll be redirected to complete your payment."),
      findsOneWidget,
    );
  });

  testWidgets('verifying state warns to keep the app open', (tester) async {
    await tester.pumpWidget(_host(PayzahCheckoutState.verifying));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Confirming your payment'), findsOneWidget);
    expect(
      find.text('This may take a few moments. Please keep the app open.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('success state shows confirmation and continue action',
      (tester) async {
    var continued = false;
    await tester.pumpWidget(_host(
      PayzahCheckoutState.success,
      onContinue: () => continued = true,
    ));
    expect(find.text('Payment confirmed'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('Continue'));
    expect(continued, isTrue);
  });

  testWidgets('failure state is distinct and retryable', (tester) async {
    var retried = false;
    await tester.pumpWidget(_host(
      PayzahCheckoutState.failure,
      onRetry: () => retried = true,
    ));
    expect(find.text('Payment unsuccessful'), findsOneWidget);
    expect(
      find.text('Your payment could not be completed and you have not been '
          'charged. Please try again.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.text('Try Again'));
    expect(retried, isTrue);
  });

  testWidgets('abandoned state offers retry and return to cart',
      (tester) async {
    var retried = false;
    var returned = false;
    await tester.pumpWidget(_host(
      PayzahCheckoutState.abandoned,
      onRetry: () => retried = true,
      onReturnToCart: () => returned = true,
    ));
    expect(find.text('Payment not completed'), findsOneWidget);
    expect(
      find.text("You haven't been charged. You can try again to finish "
          'paying, or return to your cart.'),
      findsOneWidget,
    );
    // Neutral icon — not the failure X.
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    await tester.tap(find.text('Try Again'));
    expect(retried, isTrue);
    await tester.tap(find.text('Return to cart'));
    expect(returned, isTrue);
  });

  testWidgets('under-review state warns against paying again', (tester) async {
    var continued = false;
    await tester.pumpWidget(_host(
      PayzahCheckoutState.underReview,
      onContinue: () => continued = true,
    ));
    expect(find.text('Payment under review'), findsOneWidget);
    expect(
      find.text("We couldn't confirm the outcome of your payment yet. "
          "Please don't pay again — our team is verifying it and your order "
          'will be updated shortly.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
    await tester.tap(find.text('Continue'));
    expect(continued, isTrue);
  });

  testWidgets('states render in Arabic', (tester) async {
    await tester.pumpWidget(
      _host(PayzahCheckoutState.verifying, locale: const Locale('ar')),
    );
    expect(find.text('جارٍ تأكيد عملية الدفع'), findsOneWidget);
  });
}
