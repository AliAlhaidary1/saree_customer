import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../core/json_util.dart';
import '../../core/product_media.dart';
import '../../core/promo_price.dart';
import '../../core/search_scope.dart';
import '../../widgets/app_image.dart';
import '../../widgets/closed_store_badge.dart';
import '../../widgets/product_card.dart';
import '../../widgets/product_filter_drawer.dart';
import '../../widgets/product_variant_sheet.dart';
import '../../widgets/ui_helpers.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({
    super.key,
    this.categoryId,
    this.sellerId,
    this.search,
    this.hasOffer = false,
    this.sectionId,
    this.sellerSectionId,
    this.sort,
    this.minRating,
    this.inStock = false,
    this.priceMin,
    this.priceMax,
    this.canDeliver = false,
    this.isReturnable = false,
    this.listenHeaderSearch = true,
  });

  final String? categoryId;
  final String? sellerId;
  final String? search;
  final bool hasOffer;
  final String? sectionId;
  final String? sellerSectionId;
  final String? sort;
  final String? minRating;
  final bool inStock;
  final String? priceMin;
  final String? priceMax;
  final bool canDeliver;
  final bool isReturnable;

  /// False when embedded (store page): the header search must not leak
  /// a stale query into another seller's catalog.
  final bool listenHeaderSearch;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen>
    with SingleTickerProviderStateMixin {
  // Hidden query holder: the single visible search field lives in the app
  // header and drives this screen through [headerSearch].
  final _search = TextEditingController();
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = true;
  int offset = 0;
  int _seq = 0; // drops stale responses when filters change fast (race fix).
  String sort = '';
  String? categoryId;
  bool inStock = false;
  bool onlyOffers = false;
  TabController? _tabC;

  @override
  void initState() {
    super.initState();
    categoryId = widget.categoryId;
    onlyOffers = widget.hasOffer;
    sort = widget.sort ?? '';
    minRating = widget.minRating ?? '';
    inStock = widget.inStock;
    priceMin = widget.priceMin ?? '';
    priceMax = widget.priceMax ?? '';
    canDeliver = widget.canDeliver;
    isReturnable = widget.isReturnable;
    _search.text =
        widget.search ?? (widget.listenHeaderSearch ? headerSearch.productQuery : '');
    if (widget.listenHeaderSearch) {
      headerSearch.addListener(_onHeaderSearch);
    }
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant ProductsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.listenHeaderSearch) return;
    if (oldWidget.search != widget.search &&
        (widget.search ?? '') != _search.text) {
      _search.text = widget.search ?? '';
      _load(reset: true);
    }
  }

  @override
  void dispose() {
    headerSearch.removeListener(_onHeaderSearch);
    _tabC?.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onHeaderSearch() {
    if (headerSearch.productQuery == _search.text) return;
    _search.text = headerSearch.productQuery;
    _load(reset: true);
  }

  // parity with front productFilterReducer + getProductbyFilter
  String priceMin='';
  String priceMax='';
  String minRating='';
  bool canDeliver=false;
  bool isHome=false;
  bool isReturnable=false;

  String _catName(Map<String, dynamic> cat) {
    final isAr = appController.i18n.code == 'ar';
    final ar = J.str(cat['name_ar']);
    final en = J.str(cat['name_en'] ?? cat['name']);
    return isAr ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
  }

  int _tabIndexFor(List<Map<String, dynamic>> cats) {
    if (categoryId == null || categoryId!.isEmpty) return 0;
    final i = cats.indexWhere((c) => '${c['id']}' == '$categoryId');
    return i < 0 ? 0 : i + 1;
  }

  Widget _categoryTabs(AppController app) {
    final cats = app.rootCategories;
    if (cats.isEmpty) return const SizedBox(height: 48);
    if (_tabC == null || _tabC!.length != cats.length + 1) {
      _tabC?.dispose();
      _tabC = TabController(
        length: cats.length + 1,
        vsync: this,
        initialIndex: _tabIndexFor(cats),
      );
    } else {
      final want = _tabIndexFor(cats);
      if (_tabC!.index != want && !_tabC!.indexIsChanging) {
        _tabC!.index = want;
      }
    }
    return TabBar(
      controller: _tabC,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelColor: AppTheme.accentOrange,
      unselectedLabelColor: AppTheme.textSecondary,
      indicatorColor: AppTheme.accentOrange,
      indicatorWeight: 3,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      unselectedLabelStyle:
          const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      onTap: (i) {
        final next = i == 0 ? null : '${cats[i - 1]['id']}';
        if ('$next' == '$categoryId') return;
        setState(() => categoryId = next);
        _load(reset: true);
      },
      tabs: [
        Tab(text: app.t('all') == 'all' ? 'الكل' : app.t('all')),
        for (final c in cats) Tab(text: _catName(c)),
      ],
    );
  }

  ProductFilterValue get _drawerValue => ProductFilterValue(
        sort: sort,
        categoryId: categoryId,
        priceMin: priceMin,
        priceMax: priceMax,
        minRating: minRating,
        inStock: inStock,
        onlyOffers: onlyOffers,
        canDeliver: canDeliver,
        isReturnable: isReturnable,
      );

  void _applyDrawer(ProductFilterValue v) {
    sort = v.sort;
    categoryId = v.categoryId;
    priceMin = v.priceMin;
    priceMax = v.priceMax;
    minRating = v.minRating;
    inStock = v.inStock;
    onlyOffers = v.onlyOffers;
    canDeliver = v.canDeliver;
    isReturnable = v.isReturnable;
    _load(reset: true);
  }

  /// Opens the filter bottom sheet; the price slider bounds follow the
  /// prices present in the currently loaded list.
  void _openFilters() {
    var hi = 0.0;
    for (final p in items) {
      final variants = J.maps(p['variants']);
      final variant = variants.isNotEmpty ? variants.first : p;
      final price = variantDisplayPrice(variant).finalPrice;
      if (price > hi) hi = price;
    }
    showProductFilterSheet(
      context,
      initial: _drawerValue,
      categories: appController.rootCategories,
      onApply: _applyDrawer,
      priceMaxBound: hi > 0 ? (hi * 1.1).ceilToDouble() : 1000,
    );
  }

  Map<String, dynamic> get _filters => {
    'limit': AppConfig.productPageSize,
    'offset': offset,
    if (categoryId != null && categoryId!.isNotEmpty)
      'category_ids': categoryId,
    if (widget.sellerId != null) 'seller_id': widget.sellerId,
    if (widget.sectionId != null && widget.sectionId!.isNotEmpty)
      'section_id': widget.sectionId,
    if (widget.sellerSectionId != null && widget.sellerSectionId!.isNotEmpty)
      'seller_section_id': widget.sellerSectionId,
    if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
    if (sort.isNotEmpty) 'sort': sort,
    if (inStock) 'in_stock': 1,
    if (widget.hasOffer || onlyOffers) 'has_offer': 1,
    if (priceMin.isNotEmpty) 'price_min': priceMin,
    if (priceMax.isNotEmpty) 'price_max': priceMax,
    if (minRating.isNotEmpty) 'min_seller_rating': minRating,
    if (canDeliver) 'can_deliver': 1,
    if (isHome) 'is_home_product': 1,
    if (isReturnable) 'is_returnable': 1,
    'latitude': appController.browseCoords.latitude,
    'longitude': appController.browseCoords.longitude,
  };

  Future<void> _load({bool reset = false}) async {
    if (!reset && (loadingMore || !hasMore)) return;
    final mySeq = ++_seq;
    final point = appController.browseCoords;
    if (reset) {
      offset = 0;
      hasMore = true;
      setState(() => loading = true);
    } else {
      setState(() => loadingMore = true);
    }
    final result = await appController.api.products(
      latitude: point.latitude,
      longitude: point.longitude,
      filters: _filters,
    );
    if (!mounted || mySeq != _seq) return; // stale response: ignore.
    final next = result.dataMaps;
    setState(() {
      items = reset ? next : [...items, ...next];
      offset = items.length;
      hasMore = next.length >= AppConfig.productPageSize;
      loading = false;
      loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final activeCount = [
      sort.isNotEmpty,
      minRating.isNotEmpty,
      priceMin.isNotEmpty || priceMax.isNotEmpty,
      inStock,
      onlyOffers,
      canDeliver,
      isReturnable,
    ].where((e) => e).length;
    return Scaffold(
      body: Column(
      children: [
        // Category TABS on a solid bar (never transparent, so products can
        // never show through from underneath). The only search field is the
        // header one — it drives [_search] through [headerSearch].
        Container(
          color: Colors.white,
          padding: const EdgeInsetsDirectional.only(start: 8),
          child: Row(
            children: [
              Expanded(child: _categoryTabs(app)),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  IconButton(
                    onPressed: _openFilters,
                    icon: const Icon(Icons.tune),
                    tooltip: app.t('filters'),
                  ),
                  if (activeCount > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.accentOrange,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          '$activeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
              ? EmptyState(message: app.t('no_products_found'))
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.pixels > n.metrics.maxScrollExtent - 240 &&
                        !loadingMore &&
                        hasMore) {
                      _load();
                    }
                    return false;
                  },
                  child: LayoutBuilder(builder: (ctx, c){
                    final count = c.maxWidth >= 900 ? 4 : c.maxWidth >= 600 ? 3 : 2;
                    final aspect = c.maxWidth >= 600 ? 0.6 : 0.55;
                    return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    addRepaintBoundaries: true,
                    addAutomaticKeepAlives: false,
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: count,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: aspect,
                        ),
                    itemCount: items.length + (loadingMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= items.length)
                        return const Center(child: CircularProgressIndicator());
                      final product = items[i];
                      return ProductCard(
                        product: product,
                        onTap: () {
                          final slug = J.str(product['slug']);
                          context.push(
                            slug.isNotEmpty
                                ? '/product/$slug'
                                : '/product/${product['id']}',
                          );
                        },
                        onAdd: () => addProductFromCatalog(context, product),
                      );
                    },
                  );}),
                ),
        ),
      ],
      ),
    );
  }
}

class ProductDetailsScreen extends StatefulWidget {
  const ProductDetailsScreen({super.key, required this.slug});
  final String slug;

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  Map<String, dynamic>? product;
  Map<String, dynamic>? variant;
  int qty = 1;
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> similar = [];
  List<Map<String, dynamic>> offers = [];
  List<Map<String, dynamic>> ratings = [];
  double ratingAvg = 0;
  int ratingCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final point = appController.browseCoords;
    final id = int.tryParse(widget.slug);
    final result = await appController.api.productById(
      latitude: point.latitude,
      longitude: point.longitude,
      id: id,
      slug: id == null ? widget.slug : '',
    );
    if (!result.ok) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = result.message;
      });
      return;
    }
    final data = result.dataMap.isNotEmpty
        ? result.dataMap
        : (result.dataMaps.isNotEmpty
              ? result.dataMaps.first
              : <String, dynamic>{});
    final variants = J.maps(data['variants']);
    if (!mounted) return;
    setState(() {
      product = data;
      variant = variants.isNotEmpty ? variants.first : data;
      loading = false;
    });
    _loadExtras(data);
  }

  Future<void> _loadExtras(Map<String, dynamic> data) async {
    final app = appController;
    final point = app.browseCoords;
    final tags = J.str(data['tag_names'] ?? data['tags']);
    // Parallel: ratings + similar + catalog offers in one wave.
    final results = await Future.wait([
      app.api
          .productRatings(productId: data['id'], limit: 5)
          .timeout(const Duration(seconds: 12),
              onTimeout: () => ApiResult({'status': 0}))
          .catchError((_) => ApiResult({'status': 0})),
      if (tags.isNotEmpty)
        app.api
            .products(
              latitude: point.latitude,
              longitude: point.longitude,
              tagNames: tags,
              filters: {'limit': 10, 'in_stock': 1},
            )
            .timeout(const Duration(seconds: 12),
                onTimeout: () => ApiResult({'status': 0}))
            .catchError((_) => ApiResult({'status': 0})),
      app.api
          .catalogOffers(productId: data['id'])
          .timeout(const Duration(seconds: 12),
              onTimeout: () => ApiResult({'status': 0}))
          .catchError((_) => ApiResult({'status': 0})),
    ]);
    if (!mounted) return;
    final r = results[0];
    final o = results.last;
    final s = results.length == 3 ? results[1] : null;
    setState(() {
      if (r.ok) {
        final d = J.map(r.dataMap['data']);
        final list = J.maps(r.dataMap['data']).isNotEmpty
            ? J.maps(r.dataMap['data'])
            : r.dataMaps;
        ratings = list;
        ratingAvg = double.tryParse(
                '${d['average'] ?? data['average_rating'] ?? ''}') ??
            0;
        ratingCount = int.tryParse(
                '${d['count'] ?? d['total'] ?? data['rating_count'] ?? ''}') ??
            list.length;
      }
      if (s != null && s.ok) {
        similar = s.dataMaps
            .where((p) => '${p['id']}' != '${data['id']}')
            .take(10)
            .toList();
      }
      if (o.ok) offers = o.dataMaps;
    });
  }

  Future<void> _share() async {
    final app = appController;
    final name = J.str(product!['name']);
    final slug = J.str(product!['slug']);
    final id = '${product!['id']}';
    final link = 'https://sreamart.com/product/${slug.isNotEmpty ? slug : id}';
    final text = '$name\n$link';
    final encoded = Uri.encodeComponent(text);
    final actions = <String, String>{
      'whatsapp': 'https://wa.me/?text=$encoded',
      'telegram': 'https://t.me/share/url?url=${Uri.encodeComponent(link)}&text=${Uri.encodeComponent(name)}',
      'facebook': 'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(link)}',
    };
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat),
              title: Text(app.t('whatsapp')),
              onTap: () => Navigator.pop(ctx, 'whatsapp'),
            ),
            ListTile(
              leading: const Icon(Icons.send),
              title: const Text('Telegram'),
              onTap: () => Navigator.pop(ctx, 'telegram'),
            ),
            ListTile(
              leading: const Icon(Icons.facebook),
              title: const Text('Facebook'),
              onTap: () => Navigator.pop(ctx, 'facebook'),
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(app.t('copied') == 'copied' ? 'نسخ الرابط' : app.t('share_product')),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(app.t('copied'))));
      }
      return;
    }
    final url = actions[choice];
    if (url != null) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _writeReview() async {
    final app = appController;
    if (!app.isLoggedIn) {
      if (mounted) {
        context.push(
            '/login?next=${Uri.encodeComponent('/product/${widget.slug}')}');
      }
      return;
    }
    int stars = 0;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(app.t('write_review')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      icon: Icon(
                        i <= stars ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                      ),
                      onPressed: () => setS(() => stars = i),
                    ),
                ],
              ),
              TextField(
                controller: ctrl,
                maxLines: 3,
                decoration: InputDecoration(hintText: app.t('write_review')),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(app.t('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(app.t('submit_rating'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (stars == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(app.t('rating_required'))));
      return;
    }
    final res = await app.api.addProductRating({
      'product_id': product!['id'],
      'rate': stars,
      'review': ctrl.text.trim(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message.isNotEmpty ? res.message : app.t('rating_saved_successfully'))));
    if (res.ok) _loadExtras(product!);
  }

  Future<void> _showOffers() async {
    final app = appController;
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text(app.t('other_sellers'),
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            ...offers.map(
              (o) => ListTile(
                title: Text(J.str(
                    o['store_name'] ?? o['seller_name'] ?? o['name'])),
                subtitle: o['price'] != null
                    ? Text(money(o['price'], app.currency, app.decimals))
                    : null,
                trailing: Text(app.t('add_to_cart')),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push(
                      '/seller/${o['seller_id'] ?? o['id']}');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    if (loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (product == null || product!.isEmpty)
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.error_outline,
          message: error ?? app.t('Oops'),
          actionLabel: app.t('retry'),
          onAction: () {
            setState(() {
              loading = true;
              error = null;
            });
            _load();
          },
        ),
      );
    final price = variantDisplayPrice(variant);
    final variants = J.maps(product!['variants']);
    final stock = J.i(variant?['stock']);
    final unlimited = J.flag(
      product!['is_unlimited_stock'] ?? variant?['is_unlimited_stock'],
    );
    final maxQty = J.i(
      product!['total_allowed_quantity'],
      unlimited ? 99 : stock,
    );
    final images = productImageUrls(product, variant: variant);

    return Scaffold(
      appBar: AppBar(
        title: Text(J.str(product!['name']), maxLines: 1),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: app.t('share'),
            onPressed: _share,
          ),
          if (app.isLoggedIn)
            IconButton(
              icon: Icon(
                app.isFavorite(product!['id'])
                    ? Icons.favorite
                    : Icons.favorite_border,
              ),
              onPressed: () async {
                await app.toggleFavorite(product!['id']);
                setState(() {});
              },
            ),
        ],
      ),
      body: ListView(
        children: [
          SizedBox(
            height: 280,
            child: Stack(
              fit: StackFit.expand,
              children: [
                images.isEmpty
                    ? AppImage('', placeholder: app.placeholder)
                    : PageView(
                        children: images
                            .map(
                              (url) =>
                                  AppImage(url, placeholder: app.placeholder),
                            )
                            .toList(),
                      ),
                if (isProductStoreClosed(product!))
                  const ColoredBox(color: Color(0x66000000)),
                Positioned(
                  top: 12,
                  left: 12,
                  child: ClosedStoreBadge(product: product!, compact: false),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  J.str(product!['name']),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      money(price.finalPrice, app.currency, app.decimals),
                      style: TextStyle(
                        fontSize: 20,
                        color: app.accentColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (price.hasDiscount)
                      Text(
                        money(price.original, app.currency, app.decimals),
                        style: const TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: Colors.grey,
                        ),
                      ),
                    if (price.isFlash) ...[
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(app.t('flash_sale')),
                        backgroundColor: Colors.red.shade50,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    if (J.flag(product!['is_returnable'] ??
                        product!['return_status']))
                      Chip(
                        label: Text(app.t('returnable')),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (!J.flag(product!['can_deliver'], true))
                      Chip(
                        label: Text(app.t('not_deliverable')),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.red.shade50,
                      ),
                    if (ratingCount > 0)
                      Chip(
                        avatar: const Icon(Icons.star,
                            size: 14, color: Colors.amber),
                        label: Text(
                            '${ratingAvg.toStringAsFixed(1)} ($ratingCount)'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${app.t('sold_by')}: ${J.str(J.map(product!['seller'])['store_name'] ?? product!['seller_name'] ?? product!['store_name'])}',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 13),
                      ),
                    ),
                    if (offers.isNotEmpty)
                      TextButton(
                        onPressed: _showOffers,
                        child: Text(
                            '${app.t('other_sellers')} (${offers.length})'),
                      ),
                  ],
                ),
                if (variants.length > 1) ...[
                  const SizedBox(height: 12),
                  Text(
                    app.t('productVariants'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: variants
                        .map(
                          (item) => ChoiceChip(
                            label: Text(
                              [
                                J.str(item['measurement']),
                                J.str(item['stock_unit_name']),
                              ].where((e) => e.isNotEmpty).join(' ').isEmpty
                                  ? J.str(item['name'] ?? item['id'])
                                  : [
                                      J.str(item['measurement']),
                                      J.str(item['stock_unit_name']),
                                    ].where((e) => e.isNotEmpty).join(' '),
                            ),
                            selected: '${item['id']}' == '${variant?['id']}',
                            onSelected: (_) => setState(() => variant = item),
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      onPressed: qty > 1 ? () => setState(() => qty--) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '$qty',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: qty < (maxQty == 0 ? 99 : maxQty)
                          ? () => setState(() => qty++)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    const Spacer(),
                    if (!unlimited && stock <= 0)
                      Text(
                        app.t('out_of_stock'),
                        style: const TextStyle(color: Colors.red),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                HtmlText(J.str(product!['description'])),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${app.t('reviews')}${ratingCount > 0 ? ' ($ratingCount)' : ''}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15),
                              ),
                            ),
                            if (ratingAvg > 0)
                              Row(
                                children: [
                                  const Icon(Icons.star,
                                      size: 16, color: Colors.amber),
                                  const SizedBox(width: 2),
                                  Text(ratingAvg.toStringAsFixed(1),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            TextButton(
                              onPressed: _writeReview,
                              child: Text(app.t('write_review')),
                            ),
                          ],
                        ),
                        if (ratings.isEmpty)
                          Text(app.t('no_ratings_available_yet'),
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                        ...ratings.take(3).map(
                          (r) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(
                                J.str(r['user_name'] ?? J.map(r['user'])['name']),
                                style: const TextStyle(fontSize: 13)),
                            subtitle: J.str(r['review'] ?? r['comment'])
                                    .isNotEmpty
                                ? Text(J.str(r['review'] ?? r['comment']))
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star,
                                    size: 14, color: Colors.amber),
                                Text(' ${J.str(r['rate'] ?? r['rating'])}'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (similar.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(app.t('similar_products'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 296,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      cacheExtent: 600,
                      itemCount: similar.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 10),
                      itemBuilder: (_, i) => SizedBox(
                        width: 160,
                        child: ProductCard(
                          product: similar[i],
                          onTap: () {
                            final slug = J.str(similar[i]['slug']);
                            context.push(slug.isNotEmpty
                                ? '/product/$slug'
                                : '/product/${similar[i]['id']}');
                          },
                          onAdd: () => addProductFromCatalog(
                              context, similar[i]),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: (!unlimited && stock <= 0)
                ? null
                : () async {
                    final err = await app.addToCart(
                      productId: product!['id'],
                      variantId: variant?['id'],
                      qty: qty,
                      productPrice: price.finalPrice,
                      sellerId: J.sellerId(product),
                      storeName: app.storeNameOf(product),
                    );
                    if (!context.mounted) return;
                    await handleCartAddResult(
                      context,
                      error: err,
                      product: product!,
                      variantId: variant?['id'],
                      qty: qty,
                      productPrice: price.finalPrice,
                    );
                  },
            child: Text(app.t('add_to_cart')),
          ),
        ),
      ),
    );
  }
}
