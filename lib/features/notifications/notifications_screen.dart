import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_controller.dart';
import '../../core/json_util.dart';
import '../../core/notification_read.dart';
import '../../widgets/ui_helpers.dart';

/// Parity with front Notification.js + notificationRead.js + Header polling:
/// - paginated list (limit 10) with total
/// - viewed page marked as read after 1200ms
/// - unread dot for unseen items
/// - pull to refresh + load more
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  int offset = 0;
  int total = 0;
  List<String> readIds = [];
  static const _limit = 10;
  Timer? _markTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _markTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (!appController.isLoggedIn) {
      if (mounted) setState(() => loading = false);
      return;
    }
    if (!more && mounted) setState(() => loading = true);
    final nextOffset = more ? offset + _limit : 0;
    final res = await appController.api.notifications(limit: _limit, offset: nextOffset);
    final uid = appController.user?['id'];
    var rows = res.dataMaps;
    var serverTotal = J.i(res.raw['total'] ?? res.dataMap['total']);
    // Backend may nest as {data:{data:[], total}} — handle both.
    final dataNode = res.raw['data'];
    if (rows.isEmpty && dataNode is Map) {
      rows = J.maps(dataNode['data']);
      serverTotal = J.i(dataNode['total'] ?? serverTotal);
    }
    var reads = await NotificationRead.getReadIds(uid);
    reads = await NotificationRead.prune(uid, serverTotal > 0 ? serverTotal : reads.length);
    if (!mounted) return;
    setState(() {
      offset = nextOffset;
      items = more ? [...items, ...rows] : rows;
      total = serverTotal > 0 ? serverTotal : items.length;
      readIds = reads;
      loading = false;
    });
    // Front marks the viewed page as read after 1200ms.
    _markTimer?.cancel();
    _markTimer = Timer(const Duration(milliseconds: 1200), () async {
      final ids = items.map((e) => '${e['id']}').where((e) => e.isNotEmpty).toList();
      final updated = await NotificationRead.markAsRead(uid, ids);
      if (mounted) setState(() => readIds = updated);
    });
  }

  bool _isUnread(Map<String, dynamic> item) {
    final id = '${item['id']}';
    if (id.isEmpty) return false;
    return !readIds.contains(id);
  }

  /// Maps backend/web deep links to flutter routes (parity with web links
  /// like /profile/orders, /faq, /policy/*). Unknown links fall back safely.
  void _openLink(BuildContext context, String link) {
    final raw = link.trim();
    if (raw.isEmpty) return;
    const map = {
      '/profile/orders': '/orders',
      '/profile/address': '/addresses',
      '/profile/wishlist': '/wishlist',
      '/profile/wallet-transaction': '/wallet',
      '/profile/wallet': '/wallet',
      '/profile': '/account',
      '/faq': '/faq',
      '/login': '/login',
      '/register': '/register',
      '/register/customer': '/register',
      '/register/seller': '/register',
      '/register/delivery': '/register',
      '/favorites': '/wishlist',
      '/orders': '/orders',
      '/addresses': '/addresses',
      '/wallet': '/wallet',
      '/cart': '/cart',
      '/checkout': '/checkout',
      '/products': '/products',
      '/sellers': '/sellers',
      '/haraj': '/haraj',
      '/akhdimni': '/akhdimni',
      '/notifications': '/notifications',
      '/notification': '/notifications',
      '/assistant': '/assistant',
    };
    if (map.containsKey(raw)) {
      context.push(map[raw]!);
      return;
    }
    if (raw.startsWith('/policy/') ||
        raw.startsWith('/product/') ||
        raw.startsWith('/orders/') ||
        raw.startsWith('/seller/') ||
        raw.startsWith('/store/') ||
        raw.startsWith('/haraj/') ||
        raw.startsWith('/akhdimni/') ||
        raw.startsWith('/category/') ||
        raw.startsWith('/checkout-groups/')) {
      context.push(raw);
      return;
    }
    if (raw.startsWith('/store/')) {
      context.push('/store/${raw.substring('/store/'.length)}');
      return;
    }
    if (raw.startsWith('http')) return;
    context.push('/notifications');
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    if (!app.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(app.t('notification'))),
        body: const LoginRequired(),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(app.t('notification'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(),
              child: items.isEmpty
                  ? ListView(children: [EmptyState(message: app.t('no_notifications'))])
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: items.length + (total > items.length ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        if (i >= items.length) {
                          return OutlinedButton(
                            onPressed: () => _load(more: true),
                            child: Text(app.t('load_more')),
                          );
                        }
                        final item = items[i];
                        final unread = _isUnread(item);
                        final link = J.str(item['link_url'] ?? item['link']);
                        return Card(
                          child: ListTile(
                            leading: unread
                                ? Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: Colors.orange,
                                      shape: BoxShape.circle,
                                    ),
                                  )
                                : null,
                            title: Text(
                              J.str(item['title'] ?? item['message'] ?? item['id']),
                              style: TextStyle(
                                fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(J.str(
                              item['message'] != null && item['title'] != null
                                  ? item['message']
                                  : (item['date'] ?? item['created_at'] ?? item['type']),
                            )),
                            trailing: Text(J.str(item['amount'] ?? item['latest_message'] ?? '')),
                            onTap: link.isNotEmpty
                                ? () => _openLink(context, link)
                                : null,
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

/// Parity with front Header bell: unread = total - read, badge 99+, poll every 60s.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int unread = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!appController.isLoggedIn) {
      if (mounted) setState(() => unread = 0);
      return;
    }
    try {
      final res = await appController.api.notifications(limit: 1, offset: 0);
      var total = J.i(res.raw['total'] ?? res.dataMap['total']);
      final dataNode = res.raw['data'];
      if (total == 0 && dataNode is Map) total = J.i(dataNode['total']);
      final uid = appController.user?['id'];
      var reads = await NotificationRead.getReadIds(uid);
      reads = await NotificationRead.prune(uid, total);
      if (!mounted) return;
      setState(() => unread = NotificationRead.computeUnreadCount(total, reads));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () async {
        await context.push('/notifications');
        _refresh();
      },
      icon: Badge(
        isLabelVisible: unread > 0,
        backgroundColor: Colors.orange,
        label: Text(
          unread > 99 ? '99+' : '$unread',
          style: const TextStyle(fontSize: 10, color: Colors.white),
        ),
        child: const Icon(Icons.notifications_outlined, color: Colors.white),
      ),
    );
  }
}
