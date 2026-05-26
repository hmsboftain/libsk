import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

/// Central wrapper for Firebase Storage uploads. Pages should never touch
/// [FirebaseStorage.instance] directly; routing every upload through this
/// service keeps folder naming, timestamp-based naming, and error handling
/// consistent across the app.
class StorageService {
  StorageService._();

  static final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Uploads [file] into [folder] using a millisecond-timestamp filename.
  /// Returns the public download URL.
  static Future<String> uploadImage(File file, String folder) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref().child(folder).child(fileName);
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  /// Uploads each file in [files] concurrently and returns the resulting
  /// download URLs in the same order.
  static Future<List<String>> uploadImages(
    List<File> files,
    String folder,
  ) async {
    return Future.wait(files.map((f) => uploadImage(f, folder)));
  }

  /// Best-effort deletion of an image by its download URL. Swallows failures
  /// because the caller usually does not need to react to a stale/missing
  /// reference.
  static Future<void> deleteImageByUrl(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {}
  }
}
