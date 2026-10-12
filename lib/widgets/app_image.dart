import 'package:cached_network_image/cached_network_image.dart';
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
      // Downscale decode: grid ~400px, thumb ~128px. Disk cache bounded by
      // cached_network_image defaults; fade disabled to avoid shimmer jank.
      memCacheWidth: thumb ? 128 : 400,
      memCacheHeight: thumb ? 128 : null,
      cacheKey: '${thumb ? 't' : 'f'}:$src',
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => ColoredBox(color: Colors.grey.shade100),
      errorWidget: (_, __, ___) {
        if (fallback != null && fallback.isNotEmpty && fallback != src) {
          return CachedNetworkImage(
            imageUrl: fallback,
            fit: fit,
            memCacheWidth: thumb ? 128 : 400,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            errorWidget: (_, __, ___) => _iconFallback(),
          );
        }
        return _iconFallback();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final src = (url == null || url!.isEmpty) ? placeholder : url;
    if (src == null || src.isEmpty) return _iconFallback();
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
      onCssParseError: (_, __) => null,
    );
  }
}
