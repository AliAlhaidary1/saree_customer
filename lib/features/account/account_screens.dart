import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/app_controller.dart';
import '../../core/city_mode.dart';
import '../../core/json_util.dart';
import '../../core/order_status.dart';
import '../../core/promo_price.dart';
import '../../widgets/app_image.dart';
import '../../widgets/product_variant_sheet.dart';
import '../../core/app_theme.dart';
import '../../widgets/dynamic_address_fields.dart';
import '../../widgets/order_tracker.dart';
import '../../widgets/ui_helpers.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = appController;
    if (!app.isLoggedIn) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          FilledButton(
            onPressed: () => context.push('/login'),
            child: Text(app.t('login')),
          ),
          const SizedBox(height: 16),
          _cmsTile(
            context,
            Icons.privacy_tip_outlined,
            app.t('privacy_policy'),
            '/privacy',
          ),
          _cmsTile(
            context,
            Icons.article_outlined,
            app.t('terms_of_service'),
            '/terms',
          ),
          _cmsTile(context, Icons.info_outline, app.t('about_us'), '/about'),
          _cmsTile(
            context,
            Icons.mail_outline,
            app.t('contact_us'),
            '/contact',
          ),
          _cmsTile(
            context,
            Icons.chat_bubble_outline,
            app.t('assistant_title'),
            '/assistant',
          ),
        ],
      );
    }
    final name = J.str(app.user?['name']);
    final mobile = J.str(app.user?['mobile']);
    return ListView(
      children: [
        const SizedBox(height: 12),
        ListTile(
          leading: CircleAvatar(
            backgroundColor: app.accentColor,
            child: Text(name.isEmpty ? 'م' : name.substring(0, 1)),
          ),
          title: Text(name),
          subtitle: Text(mobile),
        ),
        _tile(context, Icons.receipt_long, app.t('orders'), '/orders'),
        _tile(context, Icons.favorite, app.t('wishlist'), '/wishlist'),
        _tile(context, Icons.location_on, app.t('myAddress'), '/addresses'),
        _tile(
          context,
          Icons.notifications,
          app.t('notification'),
          '/notifications',
        ),
        _tile(
          context,
          Icons.account_balance_wallet,
          app.t('wallet'),
          '/wallet',
        ),
        _tile(
          context,
          Icons.swap_horiz,
          app.t('transactions'),
          '/transactions',
        ),
        _tile(context, Icons.campaign, app.t('haraj_my_posts'), '/haraj/mine'),
        if (app.akhdimniEnabled)
          _tile(context, Icons.delivery_dining, app.t('akhdimni_my_orders'),
              '/akhdimni/orders'),
        _tile(context, Icons.person, app.t('editProfile'), '/profile'),
        _tile(
          context,
          Icons.lock_outline,
          app.t('change_password'),
          '/change-password',
        ),
        const Divider(),
        _cmsTile(
          context,
          Icons.privacy_tip_outlined,
          app.t('privacy_policy'),
          '/privacy',
        ),
        _cmsTile(
          context,
          Icons.article_outlined,
          app.t('terms_of_service'),
          '/terms',
        ),
        _cmsTile(context, Icons.info_outline, app.t('about_us'), '/about'),
        _cmsTile(context, Icons.mail_outline, app.t('contact_us'), '/contact'),
        _cmsTile(
          context,
          Icons.chat_bubble_outline,
          app.t('assistant_title'),
          '/assistant',
        ),
        _tile(context, Icons.help_outline, app.t('faq'), '/faq'),
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(app.i18n.code == 'ar' ? 'English' : 'العربية'),
          onTap: () => app.setLanguage(app.i18n.code == 'ar' ? 'en' : 'ar'),
        ),
        if (kDebugMode)
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('عنوان الخادم'),
            subtitle: Text(app.apiUrl),
            onTap: () async {
              final controller = TextEditingController(text: app.apiUrl);
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('API URL'),
                  content: TextField(controller: controller),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(app.t('cancel')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(app.t('save_info')),
                    ),
                  ],
                ),
              );
              if (ok == true) await app.setApiUrl(controller.text);
            },
          ),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: Text(app.t('logout')),
          onTap: () async {
            final ok = await confirmAction(
              context,
              title: app.t('logout'),
              body: app.t('logout_confirm'),
            );
            if (!ok || !context.mounted) return;
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) =>
                  const Center(child: CircularProgressIndicator()),
            );
            await app.logout();
            if (context.mounted) {
              Navigator.of(context, rootNavigator: true).pop();
              context.go('/');
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.devices_outlined, color: Colors.red),
          title: Text(app.t('logout_all_devices')),
          onTap: () async {
            final ok = await confirmAction(
              context,
              title: app.t('logout_all_devices'),
              body: app.t('logout_all_devices_message'),
            );
            if (!ok || !context.mounted) return;
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) =>
                  const Center(child: CircularProgressIndicator()),
            );
            final error = await app.logoutAllDevices();
            if (context.mounted) {
              Navigator.of(context, rootNavigator: true).pop();
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(error)),
                );
              } else {
                context.go('/');
              }
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_forever, color: Colors.red),
          title: Text(app.t('delete_account')),
          onTap: () => _confirmDelete(context),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, String path) {
    return ListTile(
      leading: Icon(icon, color: appController.accentColor),
      title: Text(title),
      trailing: const Icon(Icons.chevron_left),
      onTap: () => context.push(path),
    );
  }

  Widget _cmsTile(
    BuildContext context,
    IconData icon,
    String title,
    String path,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_left),
      onTap: () => context.push(path),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final app = appController;
    final confirmationController = TextEditingController();
    final passwordController = TextEditingController();
    bool hidePassword = true;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final valid =
              confirmationController.text.trim().toUpperCase() == 'DELETE';
          return AlertDialog(
            title: Text(app.t('delete_account')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(app.t('delete_user_message')),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmationController,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                    LengthLimitingTextInputFormatter(6),
                  ],
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'DELETE',
                    hintText: 'DELETE',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordController,
                  obscureText: hidePassword,
                  decoration: InputDecoration(
                    labelText: app.t('password'),
                    suffixIcon: IconButton(
                      onPressed: () => setDialogState(
                        () => hidePassword = !hidePassword,
                      ),
                      icon: Icon(
                        hidePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(app.t('cancel')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: valid ? () => Navigator.pop(ctx, true) : null,
                child: Text(app.t('delete_account')),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || !context.mounted) return;
    final error = await app.deleteAccount(
      confirmation: confirmationController.text.trim().toUpperCase(),
      password: passwordController.text.trim().isEmpty
          ? null
          : passwordController.text.trim(),
    );
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(app.t('account_deleted_success'))),
    );
    context.go('/');
  }
}

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late final tab = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> active = [];
  List<Map<String, dynamic>> previous = [];
  bool loading = true;
  int page = 1;
  int totalActive = 0;
  static const _perPage = 10;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    tab.dispose();
    super.dispose();
  }

  /// Parity with front Order.jsx fetchOrders: legacy active + legacy prev +
  /// checkout-groups, then mergeOrders + sort by created_at desc.
  Future<void> _load({bool more = false}) async {
    if (!appController.isLoggedIn) {
      if (mounted) setState(() => loading = false);
      return;
    }
    if (!more && mounted) setState(() => loading = true);
    final nextPage = more ? page + 1 : 1;
    final offset = (nextPage - 1) * _perPage;
    final legacyActive = await appController.api.orders(type: 1, limit: _perPage, offset: offset);
    final legacyPrev = await appController.api.orders(type: 0, limit: _perPage, offset: offset);
    final groups = await appController.api.checkoutGroups(page: nextPage);
    if (!mounted) return;
    final legacyActiveParsed = parseOrdersPayload(legacyActive);
    final legacyPrevParsed = parseOrdersPayload(legacyPrev);
    final groupsParsed = parseCheckoutGroupsPayload(groups);
    final freshActive = mergeOrders(legacyActiveParsed.rows, groupsParsed.rows, true);
    final freshPrev = mergeOrders(legacyPrevParsed.rows, groupsParsed.rows, false);
    setState(() {
      page = nextPage;
      active = more ? [...active, ...freshActive] : freshActive;
      previous = more ? [...previous, ...freshPrev] : freshPrev;
      totalActive = legacyActiveParsed.total + groupsParsed.total;
      loading = false;
    });
  }

  String _statusLabel(Map<String, dynamic> order) {
    if (order['is_checkout_group'] == true) {
      final d = storeDisplayFromGroupStatus(order['customer_status']);
      return appController.t(d.key);
    }
    final d = storeDisplayFromLegacy(order['active_status']);
    final name = J.str(order['status_name']);
    if (name.isNotEmpty && name != '${order['active_status']}') return name;
    return appController.t(d.key);
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    if (!app.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(app.t('orders'))),
        body: const LoginRequired(),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(app.t('orders')),
        bottom: TabBar(
          controller: tab,
          tabs: [
            Tab(text: app.t('active_orders')),
            Tab(text: app.t('previous_orders')),
          ],
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: tab,
              children: [_list(active, true), _list(previous, false)],
            ),
    );
  }

  Widget _list(List<Map<String, dynamic>> items, bool isActiveTab) {
    if (items.isEmpty) return Center(child: Text(appController.t('no_order')));
    final canMore = isActiveTab && totalActive > items.length;
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length + (canMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          if (i >= items.length) {
            return OutlinedButton(
              onPressed: () => _load(more: true),
              child: Text(appController.t('load_more')),
            );
          }
          final order = items[i];
          final isGroup = order['is_checkout_group'] == true;
          return ListTile(
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text('${appController.t('id')}${order['id'] ?? order['order_id']}'),
            subtitle: Text(
              '${_statusLabel(order)} • ${money(order['final_total'] ?? order['total'], appController.currency, appController.decimals)}',
            ),
            trailing: isGroup ? const Icon(Icons.inventory_2_outlined) : null,
            onTap: () => context.push('/orders/${order['id'] ?? order['order_id']}'),
          );
        },
      ),
    );
  }
}

class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({super.key, required this.id});
  final String id;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  Map<String, dynamic>? order;
  bool loading = true;
  bool cancellingGroup = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Parity with front fetchOrderDetails: try checkout-group first, fallback legacy.
  Future<void> _load() async {
    try {
      final cg = await appController.api.checkoutGroup(widget.id);
      if (cg.ok && cg.dataMap.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          order = mapCheckoutGroupToOrder(cg.dataMap);
          loading = false;
        });
        return;
      }
    } catch (_) {}
    final result = await appController.api.orders(orderId: widget.id);
    if (!mounted) return;
    setState(() {
      order = result.dataMaps.isNotEmpty ? result.dataMaps.first : result.dataMap;
      loading = false;
    });
  }

  bool get _isGroup => order?['is_checkout_group'] == true;
  bool get _canCancelGroup {
    final v = order?['can_cancel'];
    return v == true || v == 1 || v == '1';
  }

  bool _canReturnItem(Map<String, dynamic> item) {
    if (_isGroup) return J.flag(item['can_return']);
    return J.i(item['active_status']) == 6 &&
        J.i(item['return_status']) == 1 &&
        item['return_requested'] == null;
  }

  bool _canCancelItem(Map<String, dynamic> item) {
    if (_isGroup) return false;
    return J.i(item['active_status']) <= 6 &&
        J.i(item['active_status']) <= J.i(item['till_status']) &&
        J.i(item['cancelable_status']) == 1;
  }

  Future<String?> _askReason(String title, String hint) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          maxLines: 4,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(appController.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(appController.t('confirm')),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    return c.text.trim();
  }

  Future<void> _cancelGroup() async {
    final reason = await _askReason(
      appController.t('cancel_order'),
      appController.t('write_cancel_reason'),
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    setState(() => cancellingGroup = true);
    final res = await appController.api.cancelCheckoutGroup(widget.id, reason: reason);
    if (!mounted) return;
    setState(() => cancellingGroup = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res.ok ? appController.t('order_cancelled') : res.message)),
    );
    if (res.ok) _load();
  }

  Future<void> _cancelItem(Map<String, dynamic> item) async {
    final reason = await _askReason(
      appController.t('cancel_order'),
      appController.t('write_cancel_reason'),
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    if (_isGroup) {
      await _cancelGroupWithReason(reason);
      return;
    }
    final res = await appController.api.updateOrderItemStatus(
      orderId: order?['id'] ?? widget.id,
      orderItemId: item['id'],
      status: 7,
      reason: reason,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res.ok ? appController.t('OrderItemCancelledSuccessfully') : res.message)),
    );
    if (res.ok) _load();
  }

  Future<void> _cancelGroupWithReason(String reason) async {
    setState(() => cancellingGroup = true);
    final res = await appController.api.cancelCheckoutGroup(widget.id, reason: reason);
    if (!mounted) return;
    setState(() => cancellingGroup = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res.ok ? appController.t('order_cancelled') : res.message)),
    );
    if (res.ok) _load();
  }

  Future<void> _returnItem(Map<String, dynamic> item) async {
    final reason = await _askReason(
      appController.t('return'),
      appController.t('write_return_reason'),
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    ApiResult res;
    if (_isGroup) {
      res = await appController.api.requestCommerceReturn(item['id'], reason: reason);
    } else {
      res = await appController.api.updateOrderItemStatus(
        orderId: order?['id'] ?? widget.id,
        orderItemId: item['id'],
        status: 8,
        reason: reason,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res.ok ? res.message : res.message)),
    );
    if (res.ok) _load();
  }

  Future<void> _invoice() async {
    final id = order?['id'] ?? widget.id;
    final (ok, bytes, _) = await appController.api.invoiceBytes(id);
    if (!mounted) return;
    if (!ok || bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appController.t('something_went_wrong'))),
      );
      return;
    }
    try {
      final dir = await _tempDir();
      final file = await _writeBytes('$dir/Invoice-No:$id.pdf', bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${appController.t('invoice_downloaded_successfully')}: $file')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appController.t('something_went_wrong'))),
      );
    }
  }

  Future<void> _rateProduct(Map<String, dynamic> item) async {
    final res = await _askRate(appController.t('rate_the_product'));
    if (res == null || !mounted) return;
    final result = await appController.api.addProductRating({
      'product_id': item['product_id'],
      'rate': res.stars,
      'review': res.review,
      'order_item_id': item['id'],
      'order_id': order?['id'] ?? widget.id,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.ok ? appController.t('rating_saved_successfully') : result.message)),
    );
    if (result.ok) _load();
  }

  Future<void> _rateSeller(dynamic sellerId, String name) async {
    final res = await _askRate('${appController.t('rate_seller')}: $name');
    if (res == null || !mounted) return;
    final result = await appController.api.rateSeller({
      'seller_id': sellerId,
      'rate': res.stars,
      'review': res.review,
      'order_id': order?['id'] ?? widget.id,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.ok ? appController.t('rating_saved_successfully') : result.message)),
    );
    if (result.ok) _load();
  }

  Future<void> _rateCourier(dynamic courierId, String name) async {
    final res = await _askRate('${appController.t('rate_courier')}: $name');
    if (res == null || !mounted) return;
    final result = await appController.api.rateDeliveryBoy({
      'delivery_boy_id': courierId,
      'rate': res.stars,
      'review': res.review,
      'order_id': order?['id'] ?? widget.id,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.ok ? appController.t('rating_saved_successfully') : result.message)),
    );
    if (result.ok) _load();
  }

  Future<({int stars, String review})?> _askRate(String title) async {
    int value = 5;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final idx = i + 1;
                  return IconButton(
                    icon: Icon(idx <= value ? Icons.star : Icons.star_border,
                        color: Colors.amber),
                    onPressed: () => setS(() => value = idx),
                  );
                }),
              ),
              TextField(
                controller: ctrl,
                maxLines: 3,
                decoration: InputDecoration(
                    hintText: appController.t('write_review')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(appController.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(appController.t('submit_rating')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return null;
    return (stars: value, review: ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    if (!app.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: Text('${app.t('order')} ${widget.id}')),
        body: const LoginRequired(),
      );
    }
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (order == null || order!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('${app.t('order')} ${widget.id}')),
        body: EmptyState(
          message: app.t('no_order'),
          actionLabel: app.t('retry'),
          onAction: () {
            setState(() => loading = true);
            _load();
          },
        ),
      );
    }
    final items = J.maps(order?['items'] ?? order?['order_items']);
    final activeStatus = J.str(order?['active_status'] ?? order?['status'] ?? '2');
    final isDelivered = J.i(activeStatus) == 6;
    final isReturned = J.i(activeStatus) == 8;
    final canGetInvoice = isDelivered ||
        isReturned ||
        items.any((e) =>
            J.i(e['active_status']) == 6 ||
            J.str(e['return_status']) == 'completed' ||
            J.str(e['return_status']) == 'approved');
    final sellers = _sellersToRate();
    final courierId = order?['delivery_boy_id'] ?? order?['courier_id'];
    final courierName = J.str(
        order?['delivery_boy_name'] ?? order?['courier_name']);
    final trackingOn = app.orderTrackingEnabled ||
        J.flag(order?['order_tracking_enabled']);
    final blocked = J.str(order?['cancel_blocked_reason']);
    final publicId = J.str(order?['public_id']).isNotEmpty
        ? J.str(order?['public_id'])
        : '${order?['id'] ?? widget.id}';
    return Scaffold(
      appBar: AppBar(
        title: Text('${app.t('order')} ${widget.id}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: app.t('copy_id'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: publicId));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(app.t('copied'))));
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OrderTracker(
            status: activeStatus,
            statusLabel: J.str(order?['status_name'] ?? _displayLabel(activeStatus)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              if (_isGroup && _canCancelGroup)
                OutlinedButton.icon(
                  onPressed: cancellingGroup ? null : _cancelGroup,
                  icon: const Icon(Icons.cancel_outlined),
                  label: Text(app.t('cancel_order')),
                ),
              if (canGetInvoice)
                FilledButton.icon(
                  onPressed: _invoice,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(app.t('get_invoice')),
                ),
            ],
          ),
          if (_isGroup && !_canCancelGroup && blocked.isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(app.t('cancel')),
                subtitle: Text(blocked),
              ),
            ),
          if (trackingOn)
            Card(
              child: ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text(app.t('track_order')),
                subtitle: Text(J.str(
                  order?['tracking_status'] ??
                      order?['delivery_status'] ??
                      order?['address_snapshot'] is Map
                          ? J.str((order?['address_snapshot'] as Map)['city'])
                          : '—',
                )),
              ),
            ),
          const SizedBox(height: 8),
          ...items.map((item) {
            final tone = storeDisplayFromLegacy(item['active_status']);
            return Card(
              child: ListTile(
                title: Text(J.str(item['product_name'] ?? item['name'])),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('x${item['quantity']} • ${J.str(item['seller_name'])}'),
                    Text(app.t(tone.key)),
                    if (J.str(item['return_status']) == 'requested' ||
                        J.str(item['return_status']) == 'approved')
                      Text(app.t('return_requested')),
                    if (J.str(item['return_status']) == 'rejected')
                      Text(app.t('return_rejected')),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (_canReturnItem(item))
                          TextButton.icon(
                            onPressed: () => _returnItem(item),
                            icon: const Icon(Icons.restart_alt_outlined, size: 16),
                            label: Text(app.t('return')),
                          ),
                        if (_canCancelItem(item))
                          TextButton.icon(
                            onPressed: () => _cancelItem(item),
                            icon: const Icon(Icons.close, size: 16),
                            label: Text(app.t('cancel')),
                          ),
                        if (isDelivered)
                          TextButton.icon(
                            onPressed: () => _rateProduct(item),
                            icon: const Icon(Icons.star_border, size: 16),
                            label: Text(app.t('rate')),
                          ),
                      ],
                    ),
                  ],
                ),
                trailing: Text(
                  money(item['sub_total'] ?? item['price'], app.currency, app.decimals),
                ),
              ),
            );
          }),
          if ((isDelivered || isReturned) && sellers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(app.t('order_ratings'), style: const TextStyle(fontWeight: FontWeight.bold)),
            ...sellers.map((s) => ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(J.str(s['seller_name'])),
                  trailing: TextButton(
                    onPressed: () => _rateSeller(s['seller_id'], J.str(s['seller_name'])),
                    child: Text(app.t('rate_seller')),
                  ),
                )),
          ],
          if ((isDelivered || isReturned) && courierId != null && '$courierId'.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.delivery_dining_outlined),
              title: Text(courierName.isNotEmpty
                  ? courierName
                  : app.t('courier_rating')),
              trailing: TextButton(
                onPressed: () => _rateCourier(
                    courierId,
                    courierName.isNotEmpty
                        ? courierName
                        : app.t('courier_rating')),
                child: Text(app.t('rate_courier')),
              ),
            ),
          const Divider(),
          if (J.map(order?['address_snapshot']).isNotEmpty)
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(app.t('delivery_information')),
              subtitle: Text([
                J.str(order?['order_address'] ??
                    [
                      J.str((order?['address_snapshot'] as Map)['address']),
                      J.str((order?['address_snapshot'] as Map)['area']),
                      J.str((order?['address_snapshot'] as Map)['city']),
                      J.str((order?['address_snapshot'] as Map)['country']),
                    ].where((e) => e.isNotEmpty).join('، ')),
                if (J.str(order?['mobile']).isNotEmpty)
                  J.str(order?['mobile']),
              ].where((e) => e.isNotEmpty).join('\n')),
            ),
          _billingCard(order, app),
        ],
      ),
    );
  }

  Widget _billingCard(Map<String, dynamic>? order, AppController app) {
    Widget row(String label, String value, {bool bold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      );
    }

    final refunded = J.d(order?['refunded_amount'] ?? order?['refund_amount']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(app.t('billing_details'),
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 6),
            if (J.str(order?['payment_method']).isNotEmpty)
              row(app.t('payment_method'), J.str(order?['payment_method'])),
            if (J.str(order?['transaction_id'] ?? order?['transaction']).isNotEmpty)
              row(app.t('transaction_id'),
                  J.str(order?['transaction_id'] ?? order?['transaction'])),
            if (order?['subtotal'] != null)
              row(app.t('sub_total'),
                  money(order?['subtotal'], app.currency, app.decimals)),
            if (order?['delivery_charge'] != null)
              row(app.t('delivery_charge'),
                  money(order?['delivery_charge'], app.currency, app.decimals)),
            if (J.d(order?['promo_discount']) > 0)
              row(app.t('promo_code_discount'),
                  '- ${money(order?['promo_discount'], app.currency, app.decimals)}'),
            if (J.d(order?['wallet_balance'] ?? order?['wallet_applied']) > 0)
              row(app.t('wallet_balance_used'),
                  '- ${money(order?['wallet_balance'] ?? order?['wallet_applied'], app.currency, app.decimals)}'),
            if (J.d(order?['discount']) > 0)
              row(app.t('discount'),
                  '- ${money(order?['discount'], app.currency, app.decimals)}'),
            if (refunded > 0)
              row(app.t('refunded'),
                  money(refunded, app.currency, app.decimals)),
            const Divider(),
            row(
              app.t('total'),
              money(order?['final_total'], app.currency, app.decimals),
              bold: true,
            ),
            if (J.str(order?['order_note'] ?? order?['note']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    '${app.t('order_note')}: ${J.str(order?['order_note'] ?? order?['note'])}',
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  String _displayLabel(String activeStatus) {
    final n = J.i(activeStatus);
    final app = appController;
    if (n == 7) return app.t('cancelled');
    if (n == 8) return app.t('returned');
    if (n == 6) return app.t('delivered');
    if (n == 5) return app.t('on_the_way');
    return app.t('preparing_status');
  }

  List<Map<String, dynamic>> _sellersToRate() {
    final fromApi = J.maps(order?['sellers_to_rate']);
    if (fromApi.isNotEmpty) return fromApi;
    final seen = <String, Map<String, dynamic>>{};
    for (final item in J.maps(order?['items'] ?? order?['order_items'])) {
      final sid = J.str(item['seller_id']);
      if (sid.isEmpty) continue;
      seen[sid] = {'seller_id': sid, 'seller_name': J.str(item['seller_name'])};
    }
    return seen.values.toList();
  }
}

Future<String> _tempDir() async {
  try {
    final dir = await getTemporaryDirectory();
    return dir.path;
  } catch (_) {
    return '.';
  }
}

Future<String> _writeBytes(String path, List<int> bytes) async {
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key});

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  @override
  void initState() {
    super.initState();
    appController.loadAddresses();
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    if (!app.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(app.t('myAddress'))),
        body: const LoginRequired(),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(app.t('myAddress'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (_, __) {
          if (app.addresses.isEmpty) {
            return EmptyState(
              icon: Icons.location_on_outlined,
              message: app.t('new_address'),
              actionLabel: app.t('new_address'),
              onAction: _edit,
            );
          }
          return ListView(
            children: app.addresses
                .map(
                  (address) => RadioListTile(
                    value: '${address['id']}',
                    groupValue: '${app.selectedAddress?['id']}',
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            J.str(address['type'] ?? address['name']),
                          ),
                        ),
                        if (J.str(address['is_default']) == '1')
                          Container(
                            margin: const EdgeInsetsDirectional.only(start: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: app.accentColor.withValues(alpha: 0.12),
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
                    subtitle: Text(
                      [
                        J.str(address['name']),
                        J.str(address['address']),
                        J.str(address['custom_fields_display']),
                        J.str(address['mobile']),
                      ].where((part) => part.isNotEmpty).join(' | '),
                    ),
                    onChanged: (_) {
                      app.selectAddress(address);
                      final next = cityFromAddress(address, app.cities);
                      if (next != null) app.selectCity(next);
                    },
                    secondary: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _edit(existing: address),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final ok = await confirmAction(
                              context,
                              title: app.t('delete_address_confirm'),
                            );
                            if (!ok) return;
                            await app.api.deleteAddress(address['id']);
                            await app.loadAddresses();
                          },
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }

  String _typeLabel(AppController app, String value) {
    switch (value) {
      case 'Office':
        return app.t('address_type_office');
      case 'Shop':
        return app.t('address_type_shop');
      case 'Other':
        return app.t('address_type_other');
      default:
        return app.t('adress_type_home');
    }
  }

  Future<void> _edit({Map<String, dynamic>? existing}) async {
    final app = appController;
    final name = TextEditingController(
      text: J.str(existing?['name'] ?? app.user?['name']),
    );
    final mobile = TextEditingController(
      text: J.str(existing?['mobile'] ?? app.user?['mobile']),
    );
    final address = TextEditingController(
      text: J.str(existing?['address']),
    );
    String addressType = J.str(existing?['type'], 'Home');
    const types = ['Home', 'Office', 'Shop', 'Other'];
    if (!types.contains(addressType)) addressType = 'Home';
    final city = app.city;
    final cityId = int.tryParse('${city?['id']}');
    List<Map<String, dynamic>> dynamicFields = [];
    Map<String, dynamic> customFields = {};
    if (cityId != null) {
      final configResult = await app.api.cityConfig(cityId: cityId);
      if (configResult.ok) {
        final config = J.map(configResult.dataMap['data']);
        final rawFields = config['address_fields'];
        if (rawFields is List) {
          dynamicFields = rawFields.map((item) => J.map(item)).toList();
        }
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              app.t(existing == null ? 'new_address' : 'edit_address'),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: InputDecoration(labelText: app.t('Name')),
                  ),
                  TextField(
                    controller: mobile,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: app.t('mobile')),
                  ),
                  DropdownButtonFormField<String>(
                    value: addressType,
                    decoration: InputDecoration(
                      labelText: app.t('address_type'),
                    ),
                    items: types
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(_typeLabel(app, t)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => addressType = v);
                    },
                  ),
                  TextField(
                    controller: address,
                    decoration: InputDecoration(labelText: app.t('address')),
                  ),
                  DynamicAddressFields(
                    fields: dynamicFields,
                    values: customFields,
                    onChanged: (values) {
                      customFields = values;
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(app.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(app.t('save_info')),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isEmpty ||
        mobile.text.trim().isEmpty ||
        address.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(app.t('fill_required_fields'))));
      return;
    }
    final fields = {
      'name': name.text.trim(),
      'mobile': mobile.text.trim(),
      'type': addressType,
      'address': address.text.trim(),
      'landmark': J.str(existing?['landmark']),
      'area': J.str(existing?['area'] ?? city?['name']),
      'pincode': J.str(existing?['pincode']),
      'city': J.str(city?['name']),
      'city_id': city?['id'],
      'state': J.str(existing?['state'] ?? city?['state']),
      'country': 'Yemen',
      'latitude': existing?['latitude'] ?? city?['latitude'],
      'longitude': existing?['longitude'] ?? city?['longitude'],
      'is_default': existing != null
          ? (J.str(existing['is_default']) == '1' ? 1 : 0)
          : (app.addresses.isEmpty ? 1 : 0),
      if (customFields.isNotEmpty) 'custom_fields': jsonEncode(customFields),
    };
    if (existing != null) {
      fields['id'] = existing['id'];
      await app.api.updateAddress(fields);
    } else {
      await app.api.addAddress(fields);
    }
    await app.loadAddresses();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(app.t('address_saved_ok'))),
      );
    }
  }
}

class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!appController.isLoggedIn) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final point = appController.coords ?? (latitude: 0.0, longitude: 0.0);
    final result = await appController.api.favorites(
      latitude: point.latitude,
      longitude: point.longitude,
    );
    if (!mounted) return;
    setState(() {
      items = result.dataMaps;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return Scaffold(
      appBar: AppBar(title: Text(app.t('wishlist'))),
      body: !app.isLoggedIn
          ? const LoginRequired()
          : loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? EmptyState(
              icon: Icons.favorite_border,
              message: app.t('wishlist'),
              actionLabel: app.t('shop_now'),
              onAction: () => context.go('/products'),
            )
          : ListView(
              children: items
                  .map(
                    (item) => ListTile(
                      leading: SizedBox(
                        width: 56,
                        child: AppImage(
                          J.str(item['image_url']),
                          placeholder: app.placeholder,
                        ),
                      ),
                      title: Text(J.str(item['name'])),
                      subtitle: Text(
                        money(
                          item['price'] ?? item['final_price'],
                          app.currency,
                          app.decimals,
                        ),
                        style: TextStyle(
                          color: app.accentColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onTap: () => context.push(
                        '/product/${item['slug'] ?? item['id']}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.add_shopping_cart),
                            tooltip: app.t('add_to_cart'),
                            onPressed: () => addProductFromCatalog(
                                context, item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await app.toggleFavorite(
                                item['id'] ?? item['product_id'],
                              );
                              if (mounted) _load();
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class SimpleListScreen extends StatefulWidget {
  const SimpleListScreen({
    super.key,
    required this.title,
    required this.loader,
    this.header,
    this.pageLoader,
    this.emptyMessage,
  });
  final String title;
  final Future<List<Map<String, dynamic>>> Function() loader;
  final Widget? header;
  final Future<List<Map<String, dynamic>>> Function(int limit, int offset)?
      pageLoader;
  final String? emptyMessage;

  @override
  State<SimpleListScreen> createState() => _SimpleListScreenState();
}

class _SimpleListScreenState extends State<SimpleListScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!appController.isLoggedIn) {
      if (mounted) setState(() => loading = false);
      return;
    }
    try {
      List<Map<String, dynamic>> value;
      if (widget.pageLoader != null) {
        value = await widget.pageLoader!(10, 0);
        hasMore = value.length >= 10;
      } else {
        value = await widget.loader();
      }
      if (!mounted) return;
      setState(() {
        items = value;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (widget.pageLoader == null || loadingMore || !hasMore) return;
    setState(() => loadingMore = true);
    try {
      final value = await widget.pageLoader!(10, items.length);
      if (!mounted) return;
      setState(() {
        items = [...items, ...value];
        hasMore = value.length >= 10;
        loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: !app.isLoggedIn
          ? const LoginRequired()
          : loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (widget.header != null) widget.header!,
                if (items.isEmpty)
                  EmptyState(
                    message: widget.emptyMessage ??
                        app.t('no_notifications'),
                  )
                else ...[
                  ...items
                      .map(
                    (item) => ListTile(
                      title: Text(
                        J.str(
                          item['title'] ??
                              item['message'] ??
                              item['txn_id'] ??
                              item['id'],
                        ),
                      ),
                      subtitle: Text(
                        J.str(
                          item['date'] ?? item['created_at'] ?? item['type'],
                        ),
                      ),
                      trailing: Text(
                        J.str(item['amount'] ?? item['latest_message'] ?? ''),
                      ),
                    ),
                  )
                      .toList(),
                  if (widget.pageLoader != null && hasMore)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Center(
                        child: loadingMore
                            ? const CircularProgressIndicator()
                            : OutlinedButton(
                                onPressed: _loadMore,
                                child: Text(app.t('load_more')),
                              ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final name = TextEditingController(
    text: J.str(appController.user?['name']),
  );
  late final email = TextEditingController(
    text: J.str(appController.user?['email']),
  );
  late final mobile = TextEditingController(
    text: J.str(appController.user?['mobile']),
  );
  XFile? pickedImage;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    mobile.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (file != null && mounted) setState(() => pickedImage = file);
    } catch (_) {}
  }

  Future<void> _save() async {
    final app = appController;
    if (name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(app.t('fill_required_fields'))),
      );
      return;
    }
    setState(() => saving = true);
    try {
      MultipartFile? profile;
      if (pickedImage != null) {
        final ext = pickedImage!.path.split('.').last.toLowerCase();
        if (!['png', 'jpg', 'jpeg'].contains(ext)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(app.t('file_type_not_allowed'))),
            );
          }
          return;
        }
        profile = await MultipartFile.fromFile(
          pickedImage!.path,
          filename: pickedImage!.name,
        );
      }
      final result = await app.api.editProfile(
        name: name.text.trim(),
        email: email.text.trim(),
        mobile: mobile.text.trim(),
        profile: profile,
      );
      if (result.ok) {
        await app.reloadSettings();
        final me = await app.api.userDetails();
        if (me.ok) {
          app.setUser(me.user.isNotEmpty ? me.user : me.dataMap);
        }
        if (mounted) setState(() => pickedImage = null);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message.isEmpty ? app.t('update') : result.message,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    if (!app.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(app.t('editProfile'))),
        body: const LoginRequired(),
      );
    }
    final currentProfile = J.str(app.user?['profile']);
    return Scaffold(
      appBar: AppBar(title: Text(app.t('editProfile'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: app.accentColor.withValues(alpha: 0.15),
                  backgroundImage: pickedImage != null
                      ? FileImage(File(pickedImage!.path))
                      : (currentProfile.isNotEmpty
                            ? NetworkImage(currentProfile)
                            : null),
                  child: pickedImage == null && currentProfile.isEmpty
                      ? Text(
                          name.text.isEmpty ? 'م' : name.text.substring(0, 1),
                          style: const TextStyle(fontSize: 32),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: InkWell(
                    onTap: _pickImage,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: app.accentColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _pickImage,
            child: Text(app.t('change_photo')),
          ),
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: app.t('Name')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: app.t('email')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: mobile,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: app.t('mobile')),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: saving ? null : _save,
            child: saving
                ? const BusySpinner()
                : Text(app.t('update')),
          ),
        ],
      ),
    );
  }
}

/// Admin-controlled wallet top-up info (refill limit + transfer instructions).
class WalletSettingsHeader extends StatelessWidget {
  const WalletSettingsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final hasLimit = app.walletRefillLimit > 0;
    final hasBank = app.walletBankName.isNotEmpty ||
        app.walletAccountHolder.isNotEmpty ||
        app.walletAccountNumber.isNotEmpty ||
        app.walletTransferInstructions.isNotEmpty;
    final balance = app.user?['balance'] ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        children: [
          Card(
            color: AppTheme.primaryNavy,
            child: ListTile(
              leading: const Icon(
                Icons.account_balance_wallet,
                color: Colors.white,
              ),
              title: Text(
                app.t('wallet'),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              subtitle: Text(
                money(balance, app.currency, app.decimals),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (hasLimit)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(app.t('wallet_refill_limit_hint')
                    .replaceAll('{amount}', '${app.currency} ${app.walletRefillLimit}')),
              ),
            ),
          if (hasBank)
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance),
                title: Text([
                  if (app.walletBankName.isNotEmpty) app.walletBankName,
                  if (app.walletAccountNumber.isNotEmpty) app.walletAccountNumber,
                ].join(' • ')),
                subtitle: Text([
                  if (app.walletAccountHolder.isNotEmpty) app.walletAccountHolder,
                  if (app.walletTransferInstructions.isNotEmpty) app.walletTransferInstructions,
                ].where((e) => e.isNotEmpty).join('\n')),
              ),
            ),
        ],
      ),
    );
  }
}
