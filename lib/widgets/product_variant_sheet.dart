import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/app_theme.dart';
import '../core/json_util.dart';
import '../core/product_media.dart';
import '../core/promo_price.dart';
import 'app_image.dart';
import 'closed_store_badge.dart';

Future<void> showProductVariantSheet(
  BuildContext context,
  Map<String, dynamic> product,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ProductVariantSheet(product: product),
  );
}

Future<void> handleCartAddResult(
  BuildContext context, {
  required String? error,
  required Map<String, dynamic> product,
  required dynamic variantId,
  required int qty,
  double? productPrice,
}) async {
  final app = appController;
  if (!context.mounted) return;
  if (error == 'same_seller') {
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
    if (ok == true && context.mounted) {
      final retry = await app.addToCart(
        productId: product['id'],
        variantId: variantId,
        qty: qty,
        productPrice: productPrice,
        sellerId: J.sellerId(product),
        storeName: app.storeNameOf(product),
        replaceSeller: true,
      );
      if (!context.mounted) return;
      if (retry != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(retry)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(app.t('add_to_cart'))),
        );
      }
    }
    return;
  }
  if (error != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(app.t('add_to_cart'))),
  );
}

Future<void> addProductFromCatalog(
  BuildContext context,
  Map<String, dynamic> product,
) async {
  final variants = J.maps(product['variants']);
  if (variants.length > 1) {
    await showProductVariantSheet(context, product);
    return;
  }
  final variant = variants.isNotEmpty ? variants.first : product;
  final price = variantDisplayPrice(variant);
  final error = await appController.addToCart(
    productId: product['id'],
    variantId: variant['id'] ?? product['product_variant_id'],
    qty: 1,
    productPrice: price.finalPrice,
    sellerId: J.sellerId(product),
    storeName: appController.storeNameOf(product),
  );
  if (!context.mounted) return;
  await handleCartAddResult(
    context,
    error: error,
    product: product,
    variantId: variant['id'] ?? product['product_variant_id'],
    qty: 1,
    productPrice: price.finalPrice,
  );
}

class ProductVariantSheet extends StatefulWidget {
  const ProductVariantSheet({super.key, required this.product});
  final Map<String, dynamic> product;

  @override
  State<ProductVariantSheet> createState() => _ProductVariantSheetState();
}

class _ProductVariantSheetState extends State<ProductVariantSheet> {
  bool busy = false;

  Future<void> _add(Map<String, dynamic> variant) async {
    if (busy) return;
    setState(() => busy = true);
    final price = variantDisplayPrice(variant);
    final qty = _qtyFor(variant);
    final error = await appController.addToCart(
      productId: widget.product['id'],
      variantId: variant['id'],
      qty: qty <= 0 ? 1 : qty,
      productPrice: price.finalPrice,
      sellerId: J.sellerId(widget.product),
      storeName: appController.storeNameOf(widget.product),
    );
    if (!mounted) return;
    setState(() => busy = false);
    await handleCartAddResult(
      context,
      error: error,
      product: widget.product,
      variantId: variant['id'],
      qty: qty <= 0 ? 1 : qty,
      productPrice: price.finalPrice,
    );
  }

  int _qtyFor(Map<String, dynamic> variant) {
    final app = appController;
    final key = '${variant['id']}';
    final lines = app.isLoggedIn ? app.cartProducts : app.guestCart;
    for (final item in lines) {
      if ('${item['product_variant_id'] ?? item['id']}' == key) {
        return J.i(item['qty'] ?? item['quantity'], 1);
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final variants = J.maps(widget.product['variants']);
    final image = productImageUrl(
      widget.product,
      placeholder: app.placeholder,
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              app.t('productVariants'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 54,
                      height: 54,
                      child: AppImage(image, placeholder: app.placeholder),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          J.str(widget.product['name']),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        ClosedStoreBadge(product: widget.product),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: variants.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final variant = variants[i];
                  final price = variantDisplayPrice(variant);
                  final stock = J.i(variant['stock']);
                  final unlimited = J.flag(
                    widget.product['is_unlimited_stock'] ??
                        variant['is_unlimited_stock'],
                  );
                  final out = !unlimited && stock <= 0;
                  final qty = _qtyFor(variant);
                  final label = [
                    J.str(variant['measurement']),
                    J.str(variant['stock_unit_name']),
                  ].where((e) => e.isNotEmpty).join(' ');
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          label.isEmpty ? J.str(variant['name'] ?? variant['id']) : label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (!out)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            money(price.finalPrice, app.currency, app.decimals),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accentOrange,
                            ),
                          ),
                        ),
                      if (out)
                        Text(
                          app.t('out_of_stock'),
                          style: const TextStyle(color: Colors.red),
                        )
                      else if (qty > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      if (qty <= 1) {
                                        await app.removeCartLine(
                                          productId: widget.product['id'],
                                          variantId: variant['id'],
                                        );
                                      } else {
                                        await app.addToCart(
                                          productId: widget.product['id'],
                                          variantId: variant['id'],
                                          qty: qty - 1,
                                          productPrice: price.finalPrice,
                                          sellerId: J.sellerId(widget.product),
                                          storeName: app.storeNameOf(widget.product),
                                        );
                                      }
                                      if (mounted) setState(() {});
                                    },
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text('$qty'),
                            IconButton(
                              onPressed: busy ? null : () => _add(variant),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        )
                      else
                        FilledButton.tonal(
                          onPressed: busy ? null : () => _add(variant),
                          child: Text(app.t('add_to_cart')),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
