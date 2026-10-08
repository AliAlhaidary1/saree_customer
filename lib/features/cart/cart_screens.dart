import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_controller.dart';
import '../../core/business_hours.dart';
import '../../core/json_util.dart';
import '../../core/promo_price.dart';
import '../../widgets/app_image.dart';
import '../../widgets/ui_helpers.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool loading = true;
  String? error;

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
    // Without this guard any failure leaves the spinner on screen forever
    // and the user has to kill the app.
    if (!silent && mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      await appController
          .refreshCart()
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() => error = null);
    } catch (_) {
      if (!mounted) return;
      // Show cached lines if we have them; only block an empty cart
      // with a retryable error instead of a frozen spinner.
      if (lines.isEmpty) {
        setState(
          () => error = appController.t('cart_load_failed'),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> get lines => appController.isLoggedIn
      ? appController.cartProducts
      : appController.guestCart;

  bool _lineOutOfStock(Map<String, dynamic> e) {
    final unlimited = J.i(e['is_unlimited_stock']) == 1 ||
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
        app.promoCode?['discount'] ?? cartMap?['promo_discount']);
    return Column(
      children: [
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
                    style: const TextStyle(fontSize: 12)),
                const Spacer(),
                Text(
                    app
                        .t('max_sellers_limit')
                        .replaceAll('{max}', '${app.maxSellersPerCheckout}'),
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(silent: true),
            child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: lines.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final item = lines[i];
              final qty = J.i(item['qty'] ?? item['quantity'], 1);
              final name = J.str(item['name'] ?? item['product_name']);
              final image = J.str(item['image_url'] ?? item['image']);
              final price = variantDisplayPrice(item);
              final outOfStock = _lineOutOfStock(item);
              final unit = [
                J.str(item['measurement']),
                J.str(item['stock_unit_name'] ?? item['unit']),
              ].where((e) => e.isNotEmpty).join(' ');
              final stock = J.i(
                item['stock'] ?? item['total_stock'] ?? -1,
                -1,
              );
              final allowed = J.i(item['total_allowed_quantity'], 0);
              final unlimited = J.i(item['is_unlimited_stock']) == 1 ||
                  J.str(item['stock_status']).toLowerCase() == 'unlimited';
              final maxQty = unlimited
                  ? 99
                  : (allowed > 0 ? allowed : (stock >= 0 ? stock : 99));
              return ListTile(
                tileColor: outOfStock ? Colors.red.withValues(alpha: 0.05) : Colors.white,
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
                    if (unit.isNotEmpty)
                      Text(unit,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    Text(
                      '${money(price.finalPrice, app.currency, app.decimals)} × $qty = ${money(price.finalPrice * qty, app.currency, app.decimals)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (outOfStock)
                      Text(app.t('OutOfStock'),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.red)),
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
                                      item['product_variant_id'] ?? item['id'],
                                )
                                .then((_) {
                                  if (mounted) setState(() {});
                                })
                          : () => app
                                .addToCart(
                                  productId: item['product_id'] ?? item['id'],
                                  variantId:
                                      item['product_variant_id'] ?? item['id'],
                                  qty: qty - 1,
                                  sellerId:
                                      item['seller_id'] ?? J.sellerId(item),
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
                                  content: Text(app
                                      .t('limited_product_stock_error')
                                      .replaceAll('{max}', '$maxQty')),
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
                              );
                              if (!context.mounted) return;
                              if (err != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(err)),
                                );
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
                          .then((_) {
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
                        context.push('/login?next=${Uri.encodeComponent('/checkout')}');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(app.t('please_login_continue')),
                          ),
                        );
                        return;
                      }
                      // Parity with front Cart.js stockValidation: block zero-stock checkout.
                      final outOfStock = lines.where((e) {
                        final unlimited = J.i(e['is_unlimited_stock']) == 1 ||
                            J.str(e['stock_status']).toLowerCase() == 'unlimited';
                        if (unlimited) return false;
                        final stock = J.i(
                          e['stock'] ?? e['total_stock'] ?? e['total_allowed_quantity'] ?? -1,
                          -1,
                        );
                        if (stock == 0) return true;
                        final status = J.str(e['status'] ?? e['stock_status']).toLowerCase();
                        return status == 'out_of_stock' || status == '0';
                      }).toList();
                      if (outOfStock.isNotEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(app.t('some_items_are_out_of_stock'))),
                        );
                        return;
                      }
                      // stock / seller limit guard like front
                      if (app.distinctCartSellerCount > app.maxSellersPerCheckout) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(app.t('max_stores_exceeded').replaceAll('{max}', '${app.maxSellersPerCheckout}'))),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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
        if (!result.ok && (checkout == null || checkout!.isEmpty)) {
          loadError = result.message.isNotEmpty
              ? result.message
              : appController.t('checkout_load_failed');
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => loadError = appController.t('checkout_load_failed'),
      );
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
    if (loadingCheckout) return Scaffold(appBar: AppBar(title: Text(app.t('checkout'))), body: const Center(child: CircularProgressIndicator()));
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
    final freeDelivery = J.str(
            deliveryNode is Map ? deliveryNode['is_free_delivery'] : null) ==
        '1';
    final discount = J.d(
      app.promoCode?['discount'] ?? checkout?['promo_discount'],
    );
    final platformFee = J.d(checkout?['platform_fee'] ?? app.platformFee);
    var finalTotal = J.d(
      checkout?['final_total'] ?? checkout?['total'],
      subTotal + delivery + platformFee - discount,
    );
    final wallet = J.d(
      app.user?['balance'] ??
          app.user?['wallet'] ??
          app.settings['user_balance'],
    );
    if (walletUsed) {
      finalTotal = (finalTotal - wallet).clamp(0, double.infinity);
      if (finalTotal == 0) method = 'Wallet';
    }
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
              decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withValues(alpha: 0.4))),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    '${app.t('minimum_order_amount_is').replaceAll('{amount}', money(app.minOrderAmount, app.currency, app.decimals))}',
                    style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                  )),
                ],
              ),
            ),
          if (app.minOrderAmount > 0 && subTotal < app.minOrderAmount) const SizedBox(height: 12),
          // Business hours banner parity with front BusinessHoursBanner
          if (bh != null && !canPlace.allowed)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.withValues(alpha: 0.3))),
              child: Row(
                children: [
                  const Icon(Icons.access_time, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    canPlace.reason == 'platform'
                        ? buildMarketplaceClosedMessage(canPlace.status)
                        : buildSellerClosedMessage(
                            canPlace.status,
                            canPlace.status?.storeName ?? '',
                          ),
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  )),
                ],
              ),
            ),
          if (bh != null && !canPlace.allowed) const SizedBox(height: 12),
          // seller groups like front
          if (sellerGroups.isNotEmpty)
            ...sellerGroups.map((g) => Card(
              child: ListTile(
                leading: const Icon(Icons.store),
                title: Text(J.str(g['store_name'] ?? g['seller_id'])),
                subtitle: Text('${J.maps(g['items']).length} منتجات'),
                trailing: Text(money(deliveryFees['${g['seller_id']}']?['amount'] ?? 0, app.currency, app.decimals)),
              ),
            )),
          ListTile(
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(app.t('deliver_to')),
            subtitle: Text(
              address == null
                  ? app.t('new_address')
                  : J.str(address['address'] ?? address['formatted_address']),
            ),
            trailing: const Icon(Icons.chevron_left),
            onTap: () async {
              await context.push('/addresses');
              setState(() {});
              await _load();
            },
          ),
          const SizedBox(height: 12),
          // time slots picker like front Checkout.js
          if (app.timeSlots.isNotEmpty) ...[
            Text(app.t('select_delivery_time'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 7,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, idx) {
                  final day = DateTime.now().add(Duration(days: idx));
                  final isSel = selectedDay != null && selectedDay!.day == day.day && selectedDay!.month == day.month;
                  return ChoiceChip(
                    label: Text('${day.day}/${day.month}'),
                    selected: isSel,
                    onSelected: (_) => setState(() {
                      selectedDay = day;
                      // rebuild deliveryTime
                      if (selectedSlot != null) deliveryTime = '${day.day}-${day.month}-${day.year} $selectedSlot';
                    }),
                  );
                },
              ),
            ),
            Wrap(
              spacing: 8,
              children: app.timeSlots.map((s) => ChoiceChip(
                label: Text(s.title),
                selected: selectedSlot == s.title,
                onSelected: (_) => setState(() {
                  selectedSlot = s.title;
                  if (selectedDay != null) deliveryTime = '${selectedDay!.day}-${selectedDay!.month}-${selectedDay!.year} $s.title';
                  else deliveryTime = s.title;
                }),
              )).toList(),
            ),
            const SizedBox(height: 12),
          ],
          ...items.map(
            (item) => ListTile(
              title: Text(J.str(item['name'] ?? item['product_name'])),
              trailing: Text('x${item['qty'] ?? item['quantity']}'),
            ),
          ),
          const Divider(),
          _row(app.t('sub_total'), money(subTotal, app.currency, app.decimals)),
          _row(
            '${app.t('delivery_charge')}${freeDelivery ? ' (${app.t('free_delivery')})' : ''}',
            money(delivery, app.currency, app.decimals),
          ),
          if (platformFee > 0)
            _row(app.t('platform_fee'),
                money(platformFee, app.currency, app.decimals)),
          if (discount > 0)
            _row(
              app.t('discount'),
              '- ${money(discount, app.currency, app.decimals)}',
            ),
          _row(
            app.t('total'),
            money(finalTotal, app.currency, app.decimals),
            bold: true,
          ),
          const SizedBox(height: 12),
          if (wallet > 0)
            SwitchListTile(
              title: Text(
                '${app.t('wallet')} (${money(wallet, app.currency, app.decimals)})',
              ),
              value: walletUsed,
              onChanged: (v) => setState(() => walletUsed = v),
            ),
          // Payment methods parity with front (9 gateways)
          if (codAllowed &&
              (_methodOn('cod_payment_method') || !_paymentConfigured()))
            RadioListTile(
              title: Text(app.t('cash_on_delivery')),
              value: 'COD',
              groupValue: method,
              onChanged: walletUsed && finalTotal == 0
                  ? null
                  : (v) => setState(() => method = '$v'),
            ),
          if (_methodOn('wallet_payment_method') || walletUsed)
            RadioListTile(
              title: Text(app.t('wallet')),
              value: 'Wallet',
              groupValue: method,
              onChanged: (v) => setState(() => method = '$v'),
            ),
          if (_methodOn('stripe_payment_method') || _methodOn('stripe'))
            RadioListTile(title: const Text('Stripe'), value: 'Stripe', groupValue: method, onChanged: (v) => setState(() => method = '$v')),
          if (_methodOn('paypal_payment_method') || _methodOn('paypal'))
            RadioListTile(title: const Text('PayPal'), value: 'Paypal', groupValue: method, onChanged: (v) => setState(() => method = '$v')),
          if (_methodOn('paystack_payment_method') || _methodOn('paystack'))
            RadioListTile(title: const Text('Paystack'), value: 'Paystack', groupValue: method, onChanged: (v) => setState(() => method = '$v')),
          if (_methodOn('razorpay_payment_method') || _methodOn('razorpay'))
            RadioListTile(title: const Text('Razorpay'), value: 'Razorpay', groupValue: method, onChanged: (v) => setState(() => method = '$v')),
          if (_methodOn('cashfree_payment_method'))
            RadioListTile(title: const Text('Cashfree'), value: 'Cashfree', groupValue: method, onChanged: (v) => setState(() => method = '$v')),
          if (_methodOn('midtrans_payment_method'))
            RadioListTile(title: const Text('Midtrans'), value: 'Midtrans', groupValue: method, onChanged: (v) => setState(() => method = '$v')),
          if (_methodOn('phonepe_payment_method') ||
              _methodOn('phonepay_payment_method'))
            RadioListTile(title: const Text('PhonePe'), value: 'Phonepe', groupValue: method, onChanged: (v) => setState(() => method = '$v')),
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
                              content: Text(error ??
                                  app.t('promo_applied'))),
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
                child: Text('${app.t('delivery_time')}: $deliveryTime',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey))),
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
                canPlace.reason == 'platform' ? buildMarketplaceClosedMessage(canPlace.status) : buildSellerClosedMessage(canPlace.status, ''),
                style: const TextStyle(color: Colors.red),
              ),
            ),
          FilledButton(
            onPressed: placing || !canPlace.allowed || (app.minOrderAmount > 0 && subTotal < app.minOrderAmount)
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
                            ? app.t('pay_via_gateway').replaceAll('{method}', method)
                            : app.t('place_order'),
                  ),
          ),
        ],
      ),
    );
  }

  bool _isGateway(String m) => ['Stripe','Paypal','Paystack','Razorpay','Cashfree','Midtrans','Phonepe'].contains(m);

  Future<void> _placeOrder(
    AppController app,
    List<Map<String, dynamic>> items,
    double subTotal,
    double delivery,
    double finalTotal,
    double wallet,
    Map<String, dynamic> address,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.t('confirm_order')),
        content: Text('${money(finalTotal, app.currency, app.decimals)}\n${deliveryTime ?? ''}\n$method'),
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
    final idempotencyKey = app.buildIdempotencyKey();
    final payMethod = (walletUsed && finalTotal == 0) ? 'Wallet' : method;
    // try multi-seller first if groups >1 like front placeMultiSellerOrder
    ApiResult result;
    if (app.sellerGroups.length > 1) {
      result = await app.api.placeMultiSellerOrder({
        'address_id': address['id'],
        'payment_method': payMethod,
        'use_wallet': walletUsed ? '1' : '0',
        if (deliveryTime != null && deliveryTime!.isNotEmpty) 'delivery_time': deliveryTime,
        if (note.text.trim().isNotEmpty) 'order_note': note.text.trim(),
        if (app.promoCode != null) 'promocode_id': app.promoCode?['id'] ?? app.promoCode?['promo_code_id'],
        'idempotency_key': idempotencyKey,
        'latitude': address['latitude'] ?? app.browseCoords.latitude,
        'longitude': address['longitude'] ?? app.browseCoords.longitude,
      });
    } else {
      result = await app.api.checkout(
        addressId: address['id'],
        paymentMethod: payMethod,
        useWallet: walletUsed,
        promocodeId: app.promoCode?['id'] ?? app.promoCode?['promo_code_id'],
        deliveryTime: deliveryTime ?? 'N/A',
        orderNote: note.text.trim(),
        idempotencyKey: idempotencyKey,
      );
    }
    if (!mounted) return;
    if (!result.ok) {
      setState(() => placing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
      return;
    }
    // gateway handling like front initiate_transaction
    if (_isGateway(payMethod)) {
      final checkoutGroupId = result.dataMap['checkout_group_id'] ?? result.dataMap['id'] ?? result.dataMap['group_id'];
      if (checkoutGroupId != null) {
        final init = await app.api.initiateTransactionForCheckoutGroup(checkoutGroupId: checkoutGroupId, paymentMethod: payMethod);
        if (!mounted) return;
        if (!init.ok) {
          setState(() => placing = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(init.message)));
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
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(url)));
          }
        }
      }
    }
    setState(() => placing = false);
    app.clearPromo();
    await app.refreshCart();
    if (!mounted) return;
    final groupId = result.dataMap['checkout_group_id'] ??
        result.dataMap['group_id'] ??
        result.dataMap['id'];
    if (groupId != null && '$groupId'.isNotEmpty) {
      context.go('/orders/$groupId');
    } else {
      context.go('/orders');
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(app.t('order_placed_ok'))));
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
