import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_controller.dart';
import '../../core/business_hours.dart';
import '../../core/city_mode.dart';
import '../../core/device_location.dart';
import '../../core/json_util.dart';
import '../../core/promo_price.dart';
import '../../widgets/app_image.dart';
import '../../widgets/product_card.dart';
import '../../core/app_theme.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/ui_helpers.dart';
import '../products/products_screens.dart';

class SellersScreen extends StatefulWidget {
  const SellersScreen({super.key, this.typeId});
  final String? typeId;

  @override
  State<SellersScreen> createState() => _SellersScreenState();
}

class _SellersScreenState extends State<SellersScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  bool loadingMore = false;
  String? selectedType;
  String sort = 'nearest';
  String search = '';
  int minRating = 0;
  int total = 0;
  int offset = 0;
  static const _limit = 24;
  ({double latitude, double longitude}) origin = (latitude: 0, longitude: 0);
  final _searchC = TextEditingController();

  @override
  void initState() {
    super.initState();
    selectedType = widget.typeId;
    _load();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SellersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.typeId != widget.typeId) {
      selectedType = widget.typeId;
      _load();
    }
  }

  double? _distanceKm(Map<String, dynamic> seller) {
    final stored = seller['distance'];
    if (stored != null) {
      final parsed = double.tryParse('$stored');
      if (parsed != null) return parsed;
    }
    final lat = double.tryParse('${seller['latitude']}');
    final lng = double.tryParse('${seller['longitude']}');
    if (lat == null || lng == null || (lat == 0 && lng == 0)) return null;
    if (origin.latitude == 0 && origin.longitude == 0) return null;
    return Geolocator.distanceBetween(
          origin.latitude,
          origin.longitude,
          lat,
          lng,
        ) /
        1000;
  }

  /// Parity with front ShopBySellersPage + useShopBySellers:
  /// GET /sellers?lat,lng,limit=24,offset,sort,search,type — total displayed.
  Future<void> _load({bool more = false}) async {
    if (more) {
      if (loadingMore) return;
      setState(() => loadingMore = true);
    } else {
      setState(() => loading = true);
    }
    final device = await currentDevicePoint();
    origin = device ?? appController.browseCoords;
    // Front falls back to rating sort when no precise address/GPS.
    var effectiveSort = sort;
    if (sort == 'nearest' && origin.latitude == 0 && origin.longitude == 0) {
      effectiveSort = 'rating';
    }
    final nextOffset = more ? offset + _limit : 0;
    final res = await appController.api.sellers(
      latitude: origin.latitude,
      longitude: origin.longitude,
      limit: _limit,
      offset: nextOffset,
      search: search.isNotEmpty ? search : null,
      sort: effectiveSort.isNotEmpty ? effectiveSort : null,
      type: selectedType?.isNotEmpty == true ? selectedType : null,
      minRating: minRating > 0 ? minRating : null,
    );
    if (!mounted) return;
    var rows = res.dataMaps;
    var serverTotal = J.i(res.raw['total'] ?? res.dataMap['total']);
    final dataNode = res.raw['data'];
    if (rows.isEmpty && dataNode is Map) {
      rows = J.maps(dataNode['data']);
      serverTotal = J.i(dataNode['total'] ?? serverTotal);
    }
    setState(() {
      offset = nextOffset;
      items = more ? [...items, ...rows] : rows;
      total = serverTotal > 0 ? serverTotal : items.length;
      loading = false;
      loadingMore = false;
    });
  }

  void _selectType(String? id) {
    setState(() => selectedType = id);
    _load();
  }

  String _typeName(Map<String, dynamic> cat) {
    final isAr = appController.i18n.code == 'ar';
    final ar = J.str(cat['name_ar']);
    final en = J.str(cat['name_en'] ?? cat['name']);
    return isAr ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final types = app.rootCategories.isNotEmpty
        ? app.rootCategories
        : J.maps(app.shop?['categories']);
    // Server already filters by type/search/sort; keep local nearest fallback sort.
    final visible = List<Map<String, dynamic>>.from(items)
      ..sort((a, b) {
        if (sort != 'nearest') return 0;
        final da = _distanceKm(a);
        final db = _distanceKm(b);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });

    return Scaffold(
      backgroundColor: AppTheme.surfaceGrey,
      appBar: AppBar(title: Text(app.t('sellers'))),
      body: loading
          ? ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: 6,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, __) => const SellerCardSkeleton(),
            )
          : Column(
              children: [
                if (types.isNotEmpty)
                  SizedBox(
                    height: 46,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      scrollDirection: Axis.horizontal,
                      itemCount: types.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          final selected =
                              selectedType == null || selectedType!.isEmpty;
                          return ChoiceChip(
                            label: Text(
                              app.t('all') == 'all' ? 'الكل' : app.t('all'),
                            ),
                            selected: selected,
                            onSelected: (_) => _selectType(null),
                          );
                        }
                        final cat = types[i - 1];
                        final id = '${cat['id']}';
                        return ChoiceChip(
                          label: Text(_typeName(cat)),
                          selected: selectedType == id,
                          onSelected: (_) =>
                              _selectType(selectedType == id ? null : id),
                        );
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchC,
                          decoration: InputDecoration(
                            hintText: app.t('search_stores_placeholder'),
                            prefixIcon: const Icon(Icons.search, size: 18),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onSubmitted: (v) {
                            search = v.trim();
                            _load();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: sort,
                        items: [
                          DropdownMenuItem(
                            value: 'nearest',
                            child: Text(app.t('sort_by_nearest')),
                          ),
                          DropdownMenuItem(
                            value: 'rating',
                            child: Text(app.t('sort_by_rating')),
                          ),
                          DropdownMenuItem(
                            value: 'name',
                            child: Text(app.t('sort_by_name')),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => sort = v);
                          _load();
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Row(
                    children: [
                      Text(
                        total > 0 ? '$total • ${app.t('sellers')}' : app.t('sellers'),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const Spacer(),
                      Text(app.t('min_seller_rating'),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      ...[
                        for (var i = 1; i <= 5; i++)
                          InkWell(
                            onTap: () {
                              setState(
                                  () => minRating = minRating == i ? 0 : i);
                              _load();
                            },
                            child: Icon(
                              i <= minRating
                                  ? Icons.star
                                  : Icons.star_border,
                              size: 18,
                              color: Colors.amber,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? EmptyState(
                          message: app.t('no_stores_found'),
                          actionLabel: app.t('retry'),
                          onAction: _load,
                        )
                      : RefreshIndicator(
                          onRefresh: () => _load(),
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: visible.length + (total > visible.length ? 1 : 0),
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              if (i >= visible.length) {
                                return OutlinedButton(
                                  onPressed: loadingMore ? null : () => _load(more: true),
                                  child: loadingMore
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : Text(app.t('load_more')),
                                );
                              }
                              final seller = visible[i];
                              final distance = _distanceKm(seller);
                              final rating = double.tryParse(
                                '${seller['rating'] ?? seller['average_rating'] ?? 0}',
                              );
                              return _SellerCard(
                                seller: seller,
                                distance: distance,
                                rating: rating,
                                productCount:
                                    '${seller['product_count'] ?? 0}',
                                onTap: () {
                                  final slug = J.str(seller['slug']);
                                  context.push(
                                    slug.isNotEmpty
                                        ? '/store/$slug'
                                        : '/seller/${seller['id']}',
                                  );
                                },
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class SellerPageScreen extends StatefulWidget {
  const SellerPageScreen({super.key, this.id, this.slug});
  final String? id;
  final String? slug;

  @override
  State<SellerPageScreen> createState() => _SellerPageScreenState();
}

class _SellerPageScreenState extends State<SellerPageScreen> {
  Map<String, dynamic>? seller;
  bool loading = true;
  String? sectionId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = widget.slug != null
        ? await appController.api.sellerBySlug(widget.slug!)
        : await appController.api.sellerById('${widget.id}');
    if (!mounted) return;
    setState(() {
      seller = result.dataMap;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (seller == null || seller!.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          message: appController.t('no_stores_found'),
          actionLabel: appController.t('retry'),
          onAction: () {
            setState(() => loading = true);
            _load();
          },
        ),
      );
    }
    final id = '${seller?['id'] ?? widget.id}';
    final sections = J.maps(seller?['sections']);
    final cover = J.str(seller?['cover_url'] ?? seller?['cover'] ?? seller?['banner_url']);
    final avg = double.tryParse(
        '${seller?['average_rating'] ?? seller?['rating'] ?? ''}');
    final ratingCount =
        J.str(seller?['rating_count'] ?? seller?['ratings_count']);
    final productCount = J.str(seller?['product_count']);
    final hours = BusinessHoursSlot.from(
        seller?['business_hours'] ?? seller?['seller_business_hours']);
    final closedByFlag = seller?['seller_is_open'] == false ||
        seller?['seller_is_open'] == 0 ||
        seller?['seller_is_open'] == '0' ||
        seller?['is_open'] == false ||
        seller?['is_open'] == 0 ||
        seller?['is_open'] == '0';
    final isClosed = (hours != null && !hours.isOpen) || (hours == null && closedByFlag);
    return Scaffold(
      appBar: AppBar(
        title: Text(J.str(seller?['store_name'] ?? seller?['name'])),
      ),
      body: Column(
        children: [
          if (cover.isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 6,
              child: AppImage(cover,
                  placeholder: appController.placeholder),
            ),
          ListTile(
            leading: SellerAvatar(
              J.str(seller?['logo_url']),
              radius: 28,
              placeholder: appController.placeholder,
            ),
            title: Text(J.str(seller?['store_name'] ?? seller?['name'])),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (J.str(seller?['store_description'] ??
                        seller?['description'])
                    .isNotEmpty)
                  Text(J.str(seller?['store_description'] ??
                      seller?['description'])),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (avg != null && avg > 0) ...[
                      const Icon(Icons.star,
                          size: 14, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(
                        avg.toStringAsFixed(1) +
                            (ratingCount.isNotEmpty
                                ? ' ($ratingCount)'
                                : ''),
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (productCount.isNotEmpty)
                      Text(
                        '$productCount ${appController.t('products')}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (isClosed)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                buildSellerClosedMessage(
                    hours,
                    J.str(seller?['store_name'] ??
                        seller?['name'])),
                style: TextStyle(
                    color: Colors.red.shade700, fontSize: 12),
              ),
            ),
          if (sections.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  ChoiceChip(
                    label: Text(appController.t('all')),
                    selected: sectionId == null,
                    onSelected: (_) => setState(() => sectionId = null),
                  ),                  ...sections.map(
                    (section) => Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: ChoiceChip(
                        label: Text(J.str(section['name_ar'] ?? section['name'])),
                        selected: sectionId == '${section['id']}',
                        onSelected: (_) => setState(() => sectionId = '${section['id']}'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ProductsScreen(
              key: ValueKey('store-$id-${sectionId ?? 'all'}'),
              sellerId: id,
              sellerSectionId: sectionId,
            ),
          ),
        ],
      ),
    );
  }
}

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  List<Map<String, dynamic>> flash = [];
  List<Map<String, dynamic>> offers = [];
  Map<String, dynamic> campaigns = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final point = appController.browseCoords;
    final f = await appController.api.flashSales();
    final o = await appController.api.productsOffers(
      latitude: point.latitude,
      longitude: point.longitude,
      limit: 30,
    );
    final c = await appController.api.campaigns();
    if (!mounted) return;
    setState(() {
      flash = f.dataMaps;
      offers = o.dataMaps;
      campaigns = c.dataMap;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final products = [
      ...flash.map((item) => J.map(item['product'] ?? item)),
      ...offers,
    ].where((item) => item.isNotEmpty).toList();
    final categoryCards = J.maps(campaigns['category_discounts']);
    final bxgyCards = J.maps(campaigns['bxgy']);
    final promoCards = J.maps(campaigns['promo_codes']);
    final deliveryCards = J.maps(campaigns['delivery']);
    return Scaffold(
      appBar: AppBar(title: Text(app.t('offers'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (categoryCards.isNotEmpty ||
                    bxgyCards.isNotEmpty ||
                    promoCards.isNotEmpty ||
                    deliveryCards.isNotEmpty)
                  Text(
                    app.t('active_campaigns_title'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ...categoryCards.map(
                  (item) => Card(
                    child: ListTile(
                      leading: Icon(Icons.percent, color: app.accentColor),
                      title: Text(J.str(item['category_name'])),
                      subtitle: Text(
                        '${item['discount']}${J.str(item['discount_type']) == 'percentage' ? '%' : ''}',
                      ),
                      onTap: () => context.push(
                        '/sellers?type=${item['category_id']}',
                      ),
                    ),
                  ),
                ),
                ...promoCards.map(
                  (item) => Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.confirmation_number_outlined,
                        color: app.accentColor,
                      ),
                      title: Text(J.str(item['promo_code'])),
                      subtitle: Text(J.str(item['message'])),
                    ),
                  ),
                ),
                ...deliveryCards.map(
                  (item) => Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.local_shipping_outlined,
                        color: app.accentColor,
                      ),
                      title: Text(
                        J.str(
                          item['title'] ?? item['customer_message'],
                          'توصيل مجاني',
                        ),
                      ),
                    ),
                  ),
                ),
                if (products.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Center(
                      child: Text(
                        app.t('no_offers_available') == 'no_offers_available'
                            ? 'لا توجد عروض'
                            : app.t('no_offers_available'),
                      ),
                    ),
                  )
                else ...[
                  const SizedBox(height: 12),
                  Text(
                    app.t('discounted_products') == 'discounted_products'
                        ? 'منتجات مخفضة'
                        : app.t('discounted_products'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(builder: (ctx,c){
                    final count = c.maxWidth >= 900 ? 4 : c.maxWidth >= 600 ? 3 : 2;
                    return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: count,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: count > 2 ? 0.68 : 0.62,
                        ),
                    itemCount: products.length,
                    itemBuilder: (_, i) => ProductCard(
                      product: products[i],
                      onTap: () => context.push(
                        '/product/${products[i]['slug'] ?? products[i]['id']}',
                      ),
                    ),
                  );}),
                ],
              ],
            ),
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final controller = TextEditingController();
  List<Map<String, dynamic>> items = [];
  bool searched = false;
  bool loading = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() {
        items = [];
        searched = false;
      });
      return;
    }
    setState(() => loading = true);
    final point = appController.browseCoords;
    final result = await appController.api.products(
      latitude: point.latitude,
      longitude: point.longitude,
      filters: {'search': q, 'limit': 20, 'offset': 0},
    );
    if (!mounted) return;
    setState(() {
      items = result.dataMaps;
      searched = true;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: app.t('search'),
            border: InputBorder.none,
          ),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : !searched
          ? EmptyState(icon: Icons.search, message: app.t('search'))
          : items.isEmpty
          ? EmptyState(message: app.t('no_search_results'))
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${items.length} • ${app.t('search')}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.push(
                          '/products?search=${Uri.encodeComponent(controller.text.trim())}',
                        ),
                        child: Text(app.t('see_all_results')),
                      ),
                    ],
                  ),
                ),
                ...items.map(
                  (item) => ListTile(
                    leading: SizedBox(
                      width: 48,
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
                  ),
                ),
              ],
            ),
    );
  }
}

class CmsScreen extends StatefulWidget {
  const CmsScreen({super.key, required this.title, required this.settingKey});
  final String title;
  final String settingKey;

  @override
  State<CmsScreen> createState() => _CmsScreenState();
}

class _CmsScreenState extends State<CmsScreen> {
  String html = '';
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final content = await appController.cmsHtml(widget.settingKey);
      if (!mounted) return;
      setState(() {
        html = content;
        loading = false;
        if (content.trim().isEmpty) error = appController.t('no_content_yet');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = appController.t('network_error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: Text(appController.t('retry')),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: HtmlText(html),
            ),
    );
  }
}

class _SellerCard extends StatelessWidget {
  const _SellerCard({
    required this.seller,
    required this.onTap,
    this.distance,
    this.rating,
    required this.productCount,
  });

  final Map<String, dynamic> seller;
  final VoidCallback onTap;
  final double? distance;
  final double? rating;
  final String productCount;

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final name = J.str(seller['store_name'] ?? seller['name']);
    final hasDelivery = J.flag(seller['delivery']) ||
        J.str(seller['delivery_type']).isNotEmpty;

    return Material(
      color: AppTheme.backgroundWhite,
      elevation: 2,
      shadowColor: AppTheme.primaryNavy.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: AppImage(
                    J.str(seller['logo_url']),
                    placeholder: app.placeholder,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (rating != null && rating! > 0) ...[
                          const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: AppTheme.accentOrange,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accentOrange,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          '$productCount ${app.t('products')}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (hasDelivery)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentOrange
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.delivery_dining,
                                  size: 12,
                                  color: AppTheme.accentOrange,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  app.t('delivery') == 'delivery'
                                      ? 'توصيل'
                                      : app.t('delivery'),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.accentOrange,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (distance != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.near_me,
                            size: 12,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${distance!.toStringAsFixed(1)} كم',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_left,
                color: AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CityPickerSheet extends StatelessWidget {
  const CityPickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return ListView(
      children: app.cities
          .map(
            (city) => ListTile(
              title: Text(J.str(city['name'])),
              selected: '${app.city?['id']}' == '${city['id']}',
              onTap: () {
                app.selectCity(normalizeCity(city));
                Navigator.pop(context);
              },
            ),
          )
          .toList(),
    );
  }
}
