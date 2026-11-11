import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_controller.dart';
import '../../core/app_navigation.dart';
import '../../core/app_theme.dart';
import '../../core/json_util.dart';
import '../../core/offline/operation_policy.dart';
import '../../widgets/app_image.dart';
import '../../widgets/requires_internet_dialog.dart';
import '../../widgets/ui_helpers.dart';
import 'assistant_contract.dart';

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
                ...items.map(
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
                ),
              ],
            ),
    );
  }
}

/// Opens the store assistant as a bottom sheet over the current screen, so the
/// customer keeps their place instead of being pushed to a separate page.
Future<void> showAssistantSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => const AssistantScreen(embedded: true),
  );
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.embedded = false});

  /// Renders the assistant as a sheet panel (no Scaffold/app bar) instead of a
  /// standalone page.
  final bool embedded;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final controller = TextEditingController();
  final scroll = ScrollController();
  final messages = <Map<String, dynamic>>[];
  bool loading = false;
  bool confirming = false;
  String? conversationId;

  /// Thread history is local-only (last 30 text turns, no auto-send).
  static const _threadKey = 'assistant_thread';
  static const _conversationKey = 'assistant_conversation_id';

  @override
  void initState() {
    super.initState();
    try {
      final snap = appController.readAccountSnapshot(_threadKey);
      if (snap is List && snap.isNotEmpty) {
        messages.addAll(J.maps(snap).take(30));
      }
      final savedConversation = J.str(
        appController.readAccountSnapshot(_conversationKey),
      );
      if (savedConversation.isNotEmpty) conversationId = savedConversation;
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

  Future<void> _persistConversation() async {
    final id = conversationId?.trim() ?? '';
    if (id.isEmpty) return;
    await appController.cacheAccountSnapshot(_conversationKey, id);
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
    if (appController.looksOffline) {
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
        conversationId: conversationId,
      );
      if (!mounted) return;
      final data = result.dataMap;
      final action = data['has_action'] == true || data['has_action'] == 1
          ? J.map(data['action'])
          : <String, dynamic>{};
      final products = J.maps(data['products']);
      final nextConversationId = J.str(J.map(data['meta'])['conversation_id']);
      if (nextConversationId.isNotEmpty) {
        conversationId = nextConversationId;
        _persistConversation();
      }
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

  @override
  Widget build(BuildContext context) {
    final app = appController;
    if (widget.embedded) {
      final media = MediaQuery.of(context);
      final maxHeight = media.size.height * 0.92;
      // The panel shrinks with the keyboard so the composer stays visible.
      final available = media.size.height - media.viewInsets.bottom;
      final panelHeight = math
          .min(
            (maxHeight - media.viewInsets.bottom).clamp(320.0, maxHeight),
            available,
          )
          .toDouble();
      return AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Container(
          height: panelHeight,
          decoration: const BoxDecoration(
            color: AppTheme.surfaceGrey,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _sheetHeader(app),
              Expanded(child: _conversation(app)),
              _composer(app),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.surfaceGrey,
      appBar: AppBar(
        title: Text(
          app.t('assistant_title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (messages.isNotEmpty)
            IconButton(
              onPressed: _newChat,
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: app.t('new_chat'),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _conversation(app)),
          _composer(app),
        ],
      ),
    );
  }

  void _newChat() {
    setState(messages.clear);
    // "New chat" must also drop the persisted thread, otherwise the next cold
    // start restores the "deleted" history.
    try {
      appController.removeAccountSnapshot(_threadKey);
      appController.removeAccountSnapshot(_conversationKey);
    } catch (_) {}
    conversationId = null;
  }

  /// In a sheet the assistant closes itself before pushing a page, so the
  /// customer lands on the destination instead of behind an open sheet.
  void _openLocation(String location) {
    final target = location.trim();
    if (target.isEmpty) return;
    if (!widget.embedded) {
      openAppLocation(context, target);
      return;
    }
    final router = GoRouter.of(context);
    Navigator.of(context).maybePop();
    openRouterLocation(router, target);
  }

  Widget _sheetHeader(AppController app) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryNavy, Color(0xFF14406B)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 9),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.accentOrange.withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Icon(
                    Icons.smart_toy_outlined,
                    color: AppTheme.accentOrange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.t('assistant_title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        app.t('assistant_subtitle'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (messages.isNotEmpty)
                  IconButton(
                    onPressed: _newChat,
                    tooltip: app.t('new_chat'),
                    icon: const Icon(Icons.add_comment_outlined, size: 20),
                    color: Colors.white70,
                  ),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  tooltip: app.t('close'),
                  icon: const Icon(Icons.close, size: 20),
                  color: Colors.white70,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _conversation(AppController app) {
    if (messages.isEmpty) return _emptyState(app);
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
      itemCount: messages.length + (loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= messages.length) return _typingBubble(app);
        final item = messages[index];
        return _messageBubble(app, item, item['role'] == 'user');
      },
    );
  }

  Widget _emptyState(AppController app) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.smart_toy_outlined,
                    size: 40,
                    color: AppTheme.accentOrange,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  app.t('assistant_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  app.t('assistant_greeting'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                _faqChip(app),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _messageBubble(
    AppController app,
    Map<String, dynamic> item,
    bool isUser,
  ) {
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isUser ? 18 : 5),
      bottomRight: Radius.circular(isUser ? 5 : 18),
    );
    return Align(
      alignment: isUser ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.accentOrange, Color(0xFFFF8F3D)],
                )
              : null,
          color: isUser ? null : AppTheme.backgroundWhite,
          borderRadius: radius,
          border: isUser
              ? null
              : Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.07)),
          boxShadow: isUser
              ? null
              : [
                  BoxShadow(
                    color: AppTheme.primaryNavy.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              J.str(item['text']),
              style: TextStyle(
                height: 1.5,
                fontSize: 13.5,
                color: isUser ? Colors.white : AppTheme.textPrimary,
              ),
            ),
            _actionWidget(J.map(item['action'])),
            for (final product in assistantProductActions(item['products']))
              _AssistantProductCard(
                action: product,
                pushBot: (text) => _pushBot(text),
                onOpen: _openLocation,
              ),
            for (final seller in J.maps(item['sellers']))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    final slug = J.str(seller['slug']);
                    _openLocation(
                      slug.isNotEmpty
                          ? '/store/$slug'
                          : '/seller/${seller['id']}',
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.storefront_outlined,
                          size: 16,
                          color: AppTheme.accentOrange,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            [
                              J.str(seller['store_name']),
                              if (J.str(seller['rating_text']).isNotEmpty)
                                J.str(seller['rating_text']),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accentOrange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            for (final link in J.maps(item['links']))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () =>
                        _openLocation(assistantAppPath(J.str(link['path']))),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(J.str(link['title'])),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _typingBubble(AppController app) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.backgroundWhite,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(5),
          ),
          border: Border.all(
            color: AppTheme.primaryNavy.withValues(alpha: 0.07),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accentOrange,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              app.t('assistant_wait'),
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _faqChip(AppController app) {
    return TextButton.icon(
      onPressed: () => _openLocation('/faq'),
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.accentOrange,
        backgroundColor: AppTheme.accentOrange.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      icon: const Icon(Icons.help_outline, size: 16),
      label: Text(
        app.t('faq'),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _composer(AppController app) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundWhite,
        border: Border(
          top: BorderSide(color: AppTheme.primaryNavy.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _faqChip(app),
              const Spacer(),
              if (messages.isNotEmpty)
                TextButton.icon(
                  onPressed: _newChat,
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(
                    app.t('new_chat'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceGrey,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: controller,
                    maxLength: 1000,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: app.t('assistant_placeholder'),
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                      counterText: '',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final canSend = value.text.trim().isNotEmpty && !loading;
                  return SizedBox(
                    width: 46,
                    height: 46,
                    child: Material(
                      color: canSend
                          ? AppTheme.accentOrange
                          : AppTheme.surfaceGrey,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: canSend ? _send : null,
                        child: Icon(
                          Icons.send_rounded,
                          size: 20,
                          color: canSend
                              ? Colors.white
                              : AppTheme.textSecondary.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
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
        onOpen: _openLocation,
      );
    }
    final url = J.str(action['url']);
    if (url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.tonal(
          onPressed: () => _openLocation(assistantAppPath(url)),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 40),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(
            J.str(action['label']).isNotEmpty
                ? J.str(action['label'])
                : app.t('assistant_open_page'),
          ),
        ),
      ),
    );
  }
}

/// Web parity with AssistantProductCard: product link + qty stepper +
/// in-chat add to cart (resolves an in-stock variant first).
class _AssistantProductCard extends StatefulWidget {
  const _AssistantProductCard({
    required this.action,
    required this.pushBot,
    required this.onOpen,
  });
  final Map<String, dynamic> action;
  final ValueChanged<String> pushBot;
  final ValueChanged<String> onOpen;

  @override
  State<_AssistantProductCard> createState() => _AssistantProductCardState();
}

class _AssistantProductCardState extends State<_AssistantProductCard> {
  int qty = 0;
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
        qty: 1,
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
        setState(() {
          added = true;
          qty = 1;
        });
        // لا نرسل رسالة بوت عند الإضافة — يكفي تغيير الزر.
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
    final slug = J.str(p['slug']);
    final url = J.str(p['url']).isNotEmpty
        ? J.str(p['url'])
        : (slug.isNotEmpty || p['id'] != null
              ? '/product/${slug.isNotEmpty ? slug : p['id']}'
              : '/');
    final price = J.str(p['price']);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryNavy.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => widget.onOpen(url),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: AppImage(
                      J.str(p['image']),
                      placeholder: app.placeholder,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        J.str(p['name']).isNotEmpty
                            ? J.str(p['name'])
                            : J.str(widget.action['label']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (price.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          price,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.accentOrange,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FilledButton(
              onPressed: adding ? null : _add,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: adding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      added ? '+1' : app.t('add_to_cart'),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // The old stepper UI was removed: the product card now starts at qty=0
  // and simply shows "Add to cart" → "+1" after tapping.
}
