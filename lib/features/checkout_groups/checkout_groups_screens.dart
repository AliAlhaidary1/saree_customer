import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_controller.dart';
import '../../core/json_util.dart';
import '../../core/promo_price.dart';
import '../../widgets/requires_internet_dialog.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/ui_helpers.dart';

class CheckoutGroupsScreen extends StatefulWidget {
  const CheckoutGroupsScreen({super.key});
  @override
  State<CheckoutGroupsScreen> createState() => _CheckoutGroupsScreenState();
}

class _CheckoutGroupsScreenState extends State<CheckoutGroupsScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  int page = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Local-first: last synchronized groups paint offline (saved status).
    final snap = appController.readAccountSnapshot('checkout_groups');
    if (snap is List && snap.isNotEmpty && mounted) {
      setState(() {
        items = J.maps(snap);
        loading = false;
      });
    } else {
      if (mounted) setState(() => loading = true);
    }
    final res = await appController.loadCheckoutGroups(page: page);
    if (!mounted) return;
    if (res.ok && appController.checkoutGroups.isNotEmpty) {
      await appController.cacheAccountSnapshot(
        'checkout_groups',
        appController.checkoutGroups,
      );
    }
    if (!mounted) return;
    setState(() {
      if (res.ok) items = appController.checkoutGroups;
      loading = false;
    });
    if (!res.ok && items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appController.t('not_synced_yet'))),
      );
    }
  }

  String _statusText(dynamic s) => J.str(s);
  @override
  Widget build(BuildContext context) {
    final app = appController;
    return Scaffold(
      appBar: AppBar(title: Text(app.t('checkout_groups'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? EmptyState(message: app.t('not_synced_yet'))
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final g = items[i];
                      final status = _statusText(
                        g['status'] ?? g['customer_status'],
                      );
                      return Card(
                        child: ListTile(
                          title: Text('${app.t('checkout_group')} #${g['id']}'),
                          subtitle: Text(
                            '$status • ${money(g['final_total'] ?? g['total'], app.currency, app.decimals)}',
                          ),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () =>
                              context.push('/checkout-groups/${g['id']}'),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class CheckoutGroupDetailsScreen extends StatefulWidget {
  const CheckoutGroupDetailsScreen({super.key, required this.id});
  final String id;
  @override
  State<CheckoutGroupDetailsScreen> createState() =>
      _CheckoutGroupDetailsScreenState();
}

class _CheckoutGroupDetailsScreenState
    extends State<CheckoutGroupDetailsScreen> {
  Map<String, dynamic>? group;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _servedFromCache = false;

  Future<void> _load() async {
    // Local-first: last synchronized group paints offline (saved status).
    final snap = appController.readAccountSnapshot(
      'checkout_group_${widget.id}',
    );
    if (snap is Map && group == null && mounted) {
      setState(() {
        group = J.map(snap);
        loading = false;
        _servedFromCache = true;
      });
    }
    final res = await appController.fetchCheckoutGroup(widget.id);
    if (!mounted) return;
    final next = res.dataMap.isNotEmpty ? res.dataMap : J.map(res.raw['data']);
    if (res.ok && next.isNotEmpty) {
      await appController.cacheAccountSnapshot(
        'checkout_group_${widget.id}',
        next,
      );
    }
    setState(() {
      if (res.ok && next.isNotEmpty) group = next;
      loading = false;
      _servedFromCache = !res.ok && group != null;
    });
  }

  Future<void> _cancel() async {
    // Parity with front: cancel requires a reason (cancelCheckoutGroup reason).
    final reasonC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(appController.t('cancel_order')),
        content: TextField(
          controller: reasonC,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: appController.t('write_cancel_reason'),
          ),
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
    if (ok != true || reasonC.text.trim().isEmpty) return;
    if (!await appController.hasInternetAccess()) {
      if (mounted) await showRequiresInternetDialog(context);
      return;
    }
    final res = await appController.cancelCheckoutGroup(
      widget.id,
      reason: reasonC.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.ok ? appController.t('order_cancelled') : res.message,
        ),
      ),
    );
    if (res.ok) {
      await _load();
      if (mounted) context.pop();
    }
  }

  Future<void> _returnItem(dynamic itemId) async {
    final reasonC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(appController.t('return')),
        content: TextField(
          controller: reasonC,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: appController.t('write_return_reason'),
          ),
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
    if (ok != true || reasonC.text.trim().isEmpty) return;
    if (!await appController.hasInternetAccess()) {
      if (mounted) await showRequiresInternetDialog(context);
      return;
    }
    final res = await appController.api.requestCommerceReturn(
      itemId,
      reason: reasonC.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(res.message)));
    if (res.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('${appController.t('checkout_group')} #${widget.id}'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (group == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('${appController.t('checkout_group')} #${widget.id}'),
        ),
        body: EmptyState(
          message: appController.t('not_synced_yet'),
          actionLabel: appController.t('retry'),
          onAction: () {
            setState(() => loading = true);
            _load();
          },
        ),
      );
    }
    final app = appController;
    final orders = J.maps(group?['seller_orders'] ?? group?['orders']);
    final canCancel =
        group?['can_cancel'] == true ||
        group?['can_cancel'] == 1 ||
        group?['can_cancel'] == '1';
    final cancelReason = J.str(group?['cancel_blocked_reason']);
    final trackingOn = app.orderTrackingEnabled;
    return Scaffold(
      appBar: AppBar(
        title: Text('${app.t('checkout_group')} #${widget.id}'),
        actions: [
          if (canCancel)
            IconButton(
              icon: const Icon(Icons.cancel_outlined),
              tooltip: app.t('cancel_order'),
              onPressed: _cancel,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_servedFromCache) const SavedStatusChip(),
          ListTile(
            title: Text(app.t('status')),
            subtitle: Text(
              J.str(group?['status'] ?? group?['customer_status']),
            ),
          ),
          ListTile(
            title: Text(app.t('total')),
            subtitle: Text(
              money(
                group?['final_total'] ?? group?['total'],
                app.currency,
                app.decimals,
              ),
            ),
          ),
          if (trackingOn)
            ListTile(
              title: Text(app.t('track_order')),
              subtitle: Text(
                J.str(
                  group?['tracking_status'] ?? group?['delivery_status'] ?? '—',
                ),
              ),
            ),
          if (!canCancel && cancelReason.isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(app.t('cancel_not_available')),
                subtitle: Text(cancelReason),
              ),
            ),
          const Divider(),
          ...orders.expand(
            (o) => [
              Card(
                child: ListTile(
                  title: Text(
                    '${app.t('order')} ${o['id']} - ${J.str(o['store_name'])}',
                  ),
                  subtitle: Text(
                    '${J.maps(o['items']).length} ${app.t('products')}',
                  ),
                  trailing: Text(
                    money(
                      o['total'] ?? o['final_total'],
                      app.currency,
                      app.decimals,
                    ),
                  ),
                ),
              ),
              ...J
                  .maps(o['items'])
                  .map(
                    (it) => ListTile(
                      dense: true,
                      title: Text(J.str(it['name'] ?? it['product_name'])),
                      subtitle: Text('x${it['quantity']}'),
                      trailing: J.flag(it['can_return'])
                          ? TextButton(
                              onPressed: () => _returnItem(it['id']),
                              child: Text(appController.t('return')),
                            )
                          : null,
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 12),
          if (canCancel)
            OutlinedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.cancel_outlined),
              label: Text(appController.t('cancel_order')),
            ),
        ],
      ),
    );
  }
}
