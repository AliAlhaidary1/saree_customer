import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../core/json_util.dart';
import '../../core/promo_price.dart';
import '../../widgets/app_image.dart';
import '../../widgets/product_card.dart';
import '../../widgets/product_filter_drawer.dart';
import '../../widgets/product_variant_sheet.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/store_card.dart';
import '../more/more_screens.dart';
import '../products/categories_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ---- Hero / marketing data ----
  List<Map<String, dynamic>> sliders = [];
  List<Map<String, dynamic>> flash = [];
  List<Map<String, dynamic>> haraj = [];
  bool loading = true;
  String? loadError;
  String? _cityKey;
  bool _popupShown = false;

  // ---- Unified catalog (products ↔ stores) ----
  List<Map<String, dynamic>> _catalog = [];
  bool _catalogLoading = false;
  bool _catalogLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  int _seq = 0;
  String _view = 'products'; // products | stores
  String _sort = ''; // '' | nearest | new | rating
  ProductFilterValue _filter = ProductFilterValue();

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  static const _pageSize = AppConfig.productPageSize;

  @override
  void initState() {
    super.initState();
    _view = appController.isStoresOnly ? 'stores' : 'products';
    appController.addListener(_onApp);
    _load();
    _loadCatalog(reset: true);
  }

  @override
  void dispose() {
    appController.removeListener(_onApp);
    super.dispose();
  }

  void _onApp() {
    // Reload ONLY on city change. Cart/favorites/settings notify must not
    // rebuild the whole home (was the main cause of scroll jank).
    final key =
        '${appController.city?['id']}-${appController.city?['latitude']}';
    if (key != _cityKey) {
      _cityKey = key;
      _load();
      _loadCatalog(reset: true);
    }
  }

  Future<void> _load() async {
    final app = appController;
    _cityKey = '${app.city?['id']}-${app.city?['latitude']}';
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      Future<T> withTimeout<T>(Future<T> f, T fallback) =>
          f.timeout(const Duration(seconds: 12), onTimeout: () => fallback);
      final needCats = app.rootCategories.isEmpty;
      final List<dynamic> results = await Future.wait<dynamic>([
        withTimeout(app.api.sliders(), ApiResult({'status': 0})),
        withTimeout(app.api.flashSales(), ApiResult({'status': 0})),
        withTimeout(
            app.api.harajPosts({
              'page': 1,
              'per_page': 4,
              if (app.city?['id'] != null) 'city_id': app.city!['id'],
            }),
            ApiResult({'status': 0})),
        if (needCats)
          withTimeout(app.loadRootCategories().then((_) => true), false),
      ]);
      final sliderRes = results[0] as ApiResult;
      final flashRes = results[1] as ApiResult;
      final harajRes = results[2] as ApiResult;
      if (!mounted) return;
      setState(() {
        sliders = sliderRes.dataMaps.isNotEmpty
            ? sliderRes.dataMaps
            : J.maps(app.shop?['sliders']);
        flash = flashRes.dataMaps;
        haraj = harajRes.dataMaps;
        loading = false;
      });
      _maybeShowPopup();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        loadError = '$error';
      });
    }
  }

  Future<void> _loadCatalog({bool reset = false}) async {
    if (!reset && (_catalogLoadingMore || !_hasMore)) return;
    final mySeq = ++_seq;
    final app = appController;
    final point = app.browseCoords;
    if (reset) {
      _offset = 0;
      _hasMore = true;
      setState(() {
        _catalogLoading = true;
        _catalog = [];
      });
    } else {
      setState(() => _catalogLoadingMore = true);
    }

    if (_view == 'stores') {
      var sort = (_sort == 'nearest' || _sort == 'rating') ? _sort : 'rating';
      if (sort == 'nearest' &&
          point.latitude == 0 &&
          point.longitude == 0) {
        sort = 'rating';
      }
      final res = await app.api.sellers(
        latitude: point.latitude,
        longitude: point.longitude,
        limit: 20,
        offset: _offset,
        sort: sort.isNotEmpty ? sort : 'rating',
        type: _filter.categoryId?.isNotEmpty == true
            ? _filter.categoryId
            : null,
        minRating: _filter.minRating.isNotEmpty
            ? int.tryParse(_filter.minRating)
            : null,
      );
      if (!mounted || mySeq != _seq) return;
      var rows = res.dataMaps;
      var total = J.i(res.raw['total'] ?? res.dataMap['total']);
      final dataNode = res.raw['data'];
      if (rows.isEmpty && dataNode is Map) {
        rows = J.maps(dataNode['data']);
        total = J.i(dataNode['total'] ?? total);
      }
      setState(() {
        _catalog = reset ? rows : [..._catalog, ...rows];
        _offset = _catalog.length;
        _hasMore =
            total > 0 ? _catalog.length < total : rows.length >= 20;
        _catalogLoading = false;
        _catalogLoadingMore = false;
      });
      return;
    }

    final res = await app.api.products(
      latitude: point.latitude,
      longitude: point.longitude,
      filters: {
        'limit': _pageSize,
        'offset': _offset,
        if (_sort.isNotEmpty) 'sort': _sort,
        if (_filter.categoryId?.isNotEmpty == true)
          'category_ids': _filter.categoryId,
        if (_filter.inStock) 'in_stock': 1,
        if (_filter.onlyOffers) 'has_offer': 1,
        if (_filter.priceMin.isNotEmpty) 'price_min': _filter.priceMin,
        if (_filter.priceMax.isNotEmpty) 'price_max': _filter.priceMax,
        if (_filter.minRating.isNotEmpty)
          'min_seller_rating': _filter.minRating,
        if (_filter.isReturnable) 'is_returnable': 1,
      },
    );
    if (!mounted || mySeq != _seq) return;
    final rows = res.dataMaps;
    setState(() {
      _catalog = reset ? rows : [..._catalog, ...rows];
      _offset = _catalog.length;
      _hasMore = rows.length >= _pageSize;
      _catalogLoading = false;
      _catalogLoadingMore = false;
    });
  }

  void _setView(String v) {
    if (_view == v) return;
    if (appController.isStoresOnly && v == 'products') return;
    setState(() {
      _view = v;
      _sort = '';
    });
    _loadCatalog(reset: true);
  }

  void _applyFilter(ProductFilterValue v) {
    setState(() {
      _filter = v;
      if (v.sort.isNotEmpty) _sort = v.sort;
    });
    _loadCatalog(reset: true);
  }

  /// Opens the filter bottom sheet. The price slider bounds follow the
  /// prices actually present in the loaded catalog.
  void _openFilters(List<Map<String, dynamic>> categories) {
    var hi = 0.0;
    for (final p in _catalog) {
      final variants = J.maps(p['variants']);
      final variant = variants.isNotEmpty ? variants.first : p;
      final price = variantDisplayPrice(variant).finalPrice;
      if (price > hi) hi = price;
    }
    showProductFilterSheet(
      context,
      initial: _filter,
      categories: categories,
      onApply: _applyFilter,
      priceMaxBound: hi > 0 ? (hi * 1.1).ceilToDouble() : 1000,
    );
  }

  /// Marketing popup (parity with web MainContainer popup).
  Future<void> _maybeShowPopup() async {
    if (_popupShown || !mounted) return;
    final app = appController;
    final shop = app.shop;
    if (shop == null) return;
    final enabled = J.str(shop['popup_enabled']);
    final image = J.str(shop['popup_image'] ?? shop['popup_image_url']);
    if (!(enabled == '1' || enabled.toLowerCase() == 'true') || image.isEmpty) {
      return;
    }
    _popupShown = true;
    final type = J.str(shop['popup_type']);
    final url = J.str(shop['popup_url']);
    final category = J.map(shop['popup_category'] ?? shop['category']);
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: AppImage(image, placeholder: app.placeholder),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(app.t('cancel')),
                ),
                if (type.isNotEmpty || url.isNotEmpty || category.isNotEmpty)
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (url.isNotEmpty && type == 'url') {
                        launchUrl(Uri.parse(url),
                            mode: LaunchMode.externalApplication);
                      } else if (category.isNotEmpty) {
                        openCategory(context, category);
                      } else if (url.isNotEmpty) {
                        context.push(url);
                      }
                    },
                    child: Text(app.t('shop_now')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openOffer(Map<String, dynamic> item) {
    final type = J.str(item['type']);
    if (type == 'category' || item['category'] != null) {
      final category = J.map(item['category']);
      if (category.isNotEmpty) {
        openCategory(context, category);
        return;
      }
      context.push('/sellers?type=${item['type_id']}');
      return;
    }
    final slug = J.str(item['product']?['slug']);
    if (type == 'product' || slug.isNotEmpty) {
      if (slug.isNotEmpty) context.push('/product/$slug');
      return;
    }
    final url = J.str(item['offer_url'] ?? item['url']);
    if (url.isNotEmpty) {
      if (url.startsWith('/')) {
        context.push(url);
      } else {
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    }
  }

  List<Map<String, dynamic>> _offers(String position) {
    return J
        .maps(appController.shop?['offers'])
        .where((o) => J.str(o['position']) == position)
        .toList();
  }

  /// Merged hero slides: ads (sliders) + top offers, web parity with
  /// CampaignHero interleave (ads/offers/flash).
  List<Map<String, dynamic>> get _heroSlides {
    final ads = sliders
        .where((s) => J.str(s['image_url'] ?? s['image']).isNotEmpty)
        .toList();
    final offers = _offers('top')
        .where((o) => J.str(o['image_url'] ?? o['image']).isNotEmpty)
        .toList();
    return [...ads, ...offers];
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final shopCategories = J.maps(app.shop?['categories']);
    final categories = !app.isCategorySectionEnabled
        ? <Map<String, dynamic>>[]
        : (shopCategories.isNotEmpty ? shopCategories : app.rootCategories);
    final belowSlider = _offers('below_slider');
    final belowCategory = _offers('below_category');
    final belowSection = _offers('below_section');
    final storesOnly = app.isStoresOnly;
    final showCatalog = !storesOnly;
    final hero = _heroSlides;
    final hasContent = hero.isNotEmpty ||
        flash.isNotEmpty ||
        categories.isNotEmpty ||
        haraj.isNotEmpty ||
        app.akhdimniEnabled ||
        _catalog.isNotEmpty ||
        _catalogLoading;

    return Scaffold(
      key: _scaffoldKey,
      body: RefreshIndicator(
        onRefresh: () async {
          await app.loadShop();
          await app.loadRootCategories();
          await _load();
          await _loadCatalog(reset: true);
        },
        child: CustomScrollView(
          cacheExtent: 800,
          slivers: [
            if (app.city == null)
              SliverToBoxAdapter(
                child: ListTile(
                  leading: Icon(Icons.location_on, color: app.accentColor),
                  title: Text(app.t('choose_city_to_browse')),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => showModalBottomSheet(
                    context: context,
                    builder: (_) => const CityPickerSheet(),
                  ),
                ),
              ),
            if (loadError != null && !hasContent)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        app.t('network_error'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _load, child: Text(app.t('retry'))),
                    ],
                  ),
                ),
              ),
            if (loading && !hasContent)
              const SliverToBoxAdapter(child: HomeLoadingSkeleton()),
            if (hero.isNotEmpty)
              SliverToBoxAdapter(
                child: _HeroSlider(slides: hero, onOpen: _openOffer),
              ),
            if (belowSlider.isNotEmpty) _bannerPage(belowSlider, 140),
            if (showCatalog && flash.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  app.t('flash_sale'),
                  onSeeAll: () => context.push('/offers'),
                ),
              ),
              _productStrip(
                flash
                    .map((item) => J.map(item['product'] ?? item))
                    .where((p) => p.isNotEmpty)
                    .toList(),
              ),
            ],
            if (categories.isNotEmpty)
              _shopByTypeSection(context, categories),
            if (belowCategory.isNotEmpty) _bannerPage(belowCategory, 140),

            // === Unified catalog: tabs + view toggle + grid/list ===
            if (showCatalog || storesOnly) ...[
              SliverToBoxAdapter(child: _catalogHeader(context)),
              if (_catalogLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_catalog.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: EmptyStateInline(
                      message: app.t(
                        _view == 'stores'
                            ? 'no_stores_found'
                            : 'no_products_found',
                      ),
                    ),
                  ),
                )
              else if (_view == 'stores')
                _storeList(_catalog)
              else
                _productGrid(_catalog),
              if (!_catalogLoading && _hasMore && _catalog.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: OutlinedButton(
                      onPressed: _catalogLoadingMore
                          ? null
                          : () => _loadCatalog(),
                      child: _catalogLoadingMore
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(app.t('load_more')),
                    ),
                  ),
                ),
            ],

            if (haraj.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  app.t('haraj'),
                  onSeeAll: () => context.push('/haraj'),
                ),
              ),
              _harajStrip(haraj),
            ],
            if (app.akhdimniEnabled)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ListTile(
                    tileColor: app.accentColor.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    leading:
                        Icon(Icons.delivery_dining, color: app.accentColor),
                    title: Text(app.t('akhdimni')),
                    subtitle: Text(app.t('akhdimni_home_hint')),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => context.push('/akhdimni'),
                  ),
                ),
              ),
            if (belowSection.isNotEmpty) _bannerPage(belowSection, 140),
            if (!loading && !hasContent)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.storefront_outlined,
                          size: 64,
                          color: app.accentColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          app.t('no_products_found'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          app.t('home_city_hint'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: Text(app.t('retry')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  int get _activeFilterCount => [
        _filter.categoryId?.isNotEmpty == true,
        _filter.minRating.isNotEmpty,
        _filter.priceMin.isNotEmpty || _filter.priceMax.isNotEmpty,
        _filter.inStock,
        _filter.onlyOffers,
        _filter.isReturnable,
      ].where((e) => e).length;

  /// "تسوق حسب نوع المتجر": one grey band (web parity) holding the header and
  /// the circular category tiles. The filter button replaces "see all".
  Widget _shopByTypeSection(
    BuildContext context,
    List<Map<String, dynamic>> categories,
  ) {
    final app = appController;
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 16, 12, 0),
        padding: const EdgeInsets.only(top: 14, bottom: 14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceGrey,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, end: 6),
              child: Row(
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
                      app.t('shop_by_store_type'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 34,
                        margin: const EdgeInsetsDirectional.only(end: 6),
                        child: TextButton.icon(
                          onPressed: () => _openFilters(categories),
                          icon: const Icon(Icons.tune, size: 17),
                          label: Text(
                            app.t('filters'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.backgroundWhite,
                            backgroundColor: AppTheme.accentOrange,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      if (_activeFilterCount > 0)
                        PositionedDirectional(
                          top: -5,
                          end: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryNavy,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppTheme.backgroundWhite,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              '$_activeFilterCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 96,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                cacheExtent: 600,
                addRepaintBoundaries: true,
                itemCount: categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (_, i) {
                  final cat = categories[i];
                  return GestureDetector(
                    onTap: () => openCategory(context, cat),
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
                              color: AppTheme.backgroundWhite,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryNavy.withValues(
                                    alpha: 0.07,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: AppImage(
                                J.str(cat['image_url'] ?? cat['image']),
                                placeholder: app.placeholder,
                                thumb: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            J.str(cat['name']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "المنتجات/المتاجر" as underline tabs (web type-switch-tabs parity).
  Widget _catalogHeader(BuildContext context) {
    final app = appController;
    if (app.isStoresOnly) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: _UnderlineTabs(
        values: const ['products', 'stores'],
        labels: [app.t('view_as_products'), app.t('view_as_stores')],
        selected: _view,
        onChanged: _setView,
      ),
    );
  }

  Widget _storeList(List<Map<String, dynamic>> sellers) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      sliver: SliverList.separated(
        itemCount: sellers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final seller = sellers[i];
          final distance = double.tryParse(
            '${seller['distance_km'] ?? seller['distance'] ?? ''}',
          );
          return StoreCard(
            seller: seller,
            distanceKm: distance,
            onTap: () {
              final slug = J.str(seller['slug']);
              context.push(
                slug.isNotEmpty ? '/store/$slug' : '/seller/${seller['id']}',
              );
            },
          );
        },
      ),
    );
  }

  Widget _bannerPage(List<Map<String, dynamic>> items, double height) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: height,
        child: PageView(
          children: items
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: GestureDetector(
                    onTap: () => _openOffer(item),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AppImage(
                        J.str(item['image_url'] ?? item['image']),
                        placeholder: appController.placeholder,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _productStrip(List<Map<String, dynamic>> items) {
    if (items.isEmpty)
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 262,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          cacheExtent: 600,
          addRepaintBoundaries: true,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => SizedBox(
            width: 158,
            child: RepaintBoundary(
              child: ProductCard(
                product: items[i],
                onTap: () => _openProduct(items[i]),
                onAdd: () => addProductFromCatalog(context, items[i]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _harajStrip(List<Map<String, dynamic>> posts) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 150,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: posts.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final post = posts[i];
            return GestureDetector(
              onTap: () => context.push('/haraj/${post['id']}'),
              child: SizedBox(
                width: 160,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AppImage(
                          J.str(post['image_url'] ?? post['thumbnail']),
                          placeholder: appController.placeholder,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      J.str(post['title']),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      money(post['price'], appController.currency,
                          appController.decimals),
                      style: TextStyle(
                        color: appController.accentColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _productGrid(List<Map<String, dynamic>> items) {
    return SliverLayoutBuilder(builder: (ctx, c) {
      final w = c.crossAxisExtent;
      final count = w >= 900 ? 4 : w >= 600 ? 3 : 2;
      final aspect = w >= 600 ? 0.68 : 0.62;
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: aspect,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, i) => ProductCard(
              product: items[i],
              onTap: () => _openProduct(items[i]),
              onAdd: () => addProductFromCatalog(context, items[i]),
            ),
            childCount: items.length,
          ),
        ),
      );
    });
  }

  void _openProduct(Map<String, dynamic> product) {
    final slug = J.str(product['slug']);
    context.push(
      slug.isNotEmpty
          ? '/product/$slug'
          : '/product/${product['id']}?id=${product['id']}',
    );
  }
}

/// Auto-playing hero slider with page indicator dots (web CampaignHero parity).
class _HeroSlider extends StatefulWidget {
  const _HeroSlider({required this.slides, required this.onOpen});
  final List<Map<String, dynamic>> slides;
  final ValueChanged<Map<String, dynamic>> onOpen;

  @override
  State<_HeroSlider> createState() => _HeroSliderState();
}

class _HeroSliderState extends State<_HeroSlider> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    if (widget.slides.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_controller.hasClients) return;
        final next = (_page + 1) % widget.slides.length;
        _controller.animateToPage(
          next,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _open(Map<String, dynamic> item) {
    widget.onOpen(item);
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    if (slides.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          height: 170,
          child: PageView.builder(
            controller: _controller,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) {
              final item = slides[i];
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: GestureDetector(
                  onTap: () => _open(item),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AppImage(
                      J.str(item['image_url'] ?? item['image']),
                      placeholder: appController.placeholder,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (slides.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(slides.length, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: active
                      ? AppTheme.accentOrange
                      : AppTheme.primaryNavy.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
      ],
    );
  }
}

class _UnderlineTabs extends StatelessWidget {
  const _UnderlineTabs({
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> values;
  final List<String> labels;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.primaryNavy.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: List.generate(values.length, (i) {
          final active = values[i] == selected;
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(values[i]),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    labels[i],
                    style: TextStyle(
                      color: active
                          ? AppTheme.accentOrange
                          : AppTheme.textSecondary,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    height: active ? 5 : 0,
                    width: active ? 56 : 0,
                    decoration: BoxDecoration(
                      color: AppTheme.accentOrange,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Lightweight empty-state for inline catalog blocks (not a full screen).
class EmptyStateInline extends StatelessWidget {
  const EmptyStateInline({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.inbox_outlined, size: 48, color: AppTheme.textSecondary),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
      ],
    );
  }
}
