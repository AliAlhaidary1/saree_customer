import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';
import '../../core/business_hours.dart';
import '../../core/json_util.dart';
import '../../core/offline/offline_cache.dart';
import '../../core/promo_price.dart';
import '../../widgets/app_image.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/requires_internet_dialog.dart';
import '../../widgets/ui_helpers.dart';

/// Variant unit label for a cart line (e.g. "1 كيلو", "2 نفر").
/// Server cart items don't always carry the unit flat — it may live inside
/// a nested variant map or under alternate keys — so every known location
/// is checked before falling back to a variant display name.
String _cartLineUnit(Map<String, dynamic> item) {
  // Label captured at add time is the most reliable (server cart items
  // often omit the unit type, leaving only the number).
  final remembered = J.str(item['variant_label']);
  if (remembered.isNotEmpty) return remembered;
  final nested = item['variant'] is Map
      ? J.map(item['variant'])
      : item['product_variant'] is Map
      ? J.map(item['product_variant'])
      : J.map(item['variant_info']);
  String pick(List<dynamic> keys, [Map<String, dynamic>? from]) {
    final src = from ?? item;
    for (final k in keys) {
      final v = J.str(src[k]);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  var measure = pick(const ['measurement']);
  if (measure.isEmpty) measure = pick(const ['measurement'], nested);
  var type = pick(const [
    'stock_unit_name',
    'unit',
    'unit_name',
    'uom',
    'unit_type',
  ]);
  if (type.isEmpty) {
    type = pick(const [
      'stock_unit_name',
      'unit',
      'unit_name',
      'uom',
      'unit_type',
    ], nested);
  }
  if (type.isEmpty) {
    type = pick(const ['variant_name', 'variant_label', 'variant_title']);
  }
  if (type.isEmpty && nested.isNotEmpty) {
    final fallback = J.str(nested['name']);
    // Only accept a nested name that adds info (not the product name again).
    if (fallback.isNotEmpty && fallback != J.str(item['name'])) {
      type = fallback;
    }
  }
  return [measure, type].where((e) => e.isNotEmpty).join(' ');
}

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool loading = true;
  String? error;

  /// True when the visible lines/totals come from a failed refresh: cached
  /// prices are indicative estimates until the server revalidates them.
  bool _staleTotals = false;

  @override
  void initState() {
    super.initState();
    // Cached lines render instantly; the network refresh runs silently
    // in the background so an empty cart never waits on the network.
    if (lines.isNotEmpty) {
      loading = false;
      _load(silent: true);
    } else {
      _load();
    }
  }

  Future<void> _load({bool silent = false}) async {
    // Fast path: a guest with no local lines has nothing to refresh —
    // show the empty state instantly instead of spinning on the network.
    if (!appController.isLoggedIn && lines.isEmpty) {
      if (mounted) {
        setState(() {
          loading = false;
          error = null;
        });
      }
      return;
    }
    // Without this guard any failure leaves the spinner on screen forever
    // and the user has to kill the app.
    if (!silent && mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      // Short timeout so a slow/unreachable backend surfaces a retryable
      // error quickly instead of looking like a frozen app.
      final result = await appController.refreshCart().timeout(
        const Duration(seconds: 12),
      );
      if (!mounted) return;
      if (!result.ok && lines.isEmpty) {
        // Offline with no restorable snapshot: retryable error, never a
        // misleading "empty cart".
        setState(() {
          error = appController.t('cart_load_failed');
          _staleTotals = false;
        });
      } else {
        setState(() {
          error = null;
          _staleTotals = !result.ok && lines.isNotEmpty;
        });
      }
    } catch (_) {
      if (!mounted) return;
      // Show cached lines if we have them; only block an empty cart
      // with a retryable error instead of a frozen spinner.
      if (lines.isEmpty) {
        setState(() => error = appController.t('cart_load_failed'));
      } else {
        // Lines are locally remembered: totals are estimates, not quotes.
        setState(() => _staleTotals = true);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> get lines => appController.isLoggedIn
      ? appController.cartProducts
      : appController.guestCart;

  bool _lineOutOfStock(Map<String, dynamic> e) {
    final unlimited =
        J.i(e['is_unlimited_stock']) == 1 ||
        J.str(e['stock_status']).toLowerCase() == 'unlimited';
    if (unlimited) return false;
    final stock = J.i(
      e['stock'] ?? e['total_stock'] ?? e['total_allowed_quantity'] ?? -1,
      -1,
    );
    if (stock == 0) return true;
    final status = J.str(e['status'] ?? e['stock_status']).toLowerCase();
    return status == 'out_of_stock' || status == '0';
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    if (loading && lines.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && lines.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        message: error!,
        actionLabel: app.t('retry'),
        onAction: _load,
      );
    }
    if (lines.isEmpty) {
      return EmptyState(
        icon: Icons.shopping_cart_outlined,
        message: app.t('empty_cart'),
        actionLabel: app.t('shop_now'),
        onAction: () => context.go('/products'),
      );
    }
    final total = app.isLoggedIn ? app.cartSubTotal : app.guestCartTotal;
    final cartMap = app.cart;
    final savedAmount = J.d(cartMap?['saved_amount'] ?? cartMap?['saved']);
    final promoDiscount = J.d(
      app.promoCode?['discount'] ?? cartMap?['promo_discount'],
    );
    return Column(
      children: [
        if (_staleTotals) OfflineBanner(stale: true),
        if (app.distinctCartSellerCount > 0)
          Container(
            color: Colors.orange.withValues(alpha: 0.08),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.storefront, size: 14, color: Colors.orange),
                const SizedBox(width: 6),
                Text(
                  '${app.distinctCartSellerCount} ${app.t('sellers')}',
                  style: const TextStyle(fontSize: 12),
                ),
                const Spacer(),
                Text(
                  app
                      .t('max_sellers_limit')
                      .replaceAll('{max}', '${app.maxSellersPerCheckout}'),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(silent: true),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: lines.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final item = lines[i];
                final qty = J.i(item['qty'] ?? item['quantity'], 1);
                final name = J.str(item['name'] ?? item['product_name']);
                final image = J.str(item['image_url'] ?? item['image']);
                final price = variantDisplayPrice(item);
                final outOfStock = _lineOutOfStock(item);
                final stock = J.i(
                  item['stock'] ?? item['total_stock'] ?? -1,
                  -1,
                );
                final allowed = J.i(item['total_allowed_quantity'], 0);
                final unlimited =
                    J.i(item['is_unlimited_stock']) == 1 ||
                    J.str(item['stock_status']).toLowerCase() == 'unlimited';
                final maxQty = unlimited
                    ? 99
                    : (allowed > 0 ? allowed : (stock >= 0 ? stock : 99));
                return ListTile(
                  tileColor: outOfStock
                      ? Colors.red.withValues(alpha: 0.05)
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: SizedBox(
                    width: 56,
                    height: 56,
                    child: AppImage(image, placeholder: app.placeholder),
                  ),
                  title: Text(name, maxLines: 2),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Builder(
                        builder: (_) {
                          final unit = _cartLineUnit(item);
                          if (unit.isEmpty) return const SizedBox.shrink();
                          return Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentOrange.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.scale_outlined,
                                  size: 12,
                                  color: AppTheme.accentOrange,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    unit,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.accentOrange,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      Text(
                        '${money(price.finalPrice, app.currency, app.decimals)} × $qty = ${money(price.finalPrice * qty, app.currency, app.decimals)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (outOfStock)
                        Text(
                          app.t('OutOfStock'),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.red,
                          ),
                        ),
                    ],
                  ),
                  onTap: () {
                    final slug = J.str(item['slug']);
                    final pid = item['product_id'] ?? item['id'];
                    if (slug.isNotEmpty) {
                      context.push('/product/$slug');
                    } else if (pid != null) {
                      context.push('/product/$pid');
                    }
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: qty <= 1
                            ? () => app
                                  .removeCartLine(
                                    productId: item['product_id'] ?? item['id'],
                                    variantId:
                                        item['product_variant_id'] ??
                                        item['id'],
                                  )
                                  .then((err) async {
                                    if (err != null && context.mounted) {
                                      await showCartError(context, err);
                                    }
                                    if (mounted) setState(() {});
                                  })
                            : () => app
                                  .addToCart(
                                    productId: item['product_id'] ?? item['id'],
                                    variantId:
                                        item['product_variant_id'] ??
                                        item['id'],
                                    qty: qty - 1,
                                    sellerId:
                                        item['seller_id'] ?? J.sellerId(item),
                                    variantLabel: _cartLineUnit(item),
                                  )
                                  .then((_) {
                                    if (mounted) setState(() {});
                                  }),
                      ),
                      Text('$qty'),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: qty >= maxQty
                            ? () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      app
                                          .t('limited_product_stock_error')
                                          .replaceAll('{max}', '$maxQty'),
                                    ),
                                  ),
                                );
                              }
                            : () async {
                                final err = await app.addToCart(
                                  productId: item['product_id'] ?? item['id'],
                                  variantId:
                                      item['product_variant_id'] ?? item['id'],
                                  qty: qty + 1,
                                  sellerId:
                                      item['seller_id'] ?? J.sellerId(item),
                                  storeName: app.storeNameOf(item),
                                  variantLabel: _cartLineUnit(item),
                                );
                                if (!context.mounted) return;
                                if (err != null) {
                                  await showCartError(context, err);
                                }
                                setState(() {});
                              },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        tooltip: app.t('delete_item'),
                        onPressed: () => app
                            .removeCartLine(
                              productId: item['product_id'] ?? item['id'],
                              variantId:
                                  item['product_variant_id'] ?? item['id'],
                            )
                            .then((err) async {
                              if (err != null && context.mounted) {
                                await showCartError(context, err);
                              }
                              if (mounted) setState(() {});
                            }),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        Material(
          color: Colors.white,
          elevation: 8,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(app.t('sub_total')),
                      const Spacer(),
                      Text(
                        money(total, app.currency, app.decimals),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (promoDiscount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(app.t('promo_code_discount')),
                        const Spacer(),
                        Text(
                          '- ${money(promoDiscount, app.currency, app.decimals)}',
                          style: const TextStyle(color: Colors.green),
                        ),
                      ],
                    ),
                  ],
                  if (savedAmount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(app.t('you_saved')),
                        const Spacer(),
                        Text(
                          money(savedAmount, app.currency, app.decimals),
                          style: const TextStyle(color: Colors.green),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () {
                      if (!app.isLoggedIn) {
                        context.push(
                          '/login?next=${Uri.encodeComponent('/checkout')}',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(app.t('please_login_continue')),
                          ),
                        );
                        return;
                      }
                      // Parity with front Cart.js stockValidation: block zero-stock checkout.
                      final outOfStock = lines.where((e) {
                        final unlimited =
                            J.i(e['is_unlimited_stock']) == 1 ||
                            J.str(e['stock_status']).toLowerCase() ==
                                'unlimited';
                        if (unlimited) return false;
                        final stock = J.i(
                          e['stock'] ??
                              e['total_stock'] ??
                              e['total_allowed_quantity'] ??
                              -1,
                          -1,
                        );
                        if (stock == 0) return true;
                        final status = J
                            .str(e['status'] ?? e['stock_status'])
                            .toLowerCase();
                        return status == 'out_of_stock' || status == '0';
                      }).toList();
                      if (outOfStock.isNotEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(app.t('some_items_are_out_of_stock')),
                          ),
                        );
                        return;
                      }
                      // stock / seller limit guard like front
                      if (app.distinctCartSellerCount >
                          app.maxSellersPerCheckout) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              app
                                  .t('max_stores_exceeded')
                                  .replaceAll(
                                    '{max}',
                                    '${app.maxSellersPerCheckout}',
                                  ),
                            ),
                          ),
                        );
                        return;
                      }
                      context.push('/checkout');
                    },
                    child: Text(app.t('checkout')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  Map<String, dynamic>? checkout;
  String method = 'COD';
  bool walletUsed = false;
  bool placing = false;
  final note = TextEditingController();
  final promo = TextEditingController();
  String? deliveryTime; // "D-M-YYYY title" like front
  DateTime? selectedDay;
  String? selectedSlot;
  bool loadingCheckout = true;
  String? loadError;
  bool _staleCheckout = false;
  bool _draftRestored = false;

  /// Local checkout draft id. The draft is NEVER auto-submitted and NEVER
  /// presented as a placed order — it only restores the form after process
  /// death or navigation away.
  static const _draftFormId = 'checkout_form';

  @override
  void initState() {
    super.initState();
    _restoreDraft();
    note.addListener(_saveDraftSoon);
    _load();
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _saveDraftSoon();
  }

  void _restoreDraft() {
    try {
      final draft = appController.offline.readDraft(
        appController.accountScope,
        _draftFormId,
      );
      if (draft == null) return;
      final m = J.str(draft['method']);
      if (m.isNotEmpty) method = m;
      walletUsed = draft['walletUsed'] == true;
      final dt = J.str(draft['deliveryTime']);
      if (dt.isNotEmpty) deliveryTime = dt;
      final n = J.str(draft['note']);
      if (n.isNotEmpty) note.text = n;
      _draftRestored =
          m.isNotEmpty || dt.isNotEmpty || n.isNotEmpty || walletUsed;
    } catch (_) {}
  }

  Timer? _draftDeb;

  void _saveDraftSoon() {
    _draftDeb?.cancel();
    // Capture scope + fields together: an account switch inside the debounce
    // window drops the write instead of filing this account's form under the
    // next identity (see ScopedDraftWrite).
    final pending = ScopedDraftWrite(
      scope: appController.accountScope,
      fields: {
        'method': method,
        'walletUsed': walletUsed,
        'deliveryTime': deliveryTime ?? '',
        'note': note.text,
        'addressId': appController.selectedAddress?['id'],
      },
    );
    _draftDeb = Timer(const Duration(milliseconds: 800), () {
      final fields = pending.forScope(appController.accountScope);
      if (fields == null) return;
      try {
        appController.offline.writeDraft(pending.scope, _draftFormId, fields);
      } catch (_) {}
    });
  }

  Future<void> _clearDraft() async {
    _draftDeb?.cancel();
    try {
      await appController.offline.removeDraft(
        appController.accountScope,
        _draftFormId,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _draftDeb?.cancel();
    note.dispose();
    promo.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Same guard as the cart: never leave the spinner stuck on failure.
    if (mounted) {
      setState(() {
        loadingCheckout = true;
        loadError = null;
      });
    }
    try {
      final result = await appController
          .refreshCart(checkout: 1)
          .timeout(const Duration(seconds: 30));
      // also load multi seller if needed
      if (appController.sellerGroups.length > 1) {
        await appController.loadMultiSellerCheckout().timeout(
          const Duration(seconds: 30),
        );
      }
      if (!mounted) return;
      setState(() {
        checkout = result.dataMap.isNotEmpty
            ? result.dataMap
            : appController.cart;
        _staleCheckout = !result.ok;
        if (!result.ok && (checkout == null || checkout!.isEmpty)) {
          loadError = result.message.isNotEmpty
              ? result.message
              : appController.t('checkout_load_failed');
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _staleCheckout = checkout != null && checkout!.isNotEmpty;
        if (!_staleCheckout) {
          loadError = appController.t('checkout_load_failed');
        }
      });
    } finally {
      if (mounted) setState(() => loadingCheckout = false);
    }
  }

  bool _methodOn(String key) =>
      J.str(appController.paymentSettings[key]) == '1';

  bool _paymentConfigured() => appController.paymentSettings.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final app = appController;
    if (!app.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(app.t('checkout'))),
        body: const LoginRequired(),
      );
    }
    if (loadingCheckout) {
      return Scaffold(
        appBar: AppBar(title: Text(app.t('checkout'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (loadError != null && (checkout == null || checkout!.isEmpty)) {
      return Scaffold(
        appBar: AppBar(title: Text(app.t('checkout'))),
        body: EmptyState(
          message: loadError!,
          icon: Icons.cloud_off_outlined,
          actionLabel: app.t('retry'),
          onAction: _load,
        ),
      );
    }
    final items = J.maps(
      checkout?['cart'] ?? checkout?['items'] ?? app.cartProducts,
    );
    final subTotal = J.d(checkout?['sub_total'] ?? app.cartSubTotal);
    final deliveryNode = checkout?['delivery_charge'];
    final delivery = J.d(
      deliveryNode is Map
          ? deliveryNode['total_delivery_charge'] ?? deliveryNode['total']
          : (deliveryNode ??
                checkout?['delivery_fee'] ??
                app.multiSellerCheckout?.deliveryTotal),
    );
    final freeDelivery =
        J.str(deliveryNode is Map ? deliveryNode['is_free_delivery'] : null) ==
        '1';
    final discount = J.d(
      app.promoCode?['discount'] ?? checkout?['promo_discount'],
    );
    final platformFee = J.d(checkout?['platform_fee'] ?? app.platformFee);
    final preWalletTotal = J.d(
      checkout?['final_total'] ?? checkout?['total'],
      subTotal + delivery + platformFee - discount,
    );
    final wallet = J.d(
      app.user?['balance'] ??
          app.user?['wallet'] ??
          app.settings['user_balance'],
    );
    // Web parity: wallet deduction is always computed (even when it covers
    // everything), and the wallet card is always visible.
    final walletDeduction = walletUsed
        ? wallet.clamp(0.0, preWalletTotal)
        : 0.0;
    var finalTotal = preWalletTotal - walletDeduction;
    final fullWalletCover =
        walletUsed && preWalletTotal > 0 && walletDeduction >= preWalletTotal;
    if (fullWalletCover) method = 'Wallet';
    final codAllowed = J.flag(checkout?['cod_allowed'] ?? 1);
    final address = app.selectedAddress;
    final bh = app.businessHours;
    final canPlace = app.canPlaceOrder();
    final sellerGroups = app.sellerGroups;
    final deliveryFees = app.deliveryFees;

    return Scaffold(
      appBar: AppBar(title: Text(app.t('checkout'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Min-order guard parity with web Checkout (backend still enforces).
          if (app.minOrderAmount > 0 && subTotal < app.minOrderAmount)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      app.t('minimum_order_amount_is').replaceAll('{amount}', money(app.minOrderAmount, app.currency, app.decimals)),
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (app.minOrderAmount > 0 && subTotal < app.minOrderAmount)
            const SizedBox(height: 12),
          // Business hours banner parity with front BusinessHoursBanner
          if (bh != null && !canPlace.allowed)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      canPlace.reason == 'platform'
                          ? buildMarketplaceClosedMessage(canPlace.status)
                          : buildSellerClosedMessage(
                              canPlace.status,
                              canPlace.status?.storeName ?? '',
                            ),
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (bh != null && !canPlace.allowed) const SizedBox(height: 12),
          // ── Delivery addresses (web parity: inline radio list, not a
          // single tile that forces leaving checkout) ──
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(
                      app.t('delivery_address'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: TextButton.icon(
                      onPressed: () async {
                        await context.push('/addresses');
                        if (!mounted) return;
                        setState(() {});
                        await _load();
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(
                        app.addresses.isEmpty
                            ? app.t('add_new_address')
                            : app.t('add_another_address'),
                      ),
                    ),
                  ),
                  if (app.addresses.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        app.t('no_address_yet'),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else
                    ...app.addresses.map((a) {
                      final sel = '${a['id']}' == '${address?['id']}';
                      final line = [
                        J.str(a['address'] ?? a['formatted_address']),
                        J.str(a['area']),
                        J.str(a['city']),
                        J.str(a['mobile']),
                      ].where((p) => p.isNotEmpty).join('، ');
                      return RadioListTile<String>(
                        dense: true,
                        value: '${a['id']}',
                        groupValue: address == null ? null : '${address['id']}',
                        onChanged: (_) async {
                          app.selectAddress(a);
                          await _load();
                        },
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                J.str(a['type'] ?? a['name']),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (J.str(a['is_default']) == '1' ||
                                J.i(a['is_default']) == 1)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: app.accentColor.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  app.t('default_address_badge'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: app.accentColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: line.isEmpty
                            ? null
                            : Text(
                                line,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                        secondary: sel
                            ? Icon(Icons.check_circle, color: app.accentColor)
                            : null,
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── Stores in this order ──
          if (sellerGroups.isNotEmpty)
            Card(
              child: Column(
                children: sellerGroups
                    .map(
                      (g) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.store_outlined),
                        title: Text(J.str(g['store_name'] ?? g['seller_id'])),
                        subtitle: Text(
                          '${J.maps(g['items']).length} • ${app.t('products')}',
                        ),
                        trailing: Text(
                          money(
                            deliveryFees['${g['seller_id']}']?['amount'] ?? 0,
                            app.currency,
                            app.decimals,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          if (sellerGroups.isNotEmpty) const SizedBox(height: 12),
          // time slots picker like front Checkout.js
          if (app.timeSlots.isNotEmpty) ...[
            Text(
              app.t('select_delivery_time'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 7,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, idx) {
                  final day = DateTime.now().add(Duration(days: idx));
                  final isSel =
                      selectedDay != null &&
                      selectedDay!.day == day.day &&
                      selectedDay!.month == day.month;
                  return ChoiceChip(
                    label: Text('${day.day}/${day.month}'),
                    selected: isSel,
                    onSelected: (_) => setState(() {
                      selectedDay = day;
                      // rebuild deliveryTime
                      if (selectedSlot != null) {
                        deliveryTime =
                            '${day.day}-${day.month}-${day.year} $selectedSlot';
                      }
                    }),
                  );
                },
              ),
            ),
            Wrap(
              spacing: 8,
              children: app.timeSlots
                  .map(
                    (s) => ChoiceChip(
                      label: Text(s.title),
                      selected: selectedSlot == s.title,
                      onSelected: (_) => setState(() {
                        selectedSlot = s.title;
                        if (selectedDay != null) {
                          deliveryTime =
                              '${selectedDay!.day}-${selectedDay!.month}-${selectedDay!.year} $s.title';
                        } else {
                          deliveryTime = s.title;
                        }
                      }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
          // ── Items ──
          Card(
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  ListTile(
                    dense: true,
                    leading: _thumb(items[i], app),
                    title: Text(
                      J.str(items[i]['name'] ?? items[i]['product_name']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      'x${items[i]['qty'] ?? items[i]['quantity']}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (i < items.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── Summary ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row(
                    app.t('sub_total'),
                    money(subTotal, app.currency, app.decimals),
                  ),
                  _row(
                    '${app.t('delivery_charge')}${freeDelivery ? ' (${app.t('free_delivery')})' : ''}',
                    money(delivery, app.currency, app.decimals),
                  ),
                  if (platformFee > 0)
                    _row(
                      app.t('platform_fee'),
                      money(platformFee, app.currency, app.decimals),
                    ),
                  if (discount > 0)
                    _row(
                      app.t('discount'),
                      '- ${money(discount, app.currency, app.decimals)}',
                    ),
                  if (walletUsed && walletDeduction > 0)
                    _row(
                      app.t('walletBalance'),
                      '- ${money(walletDeduction, app.currency, app.decimals)}',
                    ),
                  const Divider(),
                  _row(
                    app.t('total'),
                    money(finalTotal, app.currency, app.decimals),
                    bold: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── Wallet (web parity: ALWAYS visible, disabled when empty) ──
          Card(
            color: walletUsed ? app.accentColor.withValues(alpha: 0.08) : null,
            child: SwitchListTile(
              value: walletUsed,
              onChanged: wallet <= 0
                  ? null
                  : (v) => setState(() {
                      walletUsed = v;
                      if (v && finalTotal - wallet <= 0) method = 'Wallet';
                    }),
              secondary: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: app.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: app.accentColor,
                ),
              ),
              title: Text(
                '${app.t('walletBalance')} • ${money(wallet, app.currency, app.decimals)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                wallet <= 0
                    ? app.t('wallet_empty_hint')
                    : (walletUsed
                          ? app.t('wallet_in_use')
                          : app.t('wallet_use_hint')),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (fullWalletCover)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      app.t('wallet_covers_full'),
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          // ── Payment methods (selectable cards, web parity) ──
          if (!fullWalletCover)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Text(
                        app.t('payment_method'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (codAllowed &&
                        (_methodOn('cod_payment_method') ||
                            !_paymentConfigured()))
                      _payTile(
                        app: app,
                        icon: Icons.money_outlined,
                        label: app.t('cash_on_delivery'),
                        value: 'COD',
                        group: method,
                        enabled: !(walletUsed && finalTotal == 0),
                        onTap: (v) => setState(() => method = v),
                      ),
                    if (_methodOn('wallet_payment_method') || walletUsed)
                      _payTile(
                        app: app,
                        icon: Icons.account_balance_wallet_outlined,
                        label: app.t('walletBalance'),
                        value: 'Wallet',
                        group: method,
                        enabled: true,
                        onTap: (v) => setState(() => method = v),
                      ),
                    if (_methodOn('stripe_payment_method') ||
                        _methodOn('stripe'))
                      _payTile(
                        app: app,
                        icon: Icons.credit_card_outlined,
                        label: 'Stripe',
                        value: 'Stripe',
                        group: method,
                        enabled: true,
                        onTap: (v) => setState(() => method = v),
                      ),
                    if (_methodOn('paypal_payment_method') ||
                        _methodOn('paypal'))
                      _payTile(
                        app: app,
                        icon: Icons.payment_outlined,
                        label: 'PayPal',
                        value: 'Paypal',
                        group: method,
                        enabled: true,
                        onTap: (v) => setState(() => method = v),
                      ),
                    if (_methodOn('paystack_payment_method') ||
                        _methodOn('paystack'))
                      _payTile(
                        app: app,
                        icon: Icons.payment_outlined,
                        label: 'Paystack',
                        value: 'Paystack',
                        group: method,
                        enabled: true,
                        onTap: (v) => setState(() => method = v),
                      ),
                    if (_methodOn('razorpay_payment_method') ||
                        _methodOn('razorpay'))
                      _payTile(
                        app: app,
                        icon: Icons.payment_outlined,
                        label: 'Razorpay',
                        value: 'Razorpay',
                        group: method,
                        enabled: true,
                        onTap: (v) => setState(() => method = v),
                      ),
                    if (_methodOn('cashfree_payment_method'))
                      _payTile(
                        app: app,
                        icon: Icons.payment_outlined,
                        label: 'Cashfree',
                        value: 'Cashfree',
                        group: method,
                        enabled: true,
                        onTap: (v) => setState(() => method = v),
                      ),
                    if (_methodOn('midtrans_payment_method'))
                      _payTile(
                        app: app,
                        icon: Icons.payment_outlined,
                        label: 'Midtrans',
                        value: 'Midtrans',
                        group: method,
                        enabled: true,
                        onTap: (v) => setState(() => method = v),
                      ),
                    if (_methodOn('phonepe_payment_method') ||
                        _methodOn('phonepay_payment_method'))
                      _payTile(
                        app: app,
                        icon: Icons.payment_outlined,
                        label: 'PhonePe',
                        value: 'Phonepe',
                        group: method,
                        enabled: true,
                        onTap: (v) => setState(() => method = v),
                      ),
                  ],
                ),
              ),
            ),
          TextField(
            controller: promo,
            decoration: InputDecoration(
              labelText: app.t('promo_code'),
              suffixIcon: app.promoCode == null
                  ? TextButton(
                      onPressed: () async {
                        final error = await app.applyPromo(
                          promo.text.trim(),
                          subTotal,
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(error ?? app.t('promo_applied')),
                          ),
                        );
                        setState(() {});
                      },
                      child: Text(app.t('apply')),
                    )
                  : TextButton(
                      onPressed: () {
                        app.clearPromo();
                        promo.clear();
                        setState(() {});
                      },
                      child: Text(app.t('remove_promo')),
                    ),
            ),
          ),
          TextField(
            controller: note,
            decoration: InputDecoration(
              labelText: app.t('order_note'),
              hintText: app.t('order_note_hint'),
            ),
          ),
          if (deliveryTime != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${app.t('delivery_time')}: $deliveryTime',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          const SizedBox(height: 16),
          if (address == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                app.t('add_address_first'),
                style: const TextStyle(color: Colors.red),
              ),
            ),
          if (!canPlace.allowed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                canPlace.reason == 'platform'
                    ? buildMarketplaceClosedMessage(canPlace.status)
                    : buildSellerClosedMessage(canPlace.status, ''),
                style: const TextStyle(color: Colors.red),
              ),
            ),
          if (_draftRestored)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                app.t('draft_saved'),
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ),
          if (_staleCheckout)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                color: Colors.orange.withValues(alpha: 0.12),
                child: ListTile(
                  leading: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                  ),
                  title: Text(app.t('checkout_stale_totals')),
                  trailing: TextButton(
                    onPressed: loadingCheckout ? null : _load,
                    child: Text(app.t('retry')),
                  ),
                ),
              ),
            ),
          FilledButton(
            onPressed:
                placing ||
                    _staleCheckout ||
                    !canPlace.allowed ||
                    (app.minOrderAmount > 0 && subTotal < app.minOrderAmount)
                ? null
                : () {
                    if (address == null) {
                      context.push('/addresses');
                      return;
                    }
                    _placeOrder(
                      app,
                      items,
                      subTotal,
                      delivery,
                      finalTotal,
                      wallet,
                      address,
                    );
                  },
            child: placing
                ? const BusySpinner()
                : Text(
                    address == null
                        ? app.t('add_address_first')
                        : _isGateway(method)
                        ? app
                              .t('pay_via_gateway')
                              .replaceAll('{method}', method)
                        : app.t('place_order'),
                  ),
          ),
        ],
      ),
    );
  }

  bool _isGateway(String m) => [
    'Stripe',
    'Paypal',
    'Paystack',
    'Razorpay',
    'Cashfree',
    'Midtrans',
    'Phonepe',
  ].contains(m);

  Future<void> _placeOrder(
    AppController app,
    List<Map<String, dynamic>> items,
    double subTotal,
    double delivery,
    double finalTotal,
    double wallet,
    Map<String, dynamic> address,
  ) async {
    if (app.unresolvedCheckout) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(app.t('unresolved_checkout_title')),
          content: Text(app.t('unresolved_checkout_message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(app.t('cancel')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.go('/orders');
              },
              child: Text(app.t('view_orders')),
            ),
          ],
        ),
      );
      return;
    }
    if (!await app.hasInternetAccess()) {
      if (context.mounted) await showRequiresInternetDialog(context);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.t('confirm_order')),
        content: Text(
          '${money(finalTotal, app.currency, app.decimals)}\n${deliveryTime ?? ''}\n$method',
        ),
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
    if (ok != true || !mounted) return;
    setState(() => placing = true);
    // Stable session key: identical across retries of this logical order so
    // the backend can deduplicate. Fresh-timestamp-per-tap would not.
    final payMethod = (walletUsed && finalTotal == 0) ? 'Wallet' : method;
    final fingerprint = app.checkoutFingerprint(
      addressId: address['id'],
      paymentMethod: payMethod,
      deliveryTime: deliveryTime,
      promoCodeId: app.promoCode?['id'] ?? app.promoCode?['promo_code_id'],
    );
    final idempotencyKey = await app.checkoutKey(
      context: {
        'address_id': '${address['id']}',
        'sellers': app.sellerGroups.length,
        'fingerprint': fingerprint,
      },
    );
    // POST /customer/checkout is the single, idempotent checkout endpoint and
    // supports multi-seller carts. The legacy placeMultiSellerOrder route does
    // not exist on the backend and must not be used.
    final result = await app.api.checkout(
      addressId: address['id'],
      paymentMethod: payMethod,
      useWallet: walletUsed,
      promocodeId: app.promoCode?['id'] ?? app.promoCode?['promo_code_id'],
      deliveryTime: deliveryTime ?? 'N/A',
      orderNote: note.text.trim(),
      idempotencyKey: idempotencyKey,
    );
    if (!mounted) return;
    if (!result.ok) {
      // Uncertain result (timeout/unreachable) keeps the session: the order
      // may have succeeded server-side. Reconcile via history BEFORE any
      // resubmission instead of blindly retrying with a new key.
      final uncertain =
          result.message.isEmpty ||
          RegExp(
            r'timeout|timed out|network|unreachable|try again|unavailable',
            caseSensitive: false,
          ).hasMatch(result.message);
      if (uncertain) {
        final exists = await app.hasRecentOrderForSession(idempotencyKey);
        if (!mounted) return;
        if (exists) {
          await app.clearCheckoutSession();
          await app.refreshCart();
          if (!mounted) return;
          context.go('/orders');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(app.t('order_uncertain_reconciled'))),
          );
          return;
        }
        // Keep session: the SAME key will be resent on the next attempt.
      }
      setState(() => placing = false);
      // Network-class failure: dedicated offline message (cart + session
      // kept, never reported as success). Other failures keep the backend's
      // message so validation errors stay actionable.
      final offline =
          app.api.likelyOffline ||
          RegExp(
            r'timeout|timed out|network|unreachable|unavailable',
            caseSensitive: false,
          ).hasMatch(result.message);
      if (offline) {
        if (context.mounted) await showRequiresInternetDialog(context);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message.isEmpty
                ? app.t('something_went_wrong')
                : result.message,
          ),
        ),
      );
      return;
    }
    await app.clearCheckoutSession();
    await _clearDraft();
    _draftRestored = false;
    // gateway handling like front initiate_transaction
    if (_isGateway(payMethod)) {
      final checkoutGroupId =
          result.dataMap['checkout_group_id'] ??
          result.dataMap['id'] ??
          result.dataMap['group_id'];
      if (checkoutGroupId != null) {
        final init = await app.api.initiateTransactionForCheckoutGroup(
          checkoutGroupId: checkoutGroupId,
          paymentMethod: payMethod,
        );
        if (!mounted) return;
        if (!init.ok) {
          setState(() => placing = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(init.message)));
          return;
        }
        // Parity with front: open gateway redirect (Stripe/Paypal/Cashfree/...) externally.
        final data = init.dataMap;
        final url = J.str(
          data['url'] ??
              data['redirect_url'] ??
              data['redirectUrl'] ??
              data['snap_url'] ??
              data['payment_url'] ??
              data['paymentUrl'],
        );
        if (url.isNotEmpty && mounted) {
          final uri = Uri.tryParse(url);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(url)));
          }
        }
      }
    }
    setState(() => placing = false);
    app.clearPromo();
    await app.refreshCart();
    if (!mounted) return;
    final groupId =
        result.dataMap['checkout_group_id'] ??
        result.dataMap['group_id'] ??
        result.dataMap['id'];
    if (groupId != null && '$groupId'.isNotEmpty) {
      context.go('/orders/$groupId');
    } else {
      context.go('/orders');
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(app.t('order_placed_ok'))));
  }

  Widget _thumb(Map<String, dynamic> item, AppController app) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 44,
        child: AppImage(
          J.str(item['image'] ?? item['image_url']),
          placeholder: app.placeholder,
        ),
      ),
    );
  }

  Widget _payTile({
    required AppController app,
    required IconData icon,
    required String label,
    required String value,
    required String group,
    required bool enabled,
    required ValueChanged<String> onTap,
  }) {
    final active = group == value;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? () => onTap(value) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active
                    ? app.accentColor
                    : Colors.grey.withValues(alpha: 0.3),
                width: active ? 1.6 : 1,
              ),
              color: active
                  ? app.accentColor.withValues(alpha: 0.07)
                  : Colors.transparent,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: active ? app.accentColor : Colors.grey.shade600,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(
                  active
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: active ? app.accentColor : Colors.grey.shade500,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
