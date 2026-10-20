import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/app_controller.dart';
import '../../core/akhdimni_status.dart';
import '../../core/city_mode.dart';
import '../../core/json_util.dart';
import '../../core/order_status.dart';
import '../../core/promo_price.dart';
import '../../widgets/app_image.dart';
import '../../widgets/product_variant_sheet.dart';
import '../../core/app_theme.dart';
import '../../core/offline/offline_cache.dart';
import '../../widgets/dynamic_address_fields.dart';
import '../../widgets/order_tracker.dart';
import '../../widgets/requires_internet_dialog.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/ui_helpers.dart';
import '../../widgets/unified_tabs.dart';

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
          _tile(
            context,
            Icons.feedback_outlined,
            app.t('complaints_suggestions'),
            '/complaints',
          ),
          _sellerAppTile(context),
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
    final mobile = J.str(app.user?['mobile'] ?? app.user?['email']);
    final profileImg = J.str(app.user?['profile'] ?? app.user?['image']);
    final wallet = J.d(
      app.user?['balance'] ??
          app.user?['wallet'] ??
          app.settings['user_balance'],
    );
    // Web parity (ProfileDashboard pf-nav): user header + wallet card +
    // focused menu. No CMS clutter, no server field (debug-only below).
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: _ProfileAvatar(
              name: name,
              profileImg: profileImg,
              radius: 26,
            ),
            title: Text(
              name.isEmpty ? app.t('profile') : name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: mobile.isEmpty ? null : Text(mobile),
            trailing: const Icon(Icons.chevron_left, size: 18),
            onTap: () => context.push('/profile'),
          ),
        ),
        Card(
          color: app.accentColor,
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: const Icon(
              Icons.account_balance_wallet_outlined,
              color: Colors.white,
              size: 30,
            ),
            title: Text(
              app.t('walletBalance'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            subtitle: Text(
              '${J.str(app.settings['currency'], '')} ${wallet.toStringAsFixed(app.decimals)}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            trailing: const Icon(Icons.chevron_left, color: Colors.white),
            onTap: () => context.push('/wallet'),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _hubCard(
                context,
                Icons.receipt_long_outlined,
                app.t('orders'),
                '/orders',
                app,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _hubCard(
                context,
                Icons.location_on_outlined,
                app.t('myAddress'),
                '/addresses',
                app,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _hubCard(
                context,
                Icons.favorite_border,
                app.t('wishlist'),
                '/wishlist',
                app,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _tile(context, Icons.person_outline, app.t('profile'), '/profile'),
        _tile(context, Icons.receipt_long_outlined, app.t('orders'), '/orders'),
        _tile(context, Icons.favorite_border, app.t('wishlist'), '/wishlist'),
        _tile(
          context,
          Icons.location_on_outlined,
          app.t('myAddress'),
          '/addresses',
        ),
        _tile(
          context,
          Icons.account_balance_wallet_outlined,
          app.t('wallet'),
          '/wallet',
        ),
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
        _tile(
          context,
          Icons.feedback_outlined,
          app.t('complaints_suggestions'),
          '/complaints',
        ),
        _sellerAppTile(context),
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
              builder: (_) => const Center(child: CircularProgressIndicator()),
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
              builder: (_) => const Center(child: CircularProgressIndicator()),
            );
            final error = await app.logoutAllDevices();
            if (context.mounted) {
              Navigator.of(context, rootNavigator: true).pop();
              if (error != null) {
                await showCartError(context, error);
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

  /// Web parity (pf-hub): quick hub cards for orders/address/wishlist.
  Widget _hubCard(
    BuildContext context,
    IconData icon,
    String label,
    String path,
    AppController app,
  ) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(path),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: app.accentColor, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Become a seller" tile — opens the seller app on Google Play
  /// (the customer app itself has no seller registration).
  Widget _sellerAppTile(BuildContext context) {
    final app = appController;
    return ListTile(
      leading: Icon(Icons.storefront_outlined, color: app.accentColor),
      title: Text(app.t('become_seller')),
      subtitle: Text(app.t('become_seller_hint')),
      trailing: const Icon(Icons.open_in_new),
      onTap: () => _openSellerApp(context),
    );
  }

  Future<void> _openSellerApp(BuildContext context) async {
    final app = appController;
    if (!await app.hasInternetAccess()) {
      if (context.mounted) await showRequiresInternetDialog(context);
      return;
    }
    var url = J.str(app.settings['seller_android_app_url']);
    if (url.isEmpty) {
      try {
        final saved = app.prefs.getString('seller_app_url');
        if (saved != null && saved.isNotEmpty) url = saved;
      } catch (_) {}
    }
    if (url.isEmpty) {
      url =
          'https://play.google.com/store/apps/details?id=com.sreamart.sreamart_seller';
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(app.t('something_went_wrong'))));
    }
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
                      onPressed: () =>
                          setDialogState(() => hidePassword = !hidePassword),
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
      await showCartError(context, error);
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(app.t('account_deleted_success'))));
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
  int _seq = 0;
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
  /// Local-first: cached orders paint instantly, then refresh.
  Future<void> _load({bool more = false}) async {
    if (!appController.isLoggedIn) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final mySeq = ++_seq;
    // Owning account for this refresh: if logout/switch happens mid-flight,
    // the late response must neither paint nor persist under the new scope.
    final scope = appController.accountScope;
    if (!more && mounted) setState(() => loading = true);

    // Paint cached account-scoped list before network.
    if (!more && active.isEmpty) {
      final cached = appController.readCachedOrders();
      if (cached.active.isNotEmpty || cached.previous.isNotEmpty) {
        setState(() {
          active = cached.active;
          previous = cached.previous;
          loading = false;
        });
      }
    }

    final nextPage = more ? page + 1 : 1;
    final offset = (nextPage - 1) * _perPage;
    final legacyActive = await appController.api.orders(
      type: 1,
      limit: _perPage,
      offset: offset,
    );
    final legacyPrev = await appController.api.orders(
      type: 0,
      limit: _perPage,
      offset: offset,
    );
    final groups = await appController.api.checkoutGroups(page: nextPage);
    final akh = await appController.api.akhdimniOrders({});
    if (!mounted || mySeq != _seq) return;
    // Account changed or session ended mid-flight: drop the response instead
    // of painting account A's orders into account B's session.
    if (!appController.isLoggedIn || appController.accountScope != scope) {
      return;
    }
    // All three failed (offline/timeout): keep the cached rows painted above
    // — never replace them with empty lists or erase the persisted snapshot.
    // Cached order status is always badged as saved (see OfflineBanner).
    if (!legacyActive.ok && !legacyPrev.ok && !groups.ok) {
      setState(() {
        loading = false;
      });
      return;
    }
    final legacyActiveParsed = parseOrdersPayload(legacyActive);
    final legacyPrevParsed = parseOrdersPayload(legacyPrev);
    final groupsParsed = parseCheckoutGroupsPayload(groups);
    final activeOk = legacyActive.ok || groups.ok;
    final prevOk = legacyPrev.ok || groups.ok;
    final baseActive = activeOk
        ? mergeOrders(legacyActiveParsed.rows, groupsParsed.rows, true)
        : active.where((e) => e['is_akhdimni'] != true).toList();
    final basePrev = prevOk
        ? mergeOrders(legacyPrevParsed.rows, groupsParsed.rows, false)
        : previous.where((e) => e['is_akhdimni'] != true).toList();
    var akhActive = active.where((e) => e['is_akhdimni'] == true).toList();
    var akhPrev = previous.where((e) => e['is_akhdimni'] == true).toList();
    if (akh.ok) {
      akhActive = [];
      akhPrev = [];
      for (final r in akh.dataMaps) {
        final status = J.str(r['active_status'] ?? r['status']);
        final m = _mapAkhOrder(r, status);
        if (_akhTerminal(status)) {
          akhPrev.add(m);
        } else {
          akhActive.add(m);
        }
      }
    }
    final freshActive = [...baseActive, ...akhActive];
    final freshPrev = [...basePrev, ...akhPrev];
    await appController.cacheOrders(freshActive, freshPrev);
    if (!mounted || mySeq != _seq || appController.accountScope != scope) {
      return;
    }
    setState(() {
      page = nextPage;
      active = more ? J.appendUnique(active, freshActive) : freshActive;
      previous = more ? J.appendUnique(previous, freshPrev) : freshPrev;
      if (activeOk) {
        totalActive =
            legacyActiveParsed.total + groupsParsed.total + akhActive.length;
      }
      loading = false;
    });
  }

  static bool _akhTerminal(String status) =>
      status == 'delivered' ||
      status == 'completed' ||
      status == 'cancelled' ||
      status == 'rejected' ||
      status == 'failed';

  Map<String, dynamic> _mapAkhOrder(Map<String, dynamic> r, String status) {
    final total = r['final_total'] ?? r['total'];
    return {
      'id': r['id'],
      'order_id': r['id'],
      'is_akhdimni': true,
      'final_total': total,
      'total': total,
      'status_name': akhdimniStatusLabel(status.isEmpty ? null : status),
      'active_status': status,
      'created_at': r['created_at'] ?? r['date'],
    };
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
    if (!app.isLoggedIn) return const LoginRequired();
    final showSkeleton = loading && active.isEmpty && previous.isEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.backgroundWhite,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: AnimatedBuilder(
                  animation: tab,
                  builder: (_, _) => UnifiedTabs(
                    labels: [
                      '${app.t('active_orders')} (${active.length})',
                      '${app.t('previous_orders')} (${previous.length})',
                    ],
                    selectedIndex: tab.index,
                    onChanged: (i) => tab.animateTo(i),
                    expanded: true,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: showSkeleton
              ? const _OrdersSkeleton()
              : TabBarView(
                  controller: tab,
                  children: [_list(active, true), _list(previous, false)],
                ),
        ),
      ],
    );
  }

  Widget _list(List<Map<String, dynamic>> items, bool isActiveTab) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: _EmptyOrders(isActive: isActiveTab),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _orderCard(items[i]),
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> order) {
    final app = appController;
    final isGroup = order['is_checkout_group'] == true;
    final isAkhdimni = order['is_akhdimni'] == true;
    final id = order['id'] ?? order['order_id'];
    final total = money(
      order['final_total'] ?? order['total'],
      app.currency,
      app.decimals,
    );
    final date = _dateLabel(order['created_at']);
    final status = _statusLabel(order);
    final tone = _statusTone(order);
    final icon = isAkhdimni
        ? Icons.delivery_dining_outlined
        : isGroup
        ? Icons.inventory_2_outlined
        : Icons.shopping_bag_outlined;
    return Material(
      color: AppTheme.backgroundWhite,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final oid = order['id'] ?? order['order_id'];
          if (isAkhdimni) {
            await context.push('/akhdimni/orders/$oid');
          } else {
            final cancelled = await context.push('/orders/$oid');
            if (cancelled == true && mounted) {
              _load();
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppTheme.primaryNavy, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${app.t('id')}$id',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isAkhdimni
                                ? AppTheme.accentOrange.withValues(alpha: 0.1)
                                : AppTheme.primaryNavy.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isAkhdimni
                                ? app.t('akhdimni')
                                : app.t('store_order'),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: isAkhdimni
                                  ? AppTheme.accentOrange
                                  : AppTheme.primaryNavy,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _OrderStatusChip(label: status, tone: tone),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            total,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.accentOrange,
                            ),
                          ),
                        ),
                        if (date.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            date,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_left,
                size: 18,
                color: AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// HH:MM-safe display date (the API sends ISO strings).
  String _dateLabel(dynamic raw) {
    final dt = DateTime.tryParse(J.str(raw))?.toLocal();
    if (dt == null) return '';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  String _statusTone(Map<String, dynamic> order) {
    if (order['is_checkout_group'] == true) {
      return storeDisplayFromGroupStatus(order['customer_status']).tone;
    }
    if (order['is_akhdimni'] == true) {
      final s = J.str(order['active_status']).toLowerCase();
      if (s == 'delivered' || s == 'completed') return 'ok';
      if (s == 'cancelled' || s == 'rejected' || s == 'failed') return 'bad';
      if (s == 'on_the_way' || s == 'out_for_delivery' || s == 'picked_up') {
        return 'alert';
      }
      return 'info';
    }
    return storeDisplayFromLegacy(order['active_status']).tone;
  }
}

/// Placeholder rows while the first page of orders loads.
class _OrdersSkeleton extends StatelessWidget {
  const _OrdersSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.backgroundWhite,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            SkeletonLoader(width: 46, height: 46, borderRadius: 12),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLoader(height: 12, width: 130),
                  SizedBox(height: 9),
                  SkeletonLoader(height: 12, width: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state for the orders list with a clear action button.
class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.accentOrange.withValues(alpha: 0.16),
                    AppTheme.primaryNavy.withValues(alpha: 0.06),
                  ],
                ),
              ),
              child: Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundWhite,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(
                    isActive
                        ? Icons.receipt_long_outlined
                        : Icons.history_outlined,
                    size: 42,
                    color: AppTheme.accentOrange,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              isActive
                  ? app.t('no_active_orders')
                  : app.t('no_previous_orders'),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                isActive
                    ? app.t('no_active_orders_hint')
                    : app.t('no_previous_orders_hint'),
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.6,
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            BrandedButton(
              onPressed: () => context.go('/'),
              label: app.t('shop_now'),
              icon: Icons.shopping_bag_outlined,
              expanded: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderStatusChip extends StatelessWidget {
  const _OrderStatusChip({required this.label, required this.tone});

  final String label;
  final String tone;

  static const _tones = {
    'ok': Color(0xFF16A34A),
    'bad': Color(0xFFDC2626),
    'warn': Color(0xFFD97706),
    'alert': Color(0xFF2563EB),
    'info': AppTheme.accentOrange,
  };

  @override
  Widget build(BuildContext context) {
    final color = _tones[tone] ?? AppTheme.accentOrange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 130),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
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

  bool _servedFromCache = false;

  /// Parity with front fetchOrderDetails: try checkout-group first, fallback legacy.
  /// Local-first: cache-miss starts spinner, cache-hit paints instantly, network refreshes.
  Future<void> _load() async {
    final scope = appController.accountScope;
    final orderId = widget.id;
    if (order == null) {
      final cached = appController.offline.readDoc(
        OfflineCache.orderDetailsKey(scope, orderId),
      );
      final payload = cached?.payload;
      if (cached?.scope == scope && payload is Map) {
        setState(() {
          order = J.map(payload);
          loading = false;
          _servedFromCache = true;
        });
      }
    }
    try {
      final cg = await appController.api.checkoutGroup(orderId);
      if (!mounted || scope != appController.accountScope) return;
      if (cg.ok && cg.dataMap.isNotEmpty) {
        final data = mapCheckoutGroupToOrder(cg.dataMap);
        await appController.offline.writeDoc(
          OfflineCache.orderDetailsKey(scope, orderId),
          data,
          scope: scope,
        );
        if (!mounted) return;
        setState(() {
          order = data;
          loading = false;
          _servedFromCache = false;
        });
        return;
      }
    } catch (_) {}
    final result = await appController.api.orders(orderId: orderId);
    if (!mounted || scope != appController.accountScope) return;
    if (result.ok) {
      final data = result.dataMaps.isNotEmpty
          ? result.dataMaps.first
          : result.dataMap;
      await appController.offline.writeDoc(
        OfflineCache.orderDetailsKey(scope, orderId),
        data,
        scope: scope,
      );
      if (!mounted) return;
      setState(() {
        order = data;
        loading = false;
        _servedFromCache = false;
      });
      return;
    }
    // Refresh failed: keep cached row if available.
    if (!mounted) return;
    setState(() {
      loading = order == null;
      _servedFromCache = order != null;
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: c,
              maxLines: 4,
              decoration: InputDecoration(hintText: hint),
              onChanged: (_) => setDialogState(() {}),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(appController.t('cancel')),
              ),
              FilledButton(
                onPressed: c.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: Text(appController.t('confirm')),
              ),
            ],
          );
        },
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
    if (!await appController.hasInternetAccess()) {
      if (mounted) await showRequiresInternetDialog(context);
      return;
    }
    setState(() => cancellingGroup = true);
    final res = await appController.api.cancelCheckoutGroup(
      widget.id,
      reason: reason,
    );
    if (!mounted) return;
    setState(() => cancellingGroup = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.ok ? appController.t('order_cancelled') : res.message,
        ),
      ),
    );
    if (res.ok) {
      context.pop(true);
      return;
    }
  }

  Future<void> _cancelItem(Map<String, dynamic> item) async {
    final reason = await _askReason(
      appController.t('cancel_order'),
      appController.t('write_cancel_reason'),
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    if (!await appController.hasInternetAccess()) {
      if (mounted) await showRequiresInternetDialog(context);
      return;
    }
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
      SnackBar(
        content: Text(
          res.ok
              ? appController.t('OrderItemCancelledSuccessfully')
              : res.message,
        ),
      ),
    );
    if (res.ok) {
      context.pop(true);
      return;
    }
  }

  Future<void> _cancelGroupWithReason(String reason) async {
    setState(() => cancellingGroup = true);
    final res = await appController.api.cancelCheckoutGroup(
      widget.id,
      reason: reason,
    );
    if (!mounted) return;
    setState(() => cancellingGroup = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.ok ? appController.t('order_cancelled') : res.message,
        ),
      ),
    );
    if (res.ok) {
      context.pop(true);
      return;
    }
  }

  Future<void> _returnItem(Map<String, dynamic> item) async {
    final reason = await _askReason(
      appController.t('return'),
      appController.t('write_return_reason'),
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    if (!await appController.hasInternetAccess()) {
      if (mounted) await showRequiresInternetDialog(context);
      return;
    }
    ApiResult res;
    if (_isGroup) {
      res = await appController.api.requestCommerceReturn(
        item['id'],
        reason: reason,
      );
    } else {
      res = await appController.api.updateOrderItemStatus(
        orderId: order?['id'] ?? widget.id,
        orderItemId: item['id'],
        status: 8,
        reason: reason,
      );
    }
    if (!mounted) return;
    final msg = res.message.isNotEmpty
        ? res.message
        : appController.t(res.ok ? 'return_requested' : 'something_went_wrong');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    if (res.ok) _load();
  }

  Future<void> _invoice() async {
    if (!await appController.hasInternetAccess()) {
      if (mounted) await showRequiresInternetDialog(context);
      return;
    }
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
        SnackBar(
          content: Text(
            '${appController.t('invoice_downloaded_successfully')}: $file',
          ),
        ),
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
    if (!await appController.hasInternetAccess()) {
      if (mounted) await showRequiresInternetDialog(context);
      return;
    }
    final result = await appController.api.addProductRating({
      'product_id': item['product_id'],
      'rate': res.stars,
      'review': res.review,
      'order_item_id': item['id'],
      'order_id': order?['id'] ?? widget.id,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? appController.t('rating_saved_successfully')
              : result.message,
        ),
      ),
    );
    if (result.ok) _load();
  }

  Future<void> _rateSeller(dynamic sellerId, String name) async {
    final res = await _askRate('${appController.t('rate_seller')}: $name');
    if (res == null || !mounted) return;
    if (!await appController.hasInternetAccess()) {
      if (mounted) await showRequiresInternetDialog(context);
      return;
    }
    final result = await appController.api.rateSeller({
      'seller_id': sellerId,
      'rate': res.stars,
      'review': res.review,
      'order_id': order?['id'] ?? widget.id,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? appController.t('rating_saved_successfully')
              : result.message,
        ),
      ),
    );
    if (result.ok) _load();
  }

  Future<void> _rateCourier(dynamic courierId, String name) async {
    final res = await _askRate('${appController.t('rate_courier')}: $name');
    if (res == null || !mounted) return;
    if (!await appController.hasInternetAccess()) {
      if (mounted) await showRequiresInternetDialog(context);
      return;
    }
    final result = await appController.api.rateDeliveryBoy({
      'delivery_boy_id': courierId,
      'rate': res.stars,
      'review': res.review,
      'order_id': order?['id'] ?? widget.id,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? appController.t('rating_saved_successfully')
              : result.message,
        ),
      ),
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
                    icon: Icon(
                      idx <= value ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                    ),
                    onPressed: () => setS(() => value = idx),
                  );
                }),
              ),
              TextField(
                controller: ctrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: appController.t('write_review'),
                ),
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
      return Scaffold(
        appBar: AppBar(title: Text('${app.t('order')} ${widget.id}')),
        body: const Center(child: CircularProgressIndicator()),
      );
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
    final activeStatus = J.str(
      order?['active_status'] ?? order?['status'] ?? '2',
    );
    final isDelivered = J.i(activeStatus) == 6;
    final isReturned = J.i(activeStatus) == 8;
    final canGetInvoice =
        isDelivered ||
        isReturned ||
        items.any(
          (e) =>
              J.i(e['active_status']) == 6 ||
              J.str(e['return_status']) == 'completed' ||
              J.str(e['return_status']) == 'approved',
        );
    final sellers = _sellersToRate();
    final courierId = order?['delivery_boy_id'] ?? order?['courier_id'];
    final courierName = J.str(
      order?['delivery_boy_name'] ?? order?['courier_name'],
    );
    final trackingOn =
        app.orderTrackingEnabled || J.flag(order?['order_tracking_enabled']);
    final blocked = J.str(order?['cancel_blocked_reason']);
    final publicId = J.str(order?['public_id']).isNotEmpty
        ? J.str(order?['public_id'])
        : '${order?['id'] ?? widget.id}';
    final orderDate = _dateLabel(order?['created_at']);
    final statusLabel = J.str(
      order?['status_name'] ?? _displayLabel(activeStatus),
    );
    final orderTotal = money(
      order?['final_total'] ?? order?['total'],
      app.currency,
      app.decimals,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${app.t('order')} #$publicId',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: app.t('copy_id'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: publicId));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(app.t('copied'))));
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Order summary hero
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryNavy, Color(0xFF123B63)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '${app.t('order_number')} #$publicId',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: orderToneColor(
                                  _statusToneFromStatus(activeStatus),
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              statusLabel,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_outlined,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        orderDate.isNotEmpty
                            ? orderDate
                            : app.t('unknown_date'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      if (_servedFromCache) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accentOrange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            app.t('cached_data'),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFFB27A),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        app.t('total'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        orderTotal,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Delivery address - compact, type-aware title
            if (J.map(order?['address_snapshot']).isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.07),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _deliveryIcon(),
                        size: 21,
                        color: AppTheme.primaryNavy,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _deliveryTitle(app),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              if (J
                                  .str(
                                    J.map(order?['address_snapshot'])['name'],
                                  )
                                  .isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    J.str(
                                      J.map(order?['address_snapshot'])['name'],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _deliveryAddressLine(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          if (J.str(order?['mobile']).isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                const Icon(
                                  Icons.phone_outlined,
                                  size: 13,
                                  color: AppTheme.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  J.str(order?['mobile']),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Order tracker
            OrderTracker(status: activeStatus, statusLabel: statusLabel),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                if (_isGroup && _canCancelGroup)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: cancellingGroup ? null : _cancelGroup,
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: Text(app.t('cancel_order')),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        side: BorderSide(
                          color: Colors.red.withValues(alpha: 0.4),
                        ),
                        foregroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                if (canGetInvoice)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _invoice,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: Text(app.t('get_invoice')),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (_isGroup && !_canCancelGroup && blocked.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.red.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.red),
                  title: Text(
                    app.t('cancel_not_available'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(blocked),
                ),
              ),
            ],
            if (trackingOn) ...[
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(
                  Icons.local_shipping_outlined,
                  color: AppTheme.primaryNavy,
                ),
                title: Text(
                  app.t('track_order'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  J.str(
                    order?['tracking_status'] ??
                            order?['delivery_status'] ??
                            order?['address_snapshot'] is Map
                        ? J.str((order?['address_snapshot'] as Map)['city'])
                        : '—',
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Order items
            Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 20,
                  color: AppTheme.primaryNavy,
                ),
                const SizedBox(width: 8),
                Text(
                  app.t('order_items'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${items.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryNavy,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map((item) {
              final image = J.str(
                item['image_url'] ??
                    item['image'] ??
                    item['product_image'] ??
                    item['thumbnail'],
              );
              final actions = <Widget>[];
              if (_canReturnItem(item)) {
                actions.add(
                  TextButton.icon(
                    onPressed: () => _returnItem(item),
                    icon: const Icon(Icons.restart_alt_outlined, size: 16),
                    label: Text(app.t('return')),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.orange,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                );
              }
              if (_canCancelItem(item)) {
                actions.add(
                  TextButton.icon(
                    onPressed: () => _cancelItem(item),
                    icon: const Icon(Icons.close, size: 16),
                    label: Text(app.t('cancel')),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                );
              }
              if (isDelivered) {
                actions.add(
                  TextButton.icon(
                    onPressed: () => _rateProduct(item),
                    icon: const Icon(Icons.star_border, size: 16),
                    label: Text(app.t('rate')),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accentOrange,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                );
              }
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundWhite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 54,
                            height: 54,
                            child: image.isNotEmpty
                                ? AppImage(image, thumb: true)
                                : Container(
                                    color: AppTheme.surfaceGrey,
                                    child: const Icon(
                                      Icons.shopping_bag_outlined,
                                      color: AppTheme.textSecondary,
                                      size: 24,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                J.str(item['product_name'] ?? item['name']),
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceGrey,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '×${J.str(item['quantity'], '1')}',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                  if (J
                                      .str(item['seller_name'])
                                      .isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        J.str(item['seller_name']),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          money(
                            item['sub_total'] ?? item['price'],
                            app.currency,
                            app.decimals,
                          ),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.accentOrange,
                          ),
                        ),
                      ],
                    ),
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: actions,
                      ),
                    ],
                  ],
                ),
              );
            }),

            const SizedBox(height: 20),

            // Order ratings (sellers & courier) - compact, no cards
            if ((isDelivered || isReturned) && sellers.isNotEmpty) ...[
              Text(
                app.t('order_ratings'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              ...sellers.map(
                (s) => ListTile(
                  leading: const Icon(
                    Icons.storefront_outlined,
                    color: AppTheme.primaryNavy,
                  ),
                  title: Text(
                    J.str(s['seller_name']),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: TextButton(
                    onPressed: () =>
                        _rateSeller(s['seller_id'], J.str(s['seller_name'])),
                    child: Text(app.t('rate_seller')),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if ((isDelivered || isReturned) &&
                courierId != null &&
                '$courierId'.isNotEmpty)
              ListTile(
                leading: const Icon(
                  Icons.delivery_dining_outlined,
                  color: AppTheme.primaryNavy,
                ),
                title: Text(
                  courierName.isNotEmpty
                      ? courierName
                      : app.t('courier_rating'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: TextButton(
                  onPressed: () => _rateCourier(
                    courierId,
                    courierName.isNotEmpty
                        ? courierName
                        : app.t('courier_rating'),
                  ),
                  child: Text(app.t('rate_courier')),
                ),
              ),

            const SizedBox(height: 24),

            // Compact billing totals - single card only
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.receipt_outlined,
                          color: AppTheme.primaryNavy,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          app.t('billing_details'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _TotalsRow(
                      label: app.t('payment_method'),
                      value: J.str(order?['payment_method'] ?? ''),
                      show: J.str(order?['payment_method']).isNotEmpty,
                    ),
                    _TotalsRow(
                      label: app.t('sub_total'),
                      value: money(
                        order?['subtotal'],
                        app.currency,
                        app.decimals,
                      ),
                      show: order?['subtotal'] != null,
                    ),
                    _TotalsRow(
                      label: app.t('delivery_charge'),
                      value: money(
                        order?['delivery_charge'],
                        app.currency,
                        app.decimals,
                      ),
                      show: order?['delivery_charge'] != null,
                    ),
                    _TotalsRow(
                      label: app.t('promo_code_discount'),
                      value:
                          '- ${money(order?['promo_discount'], app.currency, app.decimals)}',
                      show: J.d(order?['promo_discount']) > 0,
                    ),
                    _TotalsRow(
                      label: app.t('wallet_balance_used'),
                      value:
                          '- ${money(order?['wallet_balance'] ?? order?['wallet_applied'], app.currency, app.decimals)}',
                      show:
                          J.d(
                            order?['wallet_balance'] ??
                                order?['wallet_applied'],
                          ) >
                          0,
                    ),
                    _TotalsRow(
                      label: app.t('discount'),
                      value:
                          '- ${money(order?['discount'], app.currency, app.decimals)}',
                      show: J.d(order?['discount']) > 0,
                    ),
                    _TotalsRow(
                      label: app.t('refunded'),
                      value: money(
                        J.d(
                          order?['refunded_amount'] ?? order?['refund_amount'],
                        ),
                        app.currency,
                        app.decimals,
                      ),
                      show:
                          J.d(
                            order?['refunded_amount'] ??
                                order?['refund_amount'],
                          ) >
                          0,
                    ),
                    const Divider(),
                    _TotalsRow(
                      label: app.t('total'),
                      value: money(
                        order?['final_total'],
                        app.currency,
                        app.decimals,
                      ),
                      bold: true,
                    ),
                    if (J
                        .str(order?['order_note'] ?? order?['note'])
                        .isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${app.t('order_note')}: ${J.str(order?['order_note'] ?? order?['note'])}',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  String _deliveryAddressLine() {
    final snap = J.map(order?['address_snapshot']);
    final direct = J.str(order?['order_address']);
    if (direct.isNotEmpty) return direct;
    return [
      J.str(snap['address']),
      J.str(snap['area']),
      J.str(snap['city']),
      J.str(snap['country']),
    ].where((e) => e.isNotEmpty).join('، ');
  }

  String _deliveryType() {
    final snap = J.map(order?['address_snapshot']);
    final rawType = J
        .str(
          J.str(snap['type']).isNotEmpty
              ? snap['type']
              : J.str(snap['address_type']).isNotEmpty
              ? snap['address_type']
              : order?['address_type'],
        )
        .toLowerCase();
    if (rawType.contains('office') || rawType.contains('مكتب')) {
      return 'office';
    }
    if (rawType.contains('shop') || rawType.contains('متجر')) return 'shop';
    if (rawType.contains('other') || rawType.contains('آخر')) return 'other';
    if (rawType.isNotEmpty) return 'home';
    final hint = [
      J.str(snap['name']),
      J.str(snap['address_name']),
      J.str(snap['address']),
    ].join(' ').toLowerCase();
    if (hint.contains('office') ||
        hint.contains('مكتب') ||
        hint.contains('عمل')) {
      return 'office';
    }
    if (hint.contains('shop') ||
        hint.contains('متجر') ||
        hint.contains('محل')) {
      return 'shop';
    }
    if (hint.contains('other') ||
        hint.contains('آخر') ||
        hint.contains('اخر')) {
      return 'other';
    }
    return 'home';
  }

  String _deliveryTitle(AppController app) {
    switch (_deliveryType()) {
      case 'office':
        return app.t('delivery_to_office');
      case 'shop':
        return app.t('delivery_to_shop');
      case 'other':
        return app.t('delivery_to_other');
      default:
        return app.t('delivery_to_home');
    }
  }

  IconData _deliveryIcon() {
    switch (_deliveryType()) {
      case 'office':
        return Icons.business_center_outlined;
      case 'shop':
        return Icons.storefront_outlined;
      case 'other':
        return Icons.place_outlined;
      default:
        return Icons.home_outlined;
    }
  }

  String _dateLabel(dynamic raw) {
    final dt = DateTime.tryParse(J.str(raw))?.toLocal();
    if (dt == null) return '';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}';
  }

  String _statusToneFromStatus(String status) {
    final s = status.toLowerCase();
    if (s == 'cancelled' || s == 'rejected' || s == 'failed') return 'bad';
    if (s == 'delivered' || s == 'completed') return 'ok';
    if (s == 'on_the_way' || s == 'out_for_delivery' || s == 'picked_up') {
      return 'alert';
    }
    if (s == 'returned') return 'bad';
    return 'info';
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

Color orderToneColor(String key) {
  switch (key) {
    case 'ok':
      return const Color(0xFF16A34A);
    case 'bad':
      return const Color(0xFFDC2626);
    case 'warn':
      return const Color(0xFFD97706);
    case 'alert':
      return const Color(0xFF2563EB);
    case 'info':
    default:
      return AppTheme.accentOrange;
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.label,
    required this.value,
    this.show = true,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool show;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
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
        builder: (_, _) {
          if (app.addresses.isEmpty) {
            return EmptyState(
              icon: Icons.location_on_outlined,
              message: app.t('new_address'),
              actionLabel: app.t('new_address'),
              onAction: _edit,
            );
          }
          return RadioGroup<String>(
            groupValue: '${app.selectedAddress?['id']}',
            onChanged: (v) {
              final address = app.addresses.firstWhere(
                (x) => '${x['id']}' == v,
                orElse: () => const <String, dynamic>{},
              );
              if (address.isEmpty) return;
              app.selectAddress(address);
              final next = cityFromAddress(address, app.cities);
              if (next != null) app.selectCity(next);
            },
            child: ListView(
              children: app.addresses
                  .map(
                    (address) => RadioListTile(
                      value: '${address['id']}',
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              J.str(address['type'] ?? address['name']),
                            ),
                          ),
                          if (J.str(address['is_default']) == '1')
                            Container(
                              margin: const EdgeInsetsDirectional.only(
                                start: 6,
                              ),
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
                              final res = await app.api.deleteAddress(
                                address['id'],
                              );
                              if (context.mounted && !res.ok) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      res.message.isNotEmpty
                                          ? res.message
                                          : app.t('something_went_wrong'),
                                    ),
                                  ),
                                );
                              }
                              await app.loadAddresses();
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
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
    // Local draft for new addresses (never auto-submitted, cleared on save).
    Map<String, dynamic>? addressDraft;
    if (existing == null) {
      try {
        addressDraft = app.offline.readDraft(app.accountScope, 'address_form');
      } catch (_) {}
    }
    final draftName = J.str(addressDraft?['name']);
    final draftMobile = J.str(addressDraft?['mobile']);
    final draftStreet = J.str(addressDraft?['address']);
    final draftType = J.str(addressDraft?['type']);
    final name = TextEditingController(
      text: J.str(existing?['name']).isNotEmpty
          ? J.str(existing?['name'])
          : (draftName.isNotEmpty ? draftName : J.str(app.user?['name'])),
    );
    final mobile = TextEditingController(
      text: J.str(existing?['mobile']).isNotEmpty
          ? J.str(existing?['mobile'])
          : (draftMobile.isNotEmpty ? draftMobile : J.str(app.user?['mobile'])),
    );
    final address = TextEditingController(
      text: J.str(existing?['address']).isNotEmpty
          ? J.str(existing?['address'])
          : draftStreet,
    );
    final rawType = J.str(existing?['type']).isNotEmpty
        ? J.str(existing?['type'])
        : draftType;
    String addressType = rawType.isNotEmpty ? rawType : 'Home';
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
    if (!mounted) return;
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
                    initialValue: addressType,
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
    if (ok != true) {
      // Dialog dismissed: keep a local draft for new addresses.
      if (existing == null) {
        try {
          await app.offline.writeDraft(app.accountScope, 'address_form', {
            'name': name.text,
            'mobile': mobile.text,
            'address': address.text,
            'type': addressType,
          });
        } catch (_) {}
      }
      return;
    }
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
    final hadAny = app.addresses.isNotEmpty;
    if (!await app.hasInternetAccess()) {
      if (mounted) await showRequiresInternetDialog(context);
      return;
    }
    final res = existing != null
        ? await app.api.updateAddress({...fields, 'id': existing['id']})
        : await app.api.addAddress(fields);
    await app.loadAddresses();
    if (!mounted) return;
    // Surface backend errors instead of failing silently (this was why
    // addresses "never appeared" — e.g. the old required-pincode rule).
    if (!res.ok) {
      // Offline/validation failure: keep a local draft (city/zone validation
      // still happens server-side on explicit save — never queued blindly).
      if (existing == null) {
        try {
          await app.offline.writeDraft(app.accountScope, 'address_form', {
            'name': name.text,
            'mobile': mobile.text,
            'address': address.text,
            'type': addressType,
          });
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.message.isNotEmpty
                ? res.message
                : app.t('something_went_wrong'),
          ),
        ),
      );
      return;
    }
    if (existing == null) {
      try {
        await app.offline.removeDraft(app.accountScope, 'address_form');
      } catch (_) {}
    }
    if (!mounted) return;
    // Auto-select the new address so checkout sees it immediately.
    if (!hadAny && app.addresses.isNotEmpty) {
      app.selectAddress(
        app.addresses.firstWhere(
          (a) => J.i(a['is_default']) == 1,
          orElse: () => app.addresses.first,
        ),
      );
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(app.t('address_saved_ok'))));
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

  /// Offline-first: restores the account's persisted favorites + cached
  /// wishlist rows instantly, then refreshes. A failed refresh keeps the
  /// cached rows (badged as saved) instead of showing an empty list.
  Future<void> _load() async {
    if (!appController.isLoggedIn) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final scope = appController.accountScope;
    await appController.restoreCachedFavorites();
    final cached = appController.readCachedWishlist();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        items = cached;
        loading = false;
      });
    }
    final point = appController.coords ?? (latitude: 0.0, longitude: 0.0);
    final result = await appController.api.favorites(
      latitude: point.latitude,
      longitude: point.longitude,
    );
    if (!mounted) return;
    // Drop late responses after logout/account switch.
    if (!appController.isLoggedIn || appController.accountScope != scope) {
      return;
    }
    if (result.ok) {
      await appController.cacheWishlist(result.dataMaps);
      if (!mounted || appController.accountScope != scope) return;
      setState(() {
        items = result.dataMaps;
        loading = false;
      });
    } else {
      // Keep cached rows (if any); only an empty cache shows a retry affordance.
      setState(() {
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return Scaffold(
      appBar: AppBar(
        title: Text(app.t('wishlist')),
        actions: [
          ListenableBuilder(
            listenable: appController,
            builder: (_, _) => IconButton(
              onPressed: () => context.push('/cart'),
              icon: Badge(
                isLabelVisible: appController.cartCount > 0,
                label: Text(
                  '${appController.cartCount}',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              tooltip: appController.t('cart'),
            ),
          ),
        ],
      ),
      body: !app.isLoggedIn
          ? const LoginRequired()
          : loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? EmptyState(
              icon: Icons.favorite_border,
              message: app.t('wishlist'),
              actionLabel: app.t('retry'),
              onAction: _load,
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
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
                                  onPressed: () =>
                                      addProductFromCatalog(context, item),
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
                ),
              ],
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
    this.snapshotName,
  });
  final String title;
  final Future<List<Map<String, dynamic>>> Function() loader;
  final Widget? header;
  final Future<List<Map<String, dynamic>>> Function(int limit, int offset)?
  pageLoader;
  final String? emptyMessage;

  /// Offline snapshot name (account-scoped). When set, the last synchronized
  /// first page paints offline with a stale badge (spend-disabled for wallet:
  /// snapshots are never proof of balance).
  final String? snapshotName;

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
    // Local-first: last synchronized page paints offline.
    final snapName = widget.snapshotName;
    if (snapName != null && mounted) {
      final snap = appController.readAccountSnapshot(snapName);
      if (snap is List && snap.isNotEmpty) {
        setState(() {
          items = J.maps(snap);
          loading = false;
        });
      }
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
      if (value.isNotEmpty && snapName != null) {
        await appController.cacheAccountSnapshot(snapName, value);
      }
      setState(() {
        if (value.isNotEmpty) items = value;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
      });
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
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: !app.isLoggedIn
          ? const LoginRequired()
          : loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (widget.header != null) widget.header!,
                if (items.isEmpty)
                  EmptyState(
                    message: widget.emptyMessage ?? app.t('no_notifications'),
                  )
                else ...[
                  ...items.map(
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
                  ),
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
  bool _draftRestored = false;

  static const _draftFormId = 'profile_form';

  @override
  void initState() {
    super.initState();
    // Local text draft (never auto-sent; photo upload stays online-only).
    try {
      final draft = appController.offline.readDraft(
        appController.accountScope,
        _draftFormId,
      );
      if (draft != null) {
        final n = J.str(draft['name']);
        final e = J.str(draft['email']);
        final m = J.str(draft['mobile']);
        if (n.isNotEmpty || e.isNotEmpty || m.isNotEmpty) {
          if (n.isNotEmpty) name.text = n;
          if (e.isNotEmpty) email.text = e;
          if (m.isNotEmpty) mobile.text = m;
          _draftRestored = true;
        }
      }
    } catch (_) {}
    for (final c in [name, email, mobile]) {
      c.addListener(_saveDraftSoon);
    }
  }

  Timer? _draftDeb;

  void _saveDraftSoon() {
    _draftDeb?.cancel();
    _draftDeb = Timer(const Duration(milliseconds: 600), () async {
      try {
        await appController.offline.writeDraft(
          appController.accountScope,
          _draftFormId,
          {'name': name.text, 'email': email.text, 'mobile': mobile.text},
        );
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _draftDeb?.cancel();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(app.t('fill_required_fields'))));
      return;
    }
    if (!await app.hasInternetAccess()) {
      if (mounted) await showRequiresInternetDialog(context);
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
        try {
          await app.offline.removeDraft(app.accountScope, _draftFormId);
        } catch (_) {}
        _draftRestored = false;
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
                  // Guarded: vector/exotic remote avatars must not reach
                  // the platform decoder ('unimplemented' spam on API 28).
                  backgroundImage: pickedImage != null
                      ? FileImage(File(pickedImage!.path))
                      : (AppImage.isDisplayable(currentProfile)
                            ? NetworkImage(currentProfile)
                            : null),
                  onBackgroundImageError:
                      pickedImage != null ||
                          !AppImage.isDisplayable(currentProfile)
                      ? null
                      : (_, _) {},
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
          TextButton(onPressed: _pickImage, child: Text(app.t('change_photo'))),
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
            child: saving ? const BusySpinner() : Text(app.t('update')),
          ),
          if (_draftRestored)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                app.t('draft_saved'),
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
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
    final hasBank =
        app.walletBankName.isNotEmpty ||
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
                title: Text(
                  app
                      .t('wallet_refill_limit_hint')
                      .replaceAll(
                        '{amount}',
                        '${app.currency} ${app.walletRefillLimit}',
                      ),
                ),
              ),
            ),
          if (hasBank)
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance),
                title: Text(
                  [
                    if (app.walletBankName.isNotEmpty) app.walletBankName,
                    if (app.walletAccountNumber.isNotEmpty)
                      app.walletAccountNumber,
                  ].join(' • '),
                ),
                subtitle: Text(
                  [
                    if (app.walletAccountHolder.isNotEmpty)
                      app.walletAccountHolder,
                    if (app.walletTransferInstructions.isNotEmpty)
                      app.walletTransferInstructions,
                  ].where((e) => e.isNotEmpty).join('\n'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Header avatar with the same decoder guard as [_SellerAvatar]: only
/// displayable http(s) raster URLs reach the image pipeline (downscaled
/// thumb); everything else shows the initial letter. Fixes the
/// `ImageDecoder ... 'unimplemented'` spam + full-res main-thread decode
/// jank the raw `NetworkImage` caused on old devices.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.name,
    required this.profileImg,
    this.radius = 26,
  });

  final String name;
  final String profileImg;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final app = appController;
    if (!AppImage.isDisplayable(profileImg)) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: app.accentColor.withValues(alpha: 0.15),
        child: Text(
          name.isEmpty ? 'م' : name.substring(0, 1),
          style: TextStyle(
            color: app.accentColor,
            fontWeight: FontWeight.w800,
            fontSize: radius * 0.85,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: app.accentColor.withValues(alpha: 0.15),
      child: ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: AppImage(profileImg, thumb: true),
        ),
      ),
    );
  }
}
