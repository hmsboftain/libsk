import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Central wrapper for Firebase Storage uploads. Pages should never touch
/// [FirebaseStorage.instance] directly; routing every upload through this
/// service keeps folder naming, timestamp-based naming, compression, and
/// error handling consistent across the app.
class StorageService {
  StorageService._();

  static final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Longest-edge target and JPEG quality for uploaded images. Product cards
  /// and feed images render well under ~1080px, so shipping anything larger
  /// just wastes upload time and Storage egress.
  static const int _maxDimension = 1080;
  static const int _quality = 80;

  /// Compresses and resizes [file] to a web-sized JPEG. Returns a new temp
  /// file on success, or the original [file] if compression fails for any
  /// reason — so an upload can never be blocked by the compression step.
  static Future<File> _compress(File file) async {
    try {
      final dir = await getTemporaryDirectory();
      final target = p.join(
        dir.path,
        '${DateTime.now().microsecondsSinceEpoch}.jpg',
      );

      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        target,
        quality: _quality,
        minWidth: _maxDimension,
        minHeight: _maxDimension,
        format: CompressFormat.jpeg,
      );

      if (result == null) return file;
      return File(result.path);
    } catch (e) {
      debugPrint('IMAGE COMPRESS ERROR: $e');
      return file;
    }
  }

  /// Uploads [file] into [folder] using a millisecond-timestamp filename.
  /// The image is compressed to a web-sized JPEG first. Returns the public
  /// download URL.
  static Future<String> uploadImage(File file, String folder) async {
    final compressed = await _compress(file);
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref().child(folder).child(fileName);
    await ref.putFile(compressed, SettableMetadata(contentType: 'image/jpeg'));
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
