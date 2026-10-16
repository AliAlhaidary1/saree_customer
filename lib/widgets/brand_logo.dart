import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/brand/brand_config.dart';

/// Platform logo from API with bundled asset fallback.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.height = 48,
    this.brand,
    this.assetFallback = 'assets/brand/sareemart-mark.png',
  });

  final double height;
  final BrandConfig? brand;
  final String assetFallback;

  @override
  Widget build(BuildContext context) {
    final config = brand ?? appController.brand;
    final url = config.logoUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        height: height,
        fit: BoxFit.contain,
        errorWidget: (_, _, _) => Image.asset(assetFallback, height: height),
        placeholder: (_, _) => SizedBox(
          height: height,
          width: height,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return Image.asset(assetFallback, height: height);
  }
}
