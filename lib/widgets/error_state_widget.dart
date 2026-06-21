import 'package:flutter/material.dart';

import 'theme.dart';

/// Classification used by [ErrorStateWidget] to pick an icon and decide
/// whether a retry button makes sense.
enum ErrorType { notFound, network, permissionDenied, generic }

/// Branded error placeholder used by stream/future builders across the app.
///
/// Two flavours:
///   * [ErrorStateWidget.inline] — replaces a single section that failed
///   * [ErrorStateWidget.page]   — fills the whole screen
class ErrorStateWidget extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final ErrorType type;
  final bool fullPage;

  const ErrorStateWidget({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.type = ErrorType.generic,
    this.fullPage = false,
  });

  /// Full page version — use when the entire page fails to load.
  const ErrorStateWidget.page({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.type = ErrorType.generic,
  }) : fullPage = true;

  /// Inline version — use when one section of a page fails.
  const ErrorStateWidget.inline({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.type = ErrorType.generic,
  }) : fullPage = false;

  IconData get _icon {
    switch (type) {
      case ErrorType.notFound:
        return Icons.search_off_outlined;
      case ErrorType.network:
        return Icons.wifi_off_outlined;
      case ErrorType.permissionDenied:
        return Icons.lock_outline;
      case ErrorType.generic:
        return Icons.error_outline;
    }
  }

  bool get _isRetriable =>
      type == ErrorType.network || type == ErrorType.generic;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_icon, size: 36, color: AppColors.softAccent),
          const SizedBox(height: 16),
          Text(
            title,
            style: AppTextStyles.headingSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
          if (onRetry != null && _isRetriable) ...[
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Try Again'),
            ),
          ],
        ],
      ),
    );

    if (fullPage) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: Center(child: content),
        ),
      );
    }

    return Center(child: content);
  }
}

/// Branded 404 page used when a product or boutique document no longer exists.
class NotFoundPage extends StatelessWidget {
  final String message;

  const NotFoundPage({
    super.key,
    this.message = 'This item is no longer available.',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(
                    Icons.arrow_back,
                    size: 22,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/libsk_logo.png', height: 48),
                      const SizedBox(height: 32),
                      Text('404', style: AppTextStyles.displayLarge),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.secondaryText),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
