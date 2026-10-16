import 'dart:async';

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
import '../../widgets/offline_banner.dart';
import '../../widgets/product_card.dart';
import '../../widgets/product_variant_sheet.dart';
import '../../core/app_theme.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/store_card.dart';
import '../../widgets/ui_helpers.dart';
import '../../widgets/unified_tabs.dart';
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
  bool _servedFromCache = false;
  // Generation counter: search/type/sort changes and load-more races must
  // never let a stale response overwrite newer results or corrupt offsets.
  int _seq = 0;
  ({double latitude, double longitude}) origin = (latitude: 0, longitude: 0);
  final _searchC = TextEditingController();
  Timer? _searchDeb;

  @override
  void initState() {
    super.initState();
    selectedType = widget.typeId;
    _load();
  }

  @override
  void dispose() {
    _searchDeb?.cancel();
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

  /// Location resolution must never break the list: a failing provider
  /// (or a test environment without platform plugins) falls back to the
  /// controller's browse coordinates. The lookup is additionally bounded:
  /// a wedged provider that never answers must not hold the list hostage.
  Future<({double latitude, double longitude})?> _devicePoint() async {
    try {
      return await currentDevicePoint().timeout(
        const Duration(seconds: 8),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
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

  List<Map<String, dynamic>> _applyLocalSearch(
    List<Map<String, dynamic>> rows,
  ) {
    final q = search.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((s) {
      final name = J.str(s['name'] ?? s['store_name']).toLowerCase();
      return name.contains(q);
    }).toList();
  }

  /// Parity with front ShopBySellersPage + useShopBySellers:
  /// GET /sellers?lat,lng,limit=24,offset,sort,search,type — total displayed.
  Future<void> _load({bool more = false}) async {
    if (more && loadingMore) return;
    // Resets start a new generation (cancelling in-flight continuations);
    // load-more joins the current generation so a concurrent reset drops it.
    final mySeq = more ? _seq : ++_seq;
    if (more) {
      setState(() => loadingMore = true);
    } else {
      setState(() => loading = true);
      // Local-first: synchronized stores paint instantly offline.
      final local = await appController.catalogStoresLocal(limit: _limit);
      if (!mounted) return;
      if (mySeq != _seq) {
        // Superseded (only possible for load-more vs a newer reset): release
        // the spinner so a fresh continuation can fire.
        if (more) setState(() => loadingMore = false);
        return;
      }
      if (local.isNotEmpty) {
        setState(() {
          items = _applyLocalSearch(local);
          total = items.length;
          loading = false;
          _servedFromCache = true;
        });
      }
    }
    final device = await _devicePoint();
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
    if (mySeq != _seq) {
      if (more) setState(() => loadingMore = false);
      return;
    }
    if (!res.ok) {
      // Refresh failed: fall back to the synchronized store catalog, then
      // keep existing rows instead of clearing them.
      final local = await appController.catalogStoresLocal(
        limit: _limit,
        offset: more ? items.length : 0,
      );
      if (!mounted) return;
      if (mySeq != _seq) {
        if (more) setState(() => loadingMore = false);
        return;
      }
      final filtered = _applyLocalSearch(local);
      if (!mounted) return;
      if (mySeq != _seq) {
        if (more) setState(() => loadingMore = false);
        return;
      }
      setState(() {
        if (filtered.isNotEmpty) {
          items = more && search.trim().isEmpty
              ? J.appendUnique(items, filtered)
              : filtered;
          total = items.length;
          _servedFromCache = true;
        }
        loading = false;
        loadingMore = false;
      });
      return;
    }
    _servedFromCache = false;
    var rows = res.dataMaps;
    var serverTotal = J.i(res.raw['total'] ?? res.dataMap['total']);
    final dataNode = res.raw['data'];
    if (rows.isEmpty && dataNode is Map) {
      rows = J.maps(dataNode['data']);
      serverTotal = J.i(dataNode['total'] ?? serverTotal);
    }
    setState(() {
      offset = nextOffset;
      items = more ? J.appendUnique(items, rows) : rows;
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

  String _typeImage(Map<String, dynamic> cat) {
    return J.str(
      cat['image_url'] ?? cat['image'] ?? cat['icon_url'] ?? cat['icon'],
    );
  }

  int get _activeFilterCount => [
    selectedType?.isNotEmpty == true,
    search.isNotEmpty,
    sort != 'nearest' && sort.isNotEmpty,
    minRating > 0,
  ].where((e) => e).length;

  String _sortLabel(AppController app) {
    switch (sort) {
      case 'rating':
        return app.t('sort_by_rating');
      case 'name':
        return app.t('sort_by_name');
      default:
        return app.t('sort_by_nearest');
    }
  }

  String? _selectedTypeName(List<Map<String, dynamic>> types) {
    if (selectedType == null || selectedType!.isEmpty) return null;
    for (final c in types) {
      if ('${c['id']}' == selectedType) return _typeName(c);
    }
    return null;
  }

  void _onSearchChanged(String v) {
    _searchDeb?.cancel();
    _searchDeb = Timer(const Duration(milliseconds: 450), () {
      final next = v.trim();
      if (next == search) return;
      setState(() => search = next);
      _load();
    });
    // Refresh clear-button immediately.
    setState(() {});
  }

  void _clearAllFilters() {
    _searchC.clear();
    setState(() {
      selectedType = null;
      search = '';
      sort = 'nearest';
      minRating = 0;
    });
    _load();
  }

  void _openFilterSheet() {
    var tmpSort = sort;
    var tmpRating = minRating;
    final app = appController;
    final sortOptions = [
      ('nearest', app.t('sort_by_nearest'), Icons.near_me_outlined),
      ('rating', app.t('sort_by_rating'), Icons.star_outline),
      ('name', app.t('sort_by_name'), Icons.sort_by_alpha_outlined),
    ];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(ctx).padding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      app.t('filters'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setSheet(() {
                        tmpSort = 'nearest';
                        tmpRating = 0;
                      });
                    },
                    child: Text(app.t('clear_all')),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                app.t('sort_by'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              ...sortOptions.map(
                (o) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: tmpSort == o.$1
                        ? AppTheme.accentOrange.withValues(alpha: 0.1)
                        : AppTheme.surfaceGrey,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setSheet(() => tmpSort = o.$1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              o.$3,
                              size: 20,
                              color: tmpSort == o.$1
                                  ? AppTheme.accentOrange
                                  : AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                o.$2,
                                style: TextStyle(
                                  fontWeight: tmpSort == o.$1
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: tmpSort == o.$1
                                      ? AppTheme.accentOrange
                                      : AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            if (tmpSort == o.$1)
                              const Icon(
                                Icons.check_circle,
                                color: AppTheme.accentOrange,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                app.t('min_seller_rating'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => setSheet(() => tmpRating = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: tmpRating == 0
                            ? AppTheme.primaryNavy
                            : AppTheme.surfaceGrey,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        app.t('all'),
                        style: TextStyle(
                          color: tmpRating == 0
                              ? Colors.white
                              : AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 1; i <= 5; i++)
                          GestureDetector(
                            onTap: () => setSheet(
                              () => tmpRating = tmpRating == i ? 0 : i,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: Icon(
                                i <= tmpRating
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 32,
                                color: i <= tmpRating
                                    ? AppTheme.accentOrange
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (tmpRating > 0)
                    Text(
                      '$tmpRating+',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accentOrange,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    setState(() {
                      sort = tmpSort;
                      minRating = tmpRating;
                    });
                    Navigator.pop(ctx);
                    _load();
                  },
                  child: Text(app.t('apply')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Navy brand header — parity with home [_BrandHeader]: logo + title +
  /// cart, with the white search pill underneath.
  Widget _buildBrandHeader(AppController app, String title) {
    return Container(
      color: AppTheme.primaryNavy,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/');
                      }
                    },
                    icon: const Icon(
                      Icons.arrow_back,
                      color: AppTheme.backgroundWhite,
                    ),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                  ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundWhite,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.asset(
                        'assets/brand/sareemart-logo.png',
                        width: 32,
                        height: 32,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.shopping_cart_rounded,
                          color: AppTheme.accentOrange,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppTheme.backgroundWhite,
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          total > 0
                              ? '$total • ${app.t('sellers')}'
                              : app.t('sellers'),
                          style: TextStyle(
                            color: AppTheme.backgroundWhite.withValues(
                              alpha: 0.7,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ListenableBuilder(
                    listenable: app,
                    builder: (_, _) => IconButton(
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
                        child: const Icon(
                          Icons.shopping_cart_outlined,
                          color: AppTheme.backgroundWhite,
                        ),
                      ),
                      tooltip: app.t('cart'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.backgroundWhite,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      color: AppTheme.primaryNavy.withValues(alpha: 0.5),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchC,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (v) {
                          _searchDeb?.cancel();
                          setState(() => search = v.trim());
                          _load();
                        },
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: app.t('search_stores_placeholder'),
                          hintStyle: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                          ),
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    if (_searchC.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchC.clear();
                          setState(() => search = '');
                          _load();
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.cancel,
                            size: 18,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeCard({
    required bool selected,
    required String label,
    String? imageUrl,
    bool isAll = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 78,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: selected
                          ? AppTheme.accentOrange
                          : Colors.grey.shade200,
                      width: selected ? 2.5 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (selected
                                    ? AppTheme.accentOrange
                                    : AppTheme.primaryNavy)
                                .withValues(alpha: selected ? 0.25 : 0.07),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: isAll
                        ? Container(
                            color: selected
                                ? AppTheme.accentOrange
                                : AppTheme.primaryNavy,
                            child: const Icon(
                              Icons.storefront_outlined,
                              color: Colors.white,
                              size: 28,
                            ),
                          )
                        : (imageUrl != null && imageUrl.isNotEmpty
                              ? AppImage(
                                  imageUrl,
                                  placeholder: appController.placeholder,
                                  thumb: true,
                                )
                              : Container(
                                  color: AppTheme.surfaceGrey,
                                  child: const Icon(
                                    Icons.store_outlined,
                                    color: AppTheme.textSecondary,
                                  ),
                                )),
                  ),
                ),
                if (selected)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppTheme.accentOrange,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.2,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppTheme.accentOrange : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(AppController app, List<Map<String, dynamic>> types) {
    final typeName = _selectedTypeName(types);
    final chips = <Widget>[];
    if (typeName != null) {
      chips.add(
        _activeChip(
          label: typeName,
          icon: Icons.storefront_outlined,
          onDeleted: () => _selectType(null),
        ),
      );
    }
    if (search.isNotEmpty) {
      chips.add(
        _activeChip(
          label: '“$search”',
          icon: Icons.search,
          onDeleted: () {
            _searchC.clear();
            setState(() => search = '');
            _load();
          },
        ),
      );
    }
    if (minRating > 0) {
      chips.add(
        _activeChip(
          label: '$minRating+ ★',
          icon: Icons.star_rounded,
          onDeleted: () {
            setState(() => minRating = 0);
            _load();
          },
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(12),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      total > 0
                          ? '$total ${app.t('sellers')}'
                          : app.t('sellers'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _sortLabel(app),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                color: AppTheme.surfaceGrey,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _openFilterSheet,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.swap_vert,
                          size: 17,
                          color: AppTheme.primaryNavy,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _sortLabel(app),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryNavy,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Material(
                    color: AppTheme.accentOrange,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _openFilterSheet,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tune, size: 17, color: Colors.white),
                            SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_activeFilterCount > 0)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryNavy,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white, width: 1.5),
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
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...chips,
                if (_activeFilterCount > 0)
                  GestureDetector(
                    onTap: _clearAllFilters,
                    child: Text(
                      app.t('clear_all'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accentOrange,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _activeChip({
    required String label,
    required IconData icon,
    required VoidCallback onDeleted,
  }) {
    return Container(
      padding: const EdgeInsetsDirectional.only(
        start: 10,
        end: 6,
        top: 6,
        bottom: 6,
      ),
      decoration: BoxDecoration(
        color: AppTheme.accentOrange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accentOrange.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.accentOrange),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.accentOrange,
              ),
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onDeleted,
            child: const Icon(
              Icons.close,
              size: 15,
              color: AppTheme.accentOrange,
            ),
          ),
        ],
      ),
    );
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
    final selectedTitle = _selectedTypeName(types) ?? app.t('sellers');

    return Scaffold(
      backgroundColor: AppTheme.surfaceGrey,
      body: Column(
        children: [
          _buildBrandHeader(app, selectedTitle),
          Expanded(
            child: loading
                ? ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: 6,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, _) => const SellerCardSkeleton(),
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.pixels >
                              n.metrics.maxScrollExtent - 400 &&
                          !loadingMore &&
                          !loading &&
                          total > visible.length &&
                          visible.isNotEmpty) {
                        _load(more: true);
                      }
                      return false;
                    },
                    child: RefreshIndicator(
                      onRefresh: () => _load(),
                      child: CustomScrollView(
                        slivers: [
                        if (types.isNotEmpty)
                          SliverToBoxAdapter(
                            child: Container(
                              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primaryNavy.withValues(
                                      alpha: 0.06,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: SizedBox(
                                height: 102,
                                child: ListView.separated(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  scrollDirection: Axis.horizontal,
                                  itemCount: types.length + 1,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 10),
                                  itemBuilder: (_, i) {
                                    if (i == 0) {
                                      final selected =
                                          selectedType == null ||
                                          selectedType!.isEmpty;
                                      return _typeCard(
                                        selected: selected,
                                        isAll: true,
                                        label: app.t('all') == 'all'
                                            ? 'الكل'
                                            : app.t('all'),
                                        onTap: () => _selectType(null),
                                      );
                                    }
                                    final cat = types[i - 1];
                                    final id = '${cat['id']}';
                                    return _typeCard(
                                      selected: selectedType == id,
                                      label: _typeName(cat),
                                      imageUrl: _typeImage(cat),
                                      onTap: () => _selectType(
                                        selectedType == id ? null : id,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        SliverToBoxAdapter(child: _buildFilterBar(app, types)),
                        SliverToBoxAdapter(
                          child: OfflineBanner(stale: _servedFromCache),
                        ),
                        if (visible.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: EmptyState(
                              message: app.t('no_stores_found'),
                              actionLabel: app.t('retry'),
                              onAction: _load,
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.all(12),
                            sliver: SliverList.separated(
                              itemCount:
                                  visible.length +
                                  (total > visible.length ? 1 : 0),
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                if (i >= visible.length) {
                                  if (!loadingMore) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (mounted &&
                                          !loadingMore &&
                                          total > visible.length) {
                                        _load(more: true);
                                      }
                                    });
                                  }
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final seller = visible[i];
                                final distance = _distanceKm(seller);
                                return StoreCard(
                                  seller: seller,
                                  distanceKm: distance,
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
                      ],
                      ),
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

  bool _servedFromCache = false;

  Future<void> _load() async {
    // Local-first: synchronized store header paints offline. Sections below
    // load their products from the local catalog when available.
    final local = await appController.catalogStoreLocal(
      id: int.tryParse(widget.id ?? ''),
      slug: widget.slug ?? '',
    );
    if (local != null && mounted) {
      setState(() {
        seller = local;
        loading = false;
        _servedFromCache = true;
      });
    }
    final result = widget.slug != null
        ? await appController.api.sellerBySlug(widget.slug!)
        : await appController.api.sellerById('${widget.id}');
    if (!mounted) return;
    setState(() {
      if (result.ok && result.dataMap.isNotEmpty) {
        seller = result.dataMap;
        _servedFromCache = false;
      } else if (seller == null || seller!.isEmpty) {
        seller = result.dataMap;
      } else {
        _servedFromCache = true;
      }
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: Text(appController.t('sellers'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
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
    final cover = J.str(
      seller?['cover_url'] ?? seller?['cover'] ?? seller?['banner_url'],
    );
    final avg = double.tryParse(
      '${seller?['average_rating'] ?? seller?['rating'] ?? ''}',
    );
    final ratingCount = J.str(
      seller?['rating_count'] ?? seller?['ratings_count'],
    );
    final productCount = J.str(seller?['product_count']);
    final hours = BusinessHoursSlot.from(
      seller?['business_hours'] ?? seller?['seller_business_hours'],
    );
    final closedByFlag =
        seller?['seller_is_open'] == false ||
        seller?['seller_is_open'] == 0 ||
        seller?['seller_is_open'] == '0' ||
        seller?['is_open'] == false ||
        seller?['is_open'] == 0 ||
        seller?['is_open'] == '0';
    final isClosed =
        (hours != null && !hours.isOpen) || (hours == null && closedByFlag);
    final storeName = J.str(seller?['store_name'] ?? seller?['name']);
    final storeDesc = J.str(
      seller?['store_description'] ?? seller?['description'],
    );
    final hasDelivery =
        J.flag(seller?['delivery']) ||
        J.str(seller?['delivery_type']).isNotEmpty ||
        J.flag(seller?['can_deliver']);
    return Scaffold(
      backgroundColor: AppTheme.surfaceGrey,
      appBar: AppBar(
        title: Text(storeName),
        actions: [
          ListenableBuilder(
            listenable: appController,
            builder: (_, _) => IconButton(
              onPressed: () => context.push('/cart'),
              icon: Badge(
                isLabelVisible: appController.cartCount > 0,
                backgroundColor: AppTheme.accentOrange,
                label: Text(
                  '${appController.cartCount}',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              tooltip: appController.t('cart'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          OfflineBanner(stale: _servedFromCache),
          // ---- Premium store header: cover + overlapping info card ----
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 148,
                width: double.infinity,
                color: AppTheme.primaryNavy,
                child: cover.isNotEmpty
                    ? AppImage(cover, placeholder: appController.placeholder)
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppTheme.primaryNavy,
                              AppTheme.primaryNavy.withValues(alpha: 0.85),
                            ],
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.storefront_outlined,
                            size: 56,
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
              ),
              Container(
                height: 148,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      AppTheme.primaryNavy.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
              if (isClosed)
                PositionedDirectional(
                  top: 10,
                  start: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          appController.t('closed'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: -42,
                child: Container(
                  padding: const EdgeInsets.all(12),
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
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isClosed
                                ? Colors.grey.shade300
                                : AppTheme.accentOrange,
                            width: 2,
                          ),
                        ),
                        child: SellerAvatar(
                          J.str(seller?['logo_url']),
                          radius: 30,
                          placeholder: appController.placeholder,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    storeName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: isClosed ? Colors.red : Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                            if (storeDesc.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                storeDesc,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (avg != null && avg > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(
                                        alpha: 0.15,
                                      ),
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
                                          avg.toStringAsFixed(1) +
                                              (ratingCount.isNotEmpty
                                                  ? ' ($ratingCount)'
                                                  : ''),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (productCount.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surfaceGrey,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '$productCount ${appController.t('products')}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                if (hasDelivery)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accentOrange.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.delivery_dining,
                                          size: 13,
                                          color: AppTheme.accentOrange,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          appController.t('delivery'),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.accentOrange,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 54),
          if (isClosed)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 15, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      buildSellerClosedMessage(hours, storeName),
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (sections.isNotEmpty)
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: StoreSectionPills(
                labels: [
                  appController.t('all'),
                  ...sections.map(
                    (s) => J.str(
                      s['name_ar'] ?? s['name'] ?? s['title'],
                      appController.t('all'),
                    ),
                  ),
                ],
                selectedIndex: sectionId == null
                    ? 0
                    : (sections.indexWhere((s) => '${s['id']}' == sectionId) +
                          1),
                onChanged: (i) {
                  if (i == 0) {
                    setState(() => sectionId = null);
                  } else {
                    final sid = '${sections[i - 1]['id']}';
                    setState(() => sectionId = sectionId == sid ? null : sid);
                  }
                },
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: ProductsScreen(
              key: ValueKey('store-$id-${sectionId ?? 'all'}'),
              sellerId: id,
              sellerSectionId: sectionId,
              listenHeaderSearch: false,
              hideHeader: true,
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
  bool _servedFromCache = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Local-first: last offers/campaigns snapshot paints offline.
    final snap = appController.readPublicSnapshot('offers_page') as Map?;
    if (snap != null && mounted) {
      final m = J.map(snap);
      setState(() {
        flash = J.maps(m['flash']);
        offers = J.maps(m['offers']);
        campaigns = J.map(m['campaigns']);
        loading = false;
        _servedFromCache = true;
      });
    }
    final point = appController.browseCoords;
    final f = await appController.api.flashSales();
    final o = await appController.api.productsOffers(
      latitude: point.latitude,
      longitude: point.longitude,
      limit: 30,
    );
    final c = await appController.api.campaigns();
    if (!mounted) return;
    if (f.ok || o.ok || c.ok) {
      final next = {
        'flash': f.ok ? f.dataMaps : flash,
        'offers': o.ok ? o.dataMaps : offers,
        'campaigns': c.ok ? c.dataMap : campaigns,
      };
      await appController.cachePublicSnapshot('offers_page', next);
      setState(() {
        flash = J.maps(next['flash']);
        offers = J.maps(next['offers']);
        campaigns = J.map(next['campaigns']);
        loading = false;
        _servedFromCache = false;
      });
    } else if (mounted) {
      setState(() => loading = flash.isEmpty && offers.isEmpty);
    }
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
      appBar: AppBar(
        title: Text(app.t('offers')),
        actions: [
          ListenableBuilder(
            listenable: appController,
            builder: (_, _) => IconButton(
              onPressed: () => context.push('/cart'),
              icon: Badge(
                isLabelVisible: appController.cartCount > 0,
                backgroundColor: AppTheme.accentOrange,
                label: Text(
                  '${appController.cartCount}',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              tooltip: appController.t('cart'),
            ),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                OfflineBanner(stale: _servedFromCache),
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
                      onTap: () =>
                          context.push('/sellers?type=${item['category_id']}'),
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
                  LayoutBuilder(
                    builder: (ctx, c) {
                      final count = c.maxWidth >= 900
                          ? 4
                          : c.maxWidth >= 600
                          ? 3
                          : 2;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: count,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: count > 2 ? 0.6 : 0.55,
                        ),
                        itemCount: products.length,
                        itemBuilder: (_, i) => ProductCard(
                          product: products[i],
                          onTap: () => context.push(
                            '/product/${products[i]['slug'] ?? products[i]['id']}',
                          ),
                          onAdd: () =>
                              addProductFromCatalog(context, products[i]),
                        ),
                      );
                    },
                  ),
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

  bool _servedFromCache = false;

  /// False when the last search never reached the server (offline). Used to
  /// distinguish "no results" from "not synchronized yet".
  bool _lastSearchOk = true;

  /// Generation counter: rapid successive submits must never let an older
  /// query's late response overwrite the latest query's results.
  int _seq = 0;

  Future<void> _search(String q) async {
    final mySeq = ++_seq;
    if (q.trim().isEmpty) {
      setState(() {
        items = [];
        searched = false;
      });
      return;
    }
    setState(() => loading = true);
    // Local FTS first: instant offline results over synchronized rows.
    final local = await appController.catalogProductsLocal(
      search: q.trim(),
      limit: 20,
    );
    if (local.isNotEmpty && mounted && mySeq == _seq) {
      setState(() {
        items = local;
        searched = true;
        loading = false;
        _servedFromCache = true;
      });
    }
    final point = appController.browseCoords;
    final result = await appController.api.products(
      latitude: point.latitude,
      longitude: point.longitude,
      filters: {'search': q, 'limit': 20, 'offset': 0},
    );
    if (!mounted || mySeq != _seq) return;
    if (result.ok) {
      setState(() {
        items = result.dataMaps;
        searched = true;
        loading = false;
        _servedFromCache = false;
        _lastSearchOk = true;
      });
      await appController.addRecentSearch(q);
    } else if (local.isEmpty) {
      // Offline with nothing synchronized: keep the "not synced" state.
      setState(() {
        items = [];
        searched = true;
        loading = false;
        _servedFromCache = false;
        _lastSearchOk = false;
      });
    } else {
      setState(() => _lastSearchOk = false);
    }
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
          ? _RecentSearches(onTap: _search)
          : items.isEmpty
          ? EmptyState(
              message: app.t(
                _lastSearchOk ? 'no_search_results' : 'not_synced_yet',
              ),
              actionLabel: app.t('retry'),
              onAction: () => _search(controller.text),
            )
          : ListView(
              children: [
                OfflineBanner(stale: _servedFromCache),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${items.length} • ${app.t('search')}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
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
                    onTap: () =>
                        context.push('/product/${item['slug'] ?? item['id']}'),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Recent searches (local, non-sensitive) shown before the first search.
class _RecentSearches extends StatelessWidget {
  const _RecentSearches({required this.onTap});

  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final recent = app.recentSearches();
    if (recent.isEmpty) {
      return EmptyState(icon: Icons.search, message: app.t('search'));
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            app.t('recent_searches'),
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
        ...recent.map(
          (q) => ListTile(
            leading: const Icon(Icons.history),
            title: Text(q),
            onTap: () => onTap(q),
          ),
        ),
      ],
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

  bool _servedFromCache = false;

  Future<void> _load() async {
    // Local-first: last CMS snapshot paints offline with a stale badge.
    final snap = appController.readPublicSnapshot('cms_${widget.settingKey}');
    if (snap is String && snap.trim().isNotEmpty && mounted) {
      setState(() {
        html = snap;
        loading = false;
        _servedFromCache = true;
      });
    } else {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final content = await appController.cmsHtml(widget.settingKey);
      if (!mounted) return;
      if (content.trim().isNotEmpty) {
        await appController.cachePublicSnapshot(
          'cms_${widget.settingKey}',
          content,
        );
      }
      setState(() {
        html = content;
        loading = false;
        _servedFromCache = false;
        if (content.trim().isEmpty) {
          error = html.trim().isNotEmpty
              ? null
              : appController.t('no_content_yet');
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        _servedFromCache = html.isNotEmpty;
        if (html.isEmpty) error = appController.t('not_synced_yet');
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OfflineBanner(stale: _servedFromCache),
                  HtmlText(html),
                ],
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
    if (app.cities.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          app.t('no_content_yet'),
          textAlign: TextAlign.center,
        ),
      );
    }
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
