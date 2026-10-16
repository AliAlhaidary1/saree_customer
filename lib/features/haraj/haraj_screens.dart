import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';
import '../../core/json_util.dart';
import '../../core/promo_price.dart';
import '../../core/search_scope.dart';
import '../../widgets/app_image.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/requires_internet_dialog.dart';
import '../../widgets/ui_helpers.dart';

Future<bool> _needInternet(BuildContext context) async {
  if (await appController.hasInternetAccess()) return true;
  if (context.mounted) await showRequiresInternetDialog(context);
  return false;
}

class HarajListScreen extends StatefulWidget {
  const HarajListScreen({super.key, this.mine = false});
  final bool mine;

  @override
  State<HarajListScreen> createState() => _HarajListScreenState();
}

class _HarajListScreenState extends State<HarajListScreen> {
  List<Map<String, dynamic>> items = [];
  List<Map<String, dynamic>> categories = [];
  String? categoryId;
  String? condition;
  String cityFilter = 'current'; // current | all | <city_id>
  int mineTab = 0; // 0 all, 1 active, 2 sold
  int page = 1;
  int lastPage = 1;
  bool loading = true;
  bool loadingMore = false;
  final search = TextEditingController();
  // Generation counter: every filter-affecting load bumps it, so late
  // responses from older queries/filters can never overwrite newer results.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.mine) {
      headerSearch.addListener(_onHeaderSearch);
      search.text = headerSearch.harajQuery;
    }
    _load(reset: true);
  }

  @override
  void dispose() {
    if (!widget.mine) headerSearch.removeListener(_onHeaderSearch);
    search.dispose();
    super.dispose();
  }

  /// The shared header owns the search field on `/haraj` (like home).
  void _onHeaderSearch() {
    if (headerSearch.harajQuery == search.text) return;
    search.text = headerSearch.harajQuery;
    _load(reset: true);
  }

  Map<String, dynamic> _params(int p) {
    final app = appController;
    final currentCityId = app.city?['id'];
    return {
      'page': p,
      'per_page': 20,
      if (cityFilter == 'current' && currentCityId != null)
        'city_id': currentCityId,
      if (cityFilter != 'current' && cityFilter != 'all') 'city_id': cityFilter,
      if (categoryId != null) 'category_id': categoryId,
      if (condition != null) 'condition': condition,
      if (search.text.trim().isNotEmpty) 'search': search.text.trim(),
      if (widget.mine && mineTab == 1) 'status': 1,
      if (widget.mine && mineTab == 2) 'status': 2,
    };
  }

  bool _servedFromCache = false;

  /// Snapshot name: my-ads are account-scoped, the public feed is global.
  String get _snapshotName => widget.mine ? 'haraj_mine' : 'haraj_feed';

  dynamic _readSnapshot(String key) => widget.mine
      ? appController.readAccountSnapshot(key)
      : appController.readPublicSnapshot(key);

  Future<void> _writeSnapshot(String key, dynamic payload) => widget.mine
      ? appController.cacheAccountSnapshot(key, payload)
      : appController.cachePublicSnapshot(key, payload);

  Future<void> _load({bool reset = false}) async {
    final mySeq = ++_seq;
    if (reset) {
      // Local-first: last synchronized feed paints offline (default query).
      final snap = _readSnapshot(_snapshotName) as Map?;
      if (snap != null && !_hasActiveFilters && mounted) {
        setState(() {
          items = J.maps(snap['items']);
          categories = J.maps(snap['categories']);
          page = 1;
          lastPage = _intOf(snap['lastPage'], 1);
          loading = false;
          _servedFromCache = true;
        });
      } else {
        setState(() {
          loading = true;
          page = 1;
        });
      }
    }
    try {
      final posts = widget.mine
          ? await appController.api.harajMyPosts(_params(1))
          : await appController.api.harajPosts(_params(1));
      final cats = await appController.api.harajCategories();
      if (!mounted || mySeq != _seq) return;
      if (!posts.ok) {
        setState(() {
          loading = false;
          _servedFromCache = items.isNotEmpty;
        });
        return;
      }
      final hasFilters = _hasActiveFilters;
      setState(() {
        items = posts.dataMaps;
        if (cats.ok && cats.dataMaps.isNotEmpty) categories = cats.dataMaps;
        page = 1;
        lastPage = _intOf(
          posts.raw['last_page'] ?? posts.dataMap['last_page'],
          1,
        );
        loading = false;
        _servedFromCache = false;
      });
      if (!hasFilters && (posts.ok || cats.ok)) {
        await _writeSnapshot(_snapshotName, {
          'items': posts.dataMaps,
          'categories': cats.dataMaps,
          'lastPage': _intOf(
            posts.raw['last_page'] ?? posts.dataMap['last_page'],
            1,
          ),
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          _servedFromCache = items.isNotEmpty;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (loadingMore || page >= lastPage) return;
    // Capture the generation: a filter change bumps _seq via _load, and this
    // stale continuation must then drop its rows instead of appending them
    // to the new query (duplicates / wrong page corruption).
    final mySeq = _seq;
    final nextPage = page + 1;
    setState(() => loadingMore = true);
    try {
      final posts = widget.mine
          ? await appController.api.harajMyPosts(_params(nextPage))
          : await appController.api.harajPosts(_params(nextPage));
      if (!mounted) return;
      if (!posts.ok) {
        if (mounted) setState(() => loadingMore = false);
        return;
      }
      if (mySeq != _seq) {
        // Superseded by a newer query: drop rows but release the spinner so
        // a fresh load-more can fire for the active filters.
        setState(() => loadingMore = false);
        return;
      }
      setState(() {
        items = J.appendUnique(items, posts.dataMaps);
        page = nextPage;
        lastPage = _intOf(
          posts.raw['last_page'] ?? posts.dataMap['last_page'],
          page,
        );
        loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  static int _intOf(dynamic v, int fallback) {
    final n = int.tryParse('$v');
    return n ?? fallback;
  }

  String _catName(Map<String, dynamic> cat) {
    final isAr = appController.i18n.code == 'ar';
    final ar = J.str(cat['name_ar']);
    final en = J.str(cat['name_en'] ?? cat['name']);
    return isAr ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
  }

  bool get _hasActiveFilters =>
      categoryId != null || condition != null || search.text.trim().isNotEmpty;

  void _clearFilters() {
    search.clear();
    setState(() {
      categoryId = null;
      condition = null;
    });
    _load(reset: true);
  }

  /// Home-style grey band: search + circular category tiles + condition pills.
  /// The city selector is intentionally hidden (always the current city).
  Widget _topSection(AppController app) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.only(top: 14, bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.mine)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, end: 12),
              child: Row(
                children: [
                  _accentBar(20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      app.t('haraj'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => app.isLoggedIn
                        ? context.push('/haraj/create')
                        : context.push(
                            '/login?next=${Uri.encodeComponent('/haraj/create')}',
                          ),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(app.t('add_post')),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accentOrange,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (widget.mine)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: search,
                onSubmitted: (_) => _load(reset: true),
                decoration: InputDecoration(
                  hintText: app.t('search_in_haraj'),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppTheme.accentOrange,
                  ),
                  filled: true,
                  fillColor: AppTheme.backgroundWhite,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.accentOrange,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
            child: Row(
              children: [
                _accentBar(20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    app.t('categories').trim(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (_hasActiveFilters)
                  TextButton.icon(
                    onPressed: _clearFilters,
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: Text(app.t('haraj_clear_filters')),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accentOrange,
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 96, child: _categoryTiles(app)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _accentBar(16),
                const SizedBox(width: 8),
                Text(
                  app.t('haraj_condition'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(app.t('all_conditions'), condition == null, () {
                  setState(() => condition = null);
                  _load(reset: true);
                }),
                _pill(app.t('condition_new'), condition == 'new', () {
                  setState(() => condition = 'new');
                  _load(reset: true);
                }),
                _pill(app.t('condition_like_new'), condition == 'like_new', () {
                  setState(() => condition = 'like_new');
                  _load(reset: true);
                }),
                _pill(app.t('condition_used'), condition == 'used', () {
                  setState(() => condition = 'used');
                  _load(reset: true);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accentBar(double height) {
    return Container(
      width: 4,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.accentOrange,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _categoryTiles(AppController app) {
    return ListView.separated(
      cacheExtent: 600, padding: const EdgeInsets.symmetric(horizontal: 16),
      scrollDirection: Axis.horizontal,
      itemCount: categories.length + 1,
      separatorBuilder: (_, _) => const SizedBox(width: 14),
      itemBuilder: (_, i) {
        final isAll = i == 0;
        final cat = isAll ? null : categories[i - 1];
        final selected = isAll
            ? categoryId == null
            : '$categoryId' == '${cat!['id']}';
        return GestureDetector(
          onTap: () {
            setState(() => categoryId = isAll ? null : '${cat!['id']}');
            _load(reset: true);
          },
          child: SizedBox(
            width: 74,
            child: Column(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? AppTheme.accentOrange
                        : AppTheme.backgroundWhite,
                    border: Border.all(
                      color: selected
                          ? AppTheme.accentOrange
                          : AppTheme.primaryNavy.withValues(alpha: 0.06),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isAll
                      ? Icon(
                          Icons.apps_rounded,
                          size: 26,
                          color: selected
                              ? Colors.white
                              : AppTheme.accentOrange,
                        )
                      : ClipOval(
                          child: AppImage(
                            J.str(cat!['image_url'] ?? cat['image']),
                            placeholder: app.placeholder,
                            thumb: true,
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  isAll ? app.t('all').trim() : _catName(cat!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? AppTheme.accentOrange
                        : AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap) {
    return Material(
      color: selected ? AppTheme.accentOrange : AppTheme.backgroundWhite,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AppTheme.accentOrange
                  : AppTheme.primaryNavy.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected)
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 5),
                  child: Icon(
                    Icons.check_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? Colors.white : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deletePost(dynamic id) async {
    final app = appController;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.t('confirm_delete_post')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(app.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(app.t('delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!await _needInternet(context)) return;
    final res = await appController.api.harajDelete(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.message.isNotEmpty ? res.message : app.t('post_deleted'),
        ),
      ),
    );
    if (res.ok) _load(reset: true);
  }

  Future<void> _markSold(dynamic id) async {
    final app = appController;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.t('mark_sold_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(app.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(app.t('mark_as_sold')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!await _needInternet(context)) return;
    final res = await appController.api.harajMarkSold(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.message.isNotEmpty ? res.message : app.t('haraj_sold'),
        ),
      ),
    );
    if (res.ok) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    if (widget.mine && !app.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(app.t('my_posts'))),
        body: const LoginRequired(),
      );
    }
    return Scaffold(
      // When opened from the shell (`/haraj`) the shared brand header is
      // shown by AppShell (logo, cart, notifications, search) — like home.
      // The "my posts" route is standalone, so it keeps its own AppBar.
      appBar: widget.mine
          ? AppBar(
              title: Text(app.t('my_posts')),
              actions: [
                IconButton(
                  onPressed: () => app.isLoggedIn
                      ? context.push('/haraj/create')
                      : context.push(
                          '/login?next=${Uri.encodeComponent('/haraj/create')}',
                        ),
                  icon: const Icon(Icons.add),
                ),
              ],
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: CustomScrollView(
          slivers: [
            if (widget.mine)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              sliver: SliverToBoxAdapter(
                child: SegmentedButton<int>(
                  segments: [
                    ButtonSegment(
                      value: 0,
                      label: Text(app.t('haraj_tab_all')),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text(app.t('haraj_tab_active')),
                    ),
                    ButtonSegment(
                      value: 2,
                      label: Text(app.t('haraj_tab_sold')),
                    ),
                  ],
                  selected: {mineTab},
                  onSelectionChanged: (s) {
                    setState(() => mineTab = s.first);
                    _load(reset: true);
                  },
                ),
              ),
            ),
          SliverToBoxAdapter(child: _topSection(app)),
          SliverToBoxAdapter(child: OfflineBanner(stale: _servedFromCache)),
          if (loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.campaign_outlined,
                message: widget.mine
                    ? app.t('haraj_my_posts_hint')
                    : app.t('no_haraj_posts'),
                actionLabel: app.isLoggedIn ? app.t('new_haraj') : null,
                onAction: app.isLoggedIn
                    ? () => context.push('/haraj/create')
                    : null,
              ),
            )
          else
            SliverLayoutBuilder(
              builder: (ctx, c) {
                final count = c.crossAxisExtent >= 900
                    ? 4
                    : c.crossAxisExtent >= 600
                    ? 3
                    : 2;
                return SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: count,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.68,
                    ),
                    delegate: SliverChildBuilderDelegate((_, i) {
                      if (i >= items.length) {
                        if (!loadingMore) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _loadMore();
                          });
                        }
                        return const Center(child: CircularProgressIndicator());
                      }
                      final post = items[i];
                      final sold = '${post['status']}' == '2';
                      final negotiable =
                          post['is_negotiable'] == 1 ||
                          post['is_negotiable'] == true ||
                          post['is_negotiable'] == '1';
                      return InkWell(
                        onTap: () => context.push('/haraj/${post['id']}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: AppImage(
                                        J.str(
                                          post['main_image_url'] ??
                                              post['image_url'] ??
                                              post['thumbnail'],
                                        ),
                                        placeholder: app.placeholder,
                                      ),
                                    ),
                                  ),
                                  if (sold)
                                    Positioned.directional(
                                      textDirection: Directionality.of(context),
                                      top: 6,
                                      start: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Text(
                                          app.t('sold'),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    )
                                  else if (negotiable)
                                    Positioned.directional(
                                      textDirection: Directionality.of(context),
                                      top: 6,
                                      start: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Text(
                                          app.t('negotiable'),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              J.str(post['title']),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            Text(
                              money(post['price'], app.currency, app.decimals),
                              style: TextStyle(
                                color: app.accentColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              [
                                J.str(
                                  post['city'] ??
                                      post['cityRef']?['name'] ??
                                      post['city_ref']?['name'],
                                ),
                                _catNameOf(post),
                                timeAgo(
                                  J.str(post['created_at'] ?? post['date']),
                                ),
                              ].where((p) => p.isNotEmpty).join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                            if (widget.mine)
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 16),
                                    tooltip: app.t('edit'),
                                    onPressed: () => context.push(
                                      '/haraj/edit/${post['id']}',
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 16),
                                    tooltip: app.t('delete'),
                                    onPressed: () => _deletePost(post['id']),
                                  ),
                                  if (!sold)
                                    IconButton(
                                      icon: const Icon(Icons.check, size: 16),
                                      tooltip: app.t('mark_as_sold'),
                                      onPressed: () => _markSold(post['id']),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      );
                    }, childCount: items.length + (page < lastPage ? 1 : 0)),
                    ),
                  );
                },
              ),
          ],
          ),
        ),
      );
  }

  String _catNameOf(Map<String, dynamic> post) {
    final cat = J.map(post['category']);
    if (cat.isEmpty) return '';
    return _catName(cat);
  }
}

String timeAgo(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  final app = appController;
  if (diff.inMinutes < 1) return app.t('just_now');
  if (diff.inHours < 1) {
    return app.t('minutes_ago').replaceAll('{n}', '${diff.inMinutes}');
  }
  if (diff.inDays < 1) {
    return app.t('hours_ago').replaceAll('{n}', '${diff.inHours}');
  }
  return app.t('days_ago').replaceAll('{n}', '${diff.inDays}');
}

class HarajDetailsScreen extends StatefulWidget {
  const HarajDetailsScreen({super.key, required this.id});
  final String id;

  @override
  State<HarajDetailsScreen> createState() => _HarajDetailsScreenState();
}

class _HarajDetailsScreenState extends State<HarajDetailsScreen> {
  Map<String, dynamic>? post;
  List<Map<String, dynamic>> comments = [];
  final comment = TextEditingController();
  bool loading = true;
  bool failed = false;
  dynamic replyTo;
  double userRating = 0;
  bool blocked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  bool _servedFromCache = false;

  Future<void> _load() async {
    // Local-first: last synchronized ad paints offline (stale-labeled).
    final snap =
        appController.readPublicSnapshot('haraj_detail_${widget.id}') as Map?;
    if (snap != null && post == null && mounted) {
      setState(() {
        post = J.map(snap['post']);
        comments = J.maps(snap['comments']);
        loading = false;
        failed = post == null || post!.isEmpty;
        _servedFromCache = true;
      });
    }
    final result = await appController.api.harajPost(widget.id);
    final c = await appController.api.harajComments(widget.id);
    if (!mounted) return;
    final next = result.dataMap.isNotEmpty
        ? result.dataMap
        : J.map(result.raw['data']);
    setState(() {
      post = result.ok ? next : post;
      comments = c.ok ? c.dataMaps : comments;
      loading = false;
      failed = post == null || post!.isEmpty;
      _servedFromCache = !result.ok && post != null;
    });
    if (result.ok && next.isNotEmpty) {
      await appController.cachePublicSnapshot('haraj_detail_${widget.id}', {
        'post': next,
        'comments': c.ok ? c.dataMaps : comments,
      });
    }
    // load ratings if post has user
    final userId = post?['user_id'] ?? post?['user']?['id'];
    if (userId != null) {
      final r = await appController.api.harajUserRatings(userId);
      if (mounted && r.ok) {
        // could show
      }
    }
  }

  Future<void> _openWhatsApp() async {
    final app = appController;
    final phone = J
        .str(post?['contact_whatsapp'])
        .replaceAll(RegExp(r'[^\d]'), '');
    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(app.t('whatsapp_not_available'))));
      return;
    }
    final title = J.str(post?['title']);
    final text = app.t('whatsapp_message').replaceAll('{{title}}', title);
    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(text)}',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(app.t('whatsapp_not_available'))));
    }
  }

  Future<void> _addComment() async {
    final app = appController;
    if (!app.isLoggedIn) {
      if (mounted) {
        context.push(
          '/login?next=${Uri.encodeComponent('/haraj/${widget.id}')}',
        );
      }
      return;
    }
    if (comment.text.trim().isEmpty) return;
    if (!await _needInternet(context)) return;
    final res = await appController.api.harajAddComment(
      widget.id,
      comment.text.trim(),
      parentId: replyTo,
    );
    if (!mounted) return;
    if (res.ok) {
      comment.clear();
      replyTo = null;
      _load();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.message)));
    }
  }

  Future<void> _updateComment(dynamic id, String old) async {
    final app = appController;
    final ctrl = TextEditingController(text: old);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.t('edit')),
        content: TextField(controller: ctrl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(app.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(app.t('save')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!await _needInternet(context)) return;
    final res = await appController.api.harajUpdateComment(
      id,
      ctrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.message.isNotEmpty ? res.message : app.t('save')),
      ),
    );
    if (res.ok) _load();
  }

  Future<void> _deleteComment(dynamic id) async {
    final app = appController;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.t('confirm_delete_comment')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(app.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(app.t('delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!await _needInternet(context)) return;
    final res = await appController.api.harajDeleteComment(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.message.isNotEmpty ? res.message : app.t('comment_deleted'),
        ),
      ),
    );
    if (res.ok) _load();
  }

  Future<void> _rateUser() async {
    final app = appController;
    final uid = post?['user_id'] ?? post?['user']?['id'];
    if (uid == null) return;
    if (!app.isLoggedIn) {
      if (mounted) {
        context.push(
          '/login?next=${Uri.encodeComponent('/haraj/${widget.id}')}',
        );
      }
      return;
    }
    int rating = 5;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(app.t('haraj_rate_seller')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      icon: Icon(
                        i <= rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                      ),
                      onPressed: () => setS(() => rating = i),
                    ),
                ],
              ),
              TextField(
                controller: ctrl,
                maxLines: 2,
                decoration: InputDecoration(hintText: app.t('write_comment')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(app.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(app.t('rate')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (!await _needInternet(context)) return;
    final res = await appController.api.harajRate({
      'rated_user_id': uid,
      'post_id': widget.id,
      'rating': rating,
      'comment': ctrl.text.trim(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.message.isNotEmpty
              ? res.message
              : app.t('rating_saved_successfully'),
        ),
      ),
    );
    if (res.ok) _load();
  }

  Future<void> _toggleBlock() async {
    final app = appController;
    final uid = post?['user_id'] ?? post?['user']?['id'];
    if (uid == null) return;
    if (!await _needInternet(context)) return;
    if (!blocked) {
      final ok = await confirmAction(
        context,
        title: app.t('block'),
        body: app.t('haraj_block_confirm'),
      );
      if (!ok) return;
    }
    final res = blocked
        ? await appController.api.harajUnblock(uid)
        : await appController.api.harajBlock(uid);
    if (!mounted) return;
    if (res.ok) setState(() => blocked = !blocked);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.message.isNotEmpty
              ? res.message
              : (blocked ? app.t('block') : app.t('unblock')),
        ),
      ),
    );
  }

  static const _reportReasons = [
    'fake',
    'scam',
    'wrong_price',
    'already_sold',
    'prohibited',
    'wrong_category',
    'other',
  ];

  String _reasonLabel(String reason) {
    return appController.t('haraj_reason_$reason');
  }

  Future<void> _report() async {
    final app = appController;
    if (!app.isLoggedIn) {
      if (mounted) {
        context.push(
          '/login?next=${Uri.encodeComponent('/haraj/${widget.id}')}',
        );
      }
      return;
    }
    String reason = 'fake';
    final detailsCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(app.t('haraj_report_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ..._reportReasons.map(
                  (r) => RadioListTile<String>(
                    value: r,
                    groupValue: reason,
                    onChanged: (v) {
                      if (v != null) setS(() => reason = v);
                    },
                    title: Text(_reasonLabel(r)),
                  ),
                ),
                TextField(
                  controller: detailsCtrl,
                  maxLines: 3,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    labelText: app.t('haraj_report_details'),
                  ),
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
              child: Text(app.t('haraj_report')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (!await _needInternet(context)) return;
    final res = await appController.api.harajReport(
      widget.id,
      reason: reason,
      details: detailsCtrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.message.isNotEmpty
              ? res.message
              : res.ok
              ? app.t('haraj_report_sent')
              : app.t('something_went_wrong'),
        ),
      ),
    );
  }

  Future<void> _markSold() async {
    final app = appController;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.t('mark_sold_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(app.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(app.t('mark_as_sold')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!await _needInternet(context)) return;
    final res = await appController.api.harajMarkSold(widget.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.message.isNotEmpty ? res.message : app.t('haraj_sold'),
        ),
      ),
    );
    if (res.ok) _load();
  }

  Future<void> _callSeller(String phone) async {
    final uri = Uri.parse('tel:$phone');
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final isMine =
        '${post?['user_id']}' == '${app.user?['id']}' && app.isLoggedIn;
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (failed || post == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.error_outline,
          message: app.t('not_synced_yet'),
          actionLabel: app.t('retry'),
          onAction: () {
            setState(() {
              loading = true;
              failed = false;
            });
            _load();
          },
        ),
      );
    }
    final p = post!;
    final sold = '${p['status']}' == '2';
    final negotiable =
        p['is_negotiable'] == 1 ||
        p['is_negotiable'] == true ||
        p['is_negotiable'] == '1';
    final gallery = <String>[
      J.str(p['main_image_url']),
      ...J.maps(p['images']).map((e) => J.str(e['image_url'] ?? e['url'])),
    ].where((u) => u.isNotEmpty).toList();
    final seller = J.map(p['user']);
    final ownerRating = J.map(p['owner_rating']);
    final myRating = J.map(p['my_rating']);
    final cat = J.map(p['category']);
    final parentCat = J.map(cat['parent']);
    final cityName = J.str(
      p['city'] ?? p['cityRef']?['name'] ?? p['city_ref']?['name'],
    );
    final allComments = J.i(p['all_comments_count']);
    final contactPhone = J
        .str(p['contact_phone'])
        .replaceAll(RegExp(r'[^\d+]'), '');
    final showContact = !isMine && !sold;
    return Scaffold(
      appBar: AppBar(
        title: Text(J.str(p['title'])),
        actions: [
          if (isMine) ...[
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: app.t('edit'),
              onPressed: () => context.push('/haraj/edit/${p['id']}'),
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: app.t('delete'),
              onPressed: () async {
                if (!await _needInternet(context)) return;
                final r = await appController.api.harajDelete(p['id']);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        r.message.isNotEmpty
                            ? r.message
                            : app.t('post_deleted'),
                      ),
                    ),
                  );
                  if (r.ok) context.pop();
                }
              },
            ),
            if (!sold)
              IconButton(
                icon: const Icon(Icons.check),
                tooltip: app.t('mark_as_sold'),
                onPressed: _markSold,
              ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.star_border),
              tooltip: app.t('haraj_rate_seller'),
              onPressed: _rateUser,
            ),
            IconButton(
              icon: Icon(blocked ? Icons.block : Icons.person_off_outlined),
              tooltip: blocked ? app.t('unblock') : app.t('block'),
              onPressed: _toggleBlock,
            ),
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: app.t('haraj_report'),
              onPressed: _report,
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OfflineBanner(stale: _servedFromCache),
          if (gallery.isNotEmpty)
            _Gallery(images: gallery, sold: sold, app: app)
          else
            AspectRatio(
              aspectRatio: 16 / 10,
              child: AppImage(null, placeholder: app.placeholder),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (sold)
                _badge(app.t('sold'), Colors.red)
              else if (negotiable)
                _badge(app.t('negotiable'), Colors.green),
              if (sold || negotiable) const SizedBox(width: 6),
              Expanded(
                child: Text(
                  J.str(p['title']),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${money(p['price'], app.currency, app.decimals)}${negotiable ? ' • ${app.t('negotiable')}' : ''}',
            style: TextStyle(
              color: app.accentColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _meta(
                Icons.access_time,
                timeAgo(J.str(p['created_at'] ?? p['date'])),
              ),
              _meta(
                Icons.visibility_outlined,
                '${J.str(p['views_count'])} ${app.t('haraj_views')}',
              ),
              if (J.str(p['condition']).isNotEmpty)
                _meta(
                  Icons.label_outline,
                  _conditionLabel(J.str(p['condition'])),
                ),
              if (cityName.isNotEmpty)
                _meta(Icons.location_on_outlined, cityName),
              if (J.str(p['location']).isNotEmpty)
                _meta(Icons.place_outlined, J.str(p['location'])),
              if (_catName(cat).isNotEmpty)
                _meta(
                  Icons.category_outlined,
                  parentCat.isNotEmpty
                      ? '${_catName(parentCat)} / ${_catName(cat)}'
                      : _catName(cat),
                ),
              if (allComments > 0)
                _meta(Icons.comment_outlined, '$allComments'),
            ],
          ),
          const SizedBox(height: 10),
          Text(J.str(p['description'])),
          const Divider(),
          // Seller
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundImage: J.str(seller['profile']).isNotEmpty
                  ? NetworkImage(J.str(seller['profile']))
                  : null,
              child: J.str(seller['profile']).isEmpty
                  ? Text(
                      J.str(seller['name']).isEmpty
                          ? '?'
                          : J.str(seller['name']).substring(0, 1),
                    )
                  : null,
            ),
            title: Text(J.str(seller['name'])),
            subtitle: _ownerRatingRow(ownerRating, myRating),
          ),
          if (myRating.isNotEmpty)
            Text(
              '${app.t('haraj_my_rating')}: ${J.str(myRating['rating'])} ★',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          const SizedBox(height: 8),
          if (showContact) ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _openWhatsApp,
                    icon: const Icon(Icons.chat),
                    label: Text(app.t('contact_seller')),
                  ),
                ),
                if (contactPhone.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _callSeller(contactPhone),
                      icon: const Icon(Icons.call),
                      label: Text(app.t('call')),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              app.t('haraj_safety_hint'),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
          const Divider(),
          Text(
            app.t('comments'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          ...comments.map((item) => _commentTile(item, isMine)),
          if (replyTo != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${app.t('haraj_comment_reply')} #$replyTo',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => replyTo = null),
                    child: Text(app.t('cancel')),
                  ),
                ],
              ),
            ),
          if (app.isLoggedIn)
            TextField(
              controller: comment,
              decoration: InputDecoration(
                hintText: app.t('write_comment'),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _addComment,
                ),
              ),
            )
          else
            TextButton(
              onPressed: () => context.push(
                '/login?next=${Uri.encodeComponent('/haraj/${widget.id}')}',
              ),
              child: Text(app.t('login_to_comment')),
            ),
        ],
      ),
    );
  }

  String _catName(Map<String, dynamic> cat) {
    final isAr = appController.i18n.code == 'ar';
    final ar = J.str(cat['name_ar']);
    final en = J.str(cat['name_en'] ?? cat['name']);
    return isAr ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
  }

  String _conditionLabel(String c) {
    final app = appController;
    switch (c) {
      case 'new':
        return app.t('condition_new');
      case 'like_new':
        return app.t('condition_like_new');
      case 'used':
        return app.t('condition_used');
      default:
        return c;
    }
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Widget _ownerRatingRow(
    Map<String, dynamic> ownerRating,
    Map<String, dynamic> myRating,
  ) {
    if (ownerRating.isEmpty && myRating.isEmpty) return const SizedBox.shrink();
    final avg = double.tryParse('${ownerRating['average'] ?? ''}') ?? 0;
    final count = J.str(ownerRating['count']);
    return Row(
      children: [
        const Icon(Icons.star, size: 14, color: Colors.amber),
        const SizedBox(width: 2),
        Text(
          avg > 0 ? avg.toStringAsFixed(1) : '—',
          style: const TextStyle(fontSize: 12),
        ),
        if (count.isNotEmpty)
          Text(
            ' ($count)',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
      ],
    );
  }

  Widget _commentTile(Map<String, dynamic> item, bool postMine) {
    final app = appController;
    final user = J.map(item['user']);
    final userName = J.str(item['user_name'] ?? user['name']);
    final mine = '${item['user_id']}' == '${app.user?['id']}' && app.isLoggedIn;
    final owner = postMine && mine;
    final replies = J.maps(item['replies']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 16,
            backgroundImage: J.str(user['profile']).isNotEmpty
                ? NetworkImage(J.str(user['profile']))
                : null,
            child: J.str(user['profile']).isEmpty
                ? Text(
                    userName.isEmpty ? '?' : userName.substring(0, 1),
                    style: const TextStyle(fontSize: 12),
                  )
                : null,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  userName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (owner)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: app.accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    app.t('owner'),
                    style: TextStyle(fontSize: 10, color: app.accentColor),
                  ),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(J.str(item['comment'] ?? item['body'])),
              Text(
                timeAgo(J.str(item['created_at'])),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.reply, size: 16),
                onPressed: () => setState(() => replyTo = item['id']),
              ),
              if (mine)
                IconButton(
                  icon: const Icon(Icons.edit, size: 16),
                  onPressed: () => _updateComment(
                    item['id'],
                    J.str(item['comment'] ?? item['body']),
                  ),
                ),
              if (mine)
                IconButton(
                  icon: const Icon(Icons.delete, size: 16),
                  onPressed: () => _deleteComment(item['id']),
                ),
            ],
          ),
        ),
        if (replies.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 32),
            child: Column(
              children: replies.map((r) {
                final ru = J.map(r['user']);
                final rMine =
                    '${r['user_id']}' == '${app.user?['id']}' && app.isLoggedIn;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: CircleAvatar(
                    radius: 13,
                    child: Text(
                      J.str(ru['name']).isEmpty
                          ? '?'
                          : J.str(ru['name']).substring(0, 1),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  title: Text(
                    J.str(ru['name']),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              J.str(r['comment'] ?? r['body']),
                              style: const TextStyle(fontSize: 13),
                            ),
                            Text(
                              timeAgo(J.str(r['created_at'])),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (rMine)
                        IconButton(
                          icon: const Icon(Icons.delete, size: 16),
                          onPressed: () => _deleteComment(r['id']),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

class _Gallery extends StatefulWidget {
  const _Gallery({required this.images, required this.sold, required this.app});
  final List<String> images;
  final bool sold;
  final AppController app;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final controller = PageController();
  int index = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 10,
          child: Stack(
            children: [
              PageView.builder(
                controller: controller,
                itemCount: widget.images.length,
                onPageChanged: (i) => setState(() => index = i),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AppImage(
                    widget.images[i],
                    placeholder: widget.app.placeholder,
                  ),
                ),
              ),
              if (widget.images.length > 1)
                Positioned.directional(
                  textDirection: Directionality.of(context),
                  bottom: 8,
                  end: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${index + 1}/${widget.images.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              if (widget.sold)
                Positioned.directional(
                  textDirection: Directionality.of(context),
                  top: 8,
                  start: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.app.t('sold'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.images.length > 1) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.images.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => controller.jumpToPage(i),
                child: Container(
                  width: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: i == index
                          ? widget.app.accentColor
                          : Colors.grey.shade300,
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: AppImage(
                      widget.images[i],
                      placeholder: widget.app.placeholder,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class HarajCreateScreen extends StatefulWidget {
  const HarajCreateScreen({super.key});

  @override
  State<HarajCreateScreen> createState() => _HarajCreateScreenState();
}

class _HarajCreateScreenState extends State<HarajCreateScreen> {
  final title = TextEditingController();
  final price = TextEditingController();
  final description = TextEditingController();
  final whatsapp = TextEditingController();
  final contactPhone = TextEditingController();
  final location = TextEditingController();
  List<Map<String, dynamic>> categories = [];
  String? categoryId;
  String? condition;
  bool negotiable = false;
  String? cityId;
  XFile? mainImage;
  List<XFile> images = [];
  bool busy = false;

  static const _maxImageBytes = 5 * 1024 * 1024;

  static const _draftFormId = 'haraj_create';
  bool _draftRestored = false;
  Timer? _draftDeb;

  @override
  void initState() {
    super.initState();
    cityId = '${appController.city?['id'] ?? ''}';
    _restoreDraft();
    for (final c in [
      title,
      price,
      description,
      whatsapp,
      contactPhone,
      location,
    ]) {
      c.addListener(_saveDraftSoon);
    }
    try {
      final snap = appController.readPublicSnapshot('haraj_feed');
      if (snap is Map && snap['categories'] is List) {
        final seeded = J.maps(snap['categories']);
        if (seeded.isNotEmpty) categories = seeded;
      }
    } catch (_) {}
    appController.api.harajCategoriesAll().then((res) {
      if (!mounted) return;
      if (res.ok && res.dataMaps.isNotEmpty) {
        setState(() => categories = res.dataMaps);
      }
    });
  }

  /// Restores the locally saved ad draft (never auto-published).
  Future<void> _restoreDraft() async {
    try {
      final draft = appController.offline.readDraft(
        appController.accountScope,
        _draftFormId,
      );
      if (draft == null) return;
      title.text = J.str(draft['title']);
      price.text = J.str(draft['price']);
      description.text = J.str(draft['description']);
      whatsapp.text = J.str(draft['whatsapp']);
      contactPhone.text = J.str(draft['contactPhone']);
      location.text = J.str(draft['location']);
      final cat = J.str(draft['categoryId']);
      if (cat.isNotEmpty) categoryId = cat;
      final cond = J.str(draft['condition']);
      if (cond.isNotEmpty) condition = cond;
      negotiable = draft['negotiable'] == true;
      final c = J.str(draft['cityId']);
      if (c.isNotEmpty) cityId = c;
      final paths = (draft['images'] as List? ?? [])
          .map((e) => J.str(e))
          .where((e) => e.isNotEmpty)
          .toList();
      final kept = <XFile>[];
      for (final p in paths) {
        try {
          if (await File(p).exists()) kept.add(XFile(p));
        } catch (_) {}
      }
      if (kept.isNotEmpty) images = kept;
      _draftRestored =
          title.text.isNotEmpty ||
          description.text.isNotEmpty ||
          price.text.isNotEmpty;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _saveDraftSoon() {
    _draftDeb?.cancel();
    _draftDeb = Timer(const Duration(milliseconds: 800), () async {
      try {
        await appController.offline.writeDraft(
          appController.accountScope,
          _draftFormId,
          {
            'title': title.text,
            'price': price.text,
            'description': description.text,
            'whatsapp': whatsapp.text,
            'contactPhone': contactPhone.text,
            'location': location.text,
            'categoryId': categoryId ?? '',
            'condition': condition ?? '',
            'negotiable': negotiable,
            'cityId': cityId ?? '',
            'images': [...images.map((e) => e.path)],
          },
        );
      } catch (_) {}
    });
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _saveDraftSoon();
  }

  @override
  void dispose() {
    _draftDeb?.cancel();
    title.dispose();
    price.dispose();
    description.dispose();
    whatsapp.dispose();
    contactPhone.dispose();
    location.dispose();
    super.dispose();
  }

  String _catName(Map<String, dynamic> cat) {
    final isAr = appController.i18n.code == 'ar';
    final ar = J.str(cat['name_ar']);
    final en = J.str(cat['name_en'] ?? cat['name']);
    return isAr ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
  }

  Future<XFile?> _pickOne() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    if (await picked.length() > _maxImageBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appController.t('image_too_large'))),
        );
      }
      return null;
    }
    return picked;
  }

  Future<void> _submit() async {
    final app = appController;
    if (title.text.trim().isEmpty ||
        title.text.trim().length > 255 ||
        price.text.trim().isEmpty ||
        description.text.trim().isEmpty ||
        categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            title.text.trim().length > 255
                ? app.t('title_max_length')
                : app.t('fill_required_fields'),
          ),
        ),
      );
      return;
    }
    if (whatsapp.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(app.t('whatsapp_required_for_haraj'))),
      );
      return;
    }
    if (cityId == null || cityId!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(app.t('select_city_required'))));
      return;
    }
    if (!await _needInternet(context)) return;
    setState(() => busy = true);
    try {
      final data = FormData();
      data.fields.addAll([
        MapEntry('title', title.text.trim()),
        MapEntry('price', price.text.trim()),
        MapEntry('description', description.text.trim()),
        MapEntry('category_id', '$categoryId'),
        MapEntry('city_id', '$cityId'),
        MapEntry('location', location.text.trim()),
        MapEntry('contact_phone', contactPhone.text.trim()),
        MapEntry('contact_whatsapp', whatsapp.text.trim()),
        if (condition != null) MapEntry('condition', condition!),
        MapEntry('is_negotiable', negotiable ? '1' : '0'),
      ]);
      if (mainImage != null) {
        data.files.add(
          MapEntry(
            'main_image',
            await MultipartFile.fromFile(
              mainImage!.path,
              filename: mainImage!.name,
            ),
          ),
        );
      }
      for (final img in images) {
        if (await img.length() > _maxImageBytes) continue;
        data.files.add(
          MapEntry(
            'images[]',
            await MultipartFile.fromFile(img.path, filename: img.name),
          ),
        );
      }
      final result = await app.api.harajCreate(data);
      if (!mounted) return;
      if (result.ok) {
        try {
          await app.offline.removeDraft(app.accountScope, _draftFormId);
        } catch (_) {}
        final created = J.map(result.dataMap['data']);
        final id = J.str(created['id']).isNotEmpty
            ? J.str(created['id'])
            : J.str(result.dataMap['id']);
        if (id.isNotEmpty) {
          context.go('/haraj/$id');
        } else {
          context.pop();
        }
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    if (!app.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(app.t('new_haraj'))),
        body: const LoginRequired(),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(app.t('new_haraj'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: title,
            maxLength: 255,
            decoration: InputDecoration(labelText: app.t('haraj_title')),
          ),
          TextField(
            controller: price,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '${app.t('price')} (${app.currency})',
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue:
                categoryId != null &&
                        categories.any((c) => '${c['id']}' == '$categoryId')
                    ? categoryId
                    : null,
            items: categories
                .map(
                  (cat) => DropdownMenuItem(
                    value: '${cat['id']}',
                    child: Text(_catName(cat)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => categoryId = v),
            decoration: InputDecoration(labelText: app.t('haraj_categories')),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String?>(
            segments: [
              ButtonSegment(value: null, label: Text(app.t('haraj_condition'))),
              ButtonSegment(value: 'new', label: Text(app.t('condition_new'))),
              ButtonSegment(
                value: 'like_new',
                label: Text(app.t('condition_like_new')),
              ),
              ButtonSegment(
                value: 'used',
                label: Text(app.t('condition_used')),
              ),
            ],
            selected: {condition},
            onSelectionChanged: (s) => setState(() => condition = s.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(app.t('haraj_is_negotiable')),
            value: negotiable,
            onChanged: (v) => setState(() => negotiable = v),
          ),
          TextField(
            controller: description,
            maxLines: 4,
            decoration: InputDecoration(labelText: app.t('haraj_description')),
          ),
          DropdownButtonFormField<String>(
            initialValue:
                cityId!.isEmpty ||
                    app.cities.every((c) => '${c['id']}' != cityId)
                ? null
                : cityId,
            items: app.cities
                .map(
                  (c) => DropdownMenuItem(
                    value: '${c['id']}',
                    child: Text(J.str(c['name'])),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => cityId = v),
            decoration: InputDecoration(labelText: '${app.t('haraj_city')} *'),
          ),
          TextField(
            controller: location,
            decoration: InputDecoration(labelText: app.t('haraj_location')),
          ),
          TextField(
            controller: contactPhone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: app.t('haraj_contact_phone'),
            ),
          ),
          TextField(
            controller: whatsapp,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: '${app.t('whatsapp_number')} *',
              helperText: app.t('whatsapp_preferred_hint'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            app.t('haraj_main_image'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextButton.icon(
            onPressed: () async {
              final one = await _pickOne();
              if (one != null && mounted) setState(() => mainImage = one);
            },
            icon: const Icon(Icons.image),
            label: Text(
              mainImage == null ? app.t('haraj_main_image') : mainImage!.name,
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              final picked = await ImagePicker().pickMultiImage();
              if (picked.isNotEmpty && mounted) {
                final ok = <XFile>[];
                for (final p in picked) {
                  if (await p.length() <= _maxImageBytes) ok.add(p);
                }
                if (ok.length != picked.length && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(app.t('image_too_large'))),
                  );
                }
                setState(() => images = [...images, ...ok]);
              }
            },
            icon: const Icon(Icons.photo_library),
            label: Text(
              images.isEmpty
                  ? app.t('haraj_photo')
                  : '${images.length} ${app.t('haraj_photo')}',
            ),
          ),
          if (images.isNotEmpty)
            Wrap(
              children: images
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(e.name, style: const TextStyle(fontSize: 11)),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy ? null : _submit,
            child: busy ? const BusySpinner() : Text(app.t('confirm')),
          ),
          if (_draftRestored)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                appController.t('draft_saved'),
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class HarajEditScreen extends StatefulWidget {
  const HarajEditScreen({super.key, required this.id});
  final String id;
  @override
  State<HarajEditScreen> createState() => _HarajEditScreenState();
}

class _HarajEditScreenState extends State<HarajEditScreen> {
  final title = TextEditingController();
  final price = TextEditingController();
  final description = TextEditingController();
  final whatsapp = TextEditingController();
  final contactPhone = TextEditingController();
  final location = TextEditingController();
  List<Map<String, dynamic>> categories = [];
  String? categoryId;
  String? condition;
  bool negotiable = false;
  String? cityId;
  XFile? mainImage;
  String? mainImageUrl;
  List<XFile> newImages = [];
  List<Map<String, dynamic>> existingImages = [];
  bool loading = true;
  bool busy = false;

  static const _maxImageBytes = 5 * 1024 * 1024;

  String get _draftFormId => 'haraj_edit_${widget.id}';
  bool _draftRestored = false;
  Timer? _draftDeb;

  @override
  void initState() {
    super.initState();
    for (final c in [
      title,
      price,
      description,
      whatsapp,
      contactPhone,
      location,
    ]) {
      c.addListener(_saveDraftSoon);
    }
    _load();
  }

  void _saveDraftSoon() {
    _draftDeb?.cancel();
    _draftDeb = Timer(const Duration(milliseconds: 800), () async {
      try {
        await appController.offline
            .writeDraft(appController.accountScope, _draftFormId, {
              'title': title.text,
              'price': price.text,
              'description': description.text,
              'whatsapp': whatsapp.text,
              'contactPhone': contactPhone.text,
              'location': location.text,
              'categoryId': categoryId ?? '',
              'condition': condition ?? '',
              'negotiable': negotiable,
              'cityId': cityId ?? '',
            });
      } catch (_) {}
    });
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _saveDraftSoon();
  }

  @override
  void dispose() {
    _draftDeb?.cancel();
    title.dispose();
    price.dispose();
    description.dispose();
    whatsapp.dispose();
    contactPhone.dispose();
    location.dispose();
    super.dispose();
  }

  String _catName(Map<String, dynamic> cat) {
    final isAr = appController.i18n.code == 'ar';
    final ar = J.str(cat['name_ar']);
    final en = J.str(cat['name_en'] ?? cat['name']);
    return isAr ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
  }

  bool _loadFailed = false;

  Future<void> _load() async {
    try {
      final snap = appController.readPublicSnapshot('haraj_feed');
      if (snap is Map && snap['categories'] is List) {
        final seeded = J.maps(snap['categories']);
        if (seeded.isNotEmpty && mounted) setState(() => categories = seeded);
      }
    } catch (_) {}
    final catRes = await appController.api.harajCategoriesAll();
    final postRes = await appController.api.harajPost(widget.id);
    if (!mounted) return;
    Map<String, dynamic> post = postRes.ok
        ? postRes.dataMap
        : <String, dynamic>{};
    if (post.isEmpty) {
      try {
        final snap = appController.readPublicSnapshot(
          'haraj_detail_${widget.id}',
        );
        if (snap is Map) post = J.map(snap['post']);
      } catch (_) {}
    }
    if (post.isEmpty) {
      setState(() {
        if (catRes.ok && catRes.dataMaps.isNotEmpty) {
          categories = catRes.dataMaps;
        }
        loading = false;
        _loadFailed = true;
      });
      return;
    }
    // A locally edited draft wins over the server snapshot for text fields
    // (never auto-submitted; explicit Save still required).
    Map<String, dynamic>? draft;
    try {
      draft = appController.offline.readDraft(
        appController.accountScope,
        _draftFormId,
      );
    } catch (_) {}
    setState(() {
      if (catRes.ok && catRes.dataMaps.isNotEmpty) {
        categories = catRes.dataMaps;
      }
      title.text = J.str(post['title']);
      price.text = J.str(post['price']);
      description.text = J.str(post['description']);
      whatsapp.text = J.str(post['contact_whatsapp']);
      contactPhone.text = J.str(post['contact_phone']);
      location.text = J.str(post['location']);
      categoryId = '${post['category_id'] ?? ''}';
      final cond = J.str(post['condition']);
      condition = ['new', 'used', 'like_new'].contains(cond) ? cond : null;
      negotiable =
          post['is_negotiable'] == 1 ||
          post['is_negotiable'] == true ||
          post['is_negotiable'] == '1';
      cityId = J.str(post['city_id']);
      mainImageUrl = J.str(post['main_image_url']).isNotEmpty
          ? J.str(post['main_image_url'])
          : null;
      existingImages = J.maps(post['images']);
      if (draft != null) {
        final t = J.str(draft['title']);
        if (t.isNotEmpty) title.text = t;
        final pr = J.str(draft['price']);
        if (pr.isNotEmpty) price.text = pr;
        final d = J.str(draft['description']);
        if (d.isNotEmpty) description.text = d;
        final w = J.str(draft['whatsapp']);
        if (w.isNotEmpty) whatsapp.text = w;
        final cp = J.str(draft['contactPhone']);
        if (cp.isNotEmpty) contactPhone.text = cp;
        final loc = J.str(draft['location']);
        if (loc.isNotEmpty) location.text = loc;
        _draftRestored = true;
      }
      loading = false;
    });
  }

  Future<void> _submit() async {
    final app = appController;
    if (title.text.trim().isEmpty || title.text.trim().length > 255) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            title.text.trim().length > 255
                ? app.t('title_max_length')
                : app.t('fill_required_fields'),
          ),
        ),
      );
      return;
    }
    if (whatsapp.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(app.t('whatsapp_required_for_haraj'))),
      );
      return;
    }
    if (!await _needInternet(context)) return;
    setState(() => busy = true);
    try {
      final data = FormData();
      data.fields.addAll([
        MapEntry('title', title.text.trim()),
        MapEntry('price', price.text.trim()),
        MapEntry('description', description.text.trim()),
        if (categoryId != null && categoryId!.isNotEmpty)
          MapEntry('category_id', '$categoryId'),
        if (cityId != null && cityId!.isNotEmpty)
          MapEntry('city_id', '$cityId'),
        MapEntry('location', location.text.trim()),
        MapEntry('contact_phone', contactPhone.text.trim()),
        MapEntry('contact_whatsapp', whatsapp.text.trim()),
        if (condition != null) MapEntry('condition', condition!),
        MapEntry('is_negotiable', negotiable ? '1' : '0'),
      ]);
      if (mainImage != null) {
        data.files.add(
          MapEntry(
            'main_image',
            await MultipartFile.fromFile(
              mainImage!.path,
              filename: mainImage!.name,
            ),
          ),
        );
      }
      for (final img in newImages) {
        if (await img.length() > _maxImageBytes) continue;
        data.files.add(
          MapEntry(
            'images[]',
            await MultipartFile.fromFile(img.path, filename: img.name),
          ),
        );
      }
      final res = await app.api.harajUpdate(widget.id, data);
      if (!mounted) return;
      if (res.ok) {
        try {
          await app.offline.removeDraft(app.accountScope, _draftFormId);
        } catch (_) {}
        context.pop();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(res.message)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _deleteImage(dynamic imageId) async {
    final app = appController;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.t('confirm_delete_image')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(app.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(app.t('delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!await _needInternet(context)) return;
    final res = await appController.api.harajDeleteImage(widget.id, imageId);
    if (!mounted) return;
    if (res.ok) {
      setState(
        () => existingImages.removeWhere((e) => '${e['id']}' == '$imageId'),
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.message.isNotEmpty
              ? res.message
              : app.t(res.ok ? 'image_deleted' : 'something_went_wrong'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadFailed) {
      return Scaffold(
        appBar: AppBar(title: Text(app.t('edit_post'))),
        body: EmptyState(
          icon: Icons.error_outline,
          message: app.t('something_went_wrong'),
          actionLabel: app.t('retry'),
          onAction: () {
            setState(() {
              loading = true;
              _loadFailed = false;
            });
            _load();
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(app.t('edit_post'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: title,
            maxLength: 255,
            decoration: InputDecoration(labelText: app.t('haraj_title')),
          ),
          TextField(
            controller: price,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '${app.t('price')} (${app.currency})',
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: categories.any((c) => '${c['id']}' == '$categoryId')
                ? '$categoryId'
                : null,
            items: categories
                .map(
                  (cat) => DropdownMenuItem(
                    value: '${cat['id']}',
                    child: Text(_catName(cat)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => categoryId = v),
            decoration: InputDecoration(labelText: app.t('haraj_categories')),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String?>(
            segments: [
              ButtonSegment(value: null, label: Text(app.t('haraj_condition'))),
              ButtonSegment(value: 'new', label: Text(app.t('condition_new'))),
              ButtonSegment(
                value: 'like_new',
                label: Text(app.t('condition_like_new')),
              ),
              ButtonSegment(
                value: 'used',
                label: Text(app.t('condition_used')),
              ),
            ],
            selected: {condition},
            onSelectionChanged: (s) => setState(() => condition = s.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(app.t('haraj_is_negotiable')),
            value: negotiable,
            onChanged: (v) => setState(() => negotiable = v),
          ),
          TextField(
            controller: description,
            maxLines: 4,
            decoration: InputDecoration(labelText: app.t('haraj_description')),
          ),
          DropdownButtonFormField<String>(
            initialValue:
                cityId!.isEmpty ||
                    app.cities.every((c) => '${c['id']}' != cityId)
                ? null
                : cityId,
            items: app.cities
                .map(
                  (c) => DropdownMenuItem(
                    value: '${c['id']}',
                    child: Text(J.str(c['name'])),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => cityId = v),
            decoration: InputDecoration(labelText: app.t('haraj_city')),
          ),
          TextField(
            controller: location,
            decoration: InputDecoration(labelText: app.t('haraj_location')),
          ),
          TextField(
            controller: contactPhone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: app.t('haraj_contact_phone'),
            ),
          ),
          TextField(
            controller: whatsapp,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: '${app.t('whatsapp_number')} *',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            app.t('haraj_main_image'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (mainImageUrl != null && mainImage == null)
            SizedBox(
              height: 120,
              child: AppImage(mainImageUrl, placeholder: app.placeholder),
            ),
          TextButton.icon(
            onPressed: () async {
              final one = await ImagePicker().pickImage(
                source: ImageSource.gallery,
              );
              if (one == null || !mounted) return;
              if (await one.length() > _maxImageBytes) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(app.t('image_too_large'))),
                );
                return;
              }
              setState(() => mainImage = one);
            },
            icon: const Icon(Icons.image),
            label: Text(
              mainImage == null ? app.t('haraj_main_image') : mainImage!.name,
            ),
          ),
          if (existingImages.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(app.t('images')),
            Wrap(
              children: existingImages
                  .map(
                    (img) => Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: SizedBox(
                            width: 80,
                            height: 80,
                            child: AppImage(
                              J.str(img['image_url'] ?? img['url']),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => _deleteImage(img['id']),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ],
          TextButton.icon(
            onPressed: () async {
              final picked = await ImagePicker().pickMultiImage();
              if (picked.isNotEmpty && mounted) {
                final ok = <XFile>[];
                for (final p in picked) {
                  if (await p.length() <= _maxImageBytes) ok.add(p);
                }
                if (ok.length != picked.length && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(app.t('image_too_large'))),
                  );
                }
                setState(() => newImages = [...newImages, ...ok]);
              }
            },
            icon: const Icon(Icons.photo_library),
            label: Text(
              newImages.isEmpty
                  ? app.t('haraj_photo')
                  : '${newImages.length} ${app.t('haraj_photo')}',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy ? null : _submit,
            child: busy ? const BusySpinner() : Text(app.t('save')),
          ),
          if (_draftRestored)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                appController.t('draft_saved'),
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
