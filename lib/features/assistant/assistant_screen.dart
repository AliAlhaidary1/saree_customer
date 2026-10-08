import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_controller.dart';
import '../../core/json_util.dart';
import '../../widgets/app_image.dart';
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
    try {
      final res = await appController.api.faqs(limit: 50);
      if (!mounted) return;
      setState(() {
        items = res.dataMaps;
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
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
              ? EmptyState(message: app.t('no_faqs'))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: items
                      .map(
                        (f) => Card(
                          child: ExpansionTile(
                            title: Text(J.str(f['question'])),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 0, 16, 16),
                                child: Text(J.str(f['answer'])),
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

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final controller = TextEditingController();
  final messages = <Map<String, dynamic>>[];
  bool loading = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = controller.text.trim();
    if (text.isEmpty || loading) return;
    controller.clear();
    // Web parity: only the last 8 messages are sent as history.
    final history = messages.length <= 8
        ? messages
            .where((item) => J.str(item['text']).isNotEmpty)
            .map((item) => {
                  'role': J.str(item['role']),
                  'text': J.str(item['text']),
                })
            .toList()
        : messages
            .sublist(messages.length - 8)
            .where((item) => J.str(item['text']).isNotEmpty)
            .map((item) => {
                  'role': J.str(item['role']),
                  'text': J.str(item['text']),
                })
            .toList();
    setState(() {
      messages.add({'role': 'user', 'text': text});
      loading = true;
    });
    try {
      final result = await appController.api.assistantChat(text, history: history);
      if (!mounted) return;
      final data = result.dataMap;
      final action =
          data['has_action'] == true || data['has_action'] == 1 ? J.map(data['action']) : <String, dynamic>{};
      final products = J.maps(data['products']);
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        messages.add(
            {'role': 'bot', 'text': appController.t('assistant_not_found')});
      });
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
      '/categories': '/products',
      '/flash-sales': '/offers',
      '/profile/wishlist': '/wishlist',
    };
    final raw = path.trim();
    if (raw.isEmpty || raw == '#') return '/';
    if (map.containsKey(raw)) return map[raw]!;
    if (raw.startsWith('/store/')) return '/store/${raw.substring('/store/'.length)}';
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return Scaffold(
      appBar: AppBar(title: Text(app.t('assistant_title'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(app.t('assistant_greeting')),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final item = messages[index];
                final isUser = item['role'] == 'user';
                return Align(
                  alignment:
                      isUser ? Alignment.centerLeft : Alignment.centerRight,
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
                            subtitle: Text([
                              if (J.str(product['seller_name']).isNotEmpty)
                                J.str(product['seller_name']),
                              if (J.str(product['price_text']).isNotEmpty)
                                J.str(product['price_text']),
                            ].join(' · ')),
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
                            child: Text([
                              J.str(seller['store_name']),
                              if (J.str(seller['rating_text']).isNotEmpty)
                                J.str(seller['rating_text']),
                            ].join(' · ')),
                          ),
                        for (final link in J.maps(item['links']))
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: FilledButton(
                              onPressed: () =>
                                  context.push(_assistantPath(J.str(link['path']))),
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
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text(app.t('assistant_wait'),
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12)),
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
                IconButton(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                ),
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
    if (action['type'] == 'PRODUCT_CARD') {
      final product = J.map(action['product']);
      final url = J.str(product['url']).isNotEmpty
          ? _assistantPath(J.str(product['url']))
          : (J.str(product['slug']).isNotEmpty || product['id'] != null
              ? '/product/${J.str(product['slug']).isNotEmpty ? product['slug'] : product['id']}'
              : '/');
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: SizedBox(
          width: 48,
          height: 48,
          child: AppImage(
            J.str(product['image']),
            placeholder: app.placeholder,
          ),
        ),
        title: Text(J.str(product['name']).isNotEmpty
            ? J.str(product['name'])
            : J.str(action['label'])),
        subtitle: J.str(product['price']).isNotEmpty
            ? Text(J.str(product['price']))
            : null,
        trailing: Text(
          J.str(action['label']).isNotEmpty
              ? J.str(action['label'])
              : app.t('assistant_open_product'),
          style: TextStyle(
            color: app.accentColor,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        onTap: () => context.push(url),
      );
    }
    final url = J.str(action['url']);
    if (url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: FilledButton.tonal(
        onPressed: () => context.push(_assistantPath(url)),
        child: Text(J.str(action['label']).isNotEmpty
            ? J.str(action['label'])
            : app.t('assistant_open_page')),
      ),
    );
  }
}
