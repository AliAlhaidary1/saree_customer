import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';
import '../../core/catalog_store.dart';
import '../../core/config.dart';
import '../../core/diag.dart';
import '../../core/json_util.dart';
import '../../core/product_media.dart';
import '../../core/promo_price.dart';
import '../../core/search_scope.dart';
import '../../widgets/app_image.dart';
import '../../widgets/closed_store_badge.dart';
import '../../widgets/product_card.dart';
import '../../widgets/product_variant_sheet.dart';
import '../../widgets/requires_internet_dialog.dart';
import '../../widgets/ui_helpers.dart';

/// Catalog sync progress + retry strip. Visible only while a best-effort
/// sync runs or when the last run parked with an error (saved data kept).
class _CatalogSyncStrip extends StatelessWidget {
  const _CatalogSyncStrip();

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return ValueListenableBuilder<CatalogSyncProgress>(
      valueListenable: app.catalogSync.progress,
      builder: (_, p, _) {
        if (p.phase == CatalogSyncPhase.syncing) {
          final indeterminate = p.total <= 0;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: indeterminate
                        ? null
                        : (p.completed / (p.total == 0 ? 1 : p.total)).clamp(
                            0.0,
                            1.0,
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  app.t('catalog_syncing'),
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          );
        }
        if (p.phase == CatalogSyncPhase.error && p.scope.isNotEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    app.t('catalog_sync_failed'),
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ),
                TextButton(
                  onPressed: () => app.syncCatalogNow(),
                  child: Text(app.t('retry')),
                ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

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

class _ProductsScreenState extends State<ProductsScreen> {
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
        widget.search ??
        (widget.listenHeaderSearch ? headerSearch.productQuery : '');
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
    _search.dispose();
    super.dispose();
  }

  void _onHeaderSearch() {
    if (headerSearch.productQuery == _search.text) return;
    _search.text = headerSearch.productQuery;
    _load(reset: true);
  }

  // parity with front productFilterReducer + getProductbyFilter
  String priceMin = '';
  String priceMax = '';
  String minRating = '';
  bool canDeliver = false;
  bool isHome = false;
  bool isReturnable = false;

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

  /// Honest data state of the current scope (never inferred from a row count:
  /// zero rows can mean unsynchronized, failed, or genuinely empty).
  CatalogScopeStatus _catalogStatus = CatalogScopeStatus.neverSynced;

  /// Empty-state copy for the current [_catalogStatus]. `ready` (or any
  /// unknown future state) with zero items means the query matched nothing.
  String _emptyMessage() =>
      catalogEmptyMessage(_catalogStatus, appController.t);

  Future<void> _load({bool reset = false}) async {
    if (!reset && (loadingMore || !hasMore)) return;
    final mySeq = ++_seq;
    final swLoad = Diag.enabled ? (Stopwatch()..start()) : null;
    final point = appController.browseCoords;
    if (reset) {
      offset = 0;
      hasMore = true;
    }
    // Kick the network page off now, in parallel with the local-first reads
    // below. Local DB work must never postpone the request that actually
    // refreshes the grid; the response is awaited further down.
    final network =
        Future.sync(
              () => appController.api.products(
                latitude: point.latitude,
                longitude: point.longitude,
                filters: _filters,
              ),
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => ApiResult({'status': 0}),
            )
            .catchError((_) => ApiResult({'status': 0}));
    if (reset) {
      _catalogStatus = (await appController.catalogScopeState()).status;
      if (!mounted || mySeq != _seq) return;
      // Local-first: paint cached page instantly (offline-capable), then
      // refresh from network. Stale rows stay visible on refresh failure.
      final cached = appController.readCachedProductPage(_filters);
      if (cached.isNotEmpty) {
        setState(() {
          items = cached;
          offset = items.length;
          loading = false;
        });
      } else {
        // Synchronized catalog covers queries never visited (full local
        // browsing, not just the last visited page).
        final local = await appController.catalogProductsLocal(
          categoryId: int.tryParse(categoryId ?? ''),
          storeId: int.tryParse(widget.sellerId ?? ''),
          sectionId: widget.sectionId ?? '',
          sellerSectionId: widget.sellerSectionId ?? '',
          search: _search.text.trim(),
          sort: sort,
          priceMin: priceMin,
          priceMax: priceMax,
          minRating: minRating,
          inStock: inStock,
          onlyOffers: widget.hasOffer || onlyOffers,
          canDeliver: canDeliver,
          isReturnable: isReturnable,
          limit: AppConfig.productPageSize,
        );
        if (!mounted || mySeq != _seq) return;
        if (local.isNotEmpty) {
          setState(() {
            items = local;
            offset = items.length;
            loading = false;
            hasMore = local.length >= AppConfig.productPageSize;
          });
        } else {
          setState(() => loading = true);
        }
      }
    } else {
      setState(() => loadingMore = true);
    }
    try {
      // Started above, already in flight while the local-first rows painted.
      final result = await network;
      if (!mounted || mySeq != _seq) return; // stale response: ignore.
      if (swLoad != null) {
        Diag.log(
          'products:load',
          '${swLoad.elapsedMilliseconds}ms status=${result.status} '
              'rows=${result.dataMaps.length} reset=$reset offset=$offset',
        );
      }
      if (result.ok) {
        final next = result.dataMaps;
        if (reset && next.isNotEmpty) {
          // Background write: the grid paints without waiting on SQLite.
          unawaited(appController.cacheProductPage(_filters, next));
        }
        setState(() {
          // Dedupe by stable server id: offset pages over live backend data
          // can repeat rows when items are inserted between requests.
          items = reset ? next : J.appendUnique(items, next);
          offset = items.length;
          hasMore = next.length >= AppConfig.productPageSize;
          loading = false;
          loadingMore = false;
        });
      } else {
        // Refresh failed: fall back to the synchronized catalog (offline
        // pagination over all synced rows), then keep cached rows (if any).
        final local = reset
            ? await appController.catalogProductsLocal(
                categoryId: int.tryParse(categoryId ?? ''),
                storeId: int.tryParse(widget.sellerId ?? ''),
                sectionId: widget.sectionId ?? '',
                sellerSectionId: widget.sellerSectionId ?? '',
                search: _search.text.trim(),
                sort: sort,
                priceMin: priceMin,
                priceMax: priceMax,
                minRating: minRating,
                inStock: inStock,
                onlyOffers: widget.hasOffer || onlyOffers,
                canDeliver: canDeliver,
                isReturnable: isReturnable,
                limit: AppConfig.productPageSize,
              )
            : await appController.catalogProductsLocal(
                categoryId: int.tryParse(categoryId ?? ''),
                storeId: int.tryParse(widget.sellerId ?? ''),
                sectionId: widget.sectionId ?? '',
                sellerSectionId: widget.sellerSectionId ?? '',
                search: _search.text.trim(),
                sort: sort,
                priceMin: priceMin,
                priceMax: priceMax,
                minRating: minRating,
                inStock: inStock,
                onlyOffers: widget.hasOffer || onlyOffers,
                canDeliver: canDeliver,
                isReturnable: isReturnable,
                limit: AppConfig.productPageSize,
                offset: items.length,
              );
        if (!mounted || mySeq != _seq) return;
        setState(() {
          if (local.isNotEmpty) {
            items = reset ? local : J.appendUnique(items, local);
            offset = items.length;
            hasMore = local.length >= AppConfig.productPageSize;
            loading = false;
          } else {
            // Nothing to show and nothing coming: stop spinning so the
            // empty state (with status copy + retry) paints instead.
            loading = false;
          }
          loadingMore = false;
        });
      }
    } catch (_) {
      if (!mounted || mySeq != _seq) return;
      // Network threw (offline/timeout): same local-catalog fallback.
      final local = await appController.catalogProductsLocal(
        categoryId: int.tryParse(categoryId ?? ''),
        storeId: int.tryParse(widget.sellerId ?? ''),
        sectionId: widget.sectionId ?? '',
        sellerSectionId: widget.sellerSectionId ?? '',
        search: _search.text.trim(),
        sort: sort,
        priceMin: priceMin,
        priceMax: priceMax,
        minRating: minRating,
        inStock: inStock,
        onlyOffers: widget.hasOffer || onlyOffers,
        canDeliver: canDeliver,
        isReturnable: isReturnable,
        limit: AppConfig.productPageSize,
        offset: reset ? 0 : items.length,
      );
      if (!mounted || mySeq != _seq) return;
      setState(() {
        if (local.isNotEmpty) {
          items = reset ? local : J.appendUnique(items, local);
          offset = items.length;
          hasMore = local.length >= AppConfig.productPageSize;
          loading = false;
        } else {
          loading = false;
        }
        loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return Scaffold(
      body: Column(
        children: [
          const _CatalogSyncStrip(),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? EmptyState(
                    message: _emptyMessage(),
                    actionLabel: app.t('retry'),
                    onAction: () {
                      if (_catalogStatus == CatalogScopeStatus.neverSynced ||
                          _catalogStatus == CatalogScopeStatus.failed) {
                        appController.syncCatalogNow();
                      }
                      _load(reset: true);
                    },
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.pixels > n.metrics.maxScrollExtent - 240 &&
                          !loadingMore &&
                          hasMore) {
                        _load();
                      }
                      return false;
                    },
                    child: LayoutBuilder(
                      builder: (ctx, c) {
                        final count = c.maxWidth >= 900
                            ? 4
                            : c.maxWidth >= 600
                            ? 3
                            : 2;
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
                            if (i >= items.length) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
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
                              onAdd: () =>
                                  addProductFromCatalog(context, product),
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
  Map<String, dynamic>? _rateableOrderItem;
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

    // Local-first: paint cached details instantly, then refresh. The
    // synchronized catalog covers products never opened before (unlike the
    // visit-scoped JSON cache); the network refresh below still revalidates.
    if (product == null) {
      final cached = appController.readCachedProductDetails(widget.slug);
      if (cached != null) {
        final variants = J.maps(cached['variants']);
        setState(() {
          product = cached;
          variant = variants.isNotEmpty ? variants.first : cached;
          loading = false;
        });
      } else {
        final local = await appController.catalogProductLocal(
          id: id,
          slug: id == null ? widget.slug : '',
        );
        if (local != null && mounted) {
          final variants = J.maps(local['variants']);
          setState(() {
            product = local;
            variant = variants.isNotEmpty ? variants.first : local;
            loading = false;
          });
        }
      }
    }

    // Bounded: keeps the painted cached/local details on stall instead of
    // holding the page (the refresh below is idempotent).
    final result = await appController.api
        .productById(
          latitude: point.latitude,
          longitude: point.longitude,
          id: id,
          slug: id == null ? widget.slug : '',
        )
        .timeout(
          const Duration(seconds: 12),
          onTimeout: () => ApiResult({'status': 0}),
        )
        .catchError((_) => ApiResult({'status': 0}));
    if (!result.ok) {
      if (!mounted) return;
      // Keep cached row if available; show a retry button when nothing cached.
      setState(() {
        loading = product == null;
        error = product == null ? result.message : null;
      });
      return;
    }
    final data = result.dataMap.isNotEmpty
        ? result.dataMap
        : (result.dataMaps.isNotEmpty
              ? result.dataMaps.first
              : <String, dynamic>{});
    final variants = J.maps(data['variants']);
    await appController.cacheProductDetails(widget.slug, data);
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
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => ApiResult({'status': 0}),
          )
          .catchError((_) => ApiResult({'status': 0})),
      if (tags.isNotEmpty)
        app.api
            .products(
              latitude: point.latitude,
              longitude: point.longitude,
              tagNames: tags,
              filters: {'limit': 10, 'in_stock': 1},
            )
            .timeout(
              const Duration(seconds: 12),
              onTimeout: () => ApiResult({'status': 0}),
            )
            .catchError((_) => ApiResult({'status': 0})),
      app.api
          .catalogOffers(productId: data['id'])
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => ApiResult({'status': 0}),
          )
          .catchError((_) => ApiResult({'status': 0})),
    ]);
    if (!mounted) return;
    final r = results[0];
    final o = results.last;
    final s = results.length == 3 ? results[1] : null;
    setState(() {
      if (r.ok) {
        final d = r.dataMap;
        final list = J.maps(d['rating_list']);
        ratings = list;
        ratingAvg =
            double.tryParse(
              '${d['average_rating'] ?? d['average'] ?? data['average_rating'] ?? ''}',
            ) ??
            0;
        ratingCount =
            int.tryParse(
              '${d['rating_count'] ?? d['count'] ?? d['total'] ?? data['rating_count'] ?? ''}',
            ) ??
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
    // Reviews are purchase-gated (delivered order line required). Resolve the
    // eligible line so "write review" is only offered when the backend would
    // accept it.
    if (app.isLoggedIn) {
      final rateable = await app.rateableOrderItemForProduct(data['id']);
      if (!mounted) return;
      setState(() => _rateableOrderItem = rateable);
    }
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
      'telegram':
          'https://t.me/share/url?url=${Uri.encodeComponent(link)}&text=${Uri.encodeComponent(name)}',
      'facebook':
          'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(link)}',
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
              title: Text(
                app.t('copied') == 'copied'
                    ? 'نسخ الرابط'
                    : app.t('share_product'),
              ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(app.t('copied'))));
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
          '/login?next=${Uri.encodeComponent('/product/${widget.slug}')}',
        );
      }
      return;
    }
    final rateable = _rateableOrderItem;
    if (rateable == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(app.t('rating_after_purchase_only'))),
      );
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
              child: Text(app.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(app.t('submit_rating')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (stars == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(app.t('rating_required'))));
      return;
    }
    if (!await app.hasInternetAccess()) {
      if (mounted) await showRequiresInternetDialog(context);
      return;
    }
    final res = await app.api.addProductRating({
      'product_id': product!['id'],
      'rate': stars,
      'review': ctrl.text.trim(),
      'order_item_id': rateable['order_item_id'],
      'order_id': rateable['order_id'],
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
            Text(
              app.t('other_sellers'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...offers.map(
              (o) => ListTile(
                title: Text(
                  J.str(o['store_name'] ?? o['seller_name'] ?? o['name']),
                ),
                subtitle: o['price'] != null
                    ? Text(money(o['price'], app.currency, app.decimals))
                    : null,
                trailing: Text(app.t('add_to_cart')),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/seller/${o['seller_id'] ?? o['id']}');
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
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: Text(app.t('product'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (product == null || product!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(app.t('product'))),
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
    }
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
        title: Text(
          J.str(product!['name']).isEmpty
              ? app.t('product')
              : J.str(product!['name']),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          ListenableBuilder(
            listenable: app,
            builder: (_, _) => IconButton(
              onPressed: () => context.push('/cart'),
              icon: Badge(
                isLabelVisible: app.cartCount > 0,
                label: Text(
                  '${app.cartCount}',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
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
                            onPageChanged: (i) => setState(() => _imgIndex = i),
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
                            border: Border.all(color: const Color(0xFFDC2626)),
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
                                duration: const Duration(milliseconds: 200),
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
                            money(price.finalPrice, app.currency, app.decimals),
                            style: const TextStyle(
                              fontSize: 22,
                              color: AppTheme.accentOrange,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (price.hasDiscount)
                            Text(
                              money(price.original, app.currency, app.decimals),
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
                          if (J.flag(
                            product!['is_returnable'] ??
                                product!['return_status'],
                          ))
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
                              bg: AppTheme.accentOrange.withValues(alpha: 0.1),
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
                        final helperLabel = AppController.variantLabelOf(
                          item,
                          J.str(product!['name']),
                        );
                        final label = helperLabel.isEmpty
                            ? J.str(item['name'] ?? item['id'])
                            : helperLabel;
                        final selected = '${item['id']}' == '${variant?['id']}';
                        return GestureDetector(
                          onTap: () => setState(() => variant = item),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
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
                                        color: AppTheme.accentOrange.withValues(
                                          alpha: 0.3,
                                        ),
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
                      if (_rateableOrderItem != null)
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
                            for (
                              var i = 0;
                              i < ratings.take(3).length;
                              i++
                            ) ...[
                              if (i > 0) const Divider(height: 16),
                              _reviewTile(ratings.take(3).toList()[i]),
                            ],
                          ],
                        ),
                ),
                if (app.isLoggedIn && _rateableOrderItem == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 4, left: 4),
                    child: Text(
                      app.t('rating_after_purchase_only'),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
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
                      scrollCacheExtent: ScrollCacheExtent.pixels(250),
                      scrollDirection: Axis.horizontal,
                      itemCount: similar.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => SizedBox(
                        width: 160,
                        child: ProductCard(
                          product: similar[i],
                          onTap: () {
                            final slug = J.str(similar[i]['slug']);
                            context.push(
                              slug.isNotEmpty
                                  ? '/product/$slug'
                                  : '/product/${similar[i]['id']}',
                            );
                          },
                          onAdd: () =>
                              addProductFromCatalog(context, similar[i]),
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

  Widget _featureChip(IconData icon, String label, Color color, {Color? bg}) {
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
              ?trailing,
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
    showCartError(context, message);
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
        variantLabel: AppController.variantLabelOf(
          widget.variant,
          J.str(widget.product['name']),
        ),
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
            variantLabel: AppController.variantLabelOf(
              widget.variant,
              J.str(widget.product['name']),
            ),
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
          top: BorderSide(color: AppTheme.primaryNavy.withValues(alpha: 0.08)),
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
            builder: (_, _) {
              final qty = _optimistic ?? app.cartQtyFor(_variantId);
              if (qty <= 0) {
                return SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.outOfStock ? null : () => _setQty(1),
                    icon: const Icon(Icons.shopping_cart_outlined, size: 18),
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
                  _stepBtn(Icons.remove_rounded, onTap: () => _setQty(qty - 1)),
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
                  _stepBtn(Icons.add_rounded, onTap: () => _setQty(qty + 1)),
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
