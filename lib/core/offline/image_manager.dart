import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../catalog_db/catalog_database.dart';

class ImageManager {
  ImageManager(this._db);

  final CatalogDatabase _db;

  static const int _maxCacheBytes = 200 * 1024 * 1024;

  Future<String?> getLocalPath(String url) async {
    final cached = await CatalogDao(_db).getImage(url);
    if (cached != null && await File(cached.localPath).exists()) {
      await CatalogDao(_db).touchImage(url, DateTime.now());
      return cached.localPath;
    }
    return null;
  }

  Future<String?> downloadAndCache(String url) async {
    try {
      final existing = await getLocalPath(url);
      if (existing != null) return existing;

      final dir = await getApplicationSupportDirectory();
      final imagesDir = Directory('${dir.path}/catalog_images');
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      final fileName = '${url.hashCode}.jpg';
      final filePath = '${imagesDir.path}/$fileName';

      final dio = Dio();
      final response = await dio.download(url, filePath);
      if (response.statusCode == 200) {
        final localFile = File(filePath);
        if (await localFile.exists()) {
          final bytes = await localFile.length();
          await CatalogDao(_db).putImage(
            url: url,
            localPath: filePath,
            bytes: bytes,
            now: DateTime.now(),
          );
          await _enforceBudget();
          return filePath;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> prefetchImages(List<String> urls) async {
    for (final url in urls) {
      if (url.isEmpty) continue;
      final existing = await getLocalPath(url);
      if (existing == null) {
        await downloadAndCache(url);
      }
    }
  }

  Future<void> _enforceBudget() async {
    final totalBytes = await CatalogDao(_db).imagesTotalBytes();
    if (totalBytes > _maxCacheBytes) {
      final bytesToFree = totalBytes - (_maxCacheBytes * 80 ~/ 100);
      final candidates = await CatalogDao(_db).evictCandidates(bytesToFree: bytesToFree);
      for (final image in candidates) {
        try {
          final file = File(image.localPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
        await CatalogDao(_db).removeImage(image.url);
      }
    }
  }

  Future<void> clearCache() async {
    final dir = await getApplicationSupportDirectory();
    final imagesDir = Directory('${dir.path}/catalog_images');
    if (await imagesDir.exists()) {
      await imagesDir.delete(recursive: true);
    }
    await _db.customStatement('DELETE FROM cached_images');
  }

  Future<int> getCacheSize() async {
    return CatalogDao(_db).imagesTotalBytes();
  }
}
