import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

class AppImage extends StatelessWidget {
  const AppImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.thumb = false,
  });

  final String? url;
  final BoxFit fit;
  final String? placeholder;

  /// Set true for small avatars/logos: decodes a tiny bitmap instead of the
  /// full-resolution image (major jank + data saver on strips/grids).
  final bool thumb;

  Widget _iconFallback() {
    return ColoredBox(
      color: Colors.grey.shade200,
      child: const Icon(Icons.image_outlined, color: Colors.grey),
    );
  }

  Widget _network(String src, {String? fallback}) {
    return CachedNetworkImage(
      imageUrl: src,
      fit: fit,
      // Downscale decode: grid ~400px, thumb ~128px. The disk cache stores
      // the SAME downscaled bitmap, so a cached image is never re-decoded at
      // full resolution (the old setup cached full-size originals). Fade
      // disabled to avoid shimmer jank.
      memCacheWidth: thumb ? 128 : 400,
      memCacheHeight: thumb ? 128 : null,
      maxWidthDiskCache: thumb ? 128 : 400,
      maxHeightDiskCache: thumb ? 128 : null,
      cacheKey: '${thumb ? 't' : 'f'}:$src',
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      imageBuilder: (_, provider) {
        _clearFailure(src);
        return Image(image: provider, fit: fit);
      },
      placeholder: (_, _) => ColoredBox(color: Colors.grey.shade100),
      errorWidget: (_, url, error) {
        _recordFailure(url);
        if (kDebugMode) {
          debugPrint('AppImage fail: $url -> $error');
        }
        if (fallback != null && fallback.isNotEmpty && fallback != src) {
          return CachedNetworkImage(
            imageUrl: fallback,
            fit: fit,
            memCacheWidth: thumb ? 128 : 400,
            maxWidthDiskCache: thumb ? 128 : 400,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            imageBuilder: (_, provider) {
              _clearFailure(fallback);
              return Image(image: provider, fit: fit);
            },
            errorWidget: (_, _, _) => _iconFallback(),
          );
        }
        return _iconFallback();
      },
    );
  }

  /// Short-lived negative cache: a URL that just failed (dead host, 404,
  /// transient network) is not retried on every rebuild/scroll pass; the
  /// placeholder stands in until the TTL expires.
  static final Map<String, DateTime> _failedAt = <String, DateTime>{};
  static const Duration _failureTtl = Duration(minutes: 5);
  static const int _failureCacheMax = 256;

  static bool _recentlyFailed(String url) {
    final at = _failedAt[url];
    if (at == null) return false;
    if (DateTime.now().difference(at) > _failureTtl) {
      _failedAt.remove(url);
      return false;
    }
    return true;
  }

  static void _recordFailure(String url) {
    if (url.isEmpty) return;
    if (_failedAt.length >= _failureCacheMax) {
      final stale = _failedAt.keys.take(_failureCacheMax ~/ 4).toList();
      for (final k in stale) {
        _failedAt.remove(k);
      }
    }
    _failedAt[url] = DateTime.now();
  }

  static void _clearFailure(String url) => _failedAt.remove(url);

  static bool _undecodable(String src) {
    try {
      final path = Uri.parse(src).path.toLowerCase();
      return path.endsWith('.heic') ||
          path.endsWith('.heif') ||
          path.endsWith('.avif') ||
          path.endsWith('.tif') ||
          path.endsWith('.tiff') ||
          // No built-in SVG decoder (flutter_svg not a dependency):
          // Android ImageDecoder rejects these with 'unimplemented'.
          path.endsWith('.svg') ||
          path.endsWith('.svgz');
    } catch (_) {
      return false;
    }
  }

  /// Public guard for call sites that still use [CircleAvatar.backgroundImage]
  /// or [Image.network] directly: returns false for empty URLs, non-http(s)
  /// URLs, and formats Android cannot decode (see [_undecodable]).
  /// Use it to fall back to initials/asset instead of firing a doomed
  /// decoder attempt (log spam + jank on old devices).
  static bool isDisplayable(String? src) {
    if (src == null || src.trim().isEmpty) return false;
    final s = src.trim();
    final lower = s.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return false;
    }
    return !_undecodable(s);
  }

  @override
  Widget build(BuildContext context) {
    final src = (url == null || url!.isEmpty) ? placeholder : url;
    if (src == null || src.isEmpty) return _iconFallback();
    // Non-http(s) sources and formats Android cannot decode (HEIC/AVIF/SVG
    // phone uploads) are never handed to the decoder: skip the doomed
    // attempt (and its log spam) and fall through to the placeholder chain.
    if (!isDisplayable(src) || _recentlyFailed(src)) {
      if (isDisplayable(placeholder) &&
          placeholder != src &&
          !_recentlyFailed(placeholder!)) {
        return _network(placeholder!);
      }
      return _iconFallback();
    }
    return _network(src, fallback: placeholder);
  }
}

class SellerAvatar extends StatelessWidget {
  const SellerAvatar(this.url, {super.key, this.radius = 24, this.placeholder});

  final String? url;
  final double radius;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.white,
      child: ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: AppImage(url, placeholder: placeholder, thumb: true),
        ),
      ),
    );
  }
}

class HtmlText extends StatelessWidget {
  const HtmlText(this.html, {super.key, this.color});

  final String html;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final value = html.trim();
    if (value.isEmpty) return const SizedBox.shrink();
    if (!value.contains('<')) {
      return Text(
        value,
        style: TextStyle(color: color ?? Colors.grey.shade700),
      );
    }
    return Html(
      data: value,
      onCssParseError: (_, _) => null,
    );
  }
}
