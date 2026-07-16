import 'package:flutter/material.dart';
import 'package:libsk/l10n/app_localizations.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../widgets/theme.dart';

/// In-app browser for the Payzah hosted payment page (KNET / card / 3-D
/// Secure). Purely presentation: verification stays with PayzahPaymentPage.
///
/// Pops with the `libsk://payment-result` [Uri] when the payzahRedirect Cloud
/// Function bounces back — inside a WebView that link never reaches the OS or
/// the app_links listener, so the navigation delegate intercepts it — or with
/// null if the customer closes the page before finishing. Either way the
/// caller re-verifies server-side; nothing from the WebView is trusted.
class PayzahWebViewPage extends StatefulWidget {
  final String directUrl;

  const PayzahWebViewPage({super.key, required this.directUrl});

  @override
  State<PayzahWebViewPage> createState() => _PayzahWebViewPageState();
}

class _PayzahWebViewPageState extends State<PayzahWebViewPage> {
  late final WebViewController _controller;
  int _progress = 100;

  /// The redirect chain can fire the libsk:// navigation more than once
  /// (some gateways re-issue the redirect on history events) — pop only once.
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      // The KNET and 3-D Secure pages are script-driven.
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && uri.scheme == 'libsk') {
              // Payment finished server-side — hand the deep link back to
              // PayzahPaymentPage. Intercepting also avoids Android's
              // ERR_UNKNOWN_URL_SCHEME page for the custom scheme.
              if (!_finished && mounted) {
                _finished = true;
                Navigator.of(context).pop(uri);
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    // Cookie/session persistence, configured explicitly rather than assumed:
    // first-party cookies are accepted by default on both platforms, and the
    // Android plugin enables DOM storage unconditionally — but Android rejects
    // THIRD-party cookies by default, and some banks' 3-D Secure / OTP steps
    // run in iframes that need their session cookie to survive the redirect
    // chain. iOS (WKWebView) needs no extra setup for this flow.
    final platformController = _controller.platform;
    if (platformController is AndroidWebViewController) {
      AndroidWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      ).setAcceptThirdPartyCookies(platformController, true);
    }

    _controller.loadRequest(Uri.parse(widget.directUrl));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      // System back first steps through the gateway's own pages (KNET → 3DS
      // → OTP); backing out of the first page closes the sheet, which the
      // caller treats as the abandon path (attempt stays pending/retryable).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else if (!_finished) {
          navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(l10n.payment, style: AppTextStyles.labelLarge),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 20,
                        color: AppColors.primaryText,
                      ),
                      onPressed: () {
                        if (!_finished) Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.border, thickness: 0.5, height: 0.5),
              if (_progress < 100)
                LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 1.5,
                  color: AppColors.deepAccent,
                  backgroundColor: AppColors.background,
                ),
              Expanded(child: WebViewWidget(controller: _controller)),
            ],
          ),
        ),
      ),
    );
  }
}
