import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';
import '../../core/json_util.dart';
import '../../core/promo_price.dart';
import '../../widgets/app_image.dart';
import '../../widgets/product_card.dart';
import '../../widgets/product_variant_sheet.dart';
import '../../widgets/skeleton_loader.dart';
import '../more/more_screens.dart';
import '../products/categories_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> sliders = [];
  List<Map<String, dynamic>> flash = [];
  List<Map<String, dynamic>> haraj = [];
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> brands = [];
  List<Map<String, dynamic>> countries = [];
  bool loading = true;
  String? loadError;
  String? _cityKey;
  bool _popupShown = false;

  @override
  void initState() {
    super.initState();
    appController.addListener(_onApp);
    _load();
  }

  @override
  void dispose() {
    appController.removeListener(_onApp);
    super.dispose();
  }

  void _onApp() {
    final key =
        '${appController.city?['id']}-${appController.city?['latitude']}';
    if (key != _cityKey) {
      _cityKey = key;
      _load();
    } else if (mounted) {
      setState(() {});
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
      final point = app.browseCoords;
      final sliderRes = await app.api.sliders();
      final flashRes = await app.api.flashSales();
      final harajRes = await app.api.harajPosts({
        'page': 1,
        'per_page': 4,
        if (app.city?['id'] != null) 'city_id': app.city!['id'],
      });
      if (app.rootCategories.isEmpty) {
        await app.loadRootCategories();
      }
      final sections = J.maps(app.shop?['sections']);
      final sectionProducts = sections
          .expand((section) => J.maps(section['products']))
          .toList();
      List<Map<String, dynamic>> extra = [];
      if (sectionProducts.isEmpty) {
        final productRes = await app.api.products(
          latitude: point.latitude,
          longitude: point.longitude,
          filters: {'limit': 20, 'offset': 0},
        );
        extra = productRes.dataMaps;
      }
      if (!mounted) return;
      List<Map<String, dynamic>> brandRows = J.maps(app.shop?['brands']);
      List<Map<String, dynamic>> countryRows = J.maps(app.shop?['countries']);
      if (app.isBrandSectionEnabled && brandRows.isEmpty) {
        try {
          final bRes = await app.api.shopByBrands(limit: 20);
          if (bRes.ok) brandRows = bRes.dataMaps;
        } catch (_) {}
      }
      if (app.isCountrySectionEnabled && countryRows.isEmpty) {
        try {
          final cRes = await app.api.shopByCountries(limit: 20);
          if (cRes.ok) countryRows = cRes.dataMaps;
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        sliders = sliderRes.dataMaps.isNotEmpty
            ? sliderRes.dataMaps
            : J.maps(app.shop?['sliders']);
        flash = flashRes.dataMaps;
        haraj = harajRes.dataMaps;
        products = extra;
        brands = brandRows;
        countries = countryRows;
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

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final shopCategories = J.maps(app.shop?['categories']);
    final categories = !app.isCategorySectionEnabled
        ? <Map<String, dynamic>>[]
        : (shopCategories.isNotEmpty ? shopCategories : app.rootCategories);
    final sellers = app.isSellerSectionEnabled ? J.maps(app.shop?['sellers']) : <Map<String, dynamic>>[];
    final sections = J.maps(app.shop?['sections']);
    final topOffers = _offers('top');
    final belowSlider = _offers('below_slider');
    final belowCategory = _offers('below_category');
    final belowSection = _offers('below_section');
    final storesOnly = app.isStoresOnly;
    final showCatalog = !storesOnly;
    final hasContent =
        topOffers.isNotEmpty ||
        sliders.isNotEmpty ||
        categories.isNotEmpty ||
        (showCatalog && flash.isNotEmpty) ||
        sellers.isNotEmpty ||
        brands.isNotEmpty ||
        countries.isNotEmpty ||
        haraj.isNotEmpty ||
        (showCatalog && (sections.isNotEmpty || products.isNotEmpty)) ||
        app.akhdimniEnabled;

    return RefreshIndicator(
      onRefresh: () async {
        await app.loadShop();
        await app.loadRootCategories();
        await _load();
      },
      child: CustomScrollView(
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
          if (loadError != null)
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
          if (topOffers.isNotEmpty) _bannerPage(topOffers, 140),
          if (sliders.isNotEmpty) _bannerPage(sliders, 170),
          if (belowSlider.isNotEmpty) _bannerPage(belowSlider, 140),
          if (categories.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                app.t('shop_by_store_type'),
                onSeeAll: () => context.push('/sellers'),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 118,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final cat = categories[i];
                    return GestureDetector(
                      onTap: () => openCategory(context, cat),
                      child: SizedBox(
                        width: 90,
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 34,
                              backgroundColor: AppTheme.surfaceGrey,
                              child: ClipOval(
                                child: AppImage(
                                  J.str(cat['image_url'] ?? cat['image']),
                                  placeholder: app.placeholder,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              J.str(cat['name']),
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
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
          if (belowCategory.isNotEmpty) _bannerPage(belowCategory, 140),
          if (sellers.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                app.t('sellers'),
                onSeeAll: () => context.push('/sellers'),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 108,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: sellers.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final seller = sellers[i];
                    return GestureDetector(
                      onTap: () {
                        final slug = J.str(seller['slug']);
                        context.push(
                          slug.isNotEmpty
                              ? '/store/$slug'
                              : '/seller/${seller['id']}',
                        );
                      },
                      child: SizedBox(
                        width: 92,
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundColor: AppTheme.surfaceGrey,
                              child: ClipOval(
                                child: SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: AppImage(
                                    J.str(seller['logo_url']),
                                    placeholder: app.placeholder,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              J.str(seller['store_name'] ?? seller['name']),
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
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
            SliverToBoxAdapter(
              child: SizedBox(
                height: 150,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: haraj.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final post = haraj[i];
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
                                  placeholder: app.placeholder,
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
                              money(post['price'], app.currency, app.decimals),
                              style: TextStyle(
                                color: app.accentColor,
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
            ),
          ],
          if (brands.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                app.t('brands'),
                onSeeAll: () => context.push('/products'),
              ),
            ),
            _logoStrip(brands, (b) => J.str(b['store_name'] ?? b['name'] ?? b['title']), (b) => J.str(b['logo_url'] ?? b['image_url'] ?? b['image'])),
          ],
          if (countries.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                app.t('countries'),
                onSeeAll: () => context.push('/products'),
              ),
            ),
            _logoStrip(countries, (c) => J.str(c['name']), (c) => J.str(c['image_url'] ?? c['image'] ?? c['flag'])),
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
                  leading: Icon(Icons.delivery_dining, color: app.accentColor),
                  title: Text(app.t('akhdimni')),
                  subtitle: Text(app.t('akhdimni_home_hint')),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => context.push('/akhdimni'),
                ),
              ),
            ),
          if (showCatalog)
            for (final section in sections)
              if (J.maps(section['products']).isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                _sectionTitle(section),
                onSeeAll: () {
                  final type = J.str(section['product_type']);
                  if (type == 'for_you' || type == 'recently_viewed') {
                    context.push('/products');
                  } else {
                    context.push('/products?section=${section['id']}');
                  }
                },
              ),
            ),
            _productStrip(J.maps(section['products'])),
          ],
          if (belowSection.isNotEmpty) _bannerPage(belowSection, 140),
          if (showCatalog && products.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                app.t('products'),
                onSeeAll: () => context.push('/products'),
              ),
            ),
            _productGrid(products.take(8).toList()),
          ],
          if (storesOnly && sellers.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () => context.push('/sellers'),
                  child: Text(app.t('see_all_sellers')),
                ),
              ),
            ),
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
    );
  }

  String _sectionTitle(Map<String, dynamic> section) {
    final type = J.str(section['product_type']);
    if (type == 'for_you') return appController.t('for_you');
    if (type == 'recently_viewed') return appController.t('recently_viewed');
    return J.str(section['title'] ?? section['short_description']);
  }

  Widget _logoStrip(
    List<Map<String, dynamic>> items,
    String Function(Map<String, dynamic>) label,
    String Function(Map<String, dynamic>) image,
  ) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 108,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => SizedBox(
            width: 92,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppTheme.surfaceGrey,
                  child: ClipOval(
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: AppImage(
                        image(items[i]),
                        placeholder: appController.placeholder,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label(items[i]),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
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
        height: 250,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => SizedBox(
            width: 160,
            child: ProductCard(
              product: items[i],
              onTap: () => _openProduct(items[i]),
              onAdd: () => addProductFromCatalog(context, items[i]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _productGrid(List<Map<String, dynamic>> items) {
    return SliverLayoutBuilder(builder: (ctx, c){
      final w = c.crossAxisExtent;
      final count = w >= 900 ? 4 : w >= 600 ? 3 : 2;
      final aspect = w >= 600 ? 0.68 : 0.62;
      return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
    );});
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
