import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_controller.dart';
import '../../core/config.dart';
import '../../core/json_util.dart';
import '../../core/product_media.dart';
import '../../core/promo_price.dart';
import '../../widgets/app_image.dart';
import '../../widgets/closed_store_badge.dart';
import '../../widgets/product_card.dart';
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
  });

  final String? categoryId;
  final String? sellerId;
  final String? search;
  final bool hasOffer;
  final String? sectionId;
  final String? sellerSectionId;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = true;
  int offset = 0;
  String sort = '';
  String? categoryId;
  bool inStock = false;
  bool onlyOffers = false;

  @override
  void initState() {
    super.initState();
    categoryId = widget.categoryId;
    onlyOffers = widget.hasOffer;
    _search.text = widget.search ?? '';
    _load(reset: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // parity with front productFilterReducer + getProductbyFilter
  String priceMin='';
  String priceMax='';
  String brandIds='';
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

  Map<String, dynamic> get _filters => {
    'limit': AppConfig.productPageSize,
    'offset': offset,
    if (categoryId != null && categoryId!.isNotEmpty)
      'category_ids': categoryId,
    if (brandIds.isNotEmpty) 'brand_ids': brandIds,
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
    final next = result.dataMaps;
    if (!mounted) return;
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(reset: true),
                  decoration: InputDecoration(
                    hintText: app.t('search'),
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              IconButton(onPressed: _openFilters, icon: const Icon(Icons.tune)),
            ],
          ),
        ),
        if (app.rootCategories.isNotEmpty)
          SizedBox(
            height: 42,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: app.rootCategories.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                if (i == 0) {
                  final selected = categoryId == null || categoryId!.isEmpty;
                  return ChoiceChip(
                    label: Text(app.t('all') == 'all' ? 'الكل' : app.t('all')),
                    selected: selected,
                    onSelected: (_) {
                      categoryId = null;
                      _load(reset: true);
                    },
                  );
                }
                final cat = app.rootCategories[i - 1];
                final selected = '${cat['id']}' == '$categoryId';
                return ChoiceChip(
                  label: Text(_catName(cat)),
                  selected: selected,
                  onSelected: (_) {
                    categoryId = selected ? null : '${cat['id']}';
                    _load(reset: true);
                  },
                );
              },
            ),
          ),
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
                    final aspect = c.maxWidth >= 600 ? 0.68 : 0.62;
                    return GridView.builder(
                    padding: const EdgeInsets.all(16),
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
    );
  }

  Future<void> _openFilters() async {
    List<Map<String, dynamic>> brandList = [];
    try {
      final bRes = await appController.api.brands(limit: 50);
      if (bRes.ok) brandList = bRes.dataMaps;
    } catch (_) {}
    if (!mounted) return;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var localSort = sort;
        var stock = inStock;
        var offer = onlyOffers;
        var pMin = priceMin;
        var pMax = priceMax;
        var deliver = canDeliver;
        var ret = isReturnable;
        var rating = int.tryParse(minRating) ?? 0;
        var pickedBrands = brandIds.isEmpty
            ? <String>{}
            : brandIds.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
        final minCtrl = TextEditingController(text: pMin);
        final maxCtrl = TextEditingController(text: pMax);
        final t = appController.t;
        return StatefulBuilder(
          builder: (context, setModal) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t('filters'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, {'clear': true}),
                        child: Text(t('clear_all')),
                      ),
                    ],
                  ),
                  Text(t('sort_by'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  RadioListTile(title: Text(t('low_to_high')), value: 'low', groupValue: localSort, onChanged: (v) => setModal(() => localSort = v ?? '')),
                  RadioListTile(title: Text(t('high_to_low')), value: 'high', groupValue: localSort, onChanged: (v) => setModal(() => localSort = v ?? '')),
                  RadioListTile(title: Text(t('newest_first')), value: 'new', groupValue: localSort, onChanged: (v) => setModal(() => localSort = v ?? '')),
                  RadioListTile(title: Text(t('nearest')), value: 'nearest', groupValue: localSort, onChanged: (v) => setModal(() => localSort = v ?? '')),
                  const SizedBox(height: 8),
                  Text(t('min_seller_rating'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Row(
                    children: [
                      for (var i = 1; i <= 5; i++)
                        IconButton(
                          icon: Icon(
                            i <= rating ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                          ),
                          onPressed: () => setModal(() => rating = rating == i ? 0 : i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(t('brands'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (brandList.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(t('no_brands')),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      children: brandList.map((b) {
                        final id = '${b['id']}';
                        final selected = pickedBrands.contains(id);
                        return FilterChip(
                          label: Text(J.str(b['name'])),
                          selected: selected,
                          onSelected: (_) => setModal(() {
                            if (selected) {
                              pickedBrands.remove(id);
                            } else {
                              pickedBrands.add(id);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(decoration: InputDecoration(labelText: t('price_from')), keyboardType: TextInputType.number, controller: minCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(decoration: InputDecoration(labelText: t('price_to')), keyboardType: TextInputType.number, controller: maxCtrl)),
                  ]),
                  SwitchListTile(title: Text(t('in_stock_only')), value: stock, onChanged: (v) => setModal(() => stock = v)),
                  SwitchListTile(title: Text(t('offers')), value: offer, onChanged: (v) => setModal(() => offer = v)),
                  SwitchListTile(title: Text(t('can_deliver')), value: deliver, onChanged: (v)=> setModal(()=> deliver=v)),
                  SwitchListTile(title: Text(t('returnable_only')), value: ret, onChanged: (v)=> setModal(()=> ret=v)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, {
                        'sort': localSort,
                        'stock': stock,
                        'offer': offer,
                        'pMin': minCtrl.text.trim(),
                        'pMax': maxCtrl.text.trim(),
                        'deliver': deliver,
                        'returnable': ret,
                        'rating': rating > 0 ? '$rating' : '',
                        'brands': pickedBrands.join(','),
                      }),
                      child: Text(t('apply')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected != null) {
      if (selected['clear'] == true) {
        sort = '';
        inStock = false;
        onlyOffers = widget.hasOffer;
        priceMin = '';
        priceMax = '';
        canDeliver = false;
        isReturnable = false;
        minRating = '';
        brandIds = '';
      } else {
        sort = selected['sort'] ?? '';
        inStock = selected['stock'] == true;
        onlyOffers = selected['offer'] == true;
        priceMin = selected['pMin'] ?? '';
        priceMax = selected['pMax'] ?? '';
        canDeliver = selected['deliver'] == true;
        isReturnable = selected['returnable'] == true;
        minRating = selected['rating'] ?? '';
        brandIds = selected['brands'] ?? '';
      }
      _load(reset: true);
    }
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
    // Ratings summary + list
    try {
      final r = await app.api.productRatings(productId: data['id'], limit: 5);
      if (mounted && r.ok) {
        final d = J.map(r.dataMap['data']);
        final list = J.maps(r.dataMap['data']).isNotEmpty
            ? J.maps(r.dataMap['data'])
            : r.dataMaps;
        setState(() {
          ratings = list;
          ratingAvg = double.tryParse(
                  '${d['average'] ?? data['average_rating'] ?? ''}') ??
              0;
          ratingCount = int.tryParse(
                  '${d['count'] ?? d['total'] ?? data['rating_count'] ?? ''}') ??
              list.length;
        });
      }
    } catch (_) {}
    // Similar products via tags
    final tags = J.str(data['tag_names'] ?? data['tags']);
    if (tags.isNotEmpty) {
      try {
        final s = await app.api.products(
          latitude: point.latitude,
          longitude: point.longitude,
          tagNames: tags,
          filters: {'limit': 10, 'in_stock': 1},
        );
        if (mounted && s.ok) {
          setState(() {
            similar = s.dataMaps
                .where((p) => '${p['id']}' != '${data['id']}')
                .take(10)
                .toList();
          });
        }
      } catch (_) {}
    }
    // Other sellers (catalog offers)
    try {
      final o = await app.api.catalogOffers(productId: data['id']);
      if (mounted && o.ok) {
        setState(() => offers = o.dataMaps);
      }
    } catch (_) {}
  }

  Future<void> _share() async {
    final app = appController;
    final name = J.str(product!['name']);
    final slug = J.str(product!['slug']);
    final id = '${product!['id']}';
    final link = 'https://saree.market/product/${slug.isNotEmpty ? slug : id}';
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
                    height: 250,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
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
