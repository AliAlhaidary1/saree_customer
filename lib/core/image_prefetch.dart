import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'catalog_db/catalog_config.dart';
import 'catalog_db/catalog_database.dart';

/// True when [url] is worth downloading: absolute http(s) URL whose path does
/// not point at a format neither Android nor the downscaler can decode
/// (HEIC/HEIF/AVIF/TIFF typically come from phone uploads; the platform
/// decoder rejects them with 'unimplemented' and they can never display).
bool _fetchableImageUrl(String url) {
  final lower = url.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return false;
  }
  try {
    final path = Uri.parse(url).path.toLowerCase();
    for (final ext in const ['.heic', '.heif', '.avif', '.tif', '.tiff']) {
      if (path.endsWith(ext)) return false;
    }
  } catch (_) {
    return false;
  }
  return true;
}

/// Decodes + downscales one image off the main isolate (decoding on the UI
/// thread janks scrolling noticeably). Returns empty bytes on any failure.
Uint8List _decodeThumb(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return Uint8List(0);
    final w = decoded.width;
    final h = decoded.height;
    final longest = w > h ? w : h;
    final small = longest > ImagePrefetch.maxDimension
        ? img.copyResize(
            decoded,
            width: w >= h ? ImagePrefetch.maxDimension : null,
            height: h > w ? ImagePrefetch.maxDimension : null,
          )
        : decoded;
    return img.encodeJpg(small, quality: ImagePrefetch.jpegQuality);
  } catch (_) {
    return Uint8List(0);
  }
}

/// Bounded automatic offline thumbnail prefetch.
///
/// Design constraints (deliberate):
/// * automatic: runs after every completed catalog sync (no settings toggle);
///   tiny downscaled files keep mobile-data cost negligible;
/// * every stored file is a ≤512px JPEG (quality 70): typical photos shrink
///   ~20x versus originals, so the same disk budget holds ~20x more thumbnails;
/// * bounded: at most [maxFilesPerRun] files per run, [maxBytesPerFile] input
///   each, total manifest budget [CatalogDbConfig.imageBudgetBytes];
///   oldest-first LRU eviction via `evictCandidates`;
/// * file-safe ordering: write temp → rename → insert manifest row; eviction
///   removes the manifest row first, then the file (failures ignored);
/// * best-effort: failures are skipped without retry; catalog data never
///   waits for images; a timed-out download never fails the run.
class ImagePrefetch {
  ImagePrefetch();

  static const int maxFilesPerRun = 12;
  static const int maxBytesPerFile = 2 * 1024 * 1024;
  static const int maxDimension = 512;
  static const int jpegQuality = 70;

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
    // Stored files are always re-encoded JPEG thumbnails, regardless of
    // the source format.
    return '${h1.toRadixString(16)}_${h2.toRadixString(16)}_${url.length}.jpg';
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
        if (!_fetchableImageUrl(url)) continue;
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
          final raw = BytesBuilder();
          var tooBig = false;
          var stalled = false;
          try {
            // Per-chunk idle timeout: a stalled connection must skip the
            // file (not hold the single-flight gate forever).
            await for (final chunk in res.timeout(
              const Duration(seconds: 10),
            )) {
              if (raw.length + chunk.length > maxBytesPerFile) {
                tooBig = true;
                break;
              }
              raw.add(chunk);
            }
          } catch (_) {
            stalled = true;
          }
          if (stalled || tooBig || raw.isEmpty) continue;
          // Downscale to a small JPEG thumbnail in a background isolate:
          // empty output means undecodable body — skip it instead of
          // caching garbage.
          Uint8List thumb;
          try {
            thumb = await compute(_decodeThumb, raw.toBytes());
          } catch (_) {
            continue;
          }
          if (thumb.isEmpty) continue;
          if (manifestBytes + thumb.length >
              CatalogDbConfig.imageBudgetBytes) {
            await evict(thumb.length);
            manifestBytes = await refreshManifestBytes();
            if (manifestBytes + thumb.length >
                CatalogDbConfig.imageBudgetBytes) {
              continue;
            }
          }
          final tmp = File('${target.path}.part');
          try {
            await tmp.writeAsBytes(thumb, flush: true);
          } catch (_) {
            continue;
          }
          await tmp.rename(target.path);
          try {
            await dao?.putImage(
              url: url,
              localPath: target.path,
              bytes: thumb.length,
              now: DateTime.now(),
            );
            manifestBytes += thumb.length;
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
