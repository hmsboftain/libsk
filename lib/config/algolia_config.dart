import 'algolia_secrets.local.dart';

/// Algolia credentials for client-side search.
///
/// Priority:
/// 1. `--dart-define=ALGOLIA_APP_ID=...` / `ALGOLIA_SEARCH_KEY=...` (CI/production)
/// 2. `lib/config/algolia_secrets.local.dart` (local dev, gitignored)
class AlgoliaConfig {
  static const String _appIdFromEnv = String.fromEnvironment('ALGOLIA_APP_ID');
  static const String _searchKeyFromEnv =
      String.fromEnvironment('ALGOLIA_SEARCH_KEY');

  static String get appId =>
      _appIdFromEnv.isNotEmpty ? _appIdFromEnv : algoliaAppId;

  static String get searchKey =>
      _searchKeyFromEnv.isNotEmpty ? _searchKeyFromEnv : algoliaSearchKey;

  static bool get isConfigured => appId.isNotEmpty && searchKey.isNotEmpty;
}
