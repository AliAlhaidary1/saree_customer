import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

class AppImage extends StatelessWidget {
  const AppImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  final String? url;
  final BoxFit fit;
  final String? placeholder;

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
      placeholder: (_, __) => ColoredBox(color: Colors.grey.shade100),
      errorWidget: (_, __, ___) {
        if (fallback != null && fallback.isNotEmpty && fallback != src) {
          return CachedNetworkImage(
            imageUrl: fallback,
            fit: fit,
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
          child: AppImage(url, placeholder: placeholder),
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
