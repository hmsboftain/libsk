import 'package:cloud_functions/cloud_functions.dart';

/// Client for the Payzah Direct Integration Cloud Functions.
///
/// The private key and every amount live server-side only: the client hands
/// over the `paymentAttemptId` returned by `createOrder` and gets back a
/// hosted payment URL. Never send a price from here — `initializePayzahPayment`
/// reads the server-verified total off the payment_attempts doc.
///
/// Flow:
///   1. checkout calls `FirestoreService.createOrder` (provider "payzah"),
///      which returns the order + payment attempt ids
///   2. [initializePayment] returns the Payzah `direct_url`
///   3. `PayzahWebViewPage` presents it in an in-app WebView
///   4. Payzah redirects to the `payzahRedirect` Cloud Function, which
///      re-verifies via get-payment-details and issues the
///      `libsk://payment-result?...` link the WebView intercepts
///   5. the app confirms by listening to the payment_attempts doc and calling
///      [checkStatus] — never by trusting the redirect alone
class PayzahService {
  final FirebaseFunctions _functions;

  PayzahService({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Asks the server to initialize the Payzah payment for [attemptId] and
  /// returns the hosted payment URL. Re-callable while the attempt is still
  /// pending (e.g. the customer backed out of the browser and tapped retry).
  Future<String> initializePayment({
    required String attemptId,
    String language = 'ENG', // 'ARA' for Arabic-locale customers
  }) async {
    try {
      final callable = _functions.httpsCallable('initializePayzahPayment');
      final result = await callable.call<Map<String, dynamic>>({
        'attemptId': attemptId,
        'language': language,
      });
      // paymentUrl is direct_url for KNET/card and transit_url for Apple Pay
      // — the server picks based on the attempt's payment type.
      final paymentUrl = (result.data['paymentUrl'] ?? result.data['directUrl'])
          as String?;
      if (paymentUrl == null || paymentUrl.isEmpty) {
        throw PayzahException('No payment URL returned.');
      }
      return paymentUrl;
    } on FirebaseFunctionsException catch (e) {
      throw PayzahException(
        e.message ?? 'Payment initialization failed.',
        code: e.code,
      );
    }
  }

  /// Manual/backup verification — used when the WebView closes, the app
  /// resumes, or the deep link arrives, in case the redirect-side
  /// verification was missed. The server re-queries Payzah and resolves the
  /// attempt if the gateway answer is terminal; the payment_attempts listener
  /// picks up the resulting write, so callers usually ignore the return value.
  ///
  /// Returns the attempt status: paid | failed | pending | under_review.
  Future<String> checkStatus(String attemptId) async {
    try {
      final callable = _functions.httpsCallable('checkPayzahPaymentStatus');
      final result = await callable.call<Map<String, dynamic>>({
        'attemptId': attemptId,
      });
      return result.data['status']?.toString() ?? 'pending';
    } on FirebaseFunctionsException catch (e) {
      throw PayzahException(e.message ?? 'Status check failed.', code: e.code);
    }
  }
}

class PayzahException implements Exception {
  final String message;
  final String? code;
  PayzahException(this.message, {this.code});

  @override
  String toString() => 'PayzahException(${code ?? '-'}): $message';
}
