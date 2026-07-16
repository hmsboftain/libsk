import 'dart:async';

import 'package:app_links/app_links.dart';

/// Listens for `libsk://` deep links and rebroadcasts them to whichever
/// screen cares. Currently the only producer is the `payzahRedirect` Cloud
/// Function, which bounces the customer back from the browser via
/// `libsk://payment-result?status=...&trackid=...`.
///
/// Initialized once from main(); consumers subscribe to [paymentResults].
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  final _paymentResults = StreamController<Uri>.broadcast();
  StreamSubscription<Uri>? _sub;

  /// libsk://payment-result links. The payload is a hint only — the payment
  /// UI re-verifies through the payment_attempts doc / status-check callable
  /// rather than trusting the link's `status` parameter.
  Stream<Uri> get paymentResults => _paymentResults.stream;

  /// Feeds a payment-result link from an in-app source: the Payzah WebView
  /// intercepts libsk:// navigations before they ever reach the OS, so it
  /// re-injects them here to reuse the exact same pipeline as OS-delivered
  /// deep links.
  void emitPaymentResult(Uri uri) {
    if (uri.scheme == 'libsk' && uri.host == 'payment-result') {
      _paymentResults.add(uri);
    }
  }

  void init() {
    // uriLinkStream also replays the link that launched the app, so a payment
    // redirect that cold-starts the app is not lost.
    _sub ??= _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'libsk' && uri.host == 'payment-result') {
        _paymentResults.add(uri);
      }
    });
  }
}
