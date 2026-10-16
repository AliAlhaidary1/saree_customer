import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'catalog_db/catalog_config.dart';
import 'catalog_db/catalog_database.dart';

/// Bounded offline thumbnail prefetch with zero new dependencies.
///
/// Design constraints (deliberate):
/// * opt-in only (see `AppController.offlineImagesEnabled`, default OFF —
///   mobile-data safety; UI copy recommends Wi-Fi);
/// * bounded: at most [maxFilesPerRun] files per run, [maxBytesPerFile] each,
///   total manifest budget [CatalogDbConfig.imageBudgetBytes]; oldest-first
///   LRU eviction via `evictCandidates`;
/// * file-safe ordering: write temp → rename → insert manifest row; eviction
///   removes the manifest row first, then the file (failures ignored);
/// * best-effort: failures are skipped without retry; catalog data never
///   waits for images; a timed-out download never fails the run.
///
/// What this does NOT do (documented limitation): no client-side downscaling
/// (no image codec dependency) — bounded originals are cached. A ≤512px
/// JPEG pipeline remains future work.
class ImagePrefetch {
  ImagePrefetch();

  static const int maxFilesPerRun = 100;
  static const int maxBytesPerFile = 2 * 1024 * 1024;

  bool _running = false;
  bool _cancelRequested = false;

  bool get running => _running;

  void cancel() {
    _cancelRequested = true;
  }

  Future<Directory?> thumbsDir() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/catalog_thumbs');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  static String fileNameFor(String url) {
    // Two independent 32-bit hashes + length: djb2 collisions no longer
    // alias two distinct thumbnails onto one file (the old single-hash
    // name let the second URL reuse the first file via target.exists()).
    var h1 = 5381;
    var h2 = 0;
    for (var i = 0; i < url.length; i++) {
      final c = url.codeUnitAt(i);
      h1 = ((h1 << 5) + h1 + c) & 0xFFFFFFFF;
      h2 = (c + (h2 << 6) + (h2 << 16) - h2) & 0xFFFFFFFF;
    }
    // Extension from the URL path only (query strings like ?format=png
    // must not force a wrong decoder downstream).
    var ext = '.jpg';
    try {
      final path = Uri.parse(url).path.toLowerCase();
      if (path.endsWith('.png')) {
        ext = '.png';
      } else if (path.endsWith('.webp')) {
        ext = '.webp';
      }
    } catch (_) {}
    return '${h1.toRadixString(16)}_${h2.toRadixString(16)}_${url.length}$ext';
  }

  /// Downloads [urls] (deduplicated) into the thumbs directory, recording
  /// each file in the Drift manifest when [db] is provided. Returns the
  /// number of newly stored files.
  Future<int> prefetch(
    List<String> urls, {
    CatalogDatabase? db,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_running) return 0;
    _running = true;
    _cancelRequested = false;
    var stored = 0;
    final client = HttpClient();
    client.connectionTimeout = timeout;
    try {
      final dir = await thumbsDir();
      if (dir == null) return 0;
      final dao = db == null ? null : CatalogDao(db);
      var manifestBytes = 0;
      try {
        manifestBytes = await dao?.imagesTotalBytes() ?? 0;
      } catch (_) {}
      Future<void> evict(int bytesToFree) async {
        if (dao == null) return;
        try {
          final victims = await dao.evictCandidates(bytesToFree: bytesToFree);
          for (final v in victims) {
            try {
              await dao.removeImage(v.url);
            } catch (_) {}
            try {
              final f = File(v.localPath);
              if (await f.exists()) await f.delete();
            } catch (_) {}
          }
        } catch (_) {}
      }

      Future<int> refreshManifestBytes() async {
        try {
          return await dao?.imagesTotalBytes() ?? manifestBytes;
        } catch (_) {
          return manifestBytes;
        }
      }

      final seen = <String>{};
      for (final raw in urls) {
        if (_cancelRequested || stored >= maxFilesPerRun) break;
        final url = raw.trim();
        if (url.isEmpty || !seen.add(url)) continue;
        try {
          final name = fileNameFor(url);
          final target = File('${dir.path}/$name');
          if (await target.exists()) {
            try {
              // Self-repair: a file without a manifest row was never
              // budgeted or evictable (previously only `reconcile` could
              // see it — by deleting it). Record it with its ACTUAL disk
              // size so budget math stays honest. Size drift on tracked
              // rows is corrected the same way; otherwise just touch LRU.
              final actual = await target.length();
              final existing = await dao?.getImage(url);
              if (existing == null) {
                await dao?.putImage(
                  url: url,
                  localPath: target.path,
                  bytes: actual,
                  now: DateTime.now(),
                );
              } else if (existing.bytes != actual) {
                await dao?.putImage(
                  url: url,
                  localPath: target.path,
                  bytes: actual,
                  now: DateTime.now(),
                );
              } else {
                await dao?.touchImage(url, DateTime.now());
              }
              manifestBytes = await refreshManifestBytes();
            } catch (_) {}
            continue;
          }
          // Proactive oldest-first eviction when already at budget, so the
          // run keeps making room instead of stalling on every file.
          if (manifestBytes >= CatalogDbConfig.imageBudgetBytes) {
            await evict(CatalogDbConfig.imageBudgetBytes ~/ 8);
            manifestBytes = await refreshManifestBytes();
            if (manifestBytes >= CatalogDbConfig.imageBudgetBytes) break;
          }
          final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
          final res = await req.close().timeout(timeout);
          if (res.statusCode != 200) continue;
          // MIME guard: a 200 with a non-image body (e.g. an HTML error page
          // or JSON) must never be cached as a thumbnail. Absent
          // content-type is allowed (some CDNs omit it); an explicit
          // non-image type skips the URL without poisoning future attempts.
          final mime = res.headers.contentType?.mimeType ?? '';
          if (mime.isNotEmpty && !mime.startsWith('image/')) continue;
          final contentLen = res.contentLength;
          if (contentLen > maxBytesPerFile) continue;
          final tmp = File('${target.path}.part');
          final sink = tmp.openWrite();
          var bytes = 0;
          var tooBig = false;
          var stalled = false;
          try {
            // Per-chunk idle timeout: a stalled connection must skip the
            // file (not hold the single-flight gate forever).
            await for (final chunk in res.timeout(
              const Duration(seconds: 10),
            )) {
              bytes += chunk.length;
              if (bytes > maxBytesPerFile) {
                tooBig = true;
                break;
              }
              sink.add(chunk);
            }
          } catch (_) {
            stalled = true;
          }
          try {
            await sink.close();
          } catch (_) {}
          if (stalled) {
            try {
              await tmp.delete();
            } catch (_) {}
            continue;
          }
          if (tooBig || bytes == 0) {
            try {
              await tmp.delete();
            } catch (_) {}
            continue;
          }
          if (manifestBytes + bytes > CatalogDbConfig.imageBudgetBytes) {
            await evict(bytes);
            manifestBytes = await refreshManifestBytes();
            if (manifestBytes + bytes > CatalogDbConfig.imageBudgetBytes) {
              try {
                await tmp.delete();
              } catch (_) {}
              continue;
            }
          }
          await tmp.rename(target.path);
          try {
            await dao?.putImage(
              url: url,
              localPath: target.path,
              bytes: bytes,
              now: DateTime.now(),
            );
            manifestBytes += bytes;
          } catch (_) {}
          stored++;
        } catch (_) {
          // Best-effort: skip failures without retrying.
        }
      }
    } finally {
      client.close(force: true);
      _running = false;
    }
    return stored;
  }

  /// Bidirectional orphan sweep inside the app-private thumbs directory:
  /// manifest rows without files are removed; files without manifest rows
  /// are deleted. Never touches files outside the thumbs directory.
  static Future<void> reconcile(CatalogDatabase db) async {
    try {
      final dao = CatalogDao(db);
      final all = await dao.evictCandidates(bytesToFree: 1 << 60);
      final knownPaths = <String>{};
      for (final row in all) {
        knownPaths.add(row.localPath);
        try {
          if (!await File(row.localPath).exists()) {
            await dao.removeImage(row.url);
          }
        } catch (_) {}
      }
      Directory? dir;
      try {
        final base = await getApplicationSupportDirectory();
        dir = Directory('${base.path}/catalog_thumbs');
      } catch (_) {}
      if (dir != null && await dir.exists()) {
        await for (final e in dir.list()) {
          try {
            if (e is File &&
                !e.path.endsWith('.part') &&
                !knownPaths.contains(e.path)) {
              await e.delete();
            } else if (e is File && e.path.endsWith('.part')) {
              await e.delete();
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
