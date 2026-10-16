import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/app_theme.dart';
import '../core/json_util.dart';
import '../core/product_media.dart';
import '../core/promo_price.dart';
import 'app_image.dart';
import 'closed_store_badge.dart';
import 'requires_internet_dialog.dart';

/// Variant picker as a centered dialog (web parity with ProductVariantModal).
/// A dialog (not a bottom sheet) so the page never looks dimmed-and-empty:
/// fixed max size, explicit close button, and an empty-state fallback.
Future<void> showProductVariantSheet(
  BuildContext context,
  Map<String, dynamic> product,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: ProductVariantSheet(product: product, inDialog: true),
      ),
    ),
  );
}

Future<void> handleCartAddResult(
  BuildContext context, {
  required String? error,
  required Map<String, dynamic> product,
  required dynamic variantId,
  required int qty,
  double? productPrice,
  bool silentSuccess = false,
  String variantLabel = '',
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
        variantLabel: variantLabel,
      );
      if (!context.mounted) return;
      if (retry != null) {
        await showCartError(context, retry);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(app.t('add_to_cart'))),
        );
      }
    }
    return;
  }
  if (error != null) {
    await showCartError(context, error);
    return;
  }
  if (silentSuccess) return;
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
    variantLabel: AppController.variantLabelOf(
      variants.isNotEmpty ? variants.first : null,
      J.str(product['name']),
    ),
  );
  if (!context.mounted) return;
  await handleCartAddResult(
    context,
    error: error,
    product: product,
    variantId: variant['id'] ?? product['product_variant_id'],
    qty: 1,
    productPrice: price.finalPrice,
    variantLabel: AppController.variantLabelOf(
      variants.isNotEmpty ? variants.first : null,
      J.str(product['name']),
    ),
  );
}

class ProductVariantSheet extends StatefulWidget {
  const ProductVariantSheet({super.key, required this.product, this.inDialog = false});
  final Map<String, dynamic> product;
  final bool inDialog;

  @override
  State<ProductVariantSheet> createState() => _ProductVariantSheetState();
}

class _ProductVariantSheetState extends State<ProductVariantSheet> {
  /// Optimistic quantities per variant: shown instantly, request runs in
  /// background. No spinners anywhere — errors revert with a snackbar.
  final Map<String, int> _optimistic = {};
  int _seq = 0;

  int _shownQty(Map<String, dynamic> variant) {
    final key = '${variant['id']}';
    if (_optimistic.containsKey(key)) return _optimistic[key]!;
    return _qtyFor(variant);
  }

  Future<void> _setQty(
    Map<String, dynamic> variant,
    int next,
    double unitPrice,
  ) async {
    final app = appController;
    final key = '${variant['id']}';
    final mySeq = ++_seq;
    setState(() => _optimistic[key] = next);
    try {
      if (next <= 0) {
        final err = await app.removeCartLine(
          productId: widget.product['id'],
          variantId: variant['id'],
        );
        if (mySeq != _seq || !mounted) return;
        setState(() => _optimistic.remove(key));
        if (err != null && mounted) {
          await showCartError(context, err);
        }
        return;
      }
      final err = await app.addToCart(
        productId: widget.product['id'],
        variantId: variant['id'],
        qty: next,
        productPrice: unitPrice,
        sellerId: J.sellerId(widget.product),
        storeName: appController.storeNameOf(widget.product),
        variantLabel: AppController.variantLabelOf(variant, J.str(widget.product['name'])),
      );
      if (mySeq != _seq || !mounted) return;
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
            variantId: variant['id'],
            qty: next,
            productPrice: unitPrice,
            sellerId: J.sellerId(widget.product),
            storeName: appController.storeNameOf(widget.product),
            replaceSeller: true,
            variantLabel: AppController.variantLabelOf(variant, J.str(widget.product['name'])),
          );
          if (mySeq != _seq || !mounted) return;
          setState(() => _optimistic.remove(key));
          if (retry != null && mounted) {
            await showCartError(context, retry);
          }
        } else if (mounted) {
          setState(() => _optimistic.remove(key));
        }
        return;
      }
      if (err != null) {
        if (!mounted) return;
        setState(() => _optimistic.remove(key));
        if (mounted) {
          await showCartError(context, err);
        }
      } else {
        // Silent success.
        setState(() => _optimistic.remove(key));
      }
    } catch (_) {
      if (mySeq != _seq || !mounted) return;
      setState(() => _optimistic.remove(key));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appController.t('network_error'))),
      );
    }
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
            if (!widget.inDialog)
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
            if (!widget.inDialog) const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    app.t('productVariants'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (widget.inDialog)
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  ),
              ],
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
            if (variants.isEmpty)
              // List APIs sometimes omit variants: fall back to a single
              // explicit add instead of showing an empty dimmed sheet.
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _setQty(
                    {
                      'id': widget.product['product_variant_id'] ??
                          widget.product['id'],
                    },
                    1,
                    0,
                  ),
                  icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                  label: Text(app.t('add_to_cart')),
                ),
              )
            else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: variants.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final variant = variants[i];
                  final price = variantDisplayPrice(variant);
                  final stock = J.i(variant['stock']);
                  final unlimited = J.flag(
                    widget.product['is_unlimited_stock'] ??
                        variant['is_unlimited_stock'],
                  );
                  final out = !unlimited && stock <= 0;
                  final qty = _shownQty(variant);
                  final rowLabel = AppController.variantLabelOf(
                    variant,
                    J.str(widget.product['name']),
                  );
                  final label = rowLabel.isEmpty
                      ? J.str(variant['name'] ??
                          variant['id'])
                      : rowLabel;
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
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
                              onPressed: () =>
                                  _setQty(variant, qty - 1, price.finalPrice),
                              icon:
                                  const Icon(Icons.remove_circle_outline),
                            ),
                            Text('$qty'),
                            IconButton(
                              onPressed: () =>
                                  _setQty(variant, qty + 1, price.finalPrice),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        )
                      else
                        FilledButton.tonal(
                          onPressed: () =>
                              _setQty(variant, 1, price.finalPrice),
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
