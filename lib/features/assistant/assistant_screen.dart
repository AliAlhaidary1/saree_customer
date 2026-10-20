import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_controller.dart';
import '../../core/json_util.dart';
import '../../core/offline/operation_policy.dart';
import '../../widgets/app_image.dart';
import '../../widgets/requires_internet_dialog.dart';
import '../../widgets/ui_helpers.dart';

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Local-first: last FAQ snapshot paints offline.
    final snap = appController.readPublicSnapshot('faqs');
    if (snap is List && snap.isNotEmpty && mounted) {
      setState(() {
        items = J.maps(snap);
        loading = false;
      });
    }
    try {
      final res = await appController.api.faqs(limit: 50);
      if (!mounted) return;
      if (res.ok && res.dataMaps.isNotEmpty) {
        await appController.cachePublicSnapshot('faqs', res.dataMaps);
      }
      setState(() {
        if (res.ok) items = res.dataMaps;
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return Scaffold(
      appBar: AppBar(title: Text(app.t('faq'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? EmptyState(message: app.t('not_synced_yet'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                ...items
                    .map(
                      (f) => Card(
                        child: ExpansionTile(
                          title: Text(J.str(f['question'])),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Text(J.str(f['answer'])),
                            ),
                          ],
                        ),
                      ),
                    )
                    ,
              ],
            ),
    );
  }
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final controller = TextEditingController();
  final scroll = ScrollController();
  final messages = <Map<String, dynamic>>[];
  bool loading = false;
  bool confirming = false;

  /// Thread history is local-only (last 30 text turns, no auto-send).
  static const _threadKey = 'assistant_thread';

  @override
  void initState() {
    super.initState();
    try {
      final snap = appController.readAccountSnapshot(_threadKey);
      if (snap is List && snap.isNotEmpty) {
        messages.addAll(J.maps(snap).take(30));
      }
    } catch (_) {}
  }

  Future<void> _persistThread() async {
    try {
      final slim = messages
          .where((m) => J.str(m['text']).isNotEmpty)
          .map((m) => {'role': J.str(m['role']), 'text': J.str(m['text'])})
          .toList();
      final tail = slim.length > 30 ? slim.sublist(slim.length - 30) : slim;
      await appController.cacheAccountSnapshot(_threadKey, tail);
    } catch (_) {}
  }

  @override
  void dispose() {
    controller.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _pushBot(
    String text, {
    Map<String, dynamic>? action,
    List<Map<String, dynamic>> products = const [],
  }) {
    if (!mounted) return;
    setState(() {
      messages.add({
        'role': 'bot',
        'text': text,
        'action': ?action,
        if (products.isNotEmpty) 'products': products,
      });
    });
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = controller.text.trim();
    if (text.isEmpty || loading) return;
    controller.clear();
    // Honest offline guard: recent failures prove the backend unreachable —
    // explain instead of spinning, and never auto-send later.
    if (appController.api.likelyOffline) {
      if (!mounted) return;
      setState(() {
        messages.add({'role': 'user', 'text': text});
        messages.add({
          'role': 'bot',
          'text': appController.t('assistant_offline'),
        });
      });
      _persistThread();
      _scrollDown();
      return;
    }
    // Web parity: only the last 8 messages are sent as history.
    final history = messages.length <= 8
        ? messages
              .where((item) => J.str(item['text']).isNotEmpty)
              .map(
                (item) => {
                  'role': J.str(item['role']),
                  'text': J.str(item['text']),
                },
              )
              .toList()
        : messages
              .sublist(messages.length - 8)
              .where((item) => J.str(item['text']).isNotEmpty)
              .map(
                (item) => {
                  'role': J.str(item['role']),
                  'text': J.str(item['text']),
                },
              )
              .toList();
    setState(() {
      messages.add({'role': 'user', 'text': text});
      loading = true;
    });
    _persistThread();
    _scrollDown();
    try {
      final result = await appController.api.assistantChat(
        text,
        history: history,
      );
      if (!mounted) return;
      final data = result.dataMap;
      final action = data['has_action'] == true || data['has_action'] == 1
          ? J.map(data['action'])
          : <String, dynamic>{};
      final products = J.maps(data['products']);
      if (!mounted) return;
      setState(() {
        loading = false;
        messages.add({
          'role': 'bot',
          'text': J.str(data['message']).isEmpty
              ? appController.t('assistant_not_found')
              : J.str(data['message']),
          'action': action,
          'products': products,
        });
      });
      _persistThread();
      _scrollDown();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        messages.add({
          'role': 'bot',
          'text': appController.t('assistant_not_found'),
        });
      });
      _scrollDown();
    }
  }

  /// Web parity (AssistantChat.jsx confirm button): executes the confirmed
  /// tool call and appends the follow-up message/action.
  Future<void> _confirm(Map<String, dynamic> action) async {
    final payload = J.map(action['payload']);
    final tool = J.str(payload['tool']);
    if (tool.isEmpty || confirming || loading) return;
    setState(() => confirming = true);
    try {
      final args = J.map(payload['args']);
      final res = await appController.api.assistantAct(
        tool,
        args: args,
        question: J.str(payload['question']),
      );
      final data = res.dataMap;
      final nextAction = data['has_action'] == true || data['has_action'] == 1
          ? J.map(data['action'])
          : <String, dynamic>{};
      _pushBot(
        J.str(data['message']).isEmpty
            ? appController.t('assistant_not_found')
            : J.str(data['message']),
        action: nextAction.isEmpty ? null : nextAction,
        products: J.maps(data['products']),
      );
    } catch (_) {
      _pushBot(appController.t('assistant_not_found'));
    } finally {
      if (mounted) setState(() => confirming = false);
    }
  }

  /// Web parity with AssistantChat.jsx PATH_MAP (web path → flutter path).
  String _assistantPath(String path) {
    const map = {
      '/login': '/login',
      '/forgot-password': '/login',
      '/faqs': '/faq',
      '/faq': '/faq',
      '/privacy-policy': '/privacy',
      '/returns': '/policy/ReturnsAndExchangesPolicy',
      '/shipping': '/policy/Shipping_Policy',
      '/cancellation': '/policy/Cancellation_Policy',
      '/favorites': '/wishlist',
      '/orders': '/orders',
      '/profile/orders': '/orders',
      '/addresses': '/addresses',
      '/profile/address': '/addresses',
      '/wallet': '/wallet',
      '/profile/wallet-transaction': '/wallet',
      '/seller/register': '/register',
      '/register/customer': '/register',
      '/register/seller': '/register',
      '/register/delivery': '/register',
      '/categories': '/',
      '/flash-sales': '/offers',
      '/profile/wishlist': '/wishlist',
    };
    final raw = path.trim();
    if (raw.isEmpty || raw == '#') return '/';
    if (map.containsKey(raw)) return map[raw]!;
    if (raw.startsWith('/store/')) {
      return '/store/${raw.substring('/store/'.length)}';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          app.t('assistant_title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (messages.isNotEmpty)
            IconButton(
              onPressed: () {
                setState(messages.clear);
                // "New chat" must also drop the persisted thread, otherwise
                // the next cold start restores the "deleted" history.
                try {
                  appController.removeAccountSnapshot(_threadKey);
                } catch (_) {}
              },
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: app.t('new_chat'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(app.t('assistant_greeting')),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final item = messages[index];
                final isUser = item['role'] == 'user';
                return Align(
                  alignment: isUser
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isUser
                          ? app.accentColor.withValues(alpha: 0.12)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(J.str(item['text'])),
                        _actionWidget(J.map(item['action'])),
                        for (final product in J.maps(item['products']))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: SizedBox(
                              width: 48,
                              height: 48,
                              child: AppImage(
                                J.str(product['image_url']),
                                placeholder: app.placeholder,
                              ),
                            ),
                            title: Text(J.str(product['name'])),
                            subtitle: Text(
                              [
                                if (J.str(product['seller_name']).isNotEmpty)
                                  J.str(product['seller_name']),
                                if (J.str(product['price_text']).isNotEmpty)
                                  J.str(product['price_text']),
                              ].join(' · '),
                            ),
                            trailing: Text(
                              app.t('assistant_open_product'),
                              style: TextStyle(
                                color: app.accentColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            onTap: () {
                              final path = J.str(product['path']);
                              context.push(
                                path.isNotEmpty
                                    ? path
                                    : '/product/${product['slug'] ?? product['id']}',
                              );
                            },
                          ),
                        for (final seller in J.maps(item['sellers']))
                          TextButton(
                            onPressed: () {
                              final slug = J.str(seller['slug']);
                              context.push(
                                slug.isNotEmpty
                                    ? '/store/$slug'
                                    : '/seller/${seller['id']}',
                              );
                            },
                            child: Text(
                              [
                                J.str(seller['store_name']),
                                if (J.str(seller['rating_text']).isNotEmpty)
                                  J.str(seller['rating_text']),
                              ].join(' · '),
                            ),
                          ),
                        for (final link in J.maps(item['links']))
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: FilledButton(
                              onPressed: () => context.push(
                                _assistantPath(J.str(link['path'])),
                              ),
                              child: Text(J.str(link['title'])),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    app.t('assistant_wait'),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          TextButton(
            onPressed: () => context.push('/faq'),
            child: Text(app.t('faq')),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    maxLength: 1000,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: app.t('assistant_placeholder'),
                      counterText: '',
                    ),
                  ),
                ),
                IconButton(onPressed: _send, icon: const Icon(Icons.send)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionWidget(Map<String, dynamic> action) {
    if (action.isEmpty) return const SizedBox.shrink();
    final app = appController;
    // Web parity: CONFIRM executes the tool call (assistant/act).
    if (action['type'] == 'CONFIRM' && J.map(action['payload']).isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: FilledButton.icon(
          onPressed: (confirming || loading) ? null : () => _confirm(action),
          icon: confirming
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 18),
          label: Text(
            J.str(action['label']).isNotEmpty
                ? J.str(action['label'])
                : app.t('assistant_confirm'),
          ),
        ),
      );
    }
    if (action['type'] == 'PRODUCT_CARD') {
      return _AssistantProductCard(
        action: action,
        pushBot: (text) => _pushBot(text),
      );
    }
    final url = J.str(action['url']);
    if (url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: FilledButton.tonal(
        onPressed: () => context.push(_assistantPath(url)),
        child: Text(
          J.str(action['label']).isNotEmpty
              ? J.str(action['label'])
              : app.t('assistant_open_page'),
        ),
      ),
    );
  }
}

/// Web parity with AssistantProductCard: product link + qty stepper +
/// in-chat add to cart (resolves an in-stock variant first).
class _AssistantProductCard extends StatefulWidget {
  const _AssistantProductCard({required this.action, required this.pushBot});
  final Map<String, dynamic> action;
  final ValueChanged<String> pushBot;

  @override
  State<_AssistantProductCard> createState() => _AssistantProductCardState();
}

class _AssistantProductCardState extends State<_AssistantProductCard> {
  int qty = 1;
  bool adding = false;
  bool added = false;

  Map<String, dynamic> get product => J.map(widget.action['product']);

  Future<void> _add() async {
    if (adding) return;
    final app = appController;
    setState(() => adding = true);
    try {
      final point = app.browseCoords;
      final detail = await app.api.productById(
        latitude: point.latitude,
        longitude: point.longitude,
        id: product['id'],
        slug: J.str(product['slug']),
      );
      final variants = J.maps(
        detail.dataMap['variants'] ?? detail.dataMap['product_variants'],
      );
      Map<String, dynamic>? variant;
      for (final v in variants) {
        if (J.i(v['stock']) > 0) {
          variant = v;
          break;
        }
      }
      variant ??= variants.isNotEmpty ? variants.first : null;
      final variantId =
          variant?['id'] ?? product['product_variant_id'] ?? product['id'];
      final error = await app.addToCart(
        productId: product['id'],
        variantId: variantId,
        qty: qty,
        sellerId: J.sellerId(product),
        storeName: app.storeNameOf(product),
      );
      if (!mounted) return;
      if (error != null) {
        await showCartError(context, error);
        if (error != kRequiresInternet) {
          widget.pushBot('${app.t('assistant_add_failed')}: $error');
        }
      } else {
        setState(() => added = true);
        widget.pushBot(
          '${app.t('assistant_added_to_cart')} (${J.str(product['name'])} × $qty)',
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => added = false);
        });
      }
    } catch (_) {
      if (mounted) widget.pushBot(appController.t('assistant_add_failed'));
    } finally {
      if (mounted) setState(() => adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final p = product;
    final url = J.str(p['url']).isNotEmpty
        ? p['url']
        : (J.str(p['slug']).isNotEmpty || p['id'] != null
              ? '/product/${J.str(p['slug']).isNotEmpty ? p['slug'] : p['id']}'
              : '/');
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: SizedBox(
              width: 48,
              height: 48,
              child: AppImage(J.str(p['image']), placeholder: app.placeholder),
            ),
            title: Text(
              J.str(p['name']).isNotEmpty
                  ? J.str(p['name'])
                  : J.str(widget.action['label']),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: J.str(p['price']).isNotEmpty
                ? Text(J.str(p['price']))
                : null,
            trailing: Text(
              app.t('assistant_open_product'),
              style: TextStyle(
                color: app.accentColor,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            onTap: () => context.push(url),
          ),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: adding
                    ? null
                    : () => setState(() => qty = qty > 1 ? qty - 1 : 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$qty', style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: adding
                    ? null
                    : () => setState(() => qty = qty >= 99 ? 99 : qty + 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: adding ? null : _add,
                  child: adding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          added
                              ? '✓ ${app.t('assistant_added_to_cart')}'
                              : app.t('add_to_cart'),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
