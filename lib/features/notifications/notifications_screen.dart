import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_controller.dart';
import '../../core/json_util.dart';
import '../../core/notification_read.dart';
import '../../widgets/app_image.dart';
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
  bool loadingMore = false;
  int offset = 0;
  int total = 0;
  List<String> readIds = [];
  static const _limit = 10;
  Timer? _markTimer;
  // Generation counter: a refresh (or account switch) invalidates in-flight
  // load-more continuations so stale pages can't append to the new list.
  int _seq = 0;
  int _autoSeq = -1;

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
    // Resets start a new generation; load-more joins the current one.
    final mySeq = more ? _seq : ++_seq;
    if (more && loadingMore) return;
    if (!more && mounted) setState(() => loading = true);
    if (more && mounted) setState(() => loadingMore = true);
    // Owning account: late responses after logout/switch are dropped.
    final scope = appController.accountScope;
    // Offline-first: paint the last known page instantly (account-scoped).
    if (!more && items.isEmpty) {
      final cached = appController.readCachedNotifications();
      if (cached.isNotEmpty && mounted) {
        setState(() {
          items = cached;
          total = cached.length;
          loading = false;
        });
      }
    }
    final nextOffset = more ? offset + _limit : 0;
    final res = await appController.api.notifications(
      limit: _limit,
      offset: nextOffset,
    );
    if (!res.ok) {
      // Refresh failed: keep existing/cached rows with a stale badge instead
      // of replacing them with an empty list.
      if (!mounted) return;
      setState(() {
        loading = false;
        loadingMore = false;
      });
      return;
    }
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
    reads = await NotificationRead.prune(
      uid,
      serverTotal > 0 ? serverTotal : reads.length,
    );
    if (!mounted) return;
    if (mySeq != _seq) return;
    if (!appController.isLoggedIn || appController.accountScope != scope) {
      return;
    }
    setState(() {
      offset = nextOffset;
      items = more ? J.appendUnique(items, rows) : rows;
      total = serverTotal > 0 ? serverTotal : items.length;
      readIds = reads;
      loading = false;
      loadingMore = false;
    });
    // Persist only confirmed first-page rows (account-scoped fallback).
    if (!more && rows.isNotEmpty) {
      await appController.cacheNotifications(rows);
    }
    // Front marks the viewed page as read after 1200ms.
    _markTimer?.cancel();
    _markTimer = Timer(const Duration(milliseconds: 1200), () async {
      final ids = items
          .map((e) => '${e['id']}')
          .where((e) => e.isNotEmpty)
          .toList();
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
      appBar: AppBar(
        title: Text(app.t('notification')),
        actions: [
          if (items.any(_isUnread))
            TextButton.icon(
              onPressed: _markAllRead,
              icon: const Icon(Icons.done_all, size: 18),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              label: Text(app.t('mark_all_read')),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(),
              child: items.isEmpty
                  ? ListView(
                      children: [
                        EmptyState(message: app.t('no_notifications')),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (n) {
                              if (n.metrics.pixels >
                                      n.metrics.maxScrollExtent - 400 &&
                                  !loading &&
                                  total > items.length &&
                                  items.isNotEmpty) {
                                _load(more: true);
                              }
                              return false;
                            },
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount:
                                  items.length + (total > items.length ? 1 : 0),
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                if (i >= items.length) {
                                  if (!loadingMore) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (mounted &&
                                              !loadingMore &&
                                              total > items.length &&
                                              _autoSeq != _seq) {
                                            _autoSeq = _seq;
                                            _load(more: true);
                                          }
                                        });
                                  }
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final item = items[i];
                                final unread = _isUnread(item);
                                final link = J.str(
                                  item['link_url'] ?? item['link'],
                                );
                                final img = J.str(
                                  item['image_url'] ?? item['image'] ?? '',
                                );
                                final date = J.str(
                                  item['date_sent'] ??
                                      item['date'] ??
                                      item['created_at'] ??
                                      '',
                                );
                                return Card(
                                  color: unread
                                      ? app.accentColor.withValues(alpha: 0.05)
                                      : null,
                                  child: ListTile(
                                    leading: Stack(
                                      alignment: Alignment.topRight,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: SizedBox(
                                            width: 52,
                                            height: 52,
                                            child: img.isNotEmpty
                                                ? AppImage(
                                                    img,
                                                    placeholder:
                                                        app.placeholder,
                                                  )
                                                : Container(
                                                    color: app.accentColor
                                                        .withValues(
                                                          alpha: 0.12,
                                                        ),
                                                    child: Icon(
                                                      Icons
                                                          .notifications_outlined,
                                                      color: app.accentColor,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                        if (unread)
                                          Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: app.accentColor,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    title: Text(
                                      J.str(
                                        item['title'] ??
                                            item['message'] ??
                                            item['id'],
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: unread
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (item['message'] != null &&
                                            item['title'] != null)
                                          Text(
                                            J.str(item['message']),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        if (date.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Text(
                                              date,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: link.isNotEmpty
                                        ? const Icon(
                                            Icons.chevron_left,
                                            size: 18,
                                          )
                                        : null,
                                    onTap: link.isNotEmpty
                                        ? () => _openLink(context, link)
                                        : null,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }

  Future<void> _markAllRead() async {
    final uid = appController.user?['id'];
    final ids = items
        .map((e) => '${e['id']}')
        .where((e) => e.isNotEmpty)
        .toList();
    final updated = await NotificationRead.markAsRead(uid, ids);
    if (mounted) setState(() => readIds = updated);
  }
}

/// Parity with front Header bell: unread = total - read, badge 99+, poll every 60s.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with WidgetsBindingObserver {
  int unread = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appController.addListener(_onAuth);
    _ensureTimer();
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appController.removeListener(_onAuth);
    _timer?.cancel();
    super.dispose();
  }

  void _onAuth() => _ensureTimer();

  /// Lifecycle-aware polling: runs only when logged in AND resumed.
  /// Stops on logout/background to save battery/network/server load.
  void _ensureTimer() {
    final want = appController.isLoggedIn;
    if (!want) {
      _timer?.cancel();
      _timer = null;
      if (mounted && unread != 0) setState(() => unread = 0);
      return;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 120), (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ensureTimer();
      _refresh();
    } else {
      // Pause/inactive/detached: stop polling immediately so background work
      // does not run after the widget or app is no longer visible.
      _timer?.cancel();
      _timer = null;
    }
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
      setState(
        () => unread = NotificationRead.computeUnreadCount(total, reads),
      );
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
        label: Text(
          unread > 99 ? '99+' : '$unread',
          style: const TextStyle(fontSize: 10, color: Colors.white),
        ),
        child: const Icon(Icons.notifications_outlined, color: Colors.white),
      ),
    );
  }
}
