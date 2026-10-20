import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'city_mode.dart';
import 'catalog_store.dart';
import 'catalog_db/catalog_config.dart';
import 'catalog_db/catalog_database.dart';
import 'image_prefetch.dart';
import 'notification_read.dart';
import 'business_hours.dart';
import 'checkout_models.dart';
import 'config.dart';
import 'diag.dart';
import 'i18n.dart';
import 'json_util.dart';
import 'api/api_errors.dart';
import 'api/customer_api.dart';
import 'auth/token_vault.dart';
import 'brand/brand_config.dart';
import 'brand/brand_service.dart';
import 'offline/cache_policy.dart';
import 'offline/operation_policy.dart';
import 'offline/checkout_session.dart';
import 'offline/local_cart.dart' as local_cart;
import 'offline/local_store.dart';
import 'offline/offline_cache.dart';
import 'offline/pending_ops.dart';
import 'offline/sync_engine.dart';

class AppController extends ChangeNotifier {
  AppController();

  late SharedPreferences _prefs;
  SharedPreferences get prefs => _prefs;
  late CustomerApi api;
  final i18n = I18n();

  // ---- Offline-first infrastructure (testable, no new native deps) ----
  late TokenVault vault;
  late LocalStore store;
  late OfflineCache offline;
  late SyncEngine sync;
  CheckoutSession? _checkoutSession;

  /// Best-effort catalog sync (public Drift catalog). Progress is observable
  /// via [catalogSync].progress; [sync] stays the outbox-only engine.
  final CatalogSyncService catalogSync = CatalogSyncService();
  CatalogDatabase? _catalogDb;
  DateTime? _lastCatalogSyncAttempt;
  local_cart.LocalCartRepository? _localCart;

  /// Bounded opt-in thumbnail prefetch (default OFF — mobile-data safety).
  final ImagePrefetch imagePrefetch = ImagePrefetch();

  /// True when a previous checkout session could not be reconciled against
  /// order history at startup. The UI should block new checkout attempts until
  /// the user reviews their orders.
  bool unresolvedCheckout = false;

  /// Notified ONLY on auth/city/catalog-mode transitions. GoRouter listens to
  /// this instead of the whole controller, so cart steppers no longer trigger
  /// route re-evaluation on every tap (perf fix, preserves redirect logic).
  final navTick = ValueNotifier<int>(0);

  /// Notified ONLY when chrome (locale/brand/theme-affecting settings)
  /// changes. MaterialApp listens to this + i18n instead of every cart tick.
  final chromeTick = ValueNotifier<int>(0);

  /// Stable account scope for offline docs: `u:<id>` or `guest`.
  /// Prevents one customer's orders/addresses/favorites leaking to another.
  String get accountScope => LocalStore.accountScope(user?['id']?.toString());

  /// Test-only injection: wires in-memory prefs + a fake API so offline
  /// cold-start, stale-cache, and failure-preservation behavior can be
  /// verified without network access. Never used in production code.
  @visibleForTesting
  void injectForTest({
    required SharedPreferences prefs,
    required CustomerApi testApi,
  }) {
    _prefs = prefs;
    api = testApi;
    vault = TokenVault(prefs: prefs);
    store = LocalStore(prefs);
    offline = OfflineCache(store);
    sync = SyncEngine(
      outboxForCurrentScope: () => PendingOutbox(store, accountScope),
    );
    _checkoutSession = null;
    // Test hygiene: never inherit cart serialization state across tests —
    // waiters/gates from a torn-down (FakeAsync) zone must not block the
    // next test's ops.
    _cartActive = 0;
    _cartWaiters.clear();
    _cartGen = 0;
    _refreshInFlight = null;
  }

  void _bumpNav() => navTick.value++;
  void _bumpChrome() => chromeTick.value++;

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
  static String variantLabelOf(
    Map<String, dynamic>? v, [
    String productName = '',
  ]) {
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

  /// Maximum variant display labels kept on device. Variant labels are
  /// display-only conveniences; without a bound they grow one entry per
  /// distinct variant ever added. Oldest entries are evicted first.
  static const int maxVariantLabels = 500;

  Future<void> rememberVariantLabel(dynamic variantId, String label) async {
    if (variantId == null || label.trim().isEmpty) return;
    _variantLabels.remove('$variantId');
    _variantLabels['$variantId'] = label.trim();
    while (_variantLabels.length > maxVariantLabels) {
      _variantLabels.remove(_variantLabels.keys.first);
    }
    try {
      await store.writeJson('variant_labels', _variantLabels);
    } catch (_) {}
  }

  /// Persists the guest cart with an encoded byte-size guard. Oversized carts
  /// stay memory-only (and syncable at login) instead of breaking prefs.
  Future<void> persistGuestCart() async {
    try {
      await store.writeJson('guest_cart', guestCart);
    } catch (_) {}
    // Keep the Drift mirror in sync (best-effort, never blocks the UI).
    try {
      final repo = _localCart;
      if (repo != null) {
        await repo.clear();
        for (final item in guestCart) {
          await repo.addItem(local_cart.CartItem.fromMap(item));
        }
      }
    } catch (_) {}
  }

  void _attachVariantLabels(List<Map<String, dynamic>> lines) {
    if (_variantLabels.isEmpty) return;
    for (final line in lines) {
      final key = '${line['product_variant_id'] ?? line['id']}';
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

  /// Add-to-cart UX memo for [cartAddBlockedReason] only: last check time +
  /// the seller set it covered. Repeated stepper taps for the same cart reuse
  /// the hours instead of refetching every tap. Scoped to the add path on
  /// purpose — checkout/refresh paths always fetch fresh, and the server
  /// remains authoritative at order placement, so a stale add-gate (max 90s)
  /// can never place an order while closed.
  DateTime? _lastAddHoursAt;
  String _lastAddHoursKey = '';

  /// Radical cart fix: serialize ALL cart mutations + refreshes through one
  /// FIFO gate so rapid +/- taps can never run in parallel and resurrect
  /// stale quantities. [_cartGen] lets a stale refresh response be ignored
  /// when a newer mutation already moved the truth forward.
  ///
  /// Implemented as a waiter queue of completers created fresh per op (never
  /// awaiting an inherited cross-test future), so a torn-down test zone can
  /// never leave later cart ops stuck behind a future from a dead zone.
  int _cartActive = 0;
  final List<Completer<void>> _cartWaiters = [];

  Future<T> _enqueueCart<T>(Future<T> Function() fn) async {
    // Condition-variable style lock: a waiter re-checks after waking so a new
    // op arriving in the handoff microtask can never run concurrently with it.
    while (_cartActive > 0) {
      final waiter = Completer<void>();
      _cartWaiters.add(waiter);
      try {
        await waiter.future;
      } catch (_) {}
    }
    _cartActive++;
    try {
      return await fn();
    } finally {
      _cartActive--;
      if (_cartWaiters.isNotEmpty) {
        _cartWaiters.removeAt(0).complete();
      }
    }
  }

  int _cartGen = 0;
  Future<void>? _refreshInFlight;
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
  bool get akhdimniPointToPointEnabled =>
      J.flag(settings['akhdimni_point_to_point_enabled'], true);
  bool get akhdimniSpecialItemsEnabled =>
      J.flag(settings['akhdimni_special_items_enabled'], true);
  bool get orderTrackingEnabled => J.flag(settings['order_tracking_enabled']);
  double get minOrderAmount => J.d(settings['min_order_amount']);
  int get maxCartItemsCount => J.i(settings['max_cart_items_count']);
  double get walletRefillLimit => J.d(settings['user_wallet_refill_limit']);
  String get walletBankName => J.str(settings['wallet_admin_bank_name']);
  String get walletAccountHolder =>
      J.str(settings['wallet_admin_account_holder']);
  String get walletAccountNumber =>
      J.str(settings['wallet_admin_account_number']);
  String get walletTransferInstructions =>
      J.str(settings['wallet_admin_transfer_instructions']);
  bool get isCategorySectionEnabled =>
      J.flag(settings['is_category_section_in_homepage'], true);
  bool get isBrandSectionEnabled =>
      J.flag(settings['is_brand_section_in_homepage'], true);
  bool get isSellerSectionEnabled =>
      J.flag(settings['is_seller_section_in_homepage'], true);
  bool get isCountrySectionEnabled =>
      J.flag(settings['is_country_section_in_homepage'], true);

  /// Catalog display mode (parity with web utils/catalogMode.ts).
  /// stores_only hides the global product catalog; products are only
  /// visible from inside a store.
  String get catalogMode {
    final raw = J
        .str(
          settings['catalog_mode'] ??
              webSettings['catalog_mode'] ??
              shop?['catalog_mode'],
        )
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
    final sw = Stopwatch()..start();
    void mark(String tag) {
      if (!Diag.enabled) return;
      Diag.log('boot:$tag', '${sw.elapsedMilliseconds}ms');
      sw.reset();
    }

    _prefs = await SharedPreferences.getInstance();
    vault = TokenVault(prefs: _prefs);
    store = LocalStore(_prefs);
    offline = OfflineCache(store);
    sync = SyncEngine(
      outboxForCurrentScope: () => PendingOutbox(store, accountScope),
    );
    apiUrl = AppConfig.defaultApiUrl;
    await _prefs.setString('api_url', apiUrl);
    mark('prefs');
    try {
      token = await vault.read();
    } on TokenVaultException catch (e) {
      if (kDebugMode) debugPrint('[auth] token vault read failed: $e');
      token = null;
    }
    mark('tokenVault');
    viewerKey = _prefs.getString('viewer_key');
    if (viewerKey == null || viewerKey!.length < 8) {
      viewerKey = _newViewerKey();
      await _prefs.setString('viewer_key', viewerKey!);
    }
    fcmToken = _prefs.getString('sreamart_fcm_token') ?? '';
    if (fcmToken.isEmpty) {
      // Temporary stub until PushNotifications replaces it with the real FCM
      // token (front stores sreamart_fcm_token the same way).
      fcmToken =
          '${AppConfig.devicePlatform}_${viewerKey}_${DateTime.now().millisecondsSinceEpoch}';
      await _prefs.setString('sreamart_fcm_token', fcmToken);
    }
    mark('viewer/fcm');
    final lang = _prefs.getString('language') ?? 'ar';
    await i18n.load(lang);
    i18n.addListener(notifyListeners);
    mark('i18nLoad');

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
    mark('prefsDecode');

    api = CustomerApi(baseUrl: apiUrl, token: token, viewerKey: viewerKey);
    _catalogDb = await openCatalogDbFile();
    mark('dbOpen');
    if (_catalogDb != null) {
      _localCart = local_cart.LocalCartRepository(_catalogDb!);
      await _localCart!.load();
      // RADICAL FIX (cart vanished after restart): the Drift table used to
      // SWALLOW guestCart (prefs cleared, UI list emptied) while the UI only
      // ever reads guestCart — so the cart looked empty until the next add.
      // Drift is now a mirror, guestCart stays the UI truth:
      // prefs -> Drift when prefs has rows, Drift -> guestCart otherwise.
      if (guestCart.isNotEmpty) {
        for (final item in guestCart) {
          try {
            await _localCart!.addItem(local_cart.CartItem.fromMap(item));
          } catch (_) {}
        }
      } else if (_localCart!.items.isNotEmpty) {
        guestCart = _localCart!.items.map((c) => c.toMap()).toList();
        _attachVariantLabels(guestCart);
        try {
          await store.writeJson('guest_cart', guestCart);
        } catch (_) {}
      }
    }
    mark('localCart');
    // Offline-first cold start: paint every usable persisted document BEFORE
    // any network request, so a start without connectivity still shows the
    // last visited shop, categories, and the current account's favorites.
    // TTLs only decide whether a background refresh is triggered ? they never
    // hide persisted rows (see loadShop/loadRootCategories).
    _paintStaleShopFromCache();
    _paintStaleCategoriesFromCache();
    _paintStaleCitiesFromCache();
    _paintStaleSettingsFlagsFromCache();
    await restoreCachedFavorites();
    mark('favoritesRestore');
    try {
      // Brand + session validation are independent: run together.
      final brandFuture = BrandService(apiUrl).load(prefs: _prefs);
      await Future.wait([
        brandFuture.then((b) => brand = b),
        validateSession(),
      ]);
      mark('brand+session');
      // Parallel bootstrap: settings + cities are independent.
      await Future.wait([reloadSettings(), loadCities()]);
      mark('settings+cities');
      await resolveCity();
      // If still no city and we have cities available, select the first one
      // so the app has a valid location even when starting offline without
      // prior city data. This ensures API calls use valid coordinates.
      if (city == null && cities.isNotEmpty) {
        await selectCity(normalizeCity(cities.first));
      }
      mark('resolveCity');
      // Shop + categories + hours are independent of each other.
      await Future.wait([
        loadShop(),
        loadRootCategories(),
        loadBusinessHours(),
      ]);
      mark('shop+cats+hours');
      if (isLoggedIn) {
        await Future.wait([loadAddresses(), refreshCart()]);
      }
      mark('addr+cart');
      await reconcileCheckoutSession();
      mark('checkout');
      bootstrapped = true;
      // Opportunistic best-effort catalog sync (never blocks startup, never
      // throws, no-op while the cutover flag is off). Deferred a few seconds:
      // a cold start already paints cached rows and fires its own network
      // page loads — a full catalog walk competing for the radio/CPU in the
      // first seconds is what made startup feel sluggish.
      unawaited(
        Future<void>.delayed(const Duration(seconds: 10), syncCatalogSoon),
      );
    } catch (error) {
      bootstrapError = '$error';
      bootstrapped = true;
    }
    _bumpChrome();
    _bumpNav();
    // Opportunistic replay of durable favorite ops (never checkout).
    kickSyncDelayed(const Duration(seconds: 3));
    notifyListeners();
    mark('done');
  }

  /// Validates the stored session against the backend. Proven auth failures
  /// (401/403) clear the session; offline/transient failures keep it (token
  /// + last user snapshot) so airplane restarts stay logged in with saved
  /// data instead of wiping login on every network blip.
  @visibleForTesting
  Future<void> validateSession() async {
    if (token == null) return;
    final scope = accountScope;
    final me = await api.userDetails();
    if (scope != accountScope) return;
    if (me.ok) {
      user = me.user.isNotEmpty ? me.user : me.dataMap;
      try {
        await offline.writeDoc(
          OfflineCache.snapshotKey('user::$scope'),
          user,
          scope: scope,
        );
      } catch (_) {}
    } else if (me.classifiedError?.category == ApiErrorCategory.auth) {
      await _clearSession();
    } else {
      if (user == null) {
        try {
          final snap = offline.readDoc(
            OfflineCache.snapshotKey('user::$scope'),
          );
          if (snap?.scope == scope && snap?.payload is Map) {
            user = J.map(snap?.payload);
          }
        } catch (_) {}
      }
    }
  }

  /// Runs the outbox with the safe executor (favorites/cart-merge only).
  Future<void> kickSync() => sync.run(executor: runPendingOp);

  void kickSyncDelayed(Duration delay) {
    Future<void>.delayed(delay, () {
      try {
        sync.run(executor: runPendingOp);
      } catch (_) {}
    });
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
    _bumpChrome();
    notifyListeners();
  }

  String t(String key) => i18n.t(key);

  Future<void> reloadSettings() async {
    final scope = accountScope;
    final loggedIn = isLoggedIn;
    final result = await api.settings(withAuth: loggedIn);
    if (scope != accountScope) return;
    if (result.ok) {
      var data = result.dataMap;
      if (data['web_settings'] is List) {
        data['web_settings'] = <String, dynamic>{};
      }
      if (data['firebase'] is List) {
        data['firebase'] = <String, dynamic>{};
      }
      settings = data;
      try {
        final sellerUrl = J.str(data['seller_android_app_url']);
        if (sellerUrl.isNotEmpty) {
          await _prefs.setString('seller_app_url', sellerUrl);
        }
        Future<void> saveFlag(String key, dynamic raw) async {
          if (raw == null) return;
          await _prefs.setInt(key, J.flag(raw) ? 1 : 0);
        }

        final catalogMode = J.str(
          data['catalog_mode'] ?? J.map(data['web_settings'])['catalog_mode'],
        );
        if (catalogMode.isNotEmpty) {
          await _prefs.setString('set_catalog_mode', catalogMode);
        }
        final currency = J.str(data['currency']);
        if (currency.isNotEmpty) {
          await _prefs.setString('set_currency', currency);
        }
        if (data['decimal_point'] != null) {
          await _prefs.setInt('set_decimals', J.i(data['decimal_point'], 2));
        }
        await saveFlag('flag_one_seller', data['one_seller_cart']);
        await saveFlag('flag_akhdimni', data['akhdimni_enabled']);
        await saveFlag(
          'flag_akhdimni_p2p',
          data['akhdimni_point_to_point_enabled'],
        );
        await saveFlag(
          'flag_akhdimni_special',
          data['akhdimni_special_items_enabled'],
        );
        await saveFlag('flag_order_tracking', data['order_tracking_enabled']);
      } catch (_) {}
      // Server is authoritative for favorites, but deliberate offline toggles
      // queued in the outbox must survive a stale server snapshot: pending
      // adds are re-applied on top, pending removals are filtered out, so
      // newer local intent is never wiped before the outbox replays.
      var serverFavs = J.list(data['favorite_product_ids']);
      try {
        final pending = PendingOutbox(store, scope).load();
        final pendingAdds = pending
            .where((o) => o.type == PendingOpType.favoriteAdd)
            .map((o) => '${o.payload['product_id']}')
            .where((id) => id.isNotEmpty && id != 'null')
            .toSet();
        final pendingRemoves = pending
            .where((o) => o.type == PendingOpType.favoriteRemove)
            .map((o) => '${o.payload['product_id']}')
            .where((id) => id.isNotEmpty && id != 'null')
            .toSet();
        if (pendingAdds.isNotEmpty || pendingRemoves.isNotEmpty) {
          final merged = <dynamic>[...serverFavs];
          final seen = merged.map((e) => '$e').toSet();
          for (final id in pendingAdds) {
            if (!seen.contains(id)) {
              merged.add(id);
              seen.add(id);
            }
          }
          if (pendingRemoves.isNotEmpty) {
            merged.removeWhere((e) => pendingRemoves.contains('$e'));
          }
          serverFavs = merged;
        }
      } catch (_) {}
      favoriteIds = serverFavs;
      try {
        await offline.writeDoc(
          OfflineCache.favoritesKey(scope),
          favoriteIds.toList(),
          scope: scope,
        );
      } catch (_) {}
      _bumpChrome();
      checkoutConfig = CheckoutConfig.fromSettings(data);
      final hoursRaw = data['business_hours'];
      if (hoursRaw is Map) {
        businessHours = BusinessHoursResult.fromMap(J.map(hoursRaw));
      }
    } else {
      // Refresh failed (offline/timeout): fall back to the last persisted
      // favorites for this account instead of leaving an empty list.
      await restoreCachedFavorites();
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
    if (result.ok && result.dataMaps.isNotEmpty) {
      cities = result.dataMaps;
      try {
        final dump = jsonEncode(cities);
        // Cities are small global rows; guard anyway for device safety.
        if (dump.length < 200 * 1024) {
          await _prefs.setString('cities_cache', dump);
        }
      } catch (_) {}
    } else {
      // Refresh failed: keep previously painted (stale) rows when available.
      _paintStaleCitiesFromCache();
    }
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
    _bumpNav();
    notifyListeners();
    await Future.wait([loadShop(), loadRootCategories()]);
    if (isLoggedIn) await refreshCart();
    // New city scope: start a best-effort sync so offline browsing follows
    // the city switch (old scopes are retained, reads use the new scope).
    syncCatalogSoon();
  }

  /// Paints the last persisted shop document regardless of age (cold-start
  /// offline support). Returns true when usable rows were painted.
  /// Staleness is signalled by the UI badge; a background refresh follows
  /// whenever the TTL has expired (see [loadShop]).
  bool _paintStaleShopFromCache() {
    try {
      final raw = _prefs.getString('shop_cache');
      if (raw == null || raw.isEmpty) return false;
      final decoded = J.map(jsonDecode(raw));
      if (decoded.isEmpty) return false;
      shop ??= decoded;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Paints the last persisted cities list (global, non-sensitive) so the
  /// city picker stays usable offline. Returns true when rows were painted.
  bool _paintStaleCitiesFromCache() {
    try {
      final raw = _prefs.getString('cities_cache');
      if (raw == null || raw.isEmpty) return false;
      final decoded = J.maps(jsonDecode(raw));
      if (decoded.isEmpty) return false;
      if (cities.isEmpty) {
        cities = decoded;
        citiesLoaded = true;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Paints the last persisted categories regardless of age. Returns true
  /// when usable rows were painted.
  bool _paintStaleCategoriesFromCache() {
    try {
      final raw = _prefs.getString('cats_cache');
      if (raw == null || raw.isEmpty) return false;
      final decoded = J.maps(jsonDecode(raw));
      if (decoded.isEmpty) return false;
      if (rootCategories.isEmpty) rootCategories = decoded;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Paints last persisted feature flags (tab visibility, tracking) so the
  /// bottom bar and feature tiles match the last known server state on an
  /// offline cold start instead of silently dropping tabs.
  void _paintStaleSettingsFlagsFromCache() {
    try {
      int? flag(String key) {
        if (!_prefs.containsKey(key)) return null;
        return _prefs.getInt(key);
      }

      final oneSeller = flag('flag_one_seller');
      if (oneSeller != null) settings['one_seller_cart'] = oneSeller;
      final akhdimni = flag('flag_akhdimni');
      if (akhdimni != null) settings['akhdimni_enabled'] = akhdimni;
      final p2p = flag('flag_akhdimni_p2p');
      if (p2p != null) settings['akhdimni_point_to_point_enabled'] = p2p;
      final special = flag('flag_akhdimni_special');
      if (special != null) settings['akhdimni_special_items_enabled'] = special;
      final tracking = flag('flag_order_tracking');
      if (tracking != null) settings['order_tracking_enabled'] = tracking;
      if (_prefs.containsKey('set_catalog_mode')) {
        final mode = _prefs.getString('set_catalog_mode');
        if (mode != null && mode.isNotEmpty) settings['catalog_mode'] = mode;
      }
      if (_prefs.containsKey('set_currency')) {
        final cur = _prefs.getString('set_currency');
        if (cur != null && cur.isNotEmpty) settings['currency'] = cur;
      }
      if (_prefs.containsKey('set_decimals')) {
        final dec = _prefs.getInt('set_decimals');
        if (dec != null) settings['decimal_point'] = dec;
      }
    } catch (_) {}
  }

  /// Stale-while-revalidate shop: paints cached home instantly (any age),
  /// then refreshes in background when the 2-minute freshness TTL expired.
  /// A failed refresh NEVER clears the painted rows — stale content stays
  /// visible with an offline/stale badge instead of an empty screen.
  Future<void> loadShop({bool force = false}) async {
    if (!force) {
      try {
        final raw = _prefs.getString('shop_cache');
        final at = _prefs.getInt('shop_cache_at') ?? 0;
        if (raw != null && raw.isNotEmpty) {
          final decoded = J.map(jsonDecode(raw));
          if (decoded.isNotEmpty) {
            final ageOk =
                DateTime.now().millisecondsSinceEpoch - at <
                const Duration(minutes: 2).inMilliseconds;
            shop = decoded;
            notifyListeners();
            if (ageOk) {
              // Fresh: revalidate silently without blocking the UI.
              _refreshShopInBackground();
              return;
            }
            // Stale but usable: keep painted, refresh below (foreground so
            // pull-to-refresh resolves), preserving rows on failure.
          } else {
            // Empty cache entry: keep previously painted shop if any.
          }
        } else {
          // No cache entry: keep previously painted shop if any.
        }
      } catch (_) {
        // Keep previously painted shop if any.
      }
      // If shop is still null after cache check, try previously painted value
      // from an older cycle (defensive: never show empty shop on cold-start
      // if we had data from a prior session).
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
            'shop_cache_at',
            DateTime.now().millisecondsSinceEpoch,
          );
        }
      } catch (_) {}
    } else if (shop == null) {
      // Last resort: try to recover from ancient cache (no TTL check).
      try {
        final ancientRaw = _prefs.getString('shop_cache');
        if (ancientRaw != null && ancientRaw.isNotEmpty) {
          shop = J.map(jsonDecode(ancientRaw));
          notifyListeners();
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
              'shop_cache_at',
              DateTime.now().millisecondsSinceEpoch,
            );
          }
        } catch (_) {}
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Stale-while-revalidate categories: paints persisted rows of any age,
  /// then refreshes when the 10-minute TTL expired. Failed refreshes keep
  /// the painted rows; only a successful response replaces them.
  Future<void> loadRootCategories({bool force = false}) async {
    if (!force) {
      try {
        final raw = _prefs.getString('cats_cache');
        final at = _prefs.getInt('cats_cache_at') ?? 0;
        if (raw != null && raw.isNotEmpty) {
          final decoded = J.maps(jsonDecode(raw));
          if (decoded.isNotEmpty) {
            rootCategories = decoded;
            notifyListeners();
            final ageOk =
                DateTime.now().millisecondsSinceEpoch - at <
                const Duration(minutes: 10).inMilliseconds;
            if (ageOk) {
              _refreshCategoriesInBackground();
              return;
            }
            // Stale: fall through to foreground refresh, keep rows on failure.
          } else {
            // Empty cache entry: keep previously painted categories if any.
          }
        } else {
          // No cache entry: keep previously painted categories if any.
        }
      } catch (_) {
        // Keep previously painted categories if any.
      }
      // If rootCategories is still empty after cache check, try previously
      // painted value from an older cycle (defensive: never show empty
      // categories on cold-start if we had data from a prior session).
    }
    final result = await api.categories(categoryId: 0, limit: 50, offset: 0);
    if (result.ok) {
      rootCategories = result.dataMaps;
      try {
        var dump = jsonEncode(rootCategories);
        if (dump.length < 200 * 1024) {
          await _prefs.setString('cats_cache', dump);
          await _prefs.setInt(
            'cats_cache_at',
            DateTime.now().millisecondsSinceEpoch,
          );
        }
      } catch (_) {}
    } else if (rootCategories.isEmpty) {
      // Last resort: try to recover from ancient cache (no TTL check).
      try {
        final ancientRaw = _prefs.getString('cats_cache');
        if (ancientRaw != null && ancientRaw.isNotEmpty) {
          rootCategories = J.maps(jsonDecode(ancientRaw));
          notifyListeners();
        }
      } catch (_) {}
    }
    // On failure the rows painted above are kept (never cleared here).
    notifyListeners();
  }

  Future<void> _refreshCategoriesInBackground() async {
    try {
      final result = await api.categories(categoryId: 0, limit: 50, offset: 0);
      if (result.ok && result.dataMaps.isNotEmpty) {
        rootCategories = result.dataMaps;
        try {
          var dump = jsonEncode(rootCategories);
          if (dump.length < 200 * 1024) {
            await _prefs.setString('cats_cache', dump);
            await _prefs.setInt(
              'cats_cache_at',
              DateTime.now().millisecondsSinceEpoch,
            );
          }
        } catch (_) {}
        notifyListeners();
      }
    } catch (_) {}
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
        // ignore: use_null_aware_elements
        if (productId != null) 'product_id': productId,
        'product_variant_id': variantId,
        'qty': qty,
        // ignore: use_null_aware_elements
        if (sellerId != null) 'seller_id': sellerId,
        // Display + totals read `price`; keep both keys so optimistic lines
        // never flash as 0 before the server confirms them.
        // ignore: use_null_aware_elements
        if (productPrice != null) 'price': productPrice,
        // ignore: use_null_aware_elements
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

  /// Drops a locally listed cart line that the server claims does not exist
  /// (see [removeCartLine] convergent removal). Strictly id-keyed and a
  /// no-op for null/empty ids, so it can never wipe an unrelated line.
  void _dropPhantomCartLine(dynamic variantId) {
    if (variantId == null) return;
    final key = '$variantId';
    if (key.isEmpty || key == 'null') return;
    final lines = isLoggedIn ? cartProducts : guestCart;
    final before = lines.length;
    lines.removeWhere((e) => '${e['product_variant_id'] ?? e['id']}' == key);
    if (lines.length != before) notifyListeners();
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

  /// Seller-set key for the add-path hours memo ([cartAddBlockedReason]).
  String _addHoursKey(dynamic sellerId) {
    final ids = <dynamic>[
      ..._sellerIdsFromCart(),
      // ignore: use_null_aware_elements
      if (sellerId != null) sellerId,
    ];
    return (ids.map((e) => '$e').toSet().toList()..sort()).join(',');
  }

  /// Warms the add-path hours memo (the same fetch [cartAddBlockedReason]
  /// would do). Lets [addToCart] run the hours fetch in parallel with the
  /// reachability probe. Failures are never memoized (businessHours stays
  /// null) so the next tap retries immediately.
  Future<void> _warmAddHours(dynamic sellerId) async {
    final hoursKey = _addHoursKey(sellerId);
    final lastCheck = _lastAddHoursAt;
    final hoursFresh =
        businessHours != null &&
        lastCheck != null &&
        _lastAddHoursKey == hoursKey &&
        DateTime.now().difference(lastCheck) < const Duration(seconds: 90);
    if (hoursFresh) return;
    final ids = <dynamic>[
      ..._sellerIdsFromCart(),
      // ignore: use_null_aware_elements
      if (sellerId != null) sellerId,
    ];
    await loadBusinessHours(sellerIds: ids);
    if (businessHours != null) {
      _lastAddHoursAt = DateTime.now();
      _lastAddHoursKey = hoursKey;
    }
  }

  /// Returns a user-facing reason when add-to-cart must be blocked.
  Future<String?> cartAddBlockedReason({
    dynamic sellerId,
    dynamic variantId,
    String storeName = '',
  }) async {
    await _warmAddHours(sellerId);
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
      return t(
        'max_stores_exceeded',
      ).replaceAll('{max}', '$maxSellersPerCheckout');
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
  Future<ApiResult> cancelCheckoutGroup(dynamic id, {String reason = ''}) =>
      api.cancelCheckoutGroup(id, reason: reason);

  CheckoutSession get checkoutSession {
    _checkoutSession ??= CheckoutSession(store, accountScope);
    return _checkoutSession!;
  }

  /// Stable idempotency key for the current logical checkout attempt.
  /// The SAME key is reused across retries/gateway steps; a fresh timestamp
  /// per tap would defeat server-side deduplication. Cleared only on
  /// authoritative success or explicit cancellation (see CheckoutSession).
  Future<String> checkoutKey({Map<String, dynamic>? context}) =>
      checkoutSession.begin(context: context);

  /// Deterministic fingerprint for the current cart snapshot. Changes whenever
  /// items, quantities, address, payment method, delivery slot, or promo code
  /// change, forcing a fresh idempotency key for a logically different order.
  String checkoutFingerprint({
    dynamic addressId,
    String? paymentMethod,
    String? deliveryTime,
    String? promoCodeId,
  }) => cartFingerprint(
    items: cartProducts,
    addressId: addressId,
    paymentMethod: paymentMethod,
    deliveryTime: deliveryTime,
    promoCodeId: promoCodeId,
  );

  /// Legacy alias (kept for compatibility): returns the persisted session key
  /// synchronously when available, otherwise a scoped fresh key. Prefer
  /// [checkoutKey] (async, persisted) for new code.
  String buildIdempotencyKey() {
    final existing = _checkoutSession?.key;
    if (existing != null) return existing;
    final uid = user?['id'] ?? 'guest';
    return 'checkout-$uid-${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> clearCheckoutSession() async {
    try {
      await checkoutSession.clear();
    } catch (_) {}
    _checkoutSession = null;
  }

  /// Called once at startup. If a checkout session exists, try to find a
  /// matching recent order. If found, the session is cleared; otherwise the
  /// unresolved flag is set so the UI can block resubmission until the user
  /// reconciles manually.
  Future<void> reconcileCheckoutSession() async {
    final key = checkoutSession.key;
    if (key == null) {
      unresolvedCheckout = false;
      return;
    }
    final exists = await hasRecentOrderForSession(key);
    if (exists) {
      await clearCheckoutSession();
      unresolvedCheckout = false;
    } else {
      unresolvedCheckout = true;
    }
  }

  Future<void> _invalidateCheckoutSession() async {
    if (_checkoutSession?.key != null || checkoutSession.key != null) {
      await clearCheckoutSession();
    }
  }

  /// Reconciles an uncertain checkout (timeout / crash / killed app) against
  /// the authoritative order history BEFORE offering resubmission, so a timed
  /// out request that actually succeeded never becomes a duplicate order.
  Future<bool> hasRecentOrderForSession(String sessionKey) async {
    try {
      final res = await api.orders(limit: 5, offset: 0);
      if (!res.ok) return false;
      for (final o in res.dataMaps) {
        if ('${o['idempotency_key']}' == sessionKey) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  CanPlaceOrderResult canPlaceOrder() =>
      canPlaceOrderFromBusinessHours(businessHours);

  Future<void> loadAddresses() async {
    if (!isLoggedIn) return;
    final scope = accountScope;
    // Paint cached addresses instantly (offline-first), then refresh.
    try {
      final cached = offline.readDoc(OfflineCache.addressesKey(accountScope));
      final payload = cached?.payload;
      if (payload is List && addresses.isEmpty) {
        addresses = J.maps(payload);
        selectedAddress ??= addresses.cast<Map<String, dynamic>?>().firstWhere(
          (item) => J.i(item?['is_default']) == 1,
          orElse: () => addresses.isNotEmpty ? addresses.first : null,
        );
        notifyListeners();
      }
    } catch (_) {}
    final result = await api.addresses();
    if (scope != accountScope) return;
    if (result.ok) {
      addresses = result.dataMaps;
      selectedAddress ??= addresses.cast<Map<String, dynamic>?>().firstWhere(
        (item) => J.i(item?['is_default']) == 1,
        orElse: () => addresses.isNotEmpty ? addresses.first : null,
      );
      try {
        await offline.writeDoc(
          OfflineCache.addressesKey(scope),
          addresses,
          scope: scope,
        );
      } catch (_) {}
    }
    notifyListeners();
  }

  // ---- Offline-first document helpers (local-first paint, network refresh) ----
  /// Hash includes the catalog [view] so seller rows (stores tab) can never
  /// be painted as product rows or vice versa (was a cache-key collision:
  /// both views shared the same key).
  String productPageHash(
    Map<String, dynamic> query, {
    String view = 'products',
  }) =>
      OfflineCache.queryHash({...query, 'view': view, 'city_id': city?['id']});

  Future<void> cacheProductPage(
    Map<String, dynamic> query,
    List<Map<String, dynamic>> items, {
    String view = 'products',
  }) async {
    try {
      // Bounded LRU writer: browsing never grows storage without limit.
      await offline.writeProductPage(
        OfflineCache.productsKey(productPageHash(query, view: view)),
        items,
      );
    } catch (_) {}
  }

  List<Map<String, dynamic>> readCachedProductPage(
    Map<String, dynamic> query, {
    String view = 'products',
  }) {
    try {
      final doc = offline.readDoc(
        OfflineCache.productsKey(productPageHash(query, view: view)),
      );
      final payload = doc?.payload;
      if (payload is List) return J.maps(payload);
    } catch (_) {}
    return [];
  }

  Future<void> cacheProductDetails(String id, Map<String, dynamic> data) async {
    try {
      await offline.writeProductDetails(
        OfflineCache.productDetailsKey(id),
        data,
      );
    } catch (_) {}
  }

  Map<String, dynamic>? readCachedProductDetails(String id) {
    try {
      final doc = offline.readDoc(OfflineCache.productDetailsKey(id));
      final payload = doc?.payload;
      if (payload is Map) return J.map(payload);
    } catch (_) {}
    return null;
  }

  bool isProductDetailsFresh(String id) {
    try {
      return offline.fresh(
        OfflineCache.productDetailsKey(id),
        CacheEntity.productDetails,
      );
    } catch (_) {
      return false;
    }
  }

  // ---- Local Drift catalog (public snapshots; account data never enters) ----
  /// Location scope for catalog reads/writes (`city:<id>` or `global`).
  String get catalogScope => catalogScopeForCity(city);

  /// Resolves the honest data state of the current catalog scope for empty
  /// states and retry controls. Never infers status from a row count alone:
  /// a zero count can mean disabled, failed, unsynchronized, or genuinely
  /// empty, and each needs different UI.
  Future<CatalogScopeState> catalogScopeState() async {
    final scope = catalogScope;
    if (catalogSync.progress.value.phase == CatalogSyncPhase.syncing &&
        catalogSync.progress.value.scope == scope) {
      return const CatalogScopeState(status: CatalogScopeStatus.syncing);
    }
    try {
      final db = await ensureCatalogDb();
      if (db == null) {
        return const CatalogScopeState(status: CatalogScopeStatus.neverSynced);
      }
      final dao = CatalogDao(db);
      final row = await dao.getSyncState(scope);
      if (row == null) {
        return const CatalogScopeState(status: CatalogScopeStatus.neverSynced);
      }
      final count = await dao.productCount(scope);
      final lastSyncAt = row.updatedAt;
      final stale =
          DateTime.now().difference(lastSyncAt) >
          CachePolicy.ttlOf(CacheEntity.productList);
      if (row.phase != 'full_complete') {
        return CatalogScopeState(
          status: CatalogScopeStatus.failed,
          lastSyncAt: lastSyncAt,
          listedCount: count,
          stale: true,
        );
      }
      // Count sections and haraj in current scope
      final sectionCount = await dao.sectionHarajCount(scope, 'section');
      final harajCount = await dao.sectionHarajCount(scope, 'haraj');
      final anySection = sectionCount > 0;
      final anyHaraj = harajCount > 0;
      if (count == 0 && !anySection && !anyHaraj) {
        return CatalogScopeState(
          status: CatalogScopeStatus.empty,
          lastSyncAt: lastSyncAt,
          listedCount: count,
          stale: stale,
          sectionCount: sectionCount,
          harajCount: harajCount,
        );
      }
      return CatalogScopeState(
        status: CatalogScopeStatus.ready,
        lastSyncAt: lastSyncAt,
        listedCount: count,
        stale: stale,
        sectionCount: sectionCount,
        harajCount: harajCount,
      );
    } catch (_) {
      return const CatalogScopeState(status: CatalogScopeStatus.neverSynced);
    }
  }

  /// Opens the catalog database when the cutover flag allows it. Returns null
  /// when disabled or unavailable — callers always fall back to JSON/network.
  Future<CatalogDatabase?> ensureCatalogDb() async {
    if (!CatalogDbConfig.enabledForUse) return null;
    final existing = _catalogDb;
    if (existing != null) return existing;
    try {
      _catalogDb = await openCatalogDbFile();
    } catch (_) {
      _catalogDb = null;
    }
    return _catalogDb;
  }

  /// Test seam: injects an (in-memory) catalog database directly.
  @visibleForTesting
  void setCatalogDbForTest(CatalogDatabase? db) {
    _catalogDb = db;
  }

  /// Best-effort sync of the current city scope in the background. Safe to
  /// call from bootstrap/city-change/pull-to-refresh: debounced, single
  /// flight, never throws, never blocks the UI.
  ///
  /// The debounce is PERSISTED: a full walk rewrites every catalog row plus
  /// FTS, so it must not restart on every cold start (it previously did,
  /// because the timestamp lived only in memory).
  Future<void> syncCatalogSoon() async {
    if (!CatalogDbConfig.enabledForUse) return;
    final now = DateTime.now();
    final last = _lastCatalogSyncAttempt ?? _readLastCatalogSyncAttempt();
    if (last != null && now.difference(last) < _catalogSyncMinInterval) {
      return;
    }
    _lastCatalogSyncAttempt = now;
    unawaited(_persistLastCatalogSyncAttempt(now));
    try {
      await syncCatalogNow();
    } catch (_) {}
  }

  static const Duration _catalogSyncMinInterval = Duration(minutes: 30);
  static const String _kLastCatalogSyncAttempt = 'catalog_sync_attempt_at';

  DateTime? _readLastCatalogSyncAttempt() {
    try {
      final raw = _prefs.getString(_kLastCatalogSyncAttempt);
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistLastCatalogSyncAttempt(DateTime at) async {
    try {
      await _prefs.setString(
        _kLastCatalogSyncAttempt,
        at.toUtc().toIso8601String(),
      );
    } catch (_) {}
  }

  Future<CatalogSyncResult?> syncCatalogNow() async {
    final db = await ensureCatalogDb();
    if (db == null) return null;
    final scope = catalogScope;
    final point = browseCoords;
    Future<CatalogPage> fetchProducts({
      required int limit,
      required int offset,
    }) async {
      try {
        final res = await api.products(
          latitude: point.latitude,
          longitude: point.longitude,
          filters: {'limit': limit, 'offset': offset, 'sort': 'old'},
        );
        if (!res.ok) {
          // Past-end pages (and genuinely empty catalogs) arrive as
          // status:0 + empty signal with no rows — clean end, not failure.
          if (isEmptyCatalogPage(res)) {
            return CatalogPage(rows: const [], total: offset);
          }
          return CatalogPage(rows: const [], ok: false, error: res.message);
        }
        final total = J.i(res.raw['total'] ?? res.dataMap['total'], -1);
        return CatalogPage(rows: res.dataMaps, total: total);
      } catch (e) {
        return CatalogPage(rows: const [], ok: false, error: '$e');
      }
    }

    Future<CatalogPage> fetchStores({
      required int limit,
      required int offset,
    }) async {
      try {
        final res = await api.sellers(
          latitude: point.latitude,
          longitude: point.longitude,
          limit: limit,
          offset: offset,
        );
        if (!res.ok) {
          return CatalogPage(rows: const [], ok: false, error: res.message);
        }
        var rows = res.dataMaps;
        var total = J.i(res.raw['total'] ?? res.dataMap['total'], -1);
        final node = res.raw['data'];
        if (rows.isEmpty && node is Map) {
          rows = J.maps(node['data']);
          total = J.i(node['total'] ?? total, -1);
        }
        return CatalogPage(rows: rows, total: total);
      } catch (e) {
        return CatalogPage(rows: const [], ok: false, error: '$e');
      }
    }

    Future<CatalogPage> fetchCategories({
      required int limit,
      required int offset,
    }) async {
      try {
        final res = await api.categories(
          categoryId: 0,
          limit: limit,
          offset: offset,
        );
        if (!res.ok) {
          // Same past-end/empty convention as products (verified live).
          if (isEmptyCatalogPage(res)) {
            return CatalogPage(rows: const [], total: offset);
          }
          return CatalogPage(rows: const [], ok: false, error: res.message);
        }
        // Prefer the server total (response envelope) so walks past the
        // first page work; fall back to the page length for compat.
        final total = J.i(
          res.raw['total'] ?? res.dataMap['total'],
          res.dataMaps.length,
        );
        return CatalogPage(rows: res.dataMaps, total: total);
      } catch (e) {
        return CatalogPage(rows: const [], ok: false, error: '$e');
      }
    }

    final swSync = Diag.enabled ? (Stopwatch()..start()) : null;
    final result = await catalogSync.syncScope(
      db: db,
      scope: scope,
      fetchProducts: fetchProducts,
      fetchStores: fetchStores,
      fetchCategories: fetchCategories,
    );
    if (swSync != null) {
      Diag.log(
        'sync:catalog',
        '${swSync.elapsedMilliseconds}ms complete=${result.complete} '
        'products=${result.products} stores=${result.stores} '
        'categories=${result.categories} error=${result.error}',
      );
    }
    notifyListeners();
    // Bounded thumbnails: only after a completed sync, and only after the
    // UI has had time to settle — never while the user is scrolling/browsing.
    if (result.complete) {
      unawaited(
        Future<void>.delayed(
          const Duration(seconds: 20),
          prefetchCatalogImages,
        ),
      );
    }
    return result;
  }

  /// Downloads newest catalog thumbnails automatically after every
  /// completed sync. Fire-and-forget, bounded, best-effort — catalog data
  /// never waits for images.
  Future<void> prefetchCatalogImages() async {
    try {
      final db = await ensureCatalogDb();
      if (db == null) return;
      await ImagePrefetch.reconcile(db);
      final rows = await CatalogDao(db).listProducts(catalogScope, limit: 100);
      final urls = <String>[];
      for (final p in rows) {
        final u = p.thumbnailUrl;
        if (u != null && u.isNotEmpty) urls.add(u);
      }
      await imagePrefetch.prefetch(urls, db: db);
    } catch (_) {}
  }

  /// Local product rows for offline browsing (synchronized scope only).
  /// Applies text/category/store scoping in the database, remaining filters
  /// and sorting in memory. Returns [] when the catalog is disabled, empty,
  /// or unsynchronized for this scope.
  Future<List<Map<String, dynamic>>> catalogProductsLocal({
    int? categoryId,
    int? storeId,
    String search = '',
    String sort = '',
    String sectionId = '',
    String sellerSectionId = '',
    String priceMin = '',
    String priceMax = '',
    String minRating = '',
    bool inStock = false,
    bool onlyOffers = false,
    bool canDeliver = false,
    bool isReturnable = false,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final db = await ensureCatalogDb();
      if (db == null) return [];
      // Filtering, sorting, and pagination all happen in SQL over the full
      // listed set — matches beyond the first window are never hidden.
      final found = await CatalogDao(db).queryProducts(
        catalogScope,
        categoryId: categoryId,
        storeId: storeId,
        search: search,
        sort: sort,
        sectionId: sectionId,
        sellerSectionId: sellerSectionId,
        priceMin: double.tryParse(priceMin),
        priceMax: double.tryParse(priceMax),
        minRating: double.tryParse(minRating),
        inStockOnly: inStock,
        offersOnly: onlyOffers,
        canDeliverOnly: canDeliver,
        returnableOnly: isReturnable,
        limit: limit,
        offset: offset,
      );
      return found.map((p) => J.map(jsonDecode(p.payload))).toList();
    } catch (_) {
      return [];
    }
  }

  /// Number of listed products matching the same filters as
  /// [catalogProductsLocal] (without paging). Drives result counts and the
  /// empty-state distinction together with [catalogScopeState].
  Future<int> catalogFilteredCountLocal({
    int? categoryId,
    int? storeId,
    String search = '',
    String sectionId = '',
    String sellerSectionId = '',
    String priceMin = '',
    String priceMax = '',
    String minRating = '',
    bool inStock = false,
    bool onlyOffers = false,
    bool canDeliver = false,
    bool isReturnable = false,
  }) async {
    try {
      final db = await ensureCatalogDb();
      if (db == null) return 0;
      return await CatalogDao(db).countProducts(
        catalogScope,
        categoryId: categoryId,
        storeId: storeId,
        search: search,
        sectionId: sectionId,
        sellerSectionId: sellerSectionId,
        priceMin: double.tryParse(priceMin),
        priceMax: double.tryParse(priceMax),
        minRating: double.tryParse(minRating),
        inStockOnly: inStock,
        offersOnly: onlyOffers,
        canDeliverOnly: canDeliver,
        returnableOnly: isReturnable,
      );
    } catch (_) {
      return 0;
    }
  }

  /// Offline product lookup by id or slug (synchronized rows only — covers
  /// products the user never opened, unlike the visit-scoped JSON cache).
  Future<Map<String, dynamic>?> catalogProductLocal({
    int? id,
    String slug = '',
  }) async {
    try {
      final db = await ensureCatalogDb();
      if (db == null) return null;
      final dao = CatalogDao(db);
      final scope = catalogScope;
      if (id != null && id > 0) {
        final p = await dao.getProductById(scope, id);
        if (p != null) return J.map(jsonDecode(p.payload));
      }
      if (slug.isNotEmpty) {
        final p = await dao.getProductBySlug(scope, slug);
        if (p != null) return J.map(jsonDecode(p.payload));
      }
    } catch (_) {}
    return null;
  }

  /// Number of synchronized products for the current scope. Used to
  /// distinguish "no synchronized data yet" from "no results for query".
  Future<int> catalogProductCountLocal() async {
    try {
      final db = await ensureCatalogDb();
      if (db == null) return 0;
      return await CatalogDao(db).productCount(catalogScope);
    } catch (_) {
      return 0;
    }
  }

  /// Offline store rows + lookups for the synchronized scope. Applies the same
  /// type/rating/sort filters as the online sellers request, then pages in
  /// memory (the stores table is small and always fully walked). The `type`
  /// filter keeps stores that have at least one listed product in that
  /// category, mirroring the server's seller-type semantics.
  Future<List<Map<String, dynamic>>> catalogStoresLocal({
    int limit = 50,
    int offset = 0,
    String type = '',
    String minRating = '',
    String sort = '',
  }) async {
    try {
      final db = await ensureCatalogDb();
      if (db == null) return [];
      final dao = CatalogDao(db);
      Set<int>? allowed;
      final typeId = int.tryParse(type);
      if (typeId != null && typeId > 0) {
        allowed = await dao.storeIdsWithCategory(catalogScope, typeId);
      }
      final found = await dao.allStores(catalogScope);
      var rows = found.map((s) {
        try {
          final m = J.map(jsonDecode(s.payload));
          if (m.isNotEmpty) return m;
        } catch (_) {}
        return <String, dynamic>{
          'id': s.serverId,
          'name': s.name,
          'slug': s.slug,
          'latitude': s.latitude,
          'longitude': s.longitude,
          'rating': s.rating,
          'status': s.status,
        };
      }).toList();
      if (allowed != null) {
        rows = rows
            .where((m) => allowed!.contains(J.i(m['id'] ?? m['seller_id'])))
            .toList();
      }
      final minR = double.tryParse(minRating);
      if (minR != null && minR > 0) {
        rows = rows.where((m) => _storeRating(m) >= minR).toList();
      }
      switch (sort) {
        case 'nearest':
        case 'rating':
          rows.sort((a, b) => _storeRating(b).compareTo(_storeRating(a)));
          break;
        case 'name':
          rows.sort(
            (a, b) => J.str(a['store_name'] ?? a['name'])
                .toLowerCase()
                .compareTo(J.str(b['store_name'] ?? b['name']).toLowerCase()),
          );
          break;
      }
      if (offset > 0) {
        rows = offset >= rows.length ? [] : rows.sublist(offset);
      }
      if (rows.length > limit) {
        rows = rows.sublist(0, limit);
      }
      return rows;
    } catch (_) {
      return [];
    }
  }

  double _storeRating(Map<String, dynamic> m) =>
      double.tryParse('${m['average_rating'] ?? m['rating'] ?? ''}') ?? 0;

  Future<Map<String, dynamic>?> catalogStoreLocal({
    int? id,
    String slug = '',
  }) async {
    try {
      final db = await ensureCatalogDb();
      if (db == null) return null;
      final dao = CatalogDao(db);
      final scope = catalogScope;
      if (id != null && id > 0) {
        final s = await dao.getStoreById(scope, id);
        if (s != null) {
          try {
            final m = J.map(jsonDecode(s.payload));
            if (m.isNotEmpty) return m;
          } catch (_) {}
          return <String, dynamic>{'id': s.serverId, 'name': s.name};
        }
      }
      if (slug.isNotEmpty) {
        final s = await dao.getStoreBySlug(scope, slug);
        if (s != null) {
          try {
            final m = J.map(jsonDecode(s.payload));
            if (m.isNotEmpty) return m;
          } catch (_) {}
          return <String, dynamic>{'id': s.serverId, 'name': s.name};
        }
      }
    } catch (_) {}
    return null;
  }

  /// Offline categories for the synchronized scope.
  Future<List<Map<String, dynamic>>> catalogCategoriesLocal() async {
    try {
      final db = await ensureCatalogDb();
      if (db == null) return [];
      final found = await CatalogDao(db).listCategories(catalogScope);
      return found
          .map(
            (c) => <String, dynamic>{
              'id': c.serverId,
              'name': c.name,
              'slug': c.slug,
              'image': c.imageUrl,
              'parent_id': c.parentId,
              'row_order': c.rowOrder,
            },
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ---- Generic snapshots for non-catalog domains ----
  /// Public (global) snapshot: sliders, offers, campaigns, sections, FAQs,
  /// CMS pages. Small display documents with no account data.
  Future<void> cachePublicSnapshot(String name, dynamic payload) async {
    try {
      await offline.writeDoc(
        OfflineCache.snapshotKey(name),
        payload,
        scope: 'global',
      );
    } catch (_) {}
  }

  dynamic readPublicSnapshot(String name) {
    try {
      return offline.readDoc(OfflineCache.snapshotKey(name))?.payload;
    } catch (_) {
      return null;
    }
  }

  /// Account-scoped snapshot (orders-like privacy): never painted across
  /// accounts. The owning scope is embedded in the key and verified on read.
  Future<void> cacheAccountSnapshot(String name, dynamic payload) async {
    final scope = accountScope;
    try {
      await offline.writeDoc(
        OfflineCache.snapshotKey('$name::$scope'),
        payload,
        scope: scope,
      );
    } catch (_) {}
  }

  dynamic readAccountSnapshot(String name) {
    final scope = accountScope;
    try {
      final doc = offline.readDoc(OfflineCache.snapshotKey('$name::$scope'));
      if (doc?.scope != scope) return null;
      return doc?.payload;
    } catch (_) {
      return null;
    }
  }

  /// Deletes one account-scoped snapshot (e.g. assistant "new chat").
  Future<void> removeAccountSnapshot(String name) async {
    final scope = accountScope;
    try {
      await offline.removeDoc(OfflineCache.snapshotKey('$name::$scope'));
    } catch (_) {}
  }

  // ---- Recent searches (global, non-sensitive) ----
  static const int maxRecentSearches = 10;

  List<String> recentSearches() {
    try {
      final raw = store.readJson('recent_searches');
      if (raw is List) {
        return raw
            .map((e) => '$e'.trim())
            .where((e) => e.isNotEmpty)
            .take(maxRecentSearches)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> addRecentSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    try {
      final current = recentSearches()
          .where((e) => e.toLowerCase() != q.toLowerCase())
          .toList();
      current.insert(0, q);
      await store.writeJson(
        'recent_searches',
        current.take(maxRecentSearches).toList(),
      );
    } catch (_) {}
  }

  Future<void> cacheOrders(
    List<Map<String, dynamic>> activeOrders,
    List<Map<String, dynamic>> previousOrders,
  ) async {
    // Never let an empty/failed refresh erase the last good snapshot:
    // callers must only invoke this with confirmed rows (see OrdersScreen).
    if (activeOrders.isEmpty && previousOrders.isEmpty) return;
    try {
      await offline.writeDoc(OfflineCache.ordersKey(accountScope), {
        'active': activeOrders,
        'previous': previousOrders,
      }, scope: accountScope);
    } catch (_) {}
  }

  ({List<Map<String, dynamic>> active, List<Map<String, dynamic>> previous})
  readCachedOrders() {
    try {
      final doc = offline.readDoc(OfflineCache.ordersKey(accountScope));
      final payload = doc?.payload;
      if (payload is Map) {
        final m = J.map(payload);
        // Scope guard: never paint another account's orders.
        if (doc?.scope != accountScope) {
          return (active: [], previous: []);
        }
        return (active: J.maps(m['active']), previous: J.maps(m['previous']));
      }
    } catch (_) {}
    return (active: [], previous: []);
  }

  /// Wishlist (full product rows) cache-first helpers. Favorite *ids* are
  /// cached via reloadSettings/toggleFavorite; these helpers persist the full
  /// product rows so the wishlist screen can paint offline.
  Future<void> cacheWishlist(List<Map<String, dynamic>> items) async {
    if (!isLoggedIn || items.isEmpty) return;
    try {
      await offline.writeDoc(
        OfflineCache.wishlistKey(accountScope),
        items,
        scope: accountScope,
      );
    } catch (_) {}
  }

  List<Map<String, dynamic>> readCachedWishlist() {
    try {
      final doc = offline.readDoc(OfflineCache.wishlistKey(accountScope));
      if (doc?.scope != accountScope) return [];
      final payload = doc?.payload;
      if (payload is List) return J.maps(payload);
    } catch (_) {}
    return [];
  }

  /// Last-known notifications page (account-scoped). Notifications stay
  /// server-authoritative; the cache only prevents an empty screen when a
  /// refresh fails offline.
  Future<void> cacheNotifications(List<Map<String, dynamic>> items) async {
    if (!isLoggedIn || items.isEmpty) return;
    try {
      await offline.writeDoc(
        OfflineCache.notificationsKey(accountScope),
        items,
        scope: accountScope,
      );
    } catch (_) {}
  }

  List<Map<String, dynamic>> readCachedNotifications() {
    try {
      final doc = offline.readDoc(OfflineCache.notificationsKey(accountScope));
      if (doc?.scope != accountScope) return [];
      final payload = doc?.payload;
      if (payload is List) return J.maps(payload);
    } catch (_) {}
    return [];
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
    final result = await api.loginMobile(
      mobile: mobile,
      password: password,
      fcm: fcmToken,
    );
    if (!result.ok) {
      if (result.classifiedError?.category == ApiErrorCategory.network) {
        return kRequiresInternet;
      }
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
    if (!result.ok) {
      if (result.classifiedError?.category == ApiErrorCategory.network) {
        return kRequiresInternet;
      }
      return result.message;
    }
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
    if (!result.ok) {
      if (result.classifiedError?.category == ApiErrorCategory.network) {
        return kRequiresInternet;
      }
      return result.message;
    }
    return null;
  }

  Future<void> _applyAuth(ApiResult result) async {
    await _persistAuth(result);
    // Post-login refresh runs in the background: login completion (and the
    // navigation that follows it) must never depend on settings/shop/cart
    // round-trips. A stalled auxiliary call previously left the login screen
    // stuck despite a valid server session (D1). Every refresh step below is
    // idempotent and individually guarded, so concurrent/duplicate runs are
    // safe (e.g. rapid repeated taps).
    unawaited(_refreshAfterAuth());
  }

  /// Normalizes the signed-in user map. Login/register responses nest the
  /// profile as `data.user` while `ApiResult.user` only reads a top-level
  /// `user` key, so without this the controller would keep an id-less map
  /// (wrong account scope + wrong snapshot key) even though the token is
  /// valid.
  Map<String, dynamic> _normalizeAuthUser(ApiResult result) {
    final top = result.user.isNotEmpty ? result.user : result.dataMap;
    if (top['id'] != null) return top;
    final nested = J.map(top['user']);
    if (nested['id'] != null) return nested;
    return top;
  }

  /// Durable session persistence. Awaited by login/register: navigation only
  /// proceeds once token + profile + secure storage are committed.
  Future<void> _persistAuth(ApiResult result) async {
    token = result.token;
    if (token == null || token!.isEmpty) {
      throw StateError('missing_token');
    }
    user = _normalizeAuthUser(result);
    try {
      await offline.writeDoc(
        OfflineCache.snapshotKey('user::$accountScope'),
        user,
        scope: accountScope,
      );
    } catch (_) {}
    api.setToken(token);
    try {
      await vault.write(token!);
    } on TokenVaultException {
      token = null;
      user = null;
      api.setToken(null);
      rethrow;
    }
    _checkoutSession = null;
    // New account scope: restore that account's persisted favorites BEFORE
    // the network refresh, so the wishlist paints instantly and offline
    // toggles are not lost when the refresh races or fails.
    favoriteIds = [];
    await restoreCachedFavorites();
    _bumpNav();
    notifyListeners();
  }

  /// Best-effort post-login refresh (fire-and-forget). Order matches the
  /// previous inline sequence: FCM binding, one-shot guest-cart merge, then
  /// settings/city/shop/cart refreshes and an outbox kick.
  Future<void> _refreshAfterAuth() async {
    try {
      if (fcmToken.isNotEmpty) {
        await api.updateFcmToken(fcmToken);
      }
    } catch (_) {}
    // Guest->account cart migration: attempt once during login. Because
    // bulkAddToCart is NOT idempotent, we never enqueue an automatic retry;
    // the guest cart is kept until the next successful login merge or until
    // the user clears it manually.
    if (guestCart.isNotEmpty) {
      try {
        final pending = List<Map<String, dynamic>>.from(guestCart);
        final ids = pending
            .map((item) => '${item['product_variant_id']}')
            .join(',');
        final qtys = pending.map((item) => '${item['qty']}').join(',');
        final merged = await api.bulkAddToCart(
          variantIds: ids,
          quantities: qtys,
        );
        if (merged.ok) {
          guestCart = [];
          guestCartTotal = 0;
          await _prefs.remove('guest_cart');
        }
        // On failure keep guestCart in memory and in prefs; refreshCart()
        // reconciles against the server cart without duplicating lines.
      } catch (_) {}
    }
    try {
      await reloadSettings();
    } catch (_) {}
    try {
      await resolveCity();
    } catch (_) {}
    try {
      await loadShop();
    } catch (_) {}
    try {
      await refreshCart();
    } catch (_) {}
    _bumpNav();
    _bumpChrome();
    try {
      await kickSync();
    } catch (_) {}
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
    // Capture scope BEFORE nulling user so per-account docs are wiped and
    // can never leak into the next account (orders/addresses/favorites).
    final scope = accountScope;
    final uid = user?['id'];
    token = null;
    user = null;
    cart = null;
    cartProducts = [];
    addresses = [];
    selectedAddress = null;
    promoCode = null;
    favoriteIds = [];
    _checkoutSession = null;
    _variantLabels.clear();
    try {
      await store.writeJson('variant_labels', <String, String>{});
    } catch (_) {}
    api.setToken(null);
    await vault.clear();
    try {
      await offline.clearAccountDocs(scope);
    } catch (_) {}
    // Local notification-read flags are per-account: drop the outgoing
    // account's rows so unread badges never leak across accounts.
    try {
      await NotificationRead.clear(uid);
    } catch (_) {}
    _bumpNav();
  }

  bool _isNetworkResult(ApiResult r) =>
      r.classifiedError?.category == ApiErrorCategory.network;

  Future<ApiResult> refreshCart({int checkout = 0}) {
    return _enqueueCart(() => _refreshCartInner(checkout: checkout));
  }

  /// Coalesces concurrent refresh callers onto the single in-flight request
  /// instead of firing N parallel `cart` GETs (was the main "slow cart"
  /// complaint on stepper spam + pull-to-refresh overlap).
  Future<ApiResult> _refreshCartInner({int checkout = 0}) async {
    final mine = ++_cartGen;
    final ongoing = _refreshInFlight;
    if (ongoing != null) {
      try {
        await ongoing;
      } catch (_) {}
      // A newer generation already refreshed: reuse current state.
      if (mine < _cartGen) {
        return ApiResult({'status': 1, 'data': [], 'coalesced': 1});
      }
    }
    final fut = _doRefreshCart(checkout: checkout, gen: mine);
    _refreshInFlight = fut.then((_) {});
    try {
      return await fut;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<ApiResult> _doRefreshCart({
    required int checkout,
    required int gen,
  }) async {
    final point = _cartCoords(checkout: checkout == 1);
    if (point == null) {
      // No coordinates (no city yet): local cart is the truth — still
      // notify so badges/steppers reflect optimistic updates.
      notifyListeners();
      return ApiResult({'status': 0});
    }
    if (isLoggedIn) {
      final scope = accountScope;
      final result = await api.cart(
        latitude: point.latitude,
        longitude: point.longitude,
        checkout: checkout,
      );
      if (scope != accountScope) return result;
      if (result.ok) {
        cart = result.dataMap;
        cartProducts = J.maps(cart?['cart'] ?? cart?['items'] ?? result.data);
        _attachVariantLabels(cartProducts);
        cartSubTotal = J.d(cart?['sub_total'] ?? cart?['total']);
        // Persist the confirmed snapshot so an offline restart still shows
        // the last server-confirmed lines (stale-badged, revalidated before
        // checkout — never treated as live stock/prices).
        if (checkout == 0) {
          try {
            await offline.writeDoc(OfflineCache.snapshotKey('cart::$scope'), {
              'products': cartProducts,
              'subTotal': cartSubTotal,
            }, scope: scope);
          } catch (_) {}
        }
        // parity: enrich sellerGroups etc when is_checkout=1
        if (checkout == 1) {
          sellerGroups = J.maps(
            cart?['seller_groups'] ?? cart?['sellerGroups'],
          );
          deliveryFees = J.map(cart?['delivery_fees'] ?? cart?['deliveryFees']);
          paymentSplit = J.maps(
            cart?['payment_split'] ?? cart?['paymentSplit'],
          );
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
      } else if (result.classifiedError == null) {
        // The server is REACHABLE and answered a business `status:0` with no
        // transport error map. For the non-checkout cart GET the only such
        // answer is "no items in cart" (`no_items_found_in_users_cart`): the
        // cart is genuinely EMPTY. Clearing here is essential — the old code
        // fell into the offline-snapshot restore below and re-materialised
        // the line the user had just deleted, so the last item had to be
        // deleted twice. A checkout read (is_checkout=1) can fail for
        // delivery reasons instead, so never wipe local lines for those.
        if (checkout == 0) {
          cart = null;
          cartProducts = [];
          cartSubTotal = 0;
          try {
            await offline.removeDoc(
              OfflineCache.snapshotKey('cart::$accountScope'),
            );
          } catch (_) {}
        }
      } else if (cartProducts.isEmpty) {
        // Request failed (transport/server error) with no live lines: restore
        // the last server-confirmed snapshot for this account (scope-guarded).
        // The UI badges it stale; checkout revalidates before any commit. The
        // genuinely-empty business answer is handled in the branch above, so a
        // line the user just deleted can never be resurrected from here.
        try {
          final snap = offline.readDoc(
            OfflineCache.snapshotKey('cart::$accountScope'),
          );
          if (snap?.scope == accountScope && snap?.payload is Map) {
            final m = J.map(snap?.payload);
            final rows = J.maps(m['products']);
            if (rows.isNotEmpty) {
              cartProducts = rows;
              _attachVariantLabels(cartProducts);
              cartSubTotal = J.d(m['subTotal']);
            }
          }
        } catch (_) {}
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
          localQty['${item['product_variant_id']}'] = J.i(
            item['qty'] ?? item['quantity'],
          );
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

  /// Authoritative reachability probe for online-only mutations. Always
  /// probes (no success-window shortcut: a recent success must never green-
  /// light an edit made after the link dropped). Non-network failures still
  /// count as reachable. Single cheap request, no retries.
  Future<bool> hasInternetAccess() async {
    try {
      final res = await api
          .cities(limit: 1, offset: 0)
          .timeout(const Duration(seconds: 8));
      if (res.ok) return true;
      return res.classifiedError?.category != ApiErrorCategory.network;
    } catch (_) {
      return false;
    }
  }

  /// Returns `same_seller` when mixing sellers is not allowed.
  ///
  /// RADICAL FIX (slow + conflicts):
  /// * NO `hasInternetAccess()` probe before the mutation. That probe cost an
  ///   extra 1 RTT (up to 8s on a bad link) on EVERY +/- tap. The mutation
  ///   result itself is the reachability signal: a `network`-category failure
  ///   maps to [kRequiresInternet] with zero extra requests.
  /// * NO blocking business-hours fetch. The cached memo gates obvious
  ///   closed-store taps instantly; a background warm refreshes it. The
  ///   server stays authoritative at checkout, so this can never place an
  ///   order while closed.
  /// * Serialized through [_enqueueCart]: rapid stepper taps queue FIFO, so
  ///   quantities can never interleave or resurrect stale values.
  Future<String?> addToCart({
    required dynamic productId,
    required dynamic variantId,
    required int qty,
    double? productPrice,
    dynamic sellerId,
    bool replaceSeller = false,
    String storeName = '',
    String variantLabel = '',
  }) {
    return _enqueueCart(
      () => _addToCartInner(
        productId: productId,
        variantId: variantId,
        qty: qty,
        productPrice: productPrice,
        sellerId: sellerId,
        replaceSeller: replaceSeller,
        storeName: storeName,
        variantLabel: variantLabel,
      ),
    );
  }

  Future<String?> _addToCartInner({
    required dynamic productId,
    required dynamic variantId,
    required int qty,
    double? productPrice,
    dynamic sellerId,
    bool replaceSeller = false,
    String storeName = '',
    String variantLabel = '',
  }) async {
    // Fast local guards first (zero network).
    if (!replaceSeller && maxCartItemsCount > 0 && qty > maxCartItemsCount) {
      return t(
        'max_cart_limit_error',
      ).replaceAll('{max}', '$maxCartItemsCount');
    }
    if (!replaceSeller) {
      final currentQty = _qtyInCart(variantId);
      final isNewOrIncrease = qty > currentQty;
      if (isNewOrIncrease) {
        // Adding to the cart is ALWAYS allowed, even when the store/platform
        // is closed — closure only blocks placing the order at checkout.
        // Keep hours warm so the checkout gate has fresh data.
        unawaited(_warmAddHours(sellerId));
        if (oneSellerCart && sellerId != null) {
          final existing = cartSellerIds();
          if (existing.isNotEmpty && !existing.contains('$sellerId')) {
            return 'same_seller';
          }
        }
        if (wouldExceedStoreLimit(sellerId: sellerId, variantId: variantId)) {
          return t(
            'max_stores_exceeded',
          ).replaceAll('{max}', '$maxSellersPerCheckout');
        }
      }
    } else {
      unawaited(
        loadBusinessHours(sellerIds: sellerId != null ? [sellerId] : []),
      );
    }
    if (isLoggedIn) {
      List<Map<String, dynamic>>? snapshot;
      if (replaceSeller) {
        snapshot = List<Map<String, dynamic>>.from(cartProducts);
        cartProducts = [];
        notifyListeners();
        try {
          await api.clearCart();
        } catch (_) {}
      } else {
        snapshot = List<Map<String, dynamic>>.from(cartProducts);
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
        clearFirst: false,
      );
      ApiResult result;
      try {
        result = await api.addToCart(
          productId: productId,
          variantId: variantId,
          qty: qty,
        );
       } catch (_) {
         // Transport threw outside ApiResult: keep the optimistic change when
         // the backend looks unreachable (offline add is accepted locally);
         // otherwise revert and report a generic error.
         if (api.likelyOffline) {
           try {
             await offline.writeDoc(
               OfflineCache.snapshotKey('cart::$accountScope'),
               {'products': cartProducts, 'subTotal': cartSubTotal},
               scope: accountScope,
             );
           } catch (_) {}
           await _invalidateCheckoutSession();
           return null;
         }
         cartProducts = snapshot;
         notifyListeners();
         return api.likelyOffline
             ? kRequiresInternet
             : t('something_went_wrong');
       }
       if (_isNetworkResult(result)) {
         // Offline: keep the optimistic local change (add-to-cart is accepted
         // offline); only the final checkout is rejected. Persist a snapshot so
         // an offline restart still shows the lines.
         try {
           await offline.writeDoc(
             OfflineCache.snapshotKey('cart::$accountScope'),
             {'products': cartProducts, 'subTotal': cartSubTotal},
             scope: accountScope,
           );
         } catch (_) {}
         await _invalidateCheckoutSession();
         return null;
       }
      if (result.oneSellerError == 1) {
        await _refreshCartInner(checkout: 0);
        await _invalidateCheckoutSession();
        return 'same_seller';
      }
      if (!result.ok) {
        // Reconcile: drop the optimistic change, show the real error.
        await _refreshCartInner(checkout: 0);
        await _invalidateCheckoutSession();
        return result.message.isEmpty
            ? t('something_went_wrong')
            : result.message;
      }
      await _refreshCartInner(checkout: 0);
      await _invalidateCheckoutSession();
      return null;
    }
    // Guest lines are persisted locally and accepted even when offline; server
    // pricing is reconciled on the next successful refresh. Only the final
    // checkout is rejected offline.
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
      if (productPrice != null) {
        guestCart[existingIndex]['price'] = productPrice;
        guestCart[existingIndex]['productPrice'] = productPrice;
      }
    } else {
      guestCart.add({
        'product_id': productId,
        'product_variant_id': variantId,
        'qty': qty,
        'seller_id': ?sellerId,
        // Display reads `price`; keep both keys so the line never flashes 0
        // before the server reprices it.
        'price': ?productPrice,
        'productPrice': ?productPrice,
        if (variantLabel.trim().isNotEmpty)
          'variant_label': variantLabel.trim(),
      });
    }
    await persistGuestCart();
    notifyListeners();
    await _refreshCartInner(checkout: 0);
    await _invalidateCheckoutSession();
    return null;
  }

  /// Removes one cart line. Returns an error message when the server
  /// refuses (logged-in), so callers can surface it instead of failing
  /// silently with a stepper that never moves.
  ///
  /// Convergent removal: when the server answers that the line does not
  /// exist (stale variant id, line already dropped server-side, …), the
  /// local line is dropped instead of reported as an error — otherwise the
  /// item stays visible yet can never be deleted.
  Future<String?> removeCartLine({
    required dynamic productId,
    required dynamic variantId,
  }) {
    return _enqueueCart(
      () => _removeCartLineInner(productId: productId, variantId: variantId),
    );
  }

  Future<String?> _removeCartLineInner({
    required dynamic productId,
    required dynamic variantId,
  }) async {
    if (isLoggedIn) {
      final snapshot = List<Map<String, dynamic>>.from(cartProducts);
      // Optimistic: line disappears instantly, server confirms after.
      _optimisticSetQty(variantId, 0);
      ApiResult result;
      try {
        result = await api.removeFromCart(
          productId: productId,
          variantId: variantId,
        );
      } catch (_) {
        if (api.likelyOffline) {
          try {
            await offline.writeDoc(
              OfflineCache.snapshotKey('cart::$accountScope'),
              {'products': cartProducts, 'subTotal': cartSubTotal},
              scope: accountScope,
            );
          } catch (_) {}
          await _invalidateCheckoutSession();
          return null;
        }
        cartProducts = snapshot;
        notifyListeners();
        return t('something_went_wrong');
      }
      if (_isNetworkResult(result)) {
        try {
          await offline.writeDoc(
            OfflineCache.snapshotKey('cart::$accountScope'),
            {'products': cartProducts, 'subTotal': cartSubTotal},
            scope: accountScope,
          );
        } catch (_) {}
        await _invalidateCheckoutSession();
        return null;
      }
      if (!result.ok) {
        if (_isAlreadyRemoved(result.message)) {
          await _refreshCartInner(checkout: 0);
          // The server claims this id does not exist: make sure a
          // resurrected phantom (same id echoed back by refresh) never
          // stays visible and undeletable.
          _dropPhantomCartLine(variantId);
          await _invalidateCheckoutSession();
          return null;
        }
        await _refreshCartInner(checkout: 0);
        await _invalidateCheckoutSession();
        return result.message.isEmpty
            ? t('something_went_wrong')
            : result.message;
      }
      await _refreshCartInner(checkout: 0);
      await _invalidateCheckoutSession();
      return null;
    }
    // Guest removal is also accepted offline: update the local cart and
    // reconcile with the server on the next successful refresh.
    guestCart.removeWhere(
      (item) => '${item['product_variant_id']}' == '$variantId',
    );
    await persistGuestCart();
    notifyListeners();
    await _refreshCartInner(checkout: 0);
    await _invalidateCheckoutSession();
    return null;
  }

  Future<void> clearAllCart() {
    return _enqueueCart(() async {
      // Guest clear stays probe-guarded (offline keeps the cart); logged-in
      // attempts the server clear and restores the snapshot on failure.
      if (isGuest && !await hasInternetAccess()) return;
      final snapshot = List<Map<String, dynamic>>.from(
        isLoggedIn ? cartProducts : guestCart,
      );
      if (isLoggedIn) {
        cartProducts = [];
        notifyListeners();
        try {
          final res = await api.clearCart();
          if (_isNetworkResult(res)) {
            cartProducts = snapshot;
            notifyListeners();
            return;
          }
        } catch (_) {
          cartProducts = snapshot;
          notifyListeners();
          return;
        }
      } else {
        guestCart = [];
        notifyListeners();
      }
      guestCart = [];
      await _prefs.remove('guest_cart');
      await _refreshCartInner(checkout: 0);
      await _invalidateCheckoutSession();
    });
  }

  Future<String?> applyPromo(String code, double total) async {
    final result = await api.validatePromo(promoCode: code, total: total);
    if (!result.ok) return result.message;
    promoCode = result.dataMap.isNotEmpty
        ? result.dataMap
        : {'promo_code': code, ...result.raw};
    await _invalidateCheckoutSession();
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

  bool isFavorite(dynamic productId) {
    final key = '$productId';
    for (final id in favoriteIds) {
      if ('$id' == key) return true;
    }
    return false;
  }

  /// Optimistic favorite toggle with a durable outbox. The local state moves
  /// instantly; failures are queued (coalesced by product id) and replayed by
  /// [sync]. Server removals win on next refresh (reconciliation).
  Future<void> toggleFavorite(dynamic productId) async {
    if (!isLoggedIn) return;
    final adding = !isFavorite(productId);
    if (adding) {
      favoriteIds.add(productId);
    } else {
      favoriteIds.removeWhere((id) => '$id' == '$productId');
    }
    try {
      await offline.writeDoc(
        OfflineCache.favoritesKey(accountScope),
        favoriteIds.toList(),
        scope: accountScope,
      );
    } catch (_) {}
    notifyListeners();
    final res = adding
        ? await api.addFavorite(productId)
        : await api.removeFavorite(productId);
    if (!res.ok) {
      try {
        await PendingOutbox(store, accountScope).enqueue(
          PendingOp(
            id: PendingOutbox.newId('fav'),
            type: adding
                ? PendingOpType.favoriteAdd
                : PendingOpType.favoriteRemove,
            payload: {
              'product_id': '$productId',
              // Owning account: the executor drops this op if the active
              // account changed before replay (never mutate B with A's intent).
              'account_scope': accountScope,
            },
            createdAt: DateTime.now(),
          ),
        );
      } catch (_) {}
      kickSyncDelayed(const Duration(seconds: 5));
    } else {
      // Direct success supersedes any queued opposite intent for this
      // product (D3): without this, a stale queued remove replays after a
      // newer successful add and silently undoes it on the next sync.
      // Only same-product favorite ops in the current scope are cancelled;
      // every other queued op keeps its retry guarantees.
      try {
        final outbox = PendingOutbox(store, accountScope);
        final stale = outbox.load().where(
          (o) =>
              (adding
                  ? o.type == PendingOpType.favoriteRemove
                  : o.type == PendingOpType.favoriteAdd) &&
              '${o.payload['product_id']}' == '$productId',
        );
        for (final o in stale) {
          await outbox.remove(o.id);
        }
      } catch (_) {}
    }
  }

  /// SyncEngine executor: replays ONLY safe idempotent ops. Returns true when
  /// the op is done (success or permanently rejected), false on transient
  /// failure (backoff). Auth/validation failures count as done — they are
  /// reconciled by refresh, not retried blindly.
  Future<bool> runPendingOp(PendingOp op) async {
    // Cross-account guard: an op queued by account A must never execute
    // under account B's credentials after a switch. Legacy ops without a
    // stamped scope keep the old behavior (treated as current).
    final opScope = op.payload['account_scope']?.toString();
    if (opScope != null && opScope.isNotEmpty && opScope != accountScope) {
      return true;
    }
    try {
      switch (op.type) {
        case PendingOpType.favoriteAdd:
          final r = await api.addFavorite(op.payload['product_id']);
          if (r.ok) return true;
          if (_isAlreadyFavorite(r.message)) return true;
          if (_isPermanent(r.classifiedError)) return true;
          return false;
        case PendingOpType.favoriteRemove:
          // Verified against the current backend
          // (`BasicApiController.removeFromFavorite`): with a valid
          // product_id exactly one row is deleted, so replay converges;
          // a repeat reports `no_product_found`, which also counts as done.
          // WITHOUT product_id the endpoint deletes ALL user favorites, so
          // an op with a missing/empty id is dropped, never executed.
          final pid = '${op.payload['product_id']}';
          if (pid.isEmpty || pid == 'null') return true;
          final r = await api.removeFavorite(op.payload['product_id']);
          if (r.ok) return true;
          if (_isAlreadyRemoved(r.message)) return true;
          if (_isPermanent(r.classifiedError)) return true;
          return false;
        case PendingOpType.guestCartMerge:
          // bulkAddToCart is not idempotent, so guest-cart merge is never
          // replayed automatically. Drain any legacy queued merges.
          return true;
      }
    } catch (_) {
      return false;
    }
  }

  bool _isAlreadyFavorite(String message) {
    final m = message.toLowerCase();
    return m.contains('already') && m.contains('favorite');
  }

  /// The backend reports `no_product_found` when the row is already gone:
  /// the local removal has converged, so the op is done (not retried).
  /// Matches English and Arabic phrasings (the backend answers business
  /// failures in Arabic, e.g. "المنتج غير موجود في السلة", and 404s arrive
  /// as "العنصر المطلوب غير موجود.").
  bool _isAlreadyRemoved(String message) {
    final m = message.toLowerCase();
    if (m.isEmpty) return false;
    if ((m.contains('no_product') && m.contains('found')) ||
        (m.contains('not') && m.contains('found')) ||
        (m.contains('already') && m.contains('removed')) ||
        m.contains('not exist') ||
        m.contains('does not exist') ||
        m.contains('no longer')) {
      return true;
    }
    if (m.contains('invalid') &&
        (m.contains('product') ||
            m.contains('variant') ||
            m.contains('item') ||
            m.contains('cart'))) {
      return true;
    }
    if (m.contains('no item') && m.contains('found')) return true;
    if (m.contains('empty') && m.contains('cart')) return true;
    // Backend "cart is already empty" phrasing, e.g. "لم يتم العثور على
    // عناصر في عربة المستخدم": nothing to remove means converged.
    return m.contains('غير موجود') ||
        m.contains('غير موجودة') ||
        m.contains('لم يتم العثور') ||
        m.contains('لا يوجد') ||
        m.contains('لا توجد') ||
        m.contains('محذوف') ||
        m.contains('تم حذف') ||
        m.contains('ليس في السلة') ||
        m.contains('ليست في السلة');
  }

  bool _isPermanent(ClassifiedApiError? error) {
    if (error == null) return false;
    switch (error.category) {
      case ApiErrorCategory.auth:
      case ApiErrorCategory.validation:
      case ApiErrorCategory.notFound:
        return true;
      case ApiErrorCategory.network:
      case ApiErrorCategory.server:
      case ApiErrorCategory.rateLimit:
      case ApiErrorCategory.malformed:
      case ApiErrorCategory.unknown:
        return false;
    }
  }

  /// Restores cached favorites for the current scope (offline-first paint).
  /// Wired into bootstrap, login, and settings-refresh failure so cached
  /// favorites are actually displayed offline (previously written but never
  /// read). Scope-guarded: another account's rows are never painted.
  Future<void> restoreCachedFavorites() async {
    try {
      final cached = offline.readDoc(OfflineCache.favoritesKey(accountScope));
      if (cached?.scope != accountScope) return;
      final payload = cached?.payload;
      if (payload is List && favoriteIds.isEmpty) {
        favoriteIds = payload.toList();
        notifyListeners();
      }
    } catch (_) {}
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
      if (result.classifiedError?.category == ApiErrorCategory.network) {
        return kRequiresInternet;
      }
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
      if (result.classifiedError?.category == ApiErrorCategory.network) {
        return kRequiresInternet;
      }
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
