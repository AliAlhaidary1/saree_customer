import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/app_theme.dart';
import '../core/json_util.dart';
import '../core/product_media.dart';
import '../core/promo_price.dart';
import 'app_image.dart';
import 'closed_store_badge.dart';
import 'requires_internet_dialog.dart';

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
    final hasOptions = variants.length > 1;
    final firstLabel = [
      J.str(variant['measurement']),
      J.str(variant['stock_unit_name']),
    ].where((e) => e.isNotEmpty).join(' ');
    final stock = J.i(variant['stock']);
    final unlimited = J.flag(product['is_unlimited_stock'] ?? variant['is_unlimited_stock']);
    final outOfStock = !unlimited && variants.isNotEmpty && stock <= 0;

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
                        builder: (_, _) {
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
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
                  const SizedBox(height: 6),
                  // Simple product: Add button turns into a [- qty +]
                  // stepper synced with the cart (same pattern as the
                  // product page). Multi-variant products keep opening
                  // the variant dialog.
                  if (onAdd != null)
                    SizedBox(
                      width: double.infinity,
                      height: 38,
                      child: (!hasOptions && !closed && !outOfStock)
                          ? _CardAddControl(
                              product: product,
                              variant: variant,
                              price: price.finalPrice,
                            )
                          : FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: (closed || outOfStock)
                                    ? Colors.grey.shade400
                                    : AppTheme.accentOrange,
                                foregroundColor:
                                    AppTheme.backgroundWhite,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onPressed:
                                  (closed || outOfStock) ? null : onAdd,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.shopping_cart_outlined,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      (closed || outOfStock)
                                          ? app.t('out_of_stock')
                                          : app.t('add_to_cart'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (hasOptions &&
                                      firstLabel.isNotEmpty) ...[
                                    const SizedBox(width: 2),
                                    Flexible(
                                      child: Text(
                                        '· $firstLabel',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_drop_down,
                                      size: 16,
                                    ),
                                  ] else if (hasOptions)
                                    const Icon(
                                      Icons.arrow_drop_down,
                                      size: 16,
                                    ),
                                ],
                              ),
                            ),
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

/// Compact add/stepper control for simple products on cards.
/// Plain Add first; after the first tap it becomes [- qty +] synced with
/// the cart. Optimistic: updates instantly, request runs in background.
class _CardAddControl extends StatefulWidget {
  const _CardAddControl({
    required this.product,
    required this.variant,
    required this.price,
  });

  final Map<String, dynamic> product;
  final Map<String, dynamic> variant;
  final double price;

  @override
  State<_CardAddControl> createState() => _CardAddControlState();
}

class _CardAddControlState extends State<_CardAddControl> {
  int? _optimistic;
  int _seq = 0;

  dynamic get _variantId =>
      widget.variant['id'] ??
      widget.product['product_variant_id'] ??
      widget.product['id'];

  Future<void> _setQty(int next) async {
    final app = appController;
    final mySeq = ++_seq;
    setState(() => _optimistic = next);
    try {
      if (next <= 0) {
        final err = await app.removeCartLine(
          productId: widget.product['id'],
          variantId: _variantId,
        );
        if (mySeq != _seq || !mounted) return;
        setState(() => _optimistic = null);
        if (err != null && mounted) {
          await showCartError(context, err);
        }
        return;
      }
      final err = await app.addToCart(
        productId: widget.product['id'],
        variantId: _variantId,
        qty: next,
        productPrice: widget.price,
        sellerId: J.sellerId(widget.product),
        storeName: app.storeNameOf(widget.product),
            variantLabel: AppController.variantLabelOf(widget.variant, J.str(widget.product['name'])),
      );
      if (mySeq != _seq || !mounted) return;
      setState(() => _optimistic = null);
      if (err == 'same_seller' && mounted) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: Text(app.t('same_seller_cart_prompt')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(app.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(app.t('confirm')),
              ),
            ],
          ),
        );
        if (ok == true && mounted) {
          final retry = await app.addToCart(
            productId: widget.product['id'],
            variantId: _variantId,
            qty: next,
            productPrice: widget.price,
            sellerId: J.sellerId(widget.product),
            storeName: app.storeNameOf(widget.product),
            variantLabel: AppController.variantLabelOf(widget.variant, J.str(widget.product['name'])),
            replaceSeller: true,
          );
          if (mounted && retry != null) {
            await showCartError(context, retry);
          }
        }
      } else if (err != null && mounted) {
        await showCartError(context, err);
      }
    } catch (_) {
      if (mySeq != _seq || !mounted) return;
      setState(() => _optimistic = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appController.t('network_error'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return ListenableBuilder(
      listenable: app,
      builder: (_, _) {
        final qty = _optimistic ?? app.cartQtyFor(_variantId);
        if (qty <= 0) {
          return FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentOrange,
              foregroundColor: AppTheme.backgroundWhite,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: () => _setQty(1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shopping_cart_outlined, size: 16),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    app.t('add_to_cart'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.primaryNavy.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              _outlineBtn(
                Icons.remove_rounded,
                () => _setQty(qty - 1),
              ),
              Expanded(
                child: Text(
                  '$qty',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _outlineBtn(
                Icons.add_rounded,
                () => _setQty(qty + 1),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Outlined step button: white with an orange frame, no fill.
  Widget _outlineBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppTheme.accentOrange,
              width: 1.4,
            ),
          ),
          child: Icon(icon, size: 15, color: AppTheme.accentOrange),
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
