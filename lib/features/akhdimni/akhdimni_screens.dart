import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/akhdimni_status.dart';
import '../../core/app_controller.dart';
import '../../core/app_theme.dart';
import '../../core/json_util.dart';
import '../../core/promo_price.dart';
import '../../widgets/app_image.dart';
import '../../widgets/ui_helpers.dart';

bool _isOn(dynamic v) => v == 1 || v == '1' || v == true;

bool _catActive(Map<String, dynamic> c) {
  final v = c['is_active'];
  return v == 1 || v == true || v == '1';
}

String _catName(Map<String, dynamic> c, bool isAr) {
  final ar = J.str(c['name_ar']);
  final en = J.str(c['name_en']);
  return isAr ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
}

String _catDesc(Map<String, dynamic> c, bool isAr) {
  final ar = J.str(c['description_ar']);
  final en = J.str(c['description_en']);
  return isAr ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
}

String _humanAddress(String raw) {
  if (raw.isEmpty) return '';
  final parts = raw.split(RegExp(r'[,،]')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  final seen = <String>{};
  final kept = <String>[];
  for (final p in parts) {
    if (RegExp(r'^[A-Z0-9]{4,}\+[A-Z0-9]{2,}$', caseSensitive: false).hasMatch(p)) continue;
    if (RegExp(r'^\d{4,}$').hasMatch(p)) continue;
    final k = p.toLowerCase();
    if (seen.contains(k)) continue;
    seen.add(k);
    kept.add(p);
  }
  return kept.join('، ');
}

String _formatAddressLine(Map<String, dynamic> addr) {
  return [
    J.str(addr['address']),
    J.str(addr['landmark']),
    J.str(addr['area']),
    J.str(addr['city']),
    J.str(addr['state']),
    J.str(addr['pincode']),
  ].where((p) => p.isNotEmpty).join('، ');
}

// ───────────────────────── Home ─────────────────────────

class AkhdimniHomeScreen extends StatefulWidget {
  const AkhdimniHomeScreen({super.key});

  @override
  State<AkhdimniHomeScreen> createState() => _AkhdimniHomeScreenState();
}

class _AkhdimniHomeScreenState extends State<AkhdimniHomeScreen> {
  bool loading = true;
  bool enabled = false;
  List<Map<String, dynamic>> categories = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = appController;
    try {
      List<Map<String, dynamic>> cats = [];
      try {
        final catRes = await app.api.akhdimniCategories();
        if (catRes.ok) cats = catRes.dataMaps;
      } catch (_) {}
      bool en = app.akhdimniEnabled;
      try {
        final cfgRes = await app.api.akhdimniConfig();
        if (cfgRes.ok) {
          final data = J.map(cfgRes.dataMap['data']);
          final raw = data.isNotEmpty ? data : cfgRes.dataMap;
          if (raw['akhdimni_enabled'] != null) {
            en = _isOn(raw['akhdimni_enabled']);
          }
          final cfgCats = J.maps(raw['categories']);
          if (cats.isEmpty && cfgCats.isNotEmpty) cats = cfgCats;
        }
      } catch (_) {}
      cats = cats.where(_catActive).toList()
        ..sort((a, b) {
          final sa = int.tryParse('${a['sort_order'] ?? 0}') ?? 0;
          final sb = int.tryParse('${b['sort_order'] ?? 0}') ?? 0;
          if (sa != sb) return sa.compareTo(sb);
          return '${a['id']}'.compareTo('${b['id']}');
        });
      if (!mounted) return;
      setState(() {
        categories = cats;
        enabled = en;
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          enabled = app.akhdimniEnabled;
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final isAr = app.i18n.code == 'ar';
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: Text(app.t('akhdimni'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!enabled) {
      return Scaffold(
        appBar: AppBar(title: Text(app.t('akhdimni'))),
        body: Center(child: Text(app.t('akhdimni_disabled'))),
      );
    }
    final steps = [
      (Icons.assignment_outlined, app.t('akhdimni_step_request'), app.t('akhdimni_step_request_hint')),
      (Icons.inventory_2_outlined, app.t('akhdimni_step_prepare'), app.t('akhdimni_step_prepare_hint')),
      (Icons.local_shipping_outlined, app.t('akhdimni_step_delivered'), app.t('akhdimni_step_delivered_hint')),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(app.t('akhdimni'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: AppTheme.primaryNavy,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.bolt, color: Colors.amber),
                        const SizedBox(width: 6),
                        Text(app.t('akhdimni'),
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(app.t('akhdimni_what_do_you_need'),
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(app.t('akhdimni_home_hint'),
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: categories.isEmpty
                              ? null
                              : () => context.push('/akhdimni/create?category_id=${categories.first['id']}'),
                          child: Text(app.t('akhdimni_order_now')),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => context.push('/akhdimni/orders'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                          child: Text(app.t('akhdimni_my_orders')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('${categories.length} ${app.t('store_types')}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(width: 12),
                        Text('✓ ${app.t('akhdimni_fulfillment_on_us')}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (categories.isEmpty)
              EmptyState(message: app.t('no_categories'))
            else ...[
              Text(app.t('akhdimni_choose_service'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text(app.t('akhdimni_choose_service_hint'),
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 10),
              ...categories.map((cat) {
                final name = _catName(cat, isAr);
                final desc = _catDesc(cat, isAr);
                final img = J.str(cat['image_url']);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => context.push('/akhdimni/create?category_id=${cat['id']}'),
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadiusDirectional.only(
                            topStart: Radius.circular(12),
                            bottomStart: Radius.circular(12),
                          ),
                          child: SizedBox(
                            width: 96,
                            height: 96,
                            child: AppImage(img.isNotEmpty ? img : null, placeholder: app.placeholder),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                if (desc.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  ),
                                const SizedBox(height: 6),
                                Text(app.t('akhdimni_order_btn'),
                                    style: TextStyle(color: app.accentColor, fontWeight: FontWeight.w700, fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                for (var i = 0; i < steps.length; i++)
                  Expanded(
                    child: Card(
                      margin: EdgeInsetsDirectional.only(end: i < 2 ? 8 : 0),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                        child: Column(
                          children: [
                            Icon(steps[i].$1, color: app.accentColor),
                            const SizedBox(height: 6),
                            Text(steps[i].$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            Text(steps[i].$3,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(app.t('akhdimni_home_footer'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Create ─────────────────────────

class AkhdimniCreateScreen extends StatefulWidget {
  const AkhdimniCreateScreen({super.key, this.categoryId, this.type});
  final String? categoryId;
  final String? type;

  @override
  State<AkhdimniCreateScreen> createState() => _AkhdimniCreateScreenState();
}

class _AkhdimniCreateScreenState extends State<AkhdimniCreateScreen> {
  final description = TextEditingController();
  final dropoffName = TextEditingController();
  final dropoffMobile = TextEditingController();
  List<XFile> images = [];
  List<Map<String, dynamic>> categories = [];
  Map<String, dynamic>? activeCategory;
  String? dropoffLat;
  String? dropoffLng;
  String? pickupLat;
  String? pickupLng;
  String? cityId;
  bool prefillDone = false;

  Map<String, dynamic>? pricePreview;
  bool previewLoading = false;
  bool submitting = false;
  Timer? _previewTimer;

  bool get _isCategoryMode => widget.categoryId != null || activeCategory != null;

  bool get _showPickupSection {
    final cat = activeCategory;
    if (cat == null) return widget.type == 'point_to_point';
    return _isOn(cat['pickup_enabled']);
  }

  bool get _isManualReviewCategory {
    final cat = activeCategory;
    if (cat == null) return false;
    return _isOn(cat['requires_manual_review']) ||
        cat['code'] == 'custom_service' ||
        cat['code'] == 'other';
  }

  bool get _hasDropoff => dropoffLat != null && dropoffLng != null;

  bool get _hasPickup => pickupLat != null && pickupLng != null;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    if (appController.isLoggedIn) {
      appController.loadAddresses().then((_) {
        if (mounted) _prefillDropoff();
      });
    }
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    description.dispose();
    dropoffName.dispose();
    dropoffMobile.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final res = await appController.api.akhdimniCategories();
      if (!mounted || !res.ok) return;
      final cats = res.dataMaps.where(_catActive).toList();
      setState(() {
        categories = cats;
        if (widget.categoryId != null) {
          for (final c in cats) {
            if ('${c['id']}' == widget.categoryId) activeCategory = c;
          }
        } else if (cats.isNotEmpty && _isCategoryMode) {
          activeCategory = cats.first;
        }
      });
    } catch (_) {}
  }

  void _prefillDropoff() {
    if (prefillDone) return;
    final app = appController;
    final user = app.user;
    Map<String, dynamic>? addr = app.selectedAddress;
    addr ??= _defaultAddress(app.addresses);
    prefillDone = true;
    setState(() {
      if (addr != null) {
        _applySavedDropoff(addr);
      } else {
        dropoffName.text = J.str(user?['name']);
        dropoffMobile.text = J.str(user?['mobile']);
      }
    });
  }

  Map<String, dynamic>? _defaultAddress(List<Map<String, dynamic>> list) {
    if (list.isEmpty) return null;
    for (final a in list) {
      if (J.str(a['is_default']) == '1') return a;
    }
    return list.first;
  }

  void _applySavedDropoff(Map<String, dynamic> addr) {
    final app = appController;
    setState(() {
      dropoffName.text = J.str(addr['name']).isNotEmpty
          ? J.str(addr['name'])
          : J.str(app.user?['name']);
      dropoffMobile.text = J.str(addr['mobile']).isNotEmpty
          ? J.str(addr['mobile'])
          : J.str(app.user?['mobile']);
      dropoffLat = J.str(addr['latitude']);
      dropoffLng = J.str(addr['longitude']);
      cityId = J.str(addr['city_id']).isNotEmpty
          ? J.str(addr['city_id'])
          : J.str(app.city?['id']);
    });
    _schedulePreview();
  }

  void _applySavedPickup(Map<String, dynamic> addr) {
    setState(() {
      pickupLat = J.str(addr['latitude']);
      pickupLng = J.str(addr['longitude']);
    });
    _schedulePreview();
  }

  void _clearPickup() {
    setState(() {
      pickupLat = null;
      pickupLng = null;
    });
    _schedulePreview();
  }

  String _title() {
    final app = appController;
    final isAr = app.i18n.code == 'ar';
    final cat = activeCategory;
    if (cat != null) return _catName(cat, isAr);
    if (widget.type == 'special_items') return app.t('akhdimni_special_items');
    if (widget.type == 'point_to_point') return app.t('akhdimni_point_to_point');
    return app.t('akhdimni_what_do_you_need');
  }

  Map<String, dynamic> _estimateFields() {
    return {
      if (widget.categoryId != null) 'akhdimni_category_id': widget.categoryId,
      if (widget.categoryId == null && widget.type != null) 'type': widget.type,
      if (widget.categoryId == null && widget.type == null) 'type': 'special_items',
      'dropoff_latitude': dropoffLat,
      'dropoff_longitude': dropoffLng,
      if (cityId != null && cityId!.isNotEmpty) 'city_id': cityId,
      if (_hasPickup) 'pickup_latitude': pickupLat,
      if (_hasPickup) 'pickup_longitude': pickupLng,
    };
  }

  void _schedulePreview() {
    _previewTimer?.cancel();
    if (!_hasDropoff) {
      setState(() {
        pricePreview = null;
        previewLoading = false;
      });
      return;
    }
    setState(() => previewLoading = true);
    _previewTimer = Timer(const Duration(milliseconds: 900), () async {
      try {
        final result = await appController.api.akhdimniEstimate(_estimateFields());
        if (!mounted) return;
        setState(() {
          pricePreview = result.ok ? J.map(result.dataMap['data']) : null;
          if (pricePreview != null && pricePreview!.isEmpty) {
            pricePreview = J.map(result.dataMap);
          }
          previewLoading = false;
        });
      } catch (_) {
        if (mounted) {
          setState(() {
            pricePreview = null;
            previewLoading = false;
          });
        }
      }
    });
  }

  void _requireLogin() {
    final current = GoRouterState.of(context).uri.toString();
    context.push('/login?next=${Uri.encodeComponent(current)}');
  }

  Future<void> _submit() async {
    final app = appController;
    if (!app.isLoggedIn) {
      _requireLogin();
      return;
    }
    if (description.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(app.t('akhdimni_describe_required'))),
      );
      return;
    }
    if (!_hasDropoff) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(app.t('akhdimni_dropoff_location_required'))),
      );
      return;
    }
    final profileName =
        dropoffName.text.trim().isNotEmpty ? dropoffName.text.trim() : J.str(app.user?['name']);
    final profileMobile = dropoffMobile.text.trim().isNotEmpty
        ? dropoffMobile.text.trim()
        : J.str(app.user?['mobile']);
    if (profileName.isEmpty || profileMobile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(app.t('akhdimni_profile_contact_required'))),
      );
      return;
    }
    setState(() => submitting = true);
    try {
      final dropAddr = _selectedDropoffAddress();
      final fields = <String, dynamic>{
        if (widget.categoryId != null) 'akhdimni_category_id': widget.categoryId,
        if (widget.type != null) 'type': widget.type,
        'description': description.text.trim(),
        'customer_description': description.text.trim(),
        'special_items_text': description.text.trim(),
        'item_description': description.text.trim(),
        'dropoff_name': profileName,
        'dropoff_mobile': profileMobile,
        'dropoff_address': dropAddr,
        'dropoff_latitude': dropoffLat,
        'dropoff_longitude': dropoffLng,
        'payment_method': 'COD',
        if (cityId != null && cityId!.isNotEmpty) 'city_id': cityId,
        if (_hasPickup) 'pickup_latitude': pickupLat,
        if (_hasPickup) 'pickup_longitude': pickupLng,
        if (_hasPickup) 'pickup_name': profileName,
        if (_hasPickup) 'pickup_mobile': profileMobile,
      };
      final result = await app.api.akhdimniPlace(fields, images: images.isEmpty ? null : images);
      if (!mounted) return;
      if (result.ok) {
        final data = J.map(result.dataMap['data']);
        final id = J.str(data['id']).isNotEmpty ? J.str(data['id']) : J.str(result.dataMap['id']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message.isNotEmpty ? result.message : app.t('akhdimni_order_created'))),
        );
        if (id.isNotEmpty) {
          context.go('/akhdimni/orders/$id');
        } else {
          context.go('/akhdimni/orders');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message.isNotEmpty ? result.message : app.t('something_went_wrong'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(app.t('something_went_wrong'))),
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  String _selectedDropoffAddress() {
    for (final a in appController.addresses) {
      if (J.str(a['latitude']) == dropoffLat && J.str(a['longitude']) == dropoffLng) {
        final line = _formatAddressLine(a);
        if (line.isNotEmpty) return line;
      }
    }
    return J.str(appController.selectedAddress?['address']);
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final isAr = app.i18n.code == 'ar';
    final typeDisabled = (widget.type == 'point_to_point' && !app.akhdimniPointToPointEnabled) ||
        (widget.type == 'special_items' && !app.akhdimniSpecialItemsEnabled);
    final cat = activeCategory;
    final subtitle = cat == null ? '' : _catDesc(cat, isAr);
    if (typeDisabled) {
      return Scaffold(
        appBar: AppBar(title: Text(_title())),
        body: Center(child: Text(app.t('akhdimni_type_disabled'))),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_title())),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              if (subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ),
              // 1 — order details
              _card(
                num: '1',
                title: app.t('akhdimni_order_details'),
                hint: app.t('akhdimni_order_details_hint'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_isCategoryMode && widget.type == null && categories.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: null,
                        decoration: InputDecoration(labelText: app.t('akhdimni_select_category')),
                        items: [
                          DropdownMenuItem(value: '', child: Text(app.t('akhdimni_choose_option'))),
                          ...categories.map((c) => DropdownMenuItem(
                                value: '${c['id']}',
                                child: Text(_catName(c, isAr)),
                              )),
                        ],
                        onChanged: (v) {
                          if (v != null && v.isNotEmpty) {
                            context.push('/akhdimni/create?category_id=$v');
                          }
                        },
                      ),
                    TextField(
                      controller: description,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: '${app.t('akhdimni_what_do_you_need')} *',
                        hintText: app.t('akhdimni_what_need_placeholder'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(app.t('akhdimni_what_need_hint'),
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () async {
                        final picked = await ImagePicker().pickMultiImage();
                        if (picked.isNotEmpty && mounted) {
                          setState(() => images = picked);
                        }
                      },
                      icon: const Icon(Icons.image),
                      label: Text(images.isEmpty
                          ? '${app.t('images')} (${app.t('optional')}) — ${app.t('akhdimni_add_photos')}'
                          : '${images.length} ✓'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 2 — locations
              _card(
                num: '2',
                title: app.t('akhdimni_locations'),
                hint: app.t('akhdimni_locations_hint'),
                done: _hasDropoff,
                child: ListenableBuilder(
                  listenable: app,
                  builder: (_, __) {
                    final saved = app.addresses;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${app.t('akhdimni_dropoff_label')} *',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (saved.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(app.t('no_address_yet')),
                                TextButton(
                                  onPressed: () => context.push('/addresses'),
                                  child: Text(app.t('manage_address')),
                                ),
                              ],
                            ),
                          )
                        else
                          ...saved.map((addr) {
                            final selected = J.str(addr['latitude']) == dropoffLat &&
                                J.str(addr['longitude']) == dropoffLng;
                            return RadioListTile<bool>(
                              value: true,
                              groupValue: selected ? true : null,
                              onChanged: (_) => _applySavedDropoff(addr),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(J.str(addr['name']).isNotEmpty
                                        ? J.str(addr['name'])
                                        : app.t('akhdimni_saved_address')),
                                  ),
                                  if (J.str(addr['is_default']) == '1')
                                    Text(app.t('default_address_badge'),
                                        style: TextStyle(color: app.accentColor, fontSize: 11)),
                                ],
                              ),
                              subtitle: Text(_humanAddress(_formatAddressLine(addr))),
                            );
                          }),
                        if (_showPickupSection) ...[
                          const SizedBox(height: 8),
                          Text(app.t('akhdimni_pickup_optional'),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          RadioListTile<bool>(
                            value: true,
                            groupValue: !_hasPickup ? true : null,
                            onChanged: (_) => _clearPickup(),
                            title: Text(app.t('akhdimni_no_pickup')),
                            subtitle: Text(app.t('akhdimni_no_pickup_hint')),
                          ),
                          ...saved.map((addr) {
                            final selected = _hasPickup &&
                                J.str(addr['latitude']) == pickupLat &&
                                J.str(addr['longitude']) == pickupLng;
                            return RadioListTile<bool>(
                              value: true,
                              groupValue: selected ? true : null,
                              onChanged: (_) => _applySavedPickup(addr),
                              title: Text(J.str(addr['name']).isNotEmpty
                                  ? J.str(addr['name'])
                                  : app.t('akhdimni_saved_address')),
                              subtitle: Text(_humanAddress(_formatAddressLine(addr))),
                            );
                          }),
                        ],
                        if (!_hasDropoff)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(app.t('akhdimni_select_dropoff_first'),
                                style: const TextStyle(color: Colors.red, fontSize: 12)),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              // 3 — pricing & review
              _card(
                num: '3',
                title: app.t('akhdimni_pricing_review'),
                hint: app.t('akhdimni_pricing_review_hint'),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(app.t('akhdimni_delivery_may_change'))),
                      ],
                    ),
                    if (_isManualReviewCategory) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(app.t('akhdimni_manual_price_note'))),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (submitting)
            Container(
              color: Colors.black45,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(32),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(app.t('akhdimni_submitting'),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(app.t('akhdimni_submitting_wait'),
                            style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (previewLoading && pricePreview == null)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: LinearProgressIndicator(),
                    ),
                  if (previewLoading && pricePreview == null)
                    Text(app.t('akhdimni_calculating_fee'),
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  if (pricePreview != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(app.t('akhdimni_delivery_fee')),
                        Text(
                          money(
                            pricePreview!['delivery_charge'] ??
                                pricePreview!['estimated_delivery_charge'],
                            app.currency,
                            app.decimals,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    if (pricePreview!['initial_service_fee'] != null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(app.t('akhdimni_service_fee')),
                          Text(
                            money(pricePreview!['initial_service_fee'], app.currency, app.decimals),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    if (pricePreview!['estimated_total'] != null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(app.t('akhdimni_estimated_total'),
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(
                            money(pricePreview!['estimated_total'], app.currency, app.decimals),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    Text(app.t('akhdimni_initial_price_note'),
                        style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(app.t('akhdimni_submit_agree_note'),
                            style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: submitting ? null : _submit,
                    child: submitting
                        ? const BusySpinner()
                        : Text(app.t('akhdimni_place_order')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required String num,
    required String title,
    required String hint,
    required Widget child,
    bool done = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: appController.accentColor,
                  child: Text(num,
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(hint,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                if (done)
                  const Icon(Icons.check_circle,
                      color: Colors.green, size: 20),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Orders ─────────────────────────

class AkhdimniOrdersScreen extends StatefulWidget {
  const AkhdimniOrdersScreen({super.key});

  @override
  State<AkhdimniOrdersScreen> createState() => _AkhdimniOrdersScreenState();
}

class _AkhdimniOrdersScreenState extends State<AkhdimniOrdersScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!appController.isLoggedIn) {
      if (mounted) setState(() => loading = false);
      return;
    }
    if (mounted) setState(() => error = null);
    try {
      final res = await appController.api
          .akhdimniOrders({})
          .timeout(const Duration(seconds: 25));
      if (!mounted) return;
      setState(() {
        items = res.dataMaps;
        if (!res.ok && items.isEmpty) {
          error = res.message.isNotEmpty
              ? res.message
              : appController.t('something_went_wrong');
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => error = appController.t('something_went_wrong'));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return Scaffold(
      appBar: AppBar(title: Text(app.t('akhdimni_my_orders'))),
      body: !app.isLoggedIn
          ? const LoginRequired()
          : loading && items.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : error != null && items.isEmpty
                  ? EmptyState(
                      message: error!,
                      icon: Icons.cloud_off_outlined,
                      actionLabel: app.t('retry'),
                      onAction: _load,
                    )
                  : items.isEmpty
                      ? EmptyState(
                          message: app.t('akhdimni_no_orders'),
                          actionLabel: app.t('akhdimni_order_now'),
                          onAction: () => context.push('/akhdimni'),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            children: items
                                .map(
                                  (item) => ListTile(
                                    title: Text(
                                        '#${item['id']} · ${akhdimniStatusLabel(J.str(item['active_status']))}'),
                                    subtitle: Text(_orderSubtitle(item)),
                                    trailing: Text(
                                      money(
                                        item['final_total'],
                                        app.currency,
                                        app.decimals,
                                      ),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                    onTap: () => context.push(
                                        '/akhdimni/orders/${item['id']}'),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
    );
  }

  String _orderSubtitle(Map<String, dynamic> item) {
    final cat = J.map(item['akhdimni_category']);
    if (cat.isNotEmpty) {
      return _catName(cat, appController.i18n.code == 'ar');
    }
    return J.str(item['type']);
  }
}

// ───────────────────────── Order details ─────────────────────────

class AkhdimniOrderDetailsScreen extends StatefulWidget {
  const AkhdimniOrderDetailsScreen({super.key, required this.id});
  final String id;

  @override
  State<AkhdimniOrderDetailsScreen> createState() =>
      _AkhdimniOrderDetailsScreenState();
}

class _AkhdimniOrderDetailsScreenState
    extends State<AkhdimniOrderDetailsScreen> {
  Map<String, dynamic> order = {};
  bool loading = true;
  bool cancelling = false;
  bool downloading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await appController.api.akhdimniOrder(widget.id);
      if (!mounted) return;
      setState(() {
        order = res.dataMap.isNotEmpty
            ? res.dataMap
            : J.map(res.raw['data'] ?? res.raw);
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _cancel() async {
    final app = appController;
    final ok = await confirmAction(
      context,
      title: app.t('akhdimni_cancel_request'),
      body: akhdimniStatusLabel(J.str(order['active_status'])),
    );
    if (!ok || !mounted) return;
    setState(() => cancelling = true);
    try {
      final res = await app.api.akhdimniCancel(
        widget.id,
        {'cancel_reason': 'cancelled_by_customer'},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message.isNotEmpty
              ? res.message
              : app.t('akhdimni_order_cancelled')),
        ),
      );
      if (res.ok) {
        await _load();
        if (mounted) context.pop();
      }
    } finally {
      if (mounted) setState(() => cancelling = false);
    }
  }

  Future<void> _invoice() async {
    final app = appController;
    setState(() => downloading = true);
    try {
      final (ok, bytes, _) =
          await app.api.akhdimniInvoiceBytes(widget.id);
      if (!mounted) return;
      if (!ok || bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(app.t('something_went_wrong'))),
        );
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/Akhdimni-Invoice-${widget.id}.pdf');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${app.t('invoice_downloaded_successfully')}: ${file.path}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(app.t('something_went_wrong'))),
      );
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    final isAr = app.i18n.code == 'ar';
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: Text('${app.t('akhdimni')} #${widget.id}')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (order.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('${app.t('akhdimni')} #${widget.id}')),
        body: EmptyState(
          message: app.t('something_went_wrong'),
          actionLabel: app.t('retry'),
          onAction: () {
            setState(() => loading = true);
            _load();
          },
        ),
      );
    }
    final o = order;
    final status = J.str(o['active_status']);
    final canCancel = akhdimniCancellableStatuses.contains(status);
    final cat = J.map(o['akhdimni_category']);
    final catName = cat.isNotEmpty ? _catName(cat, isAr) : '';
    final desc = _firstNonEmpty([
      o['customer_description'],
      o['description'],
      o['special_items_text'],
      o['item_description'],
    ]);
    final stepIndex = akhdimniStepIndex(status);
    final terminalFail = akhdimniIsTerminalFail(status);
    final stepLabels = [
      app.t('akhdimni_timeline_preparing'),
      app.t('akhdimni_timeline_onway'),
      app.t('akhdimni_timeline_delivered'),
    ];
    final orderImages = J.maps(o['images']);
    // فاتورة الأصناف المسعّرة من الموصل — نفس سكيمة الويب.
    final items = J.maps(o['purchase_items']);
    final purchaseTotal = _toDouble(o['purchase_amount']);
    final deliveryCharge = _toDouble(o['delivery_charge']);
    final grandTotal = _toDouble(o['final_total']);
    final courier = J.map(o['delivery_boy']);
    final canInvoice = items.isNotEmpty || status == 'delivered';

    return Scaffold(
      appBar: AppBar(
        title: Text('${app.t('akhdimni')} #${widget.id}'),
        actions: [
          if (canCancel)
            IconButton(
              icon: const Icon(Icons.cancel_outlined),
              tooltip: app.t('akhdimni_cancel_request'),
              onPressed: cancelling ? null : _cancel,
            ),
          if (canInvoice)
            IconButton(
              icon: downloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined),
              tooltip: app.t('get_invoice'),
              onPressed: downloading ? null : _invoice,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!terminalFail)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.t('akhdimni_order_progress'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var i = 0; i < 3; i++)
                          Expanded(
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: i < stepIndex
                                      ? Colors.green
                                      : (i == stepIndex
                                          ? app.accentColor
                                          : Colors.grey.shade300),
                                  child: Text(
                                    i < stepIndex ? '✓' : '${i + 1}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(stepLabels[i],
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: i == stepIndex
                                            ? FontWeight.w700
                                            : FontWeight.normal)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (catName.isNotEmpty)
            _row(app.t('category'), catName, app),
          if (desc.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.t('description'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(desc),
                  ],
                ),
              ),
            ),
          if (J.str(o['pickup_address']).isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.t('akhdimni_pickup'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('${J.str(o['pickup_name'])} — ${J.str(o['pickup_mobile'])}'),
                    Text(J.str(o['pickup_address'])),
                  ],
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.t('akhdimni_dropoff'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('${J.str(o['dropoff_name'])} — ${J.str(o['dropoff_mobile'])}'),
                  Text(J.str(o['dropoff_address'])),
                ],
              ),
            ),
          ),
          if (courier.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.t('delivery_boy'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(J.str(courier['name'])),
                    if (J.str(courier['mobile']).isNotEmpty)
                      Text(J.str(courier['mobile']),
                          style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
          // الفاتورة: أصناف الموصل + التوصيل — مثل طلبات المتاجر.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.t('akhdimni_price_breakdown'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 8),
                  if (items.isNotEmpty) ...[
                    Text(app.t('akhdimni_invoice_items'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 4),
                    ...items.map((it) {
                      final store = J.str(it['store_name']).isNotEmpty
                          ? J.str(it['store_name'])
                          : (it['seller'] is Map
                              ? J.str(it['seller']['store_name'])
                              : '');
                      final qty = _toDouble(it['quantity']);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(J.str(it['name']),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  if (store.isNotEmpty)
                                    Text('🏪 $store',
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 12)),
                                  Text(
                                    '${app.t('quantity')}: ${qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 1)} × ${money(it['unit_price'], app.currency, app.decimals)}',
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              money(it['total'], app.currency, app.decimals),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                    _priceRow(
                      app.t('akhdimni_purchase_total'),
                      money(purchaseTotal, app.currency, app.decimals),
                    ),
                  ] else if (purchaseTotal > 0)
                    _priceRow(
                      app.t('akhdimni_purchase_total'),
                      money(purchaseTotal, app.currency, app.decimals),
                    ),
                  _priceRow(
                    app.t('delivery_charge'),
                    money(deliveryCharge, app.currency, app.decimals),
                  ),
                  const Divider(),
                  _priceRow(
                    app.t('total'),
                    money(grandTotal, app.currency, app.decimals),
                    bold: true,
                  ),
                ],
              ),
            ),
          ),
          if (J.str(o['cancel_reason']).isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.t('akhdimni_rejected'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(J.str(o['cancel_reason'])),
                  ],
                ),
              ),
            ),
          if (orderImages.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.t('images'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 84,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: orderImages.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 8),
                        itemBuilder: (_, i) => ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 84,
                            child: AppImage(
                              J.str(orderImages[i]['image_url']),
                              placeholder: app.placeholder,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (canInvoice)
            FilledButton.icon(
              onPressed: downloading ? null : _invoice,
              icon: downloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: Text(app.t('get_invoice')),
            ),
          if (canInvoice) const SizedBox(height: 8),
          if (canCancel)
            OutlinedButton(
              onPressed: cancelling ? null : _cancel,
              child: cancelling
                  ? const BusySpinner()
                  : Text(app.t('cancel')),
            ),
          const SizedBox(height: 8),
          Center(
            child: Text(akhdimniStatusLabel(status),
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, AppController app) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(value, textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }

  String _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      final s = J.str(v);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }
}