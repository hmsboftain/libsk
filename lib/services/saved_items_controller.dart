import 'package:flutter/foundation.dart';

import '../models/product.dart';
import 'firestore_service.dart';

/// Shared, feed-level saved-items state (audit finding 4.2).
///
/// Replaces the per-card `isItemSaved()` get: the feed loads the saved product
/// id set ONCE via [load], and every heart reads/writes through this controller
/// instead of issuing its own `doc().get()` per card. save/unsave is optimistic
/// — local state flips immediately, the write happens in the background, and a
/// failure rolls the local state back (and rethrows so the UI can surface it).
class SavedItemsController extends ChangeNotifier {
  final Set<String> _saved = {};
  bool _loaded = false;

  bool get loaded => _loaded;
  bool isSaved(String productId) => _saved.contains(productId);

  /// One-time load of the user's saved product ids (single get, not a
  /// listener). Safe to call again (e.g. pull-to-refresh).
  Future<void> load() async {
    try {
      final ids = await FirestoreService.fetchSavedItemIds();
      _saved
        ..clear()
        ..addAll(ids);
    } catch (_) {
      // Guests / transient errors → treat as nothing saved.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Optimistically toggles saved state for [product], writing in the
  /// background. Rolls back and rethrows on failure so the caller can show an
  /// error.
  Future<void> toggle(Product product) async {
    final wasSaved = _saved.contains(product.id);
    if (wasSaved) {
      _saved.remove(product.id);
    } else {
      _saved.add(product.id);
    }
    notifyListeners();

    try {
      if (wasSaved) {
        await FirestoreService.removeSavedItem(product.id);
      } else {
        await FirestoreService.saveItem(
          productId: product.id,
          boutiqueId: product.boutiqueId,
          imageUrl: product.displayImageUrl,
          imageUrls: product.imageUrls,
          title: product.title,
          boutiqueName: product.boutiqueName,
          price: product.price,
          description: product.description,
          sizes: product.sizes,
          stock: product.stock,
        );
      }
    } catch (e) {
      // Roll back the optimistic change on failure.
      if (wasSaved) {
        _saved.add(product.id);
      } else {
        _saved.remove(product.id);
      }
      notifyListeners();
      rethrow;
    }
  }
}
