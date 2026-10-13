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
    this.hideHeader = false,
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

  /// True when embedded in a store page: the global store-type tabs and the
  /// filter button are hidden — the store shows only its own sections as tabs.
  final bool hideHeader;

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
        // When embedded in a store page [hideHeader] is true: skip the global
        // store-type tabs + filter button entirely. The store renders its own
        // sections as tabs above.
        if (!widget.hideHeader)
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
        if (!widget.hideHeader) const Divider(height: 1),
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
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> similar = [];
  List<Map<String, dynamic>> offers = [];
  List<Map<String, dynamic>> ratings = [];
  double ratingAvg = 0;
  int ratingCount = 0;
  int _imgIndex = 0;
  final _pageC = PageController();

  @override
  void dispose() {
    _pageC.dispose();
    super.dispose();
  }

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
    final images = productImageUrls(product, variant: variant);

    return Scaffold(
      backgroundColor: AppTheme.surfaceGrey,
      appBar: AppBar(
        title: Text(J.str(product!['name']), maxLines: 1),
        actions: [
          ListenableBuilder(
            listenable: app,
            builder: (_, __) => IconButton(
              onPressed: () => context.push('/cart'),
              icon: Badge(
                isLabelVisible: app.cartCount > 0,
                backgroundColor: AppTheme.accentOrange,
                label: Text(
                  '${app.cartCount}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                  ),
                ),
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              tooltip: app.t('cart'),
            ),
          ),
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
                color: app.isFavorite(product!['id'])
                    ? Colors.red.shade400
                    : null,
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
          // ---- Gallery with dots + badges ----
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 320,
                width: double.infinity,
                color: Colors.white,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    images.isEmpty
                        ? AppImage('', placeholder: app.placeholder)
                        : PageView.builder(
                            controller: _pageC,
                            itemCount: images.length,
                            onPageChanged: (i) =>
                                setState(() => _imgIndex = i),
                            itemBuilder: (_, i) => AppImage(
                              images[i],
                              placeholder: app.placeholder,
                            ),
                          ),
                    if (isProductStoreClosed(product!))
                      const ColoredBox(color: Color(0x66000000)),
                    // Discount / flash badges
                    if (price.hasDiscount)
                      PositionedDirectional(
                        top: 12,
                        start: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: price.isFlash
                                ? const Color(0xFFDC2626)
                                : AppTheme.accentOrange,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.accentOrange.withValues(
                                  alpha: 0.4,
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Text(
                            '-${price.discountPercent}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    if (price.isFlash)
                      PositionedDirectional(
                        top: 48,
                        start: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFDC2626),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.bolt,
                                size: 13,
                                color: Color(0xFFDC2626),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                app.t('flash_sale'),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: ClosedStoreBadge(
                        product: product!,
                        compact: false,
                      ),
                    ),
                    // Dots + counter
                    if (images.length > 1)
                      Positioned(
                        bottom: 44,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < images.length; i++)
                              AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                height: 6,
                                width: i == _imgIndex ? 22 : 6,
                                decoration: BoxDecoration(
                                  color: i == _imgIndex
                                      ? AppTheme.accentOrange
                                      : Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              // ---- Overlapping info card ----
              Positioned(
                left: 16,
                right: 16,
                bottom: -30,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryNavy.withValues(alpha: 0.1),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        J.str(product!['name']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                final sid = J.sellerId(product);
                                if ('$sid'.isNotEmpty) {
                                  context.push('/seller/$sid');
                                }
                              },
                              child: Text(
                                '${app.t('sold_by')}: ${J.str(J.map(product!['seller'])['store_name'] ?? product!['seller_name'] ?? product!['store_name'])}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.accentOrange,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          if (offers.isNotEmpty)
                            GestureDetector(
                              onTap: _showOffers,
                              child: Text(
                                '${app.t('other_sellers')} (${offers.length})',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primaryNavy,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            money(
                              price.finalPrice,
                              app.currency,
                              app.decimals,
                            ),
                            style: const TextStyle(
                              fontSize: 22,
                              color: AppTheme.accentOrange,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (price.hasDiscount)
                            Text(
                              money(
                                price.original,
                                app.currency,
                                app.decimals,
                              ),
                              style: const TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          const Spacer(),
                          if (ratingCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    size: 14,
                                    color: Colors.amber,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${ratingAvg.toStringAsFixed(1)} ($ratingCount)',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      // Delivery / return / stock — merged into the info card
                      // so the body has fewer stacked cards.
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (J.flag(product!['is_returnable'] ??
                              product!['return_status']))
                            _featureChip(
                              Icons.restart_alt_outlined,
                              app.t('returnable'),
                              AppTheme.primaryNavy,
                            ),
                          if (!J.flag(product!['can_deliver'], true))
                            _featureChip(
                              Icons.block_outlined,
                              app.t('not_deliverable'),
                              Colors.red.shade700,
                              bg: Colors.red.shade50,
                            )
                          else
                            _featureChip(
                              Icons.delivery_dining_outlined,
                              app.t('delivery'),
                              AppTheme.accentOrange,
                              bg: AppTheme.accentOrange.withValues(
                                alpha: 0.1,
                              ),
                            ),
                          if (!unlimited && stock <= 0)
                            _featureChip(
                              Icons.error_outline,
                              app.t('out_of_stock'),
                              Colors.red.shade700,
                              bg: Colors.red.shade50,
                            )
                          else
                            _featureChip(
                              Icons.check_circle_outline,
                              unlimited
                                  ? app.t('in_stock')
                                  : '${app.t('in_stock')} • $stock',
                              Colors.green.shade700,
                              bg: Colors.green.shade50,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 44),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- Purchase options: single card (variants only).
                // Qty lives in the bottom bar next to Add — no separate
                // qty card, so the page is not cards stacked on cards.
                if (variants.length > 1) ...[
                  _sectionCard(
                    title: app.t('productVariants'),
                    trailing: Text(
                      '${app.t('stock')}: ${unlimited ? '∞' : '$stock'}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: variants.map((item) {
                        final helperLabel =
                            AppController.variantLabelOf(
                          item,
                          J.str(product!['name']),
                        );
                        final label = helperLabel.isEmpty
                            ? J.str(item['name'] ?? item['id'])
                            : helperLabel;
                        final selected =
                            '${item['id']}' == '${variant?['id']}';
                        return GestureDetector(
                          onTap: () =>
                              setState(() => variant = item),
                          child: AnimatedContainer(
                            duration:
                                const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppTheme.accentOrange
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? AppTheme.accentOrange
                                    : AppTheme.primaryNavy.withValues(
                                        alpha: 0.12,
                                      ),
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.accentOrange
                                            .withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? Colors.white
                                    : AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // ---- Description: plain section, not another card ----
                Text(
                  app.t('description'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                HtmlText(J.str(product!['description'])),
                const SizedBox(height: 12),
                _sectionCard(
                  title:
                      '${app.t('reviews')}${ratingCount > 0 ? ' ($ratingCount)' : ''}',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (ratingAvg > 0) ...[
                        const Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          ratingAvg.toStringAsFixed(1),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      GestureDetector(
                        onTap: _writeReview,
                        child: Text(
                          app.t('write_review'),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentOrange,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  child: ratings.isEmpty
                      ? Text(
                          app.t('no_ratings_available_yet'),
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        )
                      : Column(
                          children: [
                            for (var i = 0;
                                i < ratings.take(3).length;
                                i++) ...[
                              if (i > 0) const Divider(height: 16),
                              _reviewTile(ratings.take(3).toList()[i]),
                            ],
                          ],
                        ),
                ),
                if (similar.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppTheme.accentOrange,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          app.t('similar_products'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
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
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _CartBottomBar(
        product: product!,
        variant: variant,
        price: price.finalPrice,
        outOfStock: !unlimited && stock <= 0,
      ),
    );
  }

  Widget _featureChip(
    IconData icon,
    String label,
    Color color, {
    Color? bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg ?? color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _reviewTile(Map<String, dynamic> r) {
    final stars = int.tryParse('${r['rate'] ?? r['rating'] ?? 0}') ?? 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.surfaceGrey,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.person_outline,
            size: 20,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      J.str(r['user_name'] ?? J.map(r['user'])['name']),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 1; i <= 5; i++)
                        Icon(
                          i <= stars
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 13,
                          color: Colors.amber,
                        ),
                    ],
                  ),
                ],
              ),
              if (J.str(r['review'] ?? r['comment']).isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  J.str(r['review'] ?? r['comment']),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textPrimary,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Bottom purchase bar: plain Add button first; the moment it is tapped it
/// adds 1 to the cart and turns into a [- qty +] stepper synced with the
/// cart (minus at 1 removes the line and restores the Add button).
class _CartBottomBar extends StatefulWidget {
  const _CartBottomBar({
    required this.product,
    required this.variant,
    required this.price,
    required this.outOfStock,
  });

  final Map<String, dynamic> product;
  final Map<String, dynamic>? variant;
  final double price;
  final bool outOfStock;

  @override
  State<_CartBottomBar> createState() => _CartBottomBarState();
}

class _CartBottomBarState extends State<_CartBottomBar> {
  /// Optimistic qty shown instantly while the request runs in background.
  /// Null = follow the real cart. No spinners: the UI never blocks.
  int? _optimistic;
  int _seq = 0;

  dynamic get _variantId => widget.variant?['id'] ?? widget.product['id'];

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _optimistic = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _setQty(int next) async {
    final app = appController;
    final mySeq = ++_seq;
    setState(() => _optimistic = next);
    try {
      if (next <= 0) {
        final err = await app.removeCartLine(
          productId: widget.product['id'],
          variantId: _variantId,
        );
        if (mySeq != _seq || !mounted) return;
        if (err != null) {
          _fail(err);
        } else {
          setState(() => _optimistic = null);
        }
        return;
      }
      final err = await app.addToCart(
        productId: widget.product['id'],
        variantId: _variantId,
        qty: next,
        productPrice: widget.price,
        sellerId: J.sellerId(widget.product),
        storeName: app.storeNameOf(widget.product),
            variantLabel: AppController.variantLabelOf(widget.variant, J.str(widget.product['name'])),
      );
      if (mySeq != _seq || !mounted) return;
      if (err == 'same_seller') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: Text(app.t('same_seller_cart_prompt')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(app.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(app.t('confirm')),
              ),
            ],
          ),
        );
        if (ok == true && mounted) {
          final retry = await app.addToCart(
            productId: widget.product['id'],
            variantId: _variantId,
            qty: next,
            productPrice: widget.price,
            sellerId: J.sellerId(widget.product),
            storeName: app.storeNameOf(widget.product),
            variantLabel: AppController.variantLabelOf(widget.variant, J.str(widget.product['name'])),
            replaceSeller: true,
          );
          if (mySeq != _seq || !mounted) return;
          if (retry != null) {
            _fail(retry);
          } else {
            setState(() => _optimistic = null);
          }
        } else if (mounted) {
          setState(() => _optimistic = null);
        }
        return;
      }
      if (err != null) {
        _fail(err);
      } else {
        // Silent success — no snackbar on every tap.
        setState(() => _optimistic = null);
      }
    } catch (_) {
      if (mySeq != _seq || !mounted) return;
      _fail(appController.t('network_error'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: AppTheme.primaryNavy.withValues(alpha: 0.08),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryNavy.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: ListenableBuilder(
            listenable: app,
            builder: (_, __) {
              final qty = _optimistic ?? app.cartQtyFor(_variantId);
              if (qty <= 0) {
                return SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.outOfStock ? null : () => _setQty(1),
                    icon: const Icon(
                      Icons.shopping_cart_outlined,
                      size: 18,
                    ),
                    label: Text(
                      '${app.t('add_to_cart')} • ${money(widget.price, app.currency, app.decimals)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              }
              return Row(
                children: [
                  _stepBtn(
                    Icons.remove_rounded,
                    onTap: () => _setQty(qty - 1),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceGrey,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$qty',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  _stepBtn(
                    Icons.add_rounded,
                    onTap: () => _setQty(qty + 1),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => context.push('/cart'),
                      child: Text(
                        '${app.t('cart')} • ${money(widget.price * qty, app.currency, app.decimals)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _stepBtn(IconData icon, {VoidCallback? onTap}) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? AppTheme.primaryNavy : AppTheme.surfaceGrey,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
