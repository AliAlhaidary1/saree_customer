import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/app_theme.dart';
import '../core/json_util.dart';
import '../core/promo_price.dart';

/// Shared filter state (web parity with ProductList.jsx Filter + quick chips).
/// No brands: SHOW_BRANDS=false on the web, so brands are excluded everywhere.
class ProductFilterValue {
  ProductFilterValue({
    this.sort = '',
    this.categoryId,
    this.priceMin = '',
    this.priceMax = '',
    this.minRating = '',
    this.inStock = false,
    this.onlyOffers = false,
    this.canDeliver = false,
    this.isReturnable = false,
  });

  String sort;
  String? categoryId;
  String priceMin;
  String priceMax;
  String minRating;
  bool inStock;
  bool onlyOffers;
  bool canDeliver;
  bool isReturnable;

  ProductFilterValue copy() => ProductFilterValue(
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

  bool get isEmpty =>
      sort.isEmpty &&
      (categoryId == null || categoryId!.isEmpty) &&
      priceMin.isEmpty &&
      priceMax.isEmpty &&
      minRating.isEmpty &&
      !inStock &&
      !onlyOffers &&
      !canDeliver &&
      !isReturnable;

  Map<String, String> toQuery() => {
        if (sort.isNotEmpty) 'sort': sort,
        if (categoryId != null && categoryId!.isNotEmpty)
          'category': categoryId!,
        if (priceMin.isNotEmpty) 'price_min': priceMin,
        if (priceMax.isNotEmpty) 'price_max': priceMax,
        if (minRating.isNotEmpty) 'rating': minRating,
        if (inStock) 'in_stock': '1',
        if (onlyOffers) 'offer': '1',
        if (canDeliver) 'deliver': '1',
        if (isReturnable) 'returnable': '1',
      };
}

/// Opens the filter as a bottom sheet: grouped cards, pill chips with a
/// checkmark, a dual-thumb price slider, clickable stars and switch rows.
Future<void> showProductFilterSheet(
  BuildContext context, {
  required ProductFilterValue initial,
  required List<Map<String, dynamic>> categories,
  required ValueChanged<ProductFilterValue> onApply,
  double priceMinBound = 0,
  double priceMaxBound = 1000,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ProductFilterSheet(
      initial: initial,
      categories: categories,
      onApply: onApply,
      priceMinBound: priceMinBound,
      priceMaxBound: priceMaxBound,
    ),
  );
}

class ProductFilterSheet extends StatefulWidget {
  const ProductFilterSheet({
    super.key,
    required this.initial,
    required this.categories,
    required this.onApply,
    this.priceMinBound = 0,
    this.priceMaxBound = 1000,
  });

  final ProductFilterValue initial;
  final List<Map<String, dynamic>> categories;
  final ValueChanged<ProductFilterValue> onApply;
  final double priceMinBound;
  final double priceMaxBound;

  @override
  State<ProductFilterSheet> createState() => _ProductFilterSheetState();
}

class _ProductFilterSheetState extends State<ProductFilterSheet> {
  static const _sheetGrey = Color(0xFFF6F7F9);

  late ProductFilterValue f;
  late double _lo;
  late double _hi;
  late RangeValues _range;

  double get _minBound => widget.priceMinBound;
  double get _maxBound =>
      widget.priceMaxBound > widget.priceMinBound + 1
          ? widget.priceMaxBound
          : widget.priceMinBound + 100;

  @override
  void initState() {
    super.initState();
    f = widget.initial.copy();
    _lo = _minBound;
    _hi = _maxBound;
    final lo = double.tryParse(f.priceMin);
    final hi = double.tryParse(f.priceMax);
    _range = RangeValues(
      (lo != null && lo > _lo) ? lo.clamp(_lo, _hi) : _lo,
      (hi != null && hi < _hi) ? hi.clamp(_lo, _hi) : _hi,
    );
  }

  int? get _divisions {
    final span = _hi - _lo;
    if (span <= 0) return null;
    final step = span >= 1000
        ? 100
        : span >= 200
            ? 20
            : span >= 50
                ? 5
                : 1;
    final d = (span / step).round();
    return d < 1 ? null : d;
  }

  String _catName(Map<String, dynamic> cat) {
    final isAr = appController.i18n.code == 'ar';
    final ar = J.str(cat['name_ar']);
    final en = J.str(cat['name_en'] ?? cat['name']);
    return isAr ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
  }

  int get _activeCount => [
        _range.start > _lo + 0.5 || _range.end < _hi - 0.5,
        f.categoryId?.isNotEmpty == true,
        f.minRating.isNotEmpty,
        f.inStock,
        f.onlyOffers,
        f.canDeliver,
        f.isReturnable,
      ].where((e) => e).length + (f.sort.isEmpty ? 0 : 1);

  void _clearAll() {
    setState(() {
      f = ProductFilterValue();
      _range = RangeValues(_lo, _hi);
    });
    // Apply immediately: clearing is final even when the sheet is dismissed
    // without tapping "show results", so the list returns to the default
    // state instead of keeping the previous filter. A copy is passed because
    // the sheet keeps mutating [f] while it stays open.
    widget.onApply(f.copy());
  }

  void _apply() {
    f.priceMin =
        _range.start <= _lo + 0.5 ? '' : _range.start.toStringAsFixed(0);
    f.priceMax =
        _range.end >= _hi - 0.5 ? '' : _range.end.toStringAsFixed(0);
    widget.onApply(f);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = appController.t;
    final count = _activeCount;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.backgroundWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.primaryNavy.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.tune,
                    size: 18,
                    color: AppTheme.accentOrange,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t('filters'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accentOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accentOrange,
                      ),
                    ),
                  ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppTheme.primaryNavy.withValues(alpha: 0.08)),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              children: [
                _card(
                  icon: Icons.swap_vert_rounded,
                  title: t('sort_by').trim(),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(
                        t('best_for_you'),
                        f.sort.isEmpty,
                        () => setState(() => f.sort = ''),
                      ),
                      _chip(
                        t('sort_by_nearest'),
                        f.sort == 'nearest',
                        () => setState(() => f.sort = _toggle('nearest')),
                      ),
                      _chip(
                        t('sort_newest'),
                        f.sort == 'new',
                        () => setState(() => f.sort = _toggle('new')),
                      ),
                      _chip(
                        t('sort_cheapest'),
                        f.sort == 'low',
                        () => setState(() => f.sort = _toggle('low')),
                      ),
                      _chip(
                        t('sort_priciest'),
                        f.sort == 'high',
                        () => setState(() => f.sort = _toggle('high')),
                      ),
                    ],
                  ),
                ),
                if (widget.categories.isNotEmpty)
                  _card(
                    icon: Icons.grid_view_rounded,
                    title: t('categories').trim(),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(
                          t('all_items'),
                          f.categoryId == null || f.categoryId!.isEmpty,
                          () => setState(() => f.categoryId = null),
                        ),
                        for (final c in widget.categories)
                          _chip(
                            _catName(c),
                            '${c['id']}' == '${f.categoryId}',
                            () => setState(
                              () => f.categoryId =
                                  '${c['id']}' == '${f.categoryId}'
                                      ? null
                                      : '${c['id']}',
                            ),
                          ),
                      ],
                    ),
                  ),
                _card(
                  icon: Icons.payments_outlined,
                  title: t('priceRange').trim(),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _priceBubble(_range.start, true)),
                          const SizedBox(width: 10),
                          Expanded(child: _priceBubble(_range.end, false)),
                        ],
                      ),
                      RangeSlider(
                        values: _range,
                        min: _lo,
                        max: _hi,
                        divisions: _divisions,
                        activeColor: AppTheme.accentOrange,
                        inactiveColor:
                            AppTheme.primaryNavy.withValues(alpha: 0.10),
                        labels: RangeLabels(
                          _money(_range.start),
                          _money(_range.end),
                        ),
                        onChanged: (v) => setState(() => _range = v),
                      ),
                    ],
                  ),
                ),
                _card(
                  icon: Icons.star_rounded,
                  title: t('filter_store_rating'),
                  child: Row(
                    children: [
                      for (var i = 1; i <= 5; i++)
                        InkWell(
                          onTap: () {
                            final cur = int.tryParse(f.minRating) ?? 0;
                            setState(
                              () => f.minRating = cur == i ? '' : '$i',
                            );
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 2, right: 2),
                            child: Icon(
                              i <= (int.tryParse(f.minRating) ?? 0)
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color:
                                  i <= (int.tryParse(f.minRating) ?? 0)
                                      ? const Color(0xFFF4CD32)
                                      : const Color(0xFFD0D0D0),
                              size: 30,
                            ),
                          ),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          f.minRating.isNotEmpty
                              ? t('filter_stars_and_up')
                                  .replaceAll('{{count}}', f.minRating)
                              : t('filter_choose_stars'),
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _card(
                  icon: Icons.bolt_rounded,
                  title: t('more_options'),
                  child: Column(
                    children: [
                      _switchRow(
                        t('offers'),
                        f.onlyOffers,
                        (v) => setState(() => f.onlyOffers = v),
                      ),
                      _switchRow(
                        t('returnable_only'),
                        f.isReturnable,
                        (v) => setState(() => f.isReturnable = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              color: AppTheme.backgroundWhite,
              border: Border(
                top: BorderSide(
                  color: AppTheme.primaryNavy.withValues(alpha: 0.08),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _clearAll,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.textSecondary,
                          side: BorderSide(
                            color: AppTheme.primaryNavy.withValues(alpha: 0.15),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          t('clear_all'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _apply,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accentOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          count > 0
                              ? '${t('show_results')} · $count'
                              : t('show_results'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _toggle(String v) => f.sort == v ? '' : v;

  String _money(double v) => money(v, appController.currency, 0);

  Widget _card({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: _sheetGrey,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppTheme.backgroundWhite,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.accentOrange.withValues(alpha: 0.25),
                  ),
                ),
                child: Icon(icon, size: 14, color: AppTheme.accentOrange),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
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
                  child: Icon(Icons.check_rounded, size: 15, color: Colors.white),
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

  Widget _priceBubble(double value, bool isMin) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.backgroundWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.accentOrange.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            isMin
                ? appController.t('price_from').trim()
                : appController.t('price_to').trim(),
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _money(value),
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.accentOrange,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
      decoration: BoxDecoration(
        color: AppTheme.backgroundWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? AppTheme.accentOrange.withValues(alpha: 0.40)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: value ? FontWeight.w800 : FontWeight.w600,
                color: value ? AppTheme.textPrimary : AppTheme.textSecondary,
              ),
            ),
          ),
          Switch(
            value: value,
            activeTrackColor: AppTheme.accentOrange,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
