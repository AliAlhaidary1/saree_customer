import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'city_mode.dart';
import 'business_hours.dart';
import 'checkout_models.dart';
import 'config.dart';
import 'i18n.dart';
import 'json_util.dart';
import 'api/customer_api.dart';
import 'brand/brand_config.dart';
import 'brand/brand_service.dart';

class AppController extends ChangeNotifier {
  AppController();

  late SharedPreferences _prefs;
  late CustomerApi api;
  final i18n = I18n();

  String apiUrl = AppConfig.defaultApiUrl;
  String? token;
  String? viewerKey;
  /// Device push token parity with front NotificationBootstrap (sreamart_fcm_token).
  /// Without firebase native config we keep a stable per-device token so the
  /// backend can still target this device; once firebase_messaging is added,
  /// overwrite this value with messaging.getToken().
  String fcmToken = '';
  Map<String, dynamic>? user;
  Map<String, dynamic> settings = {
    'web_settings': <String, dynamic>{},
    'firebase': <String, dynamic>{},
  };
  Map<String, dynamic> paymentSettings = {};
  List<Map<String, dynamic>> cities = [];
  List<Map<String, dynamic>> rootCategories = [];
  bool citiesLoaded = false;
  Map<String, dynamic>? city;
  Map<String, dynamic>? shop;
  List<Map<String, dynamic>> addresses = [];
  Map<String, dynamic>? selectedAddress;
  Map<String, dynamic>? cart;
  List<Map<String, dynamic>> cartProducts = [];
  double cartSubTotal = 0;
  List<Map<String, dynamic>> guestCart = [];
  double guestCartTotal = 0;
  Map<String, dynamic>? promoCode;
  List<dynamic> favoriteIds = [];
  bool bootstrapped = false;
  String? bootstrapError;
  bool busy = false;
  BrandConfig brand = BrandConfig.defaults;

  /// Variant unit labels captured at add time (e.g. variantId -> "1 كيلو").
  /// The server cart response often omits the unit type, so the label the
  /// user saw when adding is carried with the line instead.
  final Map<String, String> _variantLabels = {};

  /// Display label for a variant map ("1 كيلو"). Empty when unknown.
  /// [productName] guards against echoing the product name itself when the
  /// variant map carries no distinctive info.
  static String variantLabelOf(Map<String, dynamic>? v,
      [String productName = '']) {
    if (v == null) return '';
    final m = J.str(v['measurement']);
    final u = J.str(
      v['stock_unit_name'] ?? v['unit'] ?? v['unit_name'] ?? v['uom'],
    );
    var name = J.str(
      v['variant_name'] ?? v['variant_label'] ?? v['variant_title'],
    );
    if (name.isEmpty) {
      final vn = J.str(v['name'] ?? v['title']);
      if (vn.isNotEmpty && vn != productName) name = vn;
    }
    final parts = <String>[];
    for (final p in [m, u, name]) {
      if (p.isNotEmpty && !parts.contains(p)) parts.add(p);
    }
    return parts.join(' ');
  }

  String variantLabelFor(dynamic variantId) =>
      _variantLabels['$variantId'] ?? '';

  Future<void> rememberVariantLabel(dynamic variantId, String label) async {
    if (variantId == null || label.trim().isEmpty) return;
    _variantLabels['$variantId'] = label.trim();
    try {
      await _prefs.setString('variant_labels', jsonEncode(_variantLabels));
    } catch (_) {}
  }

  void _attachVariantLabels(List<Map<String, dynamic>> lines) {
    if (_variantLabels.isEmpty) return;
    for (final line in lines) {
      final key =
          '${line['product_variant_id'] ?? line['id']}';
      final label = _variantLabels[key];
      if (label != null &&
          label.isNotEmpty &&
          J.str(line['variant_label']).isEmpty) {
        line['variant_label'] = label;
      }
    }
  }

  // === Checkout parity with front ===
  CheckoutConfig checkoutConfig = CheckoutConfig.defaults();
  MultiSellerCheckout? multiSellerCheckout;
  BusinessHoursResult? businessHours;
  List<TimeSlot> timeSlots = [];
  List<Map<String, dynamic>> checkoutGroups = [];
  List<Map<String, dynamic>> sellerGroups = [];
  Map<String, dynamic> deliveryFees = {};
  List<Map<String, dynamic>> paymentSplit = [];
  double platformFee = 0;
  // wallet/promo parity
  bool isWalletChecked = false;

  bool get isLoggedIn => token != null && token!.isNotEmpty;
  bool get isGuest => !isLoggedIn;
  bool get maintenance => J.str(webSettings['website_mode']) == '1';
  bool get akhdimniEnabled => J.flag(settings['akhdimni_enabled']);
  bool get akhdimniPointToPointEnabled => J.flag(settings['akhdimni_point_to_point_enabled'], true);
  bool get akhdimniSpecialItemsEnabled => J.flag(settings['akhdimni_special_items_enabled'], true);
  bool get orderTrackingEnabled => J.flag(settings['order_tracking_enabled']);
  double get minOrderAmount => J.d(settings['min_order_amount']);
  int get maxCartItemsCount => J.i(settings['max_cart_items_count']);
  double get walletRefillLimit => J.d(settings['user_wallet_refill_limit']);
  String get walletBankName => J.str(settings['wallet_admin_bank_name']);
  String get walletAccountHolder => J.str(settings['wallet_admin_account_holder']);
  String get walletAccountNumber => J.str(settings['wallet_admin_account_number']);
  String get walletTransferInstructions => J.str(settings['wallet_admin_transfer_instructions']);
  bool get isCategorySectionEnabled => J.flag(settings['is_category_section_in_homepage'], true);
  bool get isBrandSectionEnabled => J.flag(settings['is_brand_section_in_homepage'], true);
  bool get isSellerSectionEnabled => J.flag(settings['is_seller_section_in_homepage'], true);
  bool get isCountrySectionEnabled => J.flag(settings['is_country_section_in_homepage'], true);

  /// Catalog display mode (parity with web utils/catalogMode.ts).
  /// stores_only hides the global product catalog; products are only
  /// visible from inside a store.
  String get catalogMode {
    final raw = J
        .str(settings['catalog_mode'] ??
            webSettings['catalog_mode'] ??
            shop?['catalog_mode'])
        .trim()
        .toLowerCase();
    if (raw == 'stores_only' ||
        raw == '0' ||
        raw == 'false' ||
        raw == 'no' ||
        raw == 'off' ||
        raw == 'disabled') {
      return 'stores_only';
    }
    return 'mixed';
  }

  bool get isStoresOnly => catalogMode == 'stores_only';
  Map<String, dynamic> get webSettings => J.map(settings['web_settings']);
  /// Deep Navy Blue — headers, navigation, primary structures.
  Color get brandColor => brand.primary;

  /// Dynamic Orange — CTAs, badges, active states.
  Color get accentColor => brand.accent;

  String get currency => J.str(settings['currency'], 'ر.ي');
  int get decimals => J.i(settings['decimal_point'], 2);
  String get placeholder => J.str(webSettings['placeholder_image']);

  /// Total units in cart (sum of quantities), so the badge moves with every
  /// +/- tap — not just when a new line appears.
  int get cartCount {
    final lines = isLoggedIn ? cartProducts : guestCart;
    var total = 0;
    for (final item in lines) {
      total += J.i(item['qty'] ?? item['quantity']);
    }
    return total;
  }
  bool get oneSellerCart => J.flag(settings['one_seller_cart']);
  int get maxSellersPerCheckout {
    final fromSettings = J.i(settings['max_sellers_per_checkout']);
    if (fromSettings > 0) return fromSettings;
    final fromConfig = checkoutConfig.maxSellersPerCheckout;
    return fromConfig > 0 ? fromConfig : kDefaultMaxSellersPerCheckout;
  }

  ({double latitude, double longitude})? get coords => shopCoordinates(city);
  ({double latitude, double longitude}) get browseCoords =>
      coords ?? (latitude: 0.0, longitude: 0.0);

  Future<void> bootstrap() async {
    _prefs = await SharedPreferences.getInstance();
    apiUrl = AppConfig.defaultApiUrl;
    await _prefs.setString('api_url', apiUrl);
    token = _prefs.getString('token');
    viewerKey = _prefs.getString('viewer_key');
    if (viewerKey == null || viewerKey!.length < 8) {
      viewerKey = _newViewerKey();
      await _prefs.setString('viewer_key', viewerKey!);
    }
    fcmToken = _prefs.getString('sreamart_fcm_token') ?? '';
    if (fcmToken.isEmpty) {
      // Temporary stub until PushNotifications replaces it with the real FCM
      // token (front stores sreamart_fcm_token the same way).
      fcmToken = '${AppConfig.devicePlatform}_${viewerKey}_${DateTime.now().millisecondsSinceEpoch}';
      await _prefs.setString('sreamart_fcm_token', fcmToken);
    }
    final lang = _prefs.getString('language') ?? 'ar';
    await i18n.load(lang);
    i18n.addListener(notifyListeners);

    // Stored strings may be corrupted (interrupted write, older build):
    // never let them break startup into a frozen splash screen.
    try {
      final guestRaw = _prefs.getString('guest_cart');
      if (guestRaw != null && guestRaw.isNotEmpty) {
        guestCart = J.maps(jsonDecode(guestRaw));
      }
    } catch (_) {
      guestCart = [];
      await _prefs.remove('guest_cart');
    }
    try {
      final labelsRaw = _prefs.getString('variant_labels');
      if (labelsRaw != null && labelsRaw.isNotEmpty) {
        final decoded = jsonDecode(labelsRaw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            final label = '$v'.trim();
            if (label.isNotEmpty) _variantLabels['$k'] = label;
          });
        }
      }
    } catch (_) {}
    try {
      final cityRaw = _prefs.getString('city');
      if (cityRaw != null && cityRaw.isNotEmpty) {
        city = J.map(jsonDecode(cityRaw));
      }
    } catch (_) {
      city = null;
      await _prefs.remove('city');
    }

    api = CustomerApi(baseUrl: apiUrl, token: token, viewerKey: viewerKey);
    try {
      brand = await BrandService(apiUrl).load(prefs: _prefs);
      if (token != null) {
        final me = await api.userDetails();
        if (me.ok) {
          user = me.user.isNotEmpty ? me.user : me.dataMap;
        } else {
          await _clearSession();
        }
      }
      // Parallel bootstrap: settings + cities are independent.
      await Future.wait([reloadSettings(), loadCities()]);
      await resolveCity();
      // Shop + categories + hours are independent of each other.
      await Future.wait([loadShop(), loadRootCategories(), loadBusinessHours()]);
      if (isLoggedIn) {
        await loadAddresses();
        await refreshCart();
      }
      bootstrapped = true;
    } catch (error) {
      bootstrapError = '$error';
      bootstrapped = true;
    }
    notifyListeners();
  }

  Future<void> setApiUrl(String url) async {
    final value = url.trim();
    apiUrl = value.isEmpty ? AppConfig.defaultApiUrl : value;
    await _prefs.setString('api_url', apiUrl);
    api.setBaseUrl(apiUrl);
    notifyListeners();
    await reloadSettings();
    await loadCities();
    await resolveCity();
    await loadShop();
    await loadRootCategories();
  }

  Future<void> setLanguage(String code) async {
    await i18n.load(code);
    await _prefs.setString('language', i18n.code);
    notifyListeners();
  }

  String t(String key) => i18n.t(key);

  Future<void> reloadSettings() async {
    final result = await api.settings(withAuth: isLoggedIn);
    if (result.ok) {
      var data = result.dataMap;
      if (data['web_settings'] is List)
        data['web_settings'] = <String, dynamic>{};
      if (data['firebase'] is List) data['firebase'] = <String, dynamic>{};
      settings = data;
      favoriteIds = J.list(data['favorite_product_ids']);
      checkoutConfig = CheckoutConfig.fromSettings(data);
      final hoursRaw = data['business_hours'];
      if (hoursRaw is Map) {
        businessHours = BusinessHoursResult.fromMap(J.map(hoursRaw));
      }
    }
    try {
      final pay = await api.paymentMethods();
      if (pay.ok) {
        var decoded = pay.data;
        if (decoded is String) {
          try {
            decoded = jsonDecode(utf8.decode(base64Decode(decoded)));
          } catch (_) {}
        }
        paymentSettings = J.map(decoded);
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> loadCities() async {
    final result = await api.cities();
    cities = result.ok ? result.dataMaps : [];
    citiesLoaded = true;
    notifyListeners();
  }

  Future<void> resolveCity() async {
    if (!citiesLoaded) return;
    if (isSingleCityMode(cities)) {
      await selectCity(normalizeCity(getSoleCity(cities)));
      return;
    }
    if (isLoggedIn) {
      await loadAddresses();
      final defaultAddress = addresses.cast<Map<String, dynamic>?>().firstWhere(
        (item) => J.i(item?['is_default']) == 1,
        orElse: () => addresses.isNotEmpty ? addresses.first : null,
      );
      selectedAddress = defaultAddress;
      final fromAddress = cityFromAddress(defaultAddress, cities);
      if (fromAddress != null) {
        await selectCity(fromAddress);
        return;
      }
    }
    if (city == null && settings['default_city'] != null) {
      await selectCity(normalizeCity(settings['default_city']));
      return;
    }
    if (city == null && cities.isNotEmpty) {
      await selectCity(normalizeCity(cities.first));
    }
  }

  Future<void> selectCity(Map<String, dynamic> next) async {
    city = next;
    await _prefs.setString('city', jsonEncode(next));
    notifyListeners();
    await loadShop();
    await loadRootCategories();
    if (isLoggedIn) await refreshCart();
  }

  /// Cache-first shop: paints cached home instantly (max 2 min old), then
  /// refreshes in background. New stores appear within ~2 min max — never hidden.
  Future<void> loadShop({bool force = false}) async {
    const ttl = Duration(minutes: 2);
    if (!force) {
      try {
        final raw = _prefs.getString('shop_cache');
        final at = _prefs.getInt('shop_cache_at') ?? 0;
        if (raw != null && raw.isNotEmpty &&
            DateTime.now().millisecondsSinceEpoch - at < ttl.inMilliseconds) {
          final decoded = J.map(jsonDecode(raw));
          if (decoded.isNotEmpty) {
            shop = decoded;
            notifyListeners();
            // Background revalidate without blocking UI.
            _refreshShopInBackground();
            return;
          }
        }
      } catch (_) {}
    }
    final point = browseCoords;
    final result = await api.shop(
      latitude: point.latitude,
      longitude: point.longitude,
    );
    if (result.ok) {
      shop = result.dataMap;
      try {
        var dump = jsonEncode(shop);
        // Device-safe: skip persisting giant payloads (>400KB).
        if (dump.length < 400 * 1024) {
          await _prefs.setString('shop_cache', dump);
          await _prefs.setInt(
              'shop_cache_at', DateTime.now().millisecondsSinceEpoch);
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _refreshShopInBackground() async {
    try {
      final point = browseCoords;
      final result = await api.shop(
        latitude: point.latitude,
        longitude: point.longitude,
      );
      if (result.ok) {
        shop = result.dataMap;
        try {
          var dump = jsonEncode(shop);
          if (dump.length < 400 * 1024) {
            await _prefs.setString('shop_cache', dump);
            await _prefs.setInt(
                'shop_cache_at', DateTime.now().millisecondsSinceEpoch);
          }
        } catch (_) {}
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> loadRootCategories({bool force = false}) async {
    const ttl = Duration(minutes: 10);
    if (!force) {
      try {
        final raw = _prefs.getString('cats_cache');
        final at = _prefs.getInt('cats_cache_at') ?? 0;
        if (raw != null && raw.isNotEmpty &&
            DateTime.now().millisecondsSinceEpoch - at < ttl.inMilliseconds) {
          final decoded = J.maps(jsonDecode(raw));
          if (decoded.isNotEmpty) {
            rootCategories = decoded;
            notifyListeners();
            return;
          }
        }
      } catch (_) {}
    }
    final result = await api.categories(categoryId: 0, limit: 50, offset: 0);
    if (result.ok) {
      rootCategories = result.dataMaps;
      try {
        var dump = jsonEncode(rootCategories);
        if (dump.length < 200 * 1024) {
          await _prefs.setString('cats_cache', dump);
          await _prefs.setInt(
              'cats_cache_at', DateTime.now().millisecondsSinceEpoch);
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  // ---- Front parity: checkout config / business hours / time slots ----
  Future<void> loadCheckoutConfig() async {
    final res = await api.checkoutConfig();
    if (res.ok) {
      checkoutConfig = CheckoutConfig.from(res, fallback: checkoutConfig);
    } else {
      checkoutConfig = CheckoutConfig.fromSettings(settings);
    }
    notifyListeners();
  }

  Future<void> loadBusinessHours({List<dynamic> sellerIds = const []}) async {
    final ids = sellerIds.isNotEmpty ? sellerIds : _sellerIdsFromCart();
    final res = await api.businessHours(sellerIds: ids);
    if (res.ok) businessHours = BusinessHoursResult.from(res);
    notifyListeners();
  }

  List<dynamic> _sellerIdsFromCart() {
    return cartSellerIds().toList();
  }

  Set<String> cartSellerIds() {
    final ids = <String>{};
    void add(dynamic sid) {
      if (sid == null) return;
      final key = '$sid';
      if (key.isEmpty || key == 'null' || key == '0') return;
      ids.add(key);
    }

    for (final p in cartProducts) {
      add(J.sellerId(p) ?? p['seller_id']);
    }
    for (final p in guestCart) {
      add(p['seller_id'] ?? J.sellerId(p));
    }
    for (final group in sellerGroups) {
      add(group['seller_id'] ?? group['sellerId'] ?? group['id']);
    }
    return ids;
  }

  int get distinctCartSellerCount => cartSellerIds().length;

  bool variantAlreadyInCart(dynamic variantId) {
    return _qtyInCart(variantId) > 0;
  }

  /// Public cart quantity for a variant (0 when not in cart).
  int cartQtyFor(dynamic variantId) => _qtyInCart(variantId);

  int _qtyInCart(dynamic variantId) {
    if (variantId == null) return 0;
    final key = '$variantId';
    final lines = isLoggedIn ? cartProducts : guestCart;
    for (final item in lines) {
      if ('${item['product_variant_id'] ?? item['id']}' == key) {
        return J.i(item['qty'] ?? item['quantity']);
      }
    }
    return 0;
  }

  /// Instant local cart mutation + notify, so badges and steppers move the
  /// moment the user taps. The following server refresh reconciles truth.
  void _optimisticSetQty(
    dynamic variantId,
    int qty, {
    dynamic productId,
    dynamic sellerId,
    double? productPrice,
    bool clearFirst = false,
  }) {
    final lines = isLoggedIn ? cartProducts : guestCart;
    if (clearFirst) lines.clear();
    if (variantId == null) {
      notifyListeners();
      return;
    }
    final key = '$variantId';
    final i = lines.indexWhere(
      (e) => '${e['product_variant_id'] ?? e['id']}' == key,
    );
    if (qty <= 0) {
      if (i >= 0) lines.removeAt(i);
    } else if (i >= 0) {
      lines[i] = {...lines[i], 'qty': qty};
    } else {
      lines.add({
        if (productId != null) 'product_id': productId,
        'product_variant_id': variantId,
        'qty': qty,
        if (sellerId != null) 'seller_id': sellerId,
        if (productPrice != null) 'productPrice': productPrice,
      });
    }
    notifyListeners();
  }

  bool wouldExceedStoreLimit({dynamic sellerId, dynamic variantId}) {
    if (sellerId == null) return false;
    if (variantAlreadyInCart(variantId)) return false;
    final key = '$sellerId';
    final existing = cartSellerIds();
    if (existing.contains(key)) return false;
    return existing.length >= maxSellersPerCheckout;
  }

  String storeNameOf(Map<String, dynamic>? product) {
    if (product == null) return '';
    return J.str(
      J.map(product['seller'])['store_name'] ??
          product['seller_name'] ??
          product['seller_store_name'] ??
          product['store_name'],
    );
  }

  /// Returns a user-facing reason when add-to-cart must be blocked.
  Future<String?> cartAddBlockedReason({
    dynamic sellerId,
    dynamic variantId,
    String storeName = '',
  }) async {
    final ids = <dynamic>[
      ..._sellerIdsFromCart(),
      if (sellerId != null) sellerId,
    ];
    await loadBusinessHours(sellerIds: ids);
    final closed = addToCartClosedMessage(
      hours: businessHours,
      sellerId: sellerId,
      storeName: storeName,
    );
    if (closed != null && closed.isNotEmpty) return closed;

    if (oneSellerCart && sellerId != null) {
      final existing = cartSellerIds();
      if (existing.isNotEmpty && !existing.contains('$sellerId')) {
        return 'same_seller';
      }
    }

    if (wouldExceedStoreLimit(sellerId: sellerId, variantId: variantId)) {
      return t('max_stores_exceeded').replaceAll('{max}', '$maxSellersPerCheckout');
    }
    return null;
  }

  Future<void> loadTimeSlots() async {
    final res = await api.timeSlots();
    if (res.ok) timeSlots = TimeSlot.parse(res);
    notifyListeners();
  }

  Future<ApiResult> loadMultiSellerCheckout() async {
    final pt = browseCoords;
    final ids = _sellerIdsFromCart();
    final res = await api.multiSellerCheckout(
      latitude: pt.latitude,
      longitude: pt.longitude,
      sellerIds: ids,
    );
    if (res.ok) {
      multiSellerCheckout = MultiSellerCheckout.from(res);
      final data = res.dataMap;
      sellerGroups = J.maps(data['seller_groups'] ?? data['sellerGroups']);
      deliveryFees = J.map(data['delivery_fees'] ?? data['deliveryFees']);
      paymentSplit = J.maps(data['payment_split'] ?? data['paymentSplit']);
      platformFee = J.d(data['platform_fee']);
      // keep cart checkout mapping parity
      cart = data.isNotEmpty ? data : cart;
    }
    notifyListeners();
    return res;
  }

  Future<ApiResult> loadCheckoutGroups({int page = 1}) async {
    final res = await api.checkoutGroups(page: page);
    if (res.ok) checkoutGroups = res.dataMaps;
    notifyListeners();
    return res;
  }

  Future<ApiResult> fetchCheckoutGroup(dynamic id) => api.checkoutGroup(id);
  Future<ApiResult> cancelCheckoutGroup(dynamic id, {String reason = ''}) => api.cancelCheckoutGroup(id, reason: reason);

  String buildIdempotencyKey() {
    final uid = user?['id'] ?? 'guest';
    return 'checkout-$uid-${DateTime.now().millisecondsSinceEpoch}';
  }

  CanPlaceOrderResult canPlaceOrder() => canPlaceOrderFromBusinessHours(businessHours);

  Future<void> loadAddresses() async {
    if (!isLoggedIn) return;
    final result = await api.addresses();
    if (result.ok) {
      addresses = result.dataMaps;
      selectedAddress ??= addresses.cast<Map<String, dynamic>?>().firstWhere(
        (item) => J.i(item?['is_default']) == 1,
        orElse: () => addresses.isNotEmpty ? addresses.first : null,
      );
    }
    notifyListeners();
  }

  Future<void> setFcmToken(String value) async {
    fcmToken = value;
    await _prefs.setString('sreamart_fcm_token', value);
    if (isLoggedIn) {
      try {
        await api.updateFcmToken(value);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<String?> login({
    required String mobile,
    required String password,
  }) async {
    final result = await api.loginMobile(mobile: mobile, password: password, fcm: fcmToken);
    if (!result.ok) {
      return result.message.isEmpty ? t('login_error') : result.message;
    }
    await _applyAuth(result);
    return null;
  }

  Future<String?> registerCustomer({
    required String name,
    required String mobile,
    required String password,
    String email = '',
    String? otp,
    int? cityId,
    String backupPhone = '',
  }) async {
    final result = await api.register(
      name: name,
      mobile: mobile,
      password: password,
      email: email,
      otp: otp,
      cityId: cityId,
      backupPhone: backupPhone,
      fcm: fcmToken,
    );
    if (!result.ok) return result.message;
    await _applyAuth(result);
    return null;
  }

  Future<String?> changePassword({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    final result = await api.changePassword(
      currentPassword: currentPassword,
      password: password,
      passwordConfirmation: passwordConfirmation,
    );
    if (!result.ok) return result.message;
    return null;
  }

  Future<void> _applyAuth(ApiResult result) async {
    token = result.token ?? J.str(result.dataMap['access_token']);
    if (token == null || token!.isEmpty) {
      throw StateError('missing_token');
    }
    user = result.user.isNotEmpty ? result.user : result.dataMap;
    api.setToken(token);
    await _prefs.setString('token', token!);
    if (fcmToken.isNotEmpty) {
      try {
        await api.updateFcmToken(fcmToken);
      } catch (_) {}
    }
    if (guestCart.isNotEmpty) {
      final ids = guestCart
          .map((item) => '${item['product_variant_id']}')
          .join(',');
      final qtys = guestCart.map((item) => '${item['qty']}').join(',');
      await api.bulkAddToCart(variantIds: ids, quantities: qtys);
      guestCart = [];
      guestCartTotal = 0;
      await _prefs.remove('guest_cart');
    }
    await reloadSettings();
    await resolveCity();
    await loadShop();
    await refreshCart();
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } catch (_) {}
    await _clearSession();
    notifyListeners();
  }

  Future<void> _clearSession() async {
    token = null;
    user = null;
    cart = null;
    cartProducts = [];
    addresses = [];
    selectedAddress = null;
    promoCode = null;
    favoriteIds = [];
    api.setToken(null);
    await _prefs.remove('token');
  }

  Future<ApiResult> refreshCart({int checkout = 0}) async {
    final point = _cartCoords(checkout: checkout == 1);
    if (point == null) {
      // No coordinates (no city yet): local cart is the truth — still
      // notify so badges/steppers reflect optimistic updates.
      notifyListeners();
      return ApiResult({'status': 0});
    }
    if (isLoggedIn) {
      final result = await api.cart(
        latitude: point.latitude,
        longitude: point.longitude,
        checkout: checkout,
      );
      if (result.ok) {
        cart = result.dataMap;
        cartProducts = J.maps(cart?['cart'] ?? cart?['items'] ?? result.data);
        _attachVariantLabels(cartProducts);
        cartSubTotal = J.d(cart?['sub_total'] ?? cart?['total']);
        // parity: enrich sellerGroups etc when is_checkout=1
        if (checkout == 1) {
          sellerGroups = J.maps(cart?['seller_groups'] ?? cart?['sellerGroups']);
          deliveryFees = J.map(cart?['delivery_fees'] ?? cart?['deliveryFees']);
          paymentSplit = J.maps(cart?['payment_split'] ?? cart?['paymentSplit']);
          platformFee = J.d(cart?['platform_fee']);
          isWalletChecked = J.i(cart?['is_wallet_checked']) == 1;
        }
        // auto load supporting data for checkout
        final cartMax = J.i(cart?['max_sellers_per_checkout']);
        if (cartMax > 0) {
          checkoutConfig = CheckoutConfig(
            maxSellersPerCheckout: cartMax,
            distanceThreshold: checkoutConfig.distanceThreshold,
            distanceFeePerKm: checkoutConfig.distanceFeePerKm,
            platformFee: checkoutConfig.platformFee,
            baseFee: checkoutConfig.baseFee,
            maxDistanceKm: checkoutConfig.maxDistanceKm,
          );
        }
        if (checkout == 1) {
          await loadBusinessHours();
          if (timeSlots.isEmpty) await loadTimeSlots();
          await loadCheckoutConfig();
        }
      }
      notifyListeners();
      return result;
    }
    if (guestCart.isEmpty) {
      guestCartTotal = 0;
      notifyListeners();
      return ApiResult({'status': 1, 'data': []});
    }
    final result = await api.guestCart(
      latitude: point.latitude,
      longitude: point.longitude,
      variantIds: guestCart
          .map((item) => '${item['product_variant_id']}')
          .join(','),
      quantities: guestCart.map((item) => '${item['qty']}').join(','),
    );
    if (result.ok) {
      guestCartTotal = J.d(
        result.dataMap['sub_total'] ?? result.dataMap['total'],
      );
      final priced = J.maps(result.dataMap['cart'] ?? result.data);
      if (priced.isNotEmpty) {
        // Keep local quantities: the server prices the lines, but the
        // user's taps are the truth for qty until the server confirms.
        final localQty = <String, int>{};
        for (final item in guestCart) {
          localQty['${item['product_variant_id']}'] =
              J.i(item['qty'] ?? item['quantity']);
        }
        for (final p in priced) {
          final key = '${p['product_variant_id'] ?? p['id']}';
          final serverQty = J.i(p['qty'] ?? p['quantity']);
          final keep = localQty[key];
          if ((serverQty <= 0) && keep != null && keep > 0) {
            p['qty'] = keep;
          }
        }
        guestCart = priced;
        _attachVariantLabels(guestCart);
      }
    }
    notifyListeners();
    return result;
  }

  ({double latitude, double longitude})? _cartCoords({required bool checkout}) {
    if (checkout && selectedAddress != null) {
      final lat = double.tryParse('${selectedAddress!['latitude']}');
      final lng = double.tryParse('${selectedAddress!['longitude']}');
      if (lat != null && lng != null) return (latitude: lat, longitude: lng);
    }
    return coords;
  }

  /// Returns `same_seller` when mixing sellers is not allowed.
  Future<String?> addToCart({
    required dynamic productId,
    required dynamic variantId,
    required int qty,
    double? productPrice,
    dynamic sellerId,
    bool replaceSeller = false,
    String storeName = '',
    String variantLabel = '',
  }) async {
    if (!replaceSeller) {
      if (maxCartItemsCount > 0 && qty > maxCartItemsCount) {
        return t('max_cart_limit_error').replaceAll('{max}', '$maxCartItemsCount');
      }
      final currentQty = _qtyInCart(variantId);
      final isNewOrIncrease = qty > currentQty;
      if (isNewOrIncrease) {
        final blocked = await cartAddBlockedReason(
          sellerId: sellerId,
          variantId: variantId,
          storeName: storeName,
        );
        if (blocked != null) return blocked;
      }
    } else {
      await loadBusinessHours(sellerIds: sellerId != null ? [sellerId] : []);
      final closed = addToCartClosedMessage(
        hours: businessHours,
        sellerId: sellerId,
        storeName: storeName,
      );
      if (closed != null && closed.isNotEmpty) return closed;
    }
    if (isLoggedIn) {
      if (replaceSeller) {
        await api.clearCart();
        cartProducts = [];
      }
      if (variantLabel.trim().isNotEmpty) {
        await rememberVariantLabel(variantId, variantLabel);
      }
      // Optimistic: badge + steppers move instantly, server confirms after.
      _optimisticSetQty(
        variantId,
        qty,
        productId: productId,
        sellerId: sellerId,
        productPrice: productPrice,
        clearFirst: replaceSeller,
      );
      final result = await api.addToCart(
        productId: productId,
        variantId: variantId,
        qty: qty,
      );
      if (result.oneSellerError == 1) {
        await refreshCart();
        return 'same_seller';
      }
      if (!result.ok) {
        // Reconcile: drop the optimistic change, show the real error.
        await refreshCart();
        return result.message.isEmpty
            ? t('something_went_wrong')
            : result.message;
      }
      await refreshCart();
      return null;
    }
    if (replaceSeller) {
      guestCart = [];
    } else if (guestCart.isNotEmpty && sellerId != null && oneSellerCart) {
      final current = guestCart.first['seller_id'];
      if (current != null &&
          '$current'.isNotEmpty &&
          '$current' != '$sellerId') {
        return 'same_seller';
      }
    }
    final existingIndex = guestCart.indexWhere(
      (item) => '${item['product_variant_id']}' == '$variantId',
    );
    if (variantLabel.trim().isNotEmpty) {
      await rememberVariantLabel(variantId, variantLabel);
    }
    if (existingIndex >= 0) {
      guestCart[existingIndex]['qty'] = qty;
      if (variantLabel.trim().isNotEmpty) {
        guestCart[existingIndex]['variant_label'] = variantLabel.trim();
      }
    } else {
      guestCart.add({
        'product_id': productId,
        'product_variant_id': variantId,
        'qty': qty,
        if (sellerId != null) 'seller_id': sellerId,
        if (productPrice != null) 'productPrice': productPrice,
        if (variantLabel.trim().isNotEmpty)
          'variant_label': variantLabel.trim(),
      });
    }
    await _prefs.setString('guest_cart', jsonEncode(guestCart));
    await refreshCart();
    return null;
  }

  /// Removes one cart line. Returns an error message when the server
  /// refuses (logged-in), so callers can surface it instead of failing
  /// silently with a stepper that never moves.
  Future<String?> removeCartLine({
    required dynamic productId,
    required dynamic variantId,
  }) async {
    if (isLoggedIn) {
      // Optimistic: line disappears instantly, server confirms after.
      _optimisticSetQty(variantId, 0);
      final result = await api.removeFromCart(
        productId: productId,
        variantId: variantId,
      );
      if (!result.ok) {
        await refreshCart();
        return result.message.isEmpty
            ? t('something_went_wrong')
            : result.message;
      }
      await refreshCart();
      return null;
    }
    guestCart.removeWhere(
      (item) => '${item['product_variant_id']}' == '$variantId',
    );
    await _prefs.setString('guest_cart', jsonEncode(guestCart));
    await refreshCart();
    return null;
  }

  Future<void> clearAllCart() async {
    if (isLoggedIn) {
      await api.clearCart();
    }
    guestCart = [];
    await _prefs.remove('guest_cart');
    await refreshCart();
  }

  Future<String?> applyPromo(String code, double total) async {
    final result = await api.validatePromo(promoCode: code, total: total);
    if (!result.ok) return result.message;
    promoCode = result.dataMap.isNotEmpty
        ? result.dataMap
        : {'promo_code': code, ...result.raw};
    notifyListeners();
    return null;
  }

  void clearPromo() {
    promoCode = null;
    notifyListeners();
  }

  void selectAddress(Map<String, dynamic>? address) {
    selectedAddress = address;
    notifyListeners();
  }

  void setUser(Map<String, dynamic>? next) {
    user = next;
    notifyListeners();
  }

  bool isFavorite(dynamic productId) =>
      favoriteIds.map((id) => '$id').contains('$productId');

  Future<void> toggleFavorite(dynamic productId) async {
    if (!isLoggedIn) return;
    if (isFavorite(productId)) {
      await api.removeFavorite(productId);
      favoriteIds.removeWhere((id) => '$id' == '$productId');
    } else {
      await api.addFavorite(productId);
      favoriteIds.add(productId);
    }
    notifyListeners();
  }

  Future<String?> deleteAccount({
    required String confirmation,
    String? password,
  }) async {
    final result = await api.deleteAccount(
      confirmation: confirmation,
      password: password,
    );
    if (!result.ok) {
      return result.message.isEmpty
          ? t('something_went_wrong')
          : result.message;
    }
    await _clearSession();
    notifyListeners();
    return null;
  }

  Future<String?> logoutAllDevices() async {
    final result = await api.logoutAllDevices();
    if (!result.ok) {
      return result.message.isEmpty
          ? t('something_went_wrong')
          : result.message;
    }
    await _clearSession();
    notifyListeners();
    return null;
  }

  Future<String> cmsHtml(String key) async {
    var html = J.html(settings[key]);
    if (html.trim().isEmpty) html = J.html(webSettings[key]);
    if (html.trim().isEmpty) {
      final result = switch (key) {
        'privacy_policy' => await api.privacyPolicy(),
        'terms_conditions' => await api.termsConditions(),
        'about_us' => await api.aboutUs(),
        'contact_us' => await api.contactUs(),
        _ => ApiResult({'status': 0}),
      };
      if (result.ok) html = result.html;
    }
    if (html.trim().isEmpty && key == 'contact_us') {
      final email = J.str(settings['support_email']);
      final phone = J.str(settings['support_number']);
      final address = J.str(settings['store_address']);
      html = [
        if (phone.isNotEmpty) '<p>$phone</p>',
        if (email.isNotEmpty) '<p>$email</p>',
        if (address.isNotEmpty) '<p>$address</p>',
      ].join();
    }
    return html;
  }

  String _newViewerKey() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random();
    return List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
  }
}

final appController = AppController();
