import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/app_theme.dart';
import '../core/json_util.dart';
import '../core/product_media.dart';
import '../core/promo_price.dart';
import 'app_image.dart';
import 'closed_store_badge.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onAdd,
  });

  final Map<String, dynamic> product;
  final VoidCallback onTap;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final variants = J.maps(product['variants']);
    final variant = variants.isNotEmpty ? variants.first : product;
    final price = variantDisplayPrice(variant);
    final image = productImageUrl(product, placeholder: app.placeholder);
    final name = J.str(product['name']);
    final seller = J.str(
      J.map(product['seller'])['store_name'] ??
          product['seller_name'] ??
          product['seller_store_name'] ??
          product['store_name'],
    );
    final closed = isProductStoreClosed(product);
    final avg = double.tryParse('${product['average_rating'] ?? product['rating'] ?? ''}');
    final ratingCount = J.str(product['rating_count'] ?? product['total_ratings']);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: AppTheme.backgroundWhite,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryNavy.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppImage(image, placeholder: app.placeholder),
                    if (closed)
                      const ColoredBox(color: Color(0x66000000)),
                    if (closed)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: ClosedStoreBadge(product: product),
                      ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: ListenableBuilder(
                        listenable: app,
                        builder: (_, __) {
                          final fav = app.isLoggedIn &&
                              app.isFavorite(product['id']);
                          return Material(
                            color: Colors.white.withValues(alpha: 0.9),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () async {
                                if (!app.isLoggedIn) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(app.t(
                                          'required_login_message_for_wishlist')),
                                    ),
                                  );
                                  return;
                                }
                                await app.toggleFavorite(product['id']);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  fav
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  size: 18,
                                  color: fav
                                      ? Colors.red
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (price.hasDiscount)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: price.isFlash
                                ? const Color(0xFFDC2626)
                                : AppTheme.accentOrange,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '-${price.discountPercent}%',
                            style: const TextStyle(
                              color: AppTheme.backgroundWhite,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if (seller.isNotEmpty)
                    Text(
                      seller,
                      maxLines: 1,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  if (avg != null && avg > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star,
                            size: 12, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          avg.toStringAsFixed(1) +
                              (ratingCount.isNotEmpty
                                  ? ' ($ratingCount)'
                                  : ''),
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              money(
                                price.finalPrice,
                                app.currency,
                                app.decimals,
                              ),
                              style: const TextStyle(
                                color: AppTheme.accentOrange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (price.hasDiscount)
                              Text(
                                money(
                                  price.original,
                                  app.currency,
                                  app.decimals,
                                ),
                                style: const TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (onAdd != null)
                        Material(
                          color: closed
                              ? Colors.grey.shade400
                              : AppTheme.accentOrange,
                          borderRadius: BorderRadius.circular(10),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: onAdd,
                            splashColor:
                                AppTheme.backgroundWhite.withValues(alpha: 0.2),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(
                                Icons.add_shopping_cart,
                                size: 18,
                                color: AppTheme.backgroundWhite,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.onSeeAll});
  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: AppTheme.accentOrange,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: Text(
                appController.t('see_all'),
                style: const TextStyle(
                  color: AppTheme.accentOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
