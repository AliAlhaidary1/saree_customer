import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../json_util.dart';
import 'api_errors.dart';

class CustomerApi {
  CustomerApi({required String baseUrl, String? token, String? viewerKey}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: _normalizeBase(baseUrl),
        connectTimeout: const Duration(seconds: 25),
        receiveTimeout: const Duration(seconds: 40),
        sendTimeout: const Duration(seconds: 40),
        headers: {AppConfig.accessKeyHeader: AppConfig.accessKey},
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    setToken(token);
    setViewerKey(viewerKey);
  }

  late final Dio _dio;

  static String _normalizeBase(String url) {
    var root = url.trim();
    if (root.endsWith('/')) root = root.substring(0, root.length - 1);
    var sub = AppConfig.apiSubUrl;
    if (!sub.startsWith('/')) sub = '/$sub';
    if (sub.endsWith('/')) sub = sub.substring(0, sub.length - 1);
    return '$root$sub/';
  }

  void setToken(String? token) {
    if (token != null && token.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  void setViewerKey(String? key) {
    if (key != null && key.isNotEmpty) {
      _dio.options.headers['X-Viewer-Key'] = key;
    } else {
      _dio.options.headers.remove('X-Viewer-Key');
    }
  }

  void setBaseUrl(String url) {
    _dio.options.baseUrl = _normalizeBase(url);
  }

  Options get _form =>
      Options(contentType: Headers.multipartFormDataContentType);

  Future<ApiResult> _guard(
    Future<Response> Function() request, {
    ApiRequestKind kind = ApiRequestKind.private,
  }) async {
    final release = ApiErrorPolicy.current.release;
    var attempt = 0;
    while (true) {
      try {
        return _parse(await request());
      } on DioException catch (error) {
        final classified = classifyDio(error, release: release);
        logApiFailure(classified, path: error.requestOptions.path);
        if (shouldRetryApi(
          error: classified,
          attempt: attempt,
          kind: kind,
          release: release,
        )) {
          attempt += 1;
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        return ApiResult(classified.toResultMap());
      } catch (error) {
        final classified = classifyUnknown(error, release: release);
        logApiFailure(classified);
        return ApiResult(classified.toResultMap());
      }
    }
  }

  Future<ApiResult> _get(String path, [Map<String, dynamic>? query]) {
    return _guard(
      () => _dio.get(path, queryParameters: _clean(query)),
      kind: inferRequestKind(path, method: 'GET'),
    );
  }

  Future<ApiResult> _post(String path, [Map<String, dynamic>? fields]) {
    return _guard(
      () => _dio.post(
        path,
        data: FormData.fromMap(_clean(fields) ?? {}),
        options: _form,
      ),
      kind: inferRequestKind(path, method: 'POST'),
    );
  }

  Future<ApiResult> _postRaw(String path, FormData data) {
    return _guard(
      () => _dio.post(path, data: data, options: _form),
      kind: inferRequestKind(path, method: 'POST'),
    );
  }

  Future<ApiResult> _postJson(String path, Map<String, dynamic> json) {
    return _guard(
      () => _dio.post(path, data: json, options: Options(contentType: Headers.jsonContentType)),
      kind: inferRequestKind(path, method: 'POST'),
    );
  }

  Map<String, dynamic>? _clean(Map<String, dynamic>? input) {
    if (input == null) return null;
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.isEmpty) return;
      out[key] = value;
    });
    return out;
  }

  ApiResult _parse(Response response) {
    final data = response.data;
    if (data is Map) return ApiResult(J.map(data));
    return ApiResult({
      'status': 0,
      'message': 'invalid_response',
      'data': data,
    });
  }

  // ---- Auth ----
  Future<ApiResult> register({
    required String name,
    String email = '',
    required String mobile,
    required String password,
    String type = 'phone',
    String fcm = '',
    String countryCode = AppConfig.countryDialCode,
    String? otp,
    int? cityId,
    String backupPhone = '',
  }) {
    return _post('register', {
      'name': name,
      'email': email,
      'mobile': mobile,
      'password': password,
      'password_confirmation': password,
      'type': type,
      'fcm_token': fcm,
      'country_code': countryCode,
      'platform': AppConfig.devicePlatform,
      if (otp != null && otp.isNotEmpty) 'otp': otp,
      if (cityId != null) 'city_id': cityId,
      if (backupPhone.isNotEmpty) 'backup_phone': backupPhone,
    });
  }

  Future<ApiResult> loginMobile({
    required String mobile,
    required String password,
    String fcm = '',
    String countryCode = AppConfig.countryDialCode,
  }) {
    return _post('login_mobile', {
      'mobile': mobile,
      'password': password,
      'fcm_token': fcm,
      'country_code': countryCode,
      'platform': AppConfig.devicePlatform,
    });
  }

  Future<ApiResult> login({
    String? id,
    String? type,
    String? email,
    String? password,
    String fcm = '',
  }) {
    return _post('login', {
      if (email != null) 'email': email,
      if (password != null) 'password': password,
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      'fcm_token': fcm,
      'platform': AppConfig.devicePlatform,
    });
  }

  Future<ApiResult> logout() => _post('logout');

  Future<ApiResult> logoutAllDevices() => _post('logout_all_devices');

  Future<ApiResult> deleteAccount({
    required String confirmation,
    String? password,
  }) =>
      _post('delete_account', {
        'confirmation': confirmation,
        if (password != null && password.isNotEmpty) 'password': password,
      });

  Future<ApiResult> userDetails() => _get('user_details');

  Future<ApiResult> editProfile({
    required String name,
    String email = '',
    String mobile = '',
    MultipartFile? profile,
  }) {
    final data = FormData.fromMap({'name': name, 'email': email, if (mobile.isNotEmpty) 'mobile': mobile});
    if (profile != null) data.files.add(MapEntry('profile', profile));
    return _postRaw('edit_profile', data);
  }

  Future<ApiResult> forgotPasswordOtp({
    required String mobile,
    String countryCode = AppConfig.countryDialCode,
  }) {
    return _post('forgot_password_otp', {
      'mobile': mobile,
      'country_code': countryCode,
    });
  }

  Future<ApiResult> resetPasswordOtp({
    required String mobile,
    required String otp,
    required String password,
    required String passwordConfirmation,
    String countryCode = AppConfig.countryDialCode,
  }) {
    return _post('reset_password_otp', {
      'mobile': mobile,
      'country_code': countryCode,
      'otp': otp,
      'password': password,
      'password_confirmation': passwordConfirmation,
    });
  }

  Future<ApiResult> changePassword({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) {
    return _post('change_password', {
      'current_password': currentPassword,
      'password': password,
      'password_confirmation': passwordConfirmation,
    });
  }

  Future<ApiResult> sendSms(
    String phone, {
    int? cityId,
    String? channel,
    String purpose = 'register',
    String? countryCode,
  }) {
    return _post('send_sms', {
      'phone': phone,
      if (cityId != null) 'city_id': cityId,
      if (channel != null) 'channel': channel,
      'purpose': purpose,
      if (countryCode != null) 'country_code': countryCode,
    });
  }

  Future<ApiResult> cityConfig({int? cityId, double? latitude, double? longitude}) {
    return _get('city-config', {
      if (cityId != null) 'city_id': cityId,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
  }

  Future<ApiResult> verifyUser({
    String? mobile,
    String? otp,
    String? countryCode,
  }) {
    return _post('verify_user', {
      if (mobile != null) 'phone': mobile,
      if (mobile != null) 'mobile': mobile,
      if (otp != null) 'otp': otp,
      if (countryCode != null) 'country_code': countryCode,
    });
  }

  Future<ApiResult> checkUserExists(String mobile) {
    return _post('verify_user', {'mobile': mobile});
  }

  // ---- Settings / location / shop ----
  Future<ApiResult> settings({bool withAuth = false}) =>
      _get('settings', {'is_web_setting': 1});

  Future<ApiResult> paymentMethods() => _get('settings/payment_methods');

  Future<ApiResult> timeSlots() => _get('settings/time_slots');

  Future<ApiResult> businessHours({List<dynamic> sellerIds = const []}) {
    final ids = sellerIds.where((e) => '${e}'.isNotEmpty).join(',');
    return _get('settings/business_hours', {
      if (ids.isNotEmpty) 'seller_ids': ids,
    });
  }

  Future<ApiResult> brand() => _get('brand');

  Future<ApiResult> systemLanguages({dynamic id = '', dynamic isDefault = ''}) {
    return _get('system_languages', {
      'system_type': 3,
      if ('$id'.isNotEmpty) 'id': id,
      if ('$isDefault'.toString().isNotEmpty) 'is_default': isDefault,
    });
  }

  Future<ApiResult> privacyPolicy() => _get('settings/privacy_policy');

  Future<ApiResult> termsConditions() => _get('settings/terms_conditions');

  Future<ApiResult> aboutUs() => _get('settings/about_us');

  Future<ApiResult> contactUs() => _get('settings/contact_us');

  Future<ApiResult> city({
    required double latitude,
    required double longitude,
  }) {
    return _get('city', {'latitude': latitude, 'longitude': longitude});
  }

  Future<ApiResult> cities({
    int limit = 100,
    int offset = 0,
    String search = '',
  }) {
    return _get('cities', {
      'limit': limit,
      'offset': offset,
      if (search.isNotEmpty) 'search': search,
    });
  }

  Future<ApiResult> shop({
    required double latitude,
    required double longitude,
  }) {
    return _get('shop', {
      'latitude': latitude,
      'longitude': longitude,
      if (_dio.options.headers['X-Viewer-Key'] != null)
        'viewer_key': _dio.options.headers['X-Viewer-Key'],
    });
  }

  Future<ApiResult> sliders() => _get('sliders');
  Future<ApiResult> offers() => _get('offers');
  Future<ApiResult> sections({
    int? cityId,
    double? latitude,
    double? longitude,
  }) {
    return _get('sections', {
      if (cityId != null) 'city_id': cityId,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
  }

  Future<ApiResult> categories({
    dynamic categoryId,
    dynamic limit,
    dynamic offset,
    String? slug,
  }) {
    return _get('categories', {
      if (categoryId != null) 'category_id': categoryId,
      if (limit != null) 'limit': limit,
      if (offset != null) 'offset': offset,
      if (slug != null) 'slug': slug,
    });
  }

  Future<ApiResult> brands({int limit = 20, int offset = 0}) {
    return _get('brands', {'limit': limit, 'offset': offset});
  }

  Future<ApiResult> sellers({
    double? latitude,
    double? longitude,
    int limit = 50,
    int offset = 0,
    String? search,
    String? sort,
    String? type,
    dynamic minRating,
  }) {
    return _get('sellers', {
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'limit': limit,
      'offset': offset,
      if (search != null && search.isNotEmpty) 'search': search,
      if (sort != null && sort.isNotEmpty) 'sort': sort,
      if (type != null && type.isNotEmpty) 'type': type,
      if (minRating != null && '$minRating'.isNotEmpty) 'min_rating': minRating,
    });
  }

  Future<ApiResult> sellerBySlug(String slug) => _get('seller/by-slug/$slug');
  Future<ApiResult> sellerById(String id) => _get('seller/by-id/$id');
  Future<ApiResult> publishedStorefront(String slug, {String? host, bool isSubdomain = false, String? customDomain}) {
    return _get('storefront/published', {
      'slug': slug,
      if (host != null) 'host': host,
      if (isSubdomain) 'is_subdomain': 1,
      if (customDomain != null) 'custom_domain': customDomain,
    });
  }

  Future<ApiResult> countries({int limit = 50, int offset = 0}) {
    return _get('countries', {'limit': limit, 'offset': offset});
  }

  Future<ApiResult> faqs({int limit = 30, int offset = 0}) {
    return _get('faqs', {'limit': limit, 'offset': offset});
  }

  Future<ApiResult> assistantChat(
    String message, {
    List<Map<String, String>> history = const [],
  }) {
    return _post('assistant/ask', {
      'question': message,
      if (history.isNotEmpty) 'history': jsonEncode(history),
    });
  }

  Future<ApiResult> assistantSearch(String query, {int limit = 10}) {
    return _get('assistant/search', {'q': query, 'limit': limit});
  }

  Future<ApiResult> flashSales({int limit = 20}) =>
      _get('flash_sales', {'limit': limit});
  Future<ApiResult> campaigns() => _get('campaigns');
  Future<ApiResult> managedCampaigns() => _get('managed-campaigns');
  Future<ApiResult> deliveryOfferHint({double? amount, dynamic cityId}) {
    return _get('delivery_offers/hint', {
      if (amount != null) 'amount': amount,
      if (cityId != null) 'city_id': cityId,
    });
  }

  // ---- Products ----
  Future<ApiResult> products({
    required double latitude,
    required double longitude,
    Map<String, dynamic> filters = const {},
    String tagNames = '',
    String slug = '',
  }) {
    return _post('products', {
      'latitude': latitude,
      'longitude': longitude,
      if (tagNames.isNotEmpty) 'tag_names': tagNames,
      if (slug.isNotEmpty) 'slug': slug,
      ...filters,
    });
  }

  Future<ApiResult> productById({
    required double latitude,
    required double longitude,
    dynamic id,
    String slug = '',
  }) {
    return _post('product_by_id', {
      'latitude': latitude,
      'longitude': longitude,
      if (id != null) 'id': id,
      if (slug.isNotEmpty) 'slug': slug,
      if (_dio.options.headers['X-Viewer-Key'] != null)
        'viewer_key': _dio.options.headers['X-Viewer-Key'],
    });
  }

  Future<ApiResult> productsOffers({
    required double latitude,
    required double longitude,
    int limit = 10,
    int offset = 0,
  }) {
    return _get('products/offers', {
      'latitude': latitude,
      'longitude': longitude,
      'limit': limit,
      'offset': offset,
    });
  }

  Future<ApiResult> catalogOffers({
    required dynamic productId,
    String name = '',
    String sort = 'price',
  }) {
    return _post('products/catalog_offers', {
      'product_id': productId,
      if (name.isNotEmpty) 'name': name,
      'sort': sort,
    });
  }

  Future<ApiResult> productRatings({
    required dynamic productId,
    int limit = 10,
    int offset = 0,
  }) {
    return _get('products/ratings_list', {
      'product_id': productId,
      'limit': limit,
      'offset': offset,
    });
  }

  Future<ApiResult> productRatingImages({
    required dynamic productId,
    int limit = 10,
    int offset = 0,
  }) {
    return _post('products/rating/image_list', {
      'product_id': productId,
      'limit': limit,
      'offset': offset,
    });
  }

  Future<ApiResult> addProductRating(Map<String, dynamic> fields) =>
      _post('products/rating/add', fields);
  Future<ApiResult> addProductRatingWithImages({
    required dynamic productId,
    required dynamic rate,
    required String review,
    List<MultipartFile> images = const [],
    dynamic orderItemId,
    dynamic orderId,
  }) {
    final data = FormData.fromMap({
      'product_id': productId,
      'rate': rate,
      'review': review,
      if (orderItemId != null) 'order_item_id': orderItemId,
      if (orderId != null) 'order_id': orderId,
    });
    for (var i = 0; i < images.length; i++) {
      data.files.add(MapEntry('image[$i]', images[i]));
    }
    return _postRaw('products/rating/add', data);
  }

  Future<ApiResult> updateProductRating(Map<String, dynamic> fields) =>
      _post('products/rating/update', fields);

  Future<ApiResult> updateProductRatingWithImages({
    required dynamic id,
    required dynamic rate,
    required String review,
    List<MultipartFile> images = const [],
    List<dynamic> deleteImageIds = const [],
  }) {
    final data = FormData.fromMap({
      'id': id,
      'rate': rate,
      'review': review,
      'deleteImageIds': '[${deleteImageIds.join(',')}]',
    });
    for (var i = 0; i < images.length; i++) {
      data.files.add(MapEntry('image[$i]', images[i]));
    }
    return _postRaw('products/rating/update', data);
  }

  Future<ApiResult> getProductRatingById(dynamic id) => _post('products/rating/edit', {'id': id});

  Future<ApiResult> rateSeller(Map<String, dynamic> fields) =>
      _post('seller_rating/add', fields);
  Future<ApiResult> rateDeliveryBoy(Map<String, dynamic> fields) =>
      _post('delivery_boy_rating/add', fields);

  // ---- Cart ----
  Future<ApiResult> cart({
    required double latitude,
    required double longitude,
    int checkout = 0,
  }) {
    return _get('cart', {
      'latitude': latitude,
      'longitude': longitude,
      'is_checkout': checkout,
    });
  }

  Future<ApiResult> cartCount() => _get('cart/get_cart_count');

  Future<ApiResult> addToCart({
    required dynamic productId,
    required dynamic variantId,
    required dynamic qty,
  }) {
    return _post('cart/add', {
      'product_id': productId,
      'product_variant_id': variantId,
      'qty': qty,
    });
  }

  Future<ApiResult> removeFromCart({
    required dynamic productId,
    required dynamic variantId,
  }) {
    return _post('cart/remove', {
      'product_id': productId,
      'product_variant_id': variantId,
      'is_remove_all': 0,
    });
  }

  Future<ApiResult> clearCart() => _post('cart/remove', {'is_remove_all': 1});

  Future<ApiResult> guestCart({
    required double latitude,
    required double longitude,
    required String variantIds,
    required String quantities,
  }) {
    return _get('cart/guest_cart', {
      'latitude': latitude,
      'longitude': longitude,
      'variant_ids': variantIds,
      'quantities': quantities,
    });
  }

  Future<ApiResult> bulkAddToCart({
    required String variantIds,
    required String quantities,
  }) {
    return _post('cart/bulk_add_to_cart_items', {
      'variant_ids': variantIds,
      'quantities': quantities,
    });
  }

  Future<ApiResult> promoCodes(double amount) =>
      _get('promo_code', {'amount': amount});

  Future<ApiResult> validatePromo({
    required String promoCode,
    required double total,
  }) {
    return _post('promo_code/validate', {
      'promo_code': promoCode,
      'total': total,
    });
  }

  // legacy single checkout -> still supported but new flow is multi seller
  Future<ApiResult> placeOrder(Map<String, dynamic> fields) =>
      _post('place_order', fields);

  Future<ApiResult> checkout({
    required dynamic addressId,
    String paymentMethod = 'COD',
    bool useWallet = false,
    dynamic promocodeId,
    dynamic campaignId,
    String deliveryTime = '',
    String orderNote = '',
    String? idempotencyKey,
  }) {
    return _post('checkout', {
      'address_id': addressId,
      'payment_method': paymentMethod,
      'use_wallet': useWallet ? '1' : '0',
      if (deliveryTime.isNotEmpty) 'delivery_time': deliveryTime,
      if (orderNote.isNotEmpty) 'order_note': orderNote,
      if (promocodeId != null) 'promocode_id': promocodeId,
      if (campaignId != null) 'campaign_id': campaignId,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
    });
  }

  Future<ApiResult> checkoutGroups({int page = 1}) => _get('checkout-groups', {'page': page});
  Future<ApiResult> checkoutGroup(dynamic id) => _get('checkout-groups/$id');
  Future<ApiResult> cancelCheckoutGroup(dynamic id, {String reason = ''}) => _post('checkout-groups/$id/cancel', {if (reason.isNotEmpty) 'reason': reason});

  Future<ApiResult> deleteOrder(dynamic orderId) =>
      _post('delete_order', {'order_id': orderId});

  Future<ApiResult> orders({
    int limit = 10,
    int offset = 0,
    int type = 1,
    dynamic orderId,
  }) {
    return _get(
      'orders',
      orderId != null
          ? {'order_id': orderId}
          : {'limit': limit, 'offset': offset, 'type': type},
    );
  }

  Future<ApiResult> updateOrderStatus(Map<String, dynamic> fields) =>
      _post('update_order_status', fields);

  /// Parity with front `api.updateOrderStatus(jwt, order_id, item_id, status, reason)`.
  /// Front sends device_type=website; mobile sends device_type=android.
  Future<ApiResult> updateOrderItemStatus({
    required dynamic orderId,
    required dynamic orderItemId,
    required dynamic status,
    String reason = '',
  }) {
    return _post('update_order_status', {
      'order_id': orderId,
      'order_item_id': orderItemId,
      'status': status,
      'device_type': AppConfig.devicePlatform,
      'app_version': '1.0',
      if (reason.isNotEmpty) 'reason': reason,
    });
  }

  /// Parity with front `api.requestCommerceReturn(jwt, itemId, reason)`
  /// -> POST order-items/{id}/return {reason}
  Future<ApiResult> requestCommerceReturn(dynamic itemId, {String reason = ''}) {
    return _post('order-items/$itemId/return', {
      if (reason.isNotEmpty) 'reason': reason,
    });
  }

  /// Best-effort FCM token sync — keeps pushes arriving when the app is closed.
  /// Real backend routes (routes/customer.php, base /customer/):
  /// `add_fcm_token` + `update_fcm_token` (CustomerAuthController — both store
  /// into UserToken{type: customer} which order notifications are sent from).
  /// Requires login (api-customers guard); failures are ignored gracefully.
  Future<ApiResult> updateFcmToken(String fcmToken) async {
    for (final path in ['add_fcm_token', 'update_fcm_token', 'update_fcm', 'user/update_fcm', 'users/update_fcm_token']) {
      try {
        final res = await _post(path, {
          'fcm_token': fcmToken,
          'platform': AppConfig.devicePlatform,
        });
        if (res.ok) return res;
      } catch (_) {}
    }
    return ApiResult({'status': 0, 'message': 'fcm_sync_skipped'});
  }
  Future<ApiResult> initiateTransaction(Map<String, dynamic> fields) =>
      _post('initiate_transaction', fields);
  Future<ApiResult> initiateTransactionForCheckoutGroup({
    required dynamic checkoutGroupId,
    required String paymentMethod,
    String type = 'checkout_group',
  }) {
    final method = _normalizePaymentMethod(paymentMethod);
    return _post('initiate_transaction', {
      'order_id': checkoutGroupId,
      'payment_method': method,
      'type': type,
      if (method == 'Paypal' || method == 'Midtrans' || method == 'Phonepe' || method == 'Cashfree') 'request_from': 'website',
    });
  }

  String _normalizePaymentMethod(String input) {
    final v = input.toLowerCase();
    if (v == 'razorpay') return 'Razorpay';
    if (v == 'stripe') return 'Stripe';
    if (v == 'paypal') return 'Paypal';
    if (v == 'midtrans') return 'Midtrans';
    if (v == 'phonepe') return 'Phonepe';
    if (v == 'cashfree') return 'Cashfree';
    if (v == 'paystack') return 'Paystack';
    return input;
  }

  Future<ApiResult> addTransaction(Map<String, dynamic> fields) =>
      _post('add_transaction', fields);

  Future<ApiResult> addRazorpayTransaction({
    required dynamic orderId,
    required String transactionId,
    String razorpayOrderId = '',
    String razorpayPaymentId = '',
    String razorpaySignature = '',
  }) {
    return _post('add_transaction', {
      'order_id': orderId,
      'transaction_id': transactionId,
      'type': 'order',
      'payment_method': 'Razorpay',
      'device_type': 'web',
      'app_version': '1.0',
      if (razorpayOrderId.isNotEmpty) 'razorpay_order_id': razorpayOrderId,
      if (razorpayPaymentId.isNotEmpty) 'razorpay_payment_id': razorpayPaymentId,
      if (razorpaySignature.isNotEmpty) 'razorpay_signature': razorpaySignature,
    });
  }

  Future<ApiResult> transactions({
    int limit = 10,
    int offset = 0,
    String type = 'transactions',
  }) {
    return _get('get_user_transactions', {
      'limit': limit,
      'offset': offset,
      'type': type,
    });
  }

  Future<ApiResult> invoice(dynamic orderId) =>
      _post('invoice_download', {'order_id': orderId});

  /// Raw PDF bytes for invoice_download (front getInvoice blob download).
  Future<(bool ok, List<int>? bytes, String message)> invoiceBytes(dynamic orderId) async {
    try {
      final res = await _dio.post(
        'invoice_download',
        data: FormData.fromMap({'order_id': '$orderId'}),
        options: Options(
          contentType: Headers.multipartFormDataContentType,
          responseType: ResponseType.bytes,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final contentType = '${res.headers.map['content-type']?.join(',') ?? ''}';
      if ((res.statusCode ?? 0) >= 200 &&
          (res.statusCode ?? 0) < 300 &&
          !contentType.contains('application/json')) {
        final data = res.data;
        if (data is List<int>) return (true, data, '');
        if (data is List) return (true, data.cast<int>(), '');
      }
      return (false, null, 'something_went_wrong');
    } catch (_) {
      return (false, null, 'something_went_wrong');
    }
  }

  // ---- Favorites / address / notifications ----
  Future<ApiResult> favorites({
    required double latitude,
    required double longitude,
  }) {
    return _get('favorites', {'latitude': latitude, 'longitude': longitude});
  }

  Future<ApiResult> addFavorite(dynamic productId) =>
      _post('favorites/add', {'product_id': productId});
  Future<ApiResult> removeFavorite(dynamic productId) =>
      _post('favorites/remove', {'product_id': productId});

  Future<ApiResult> addresses() => _get('address');
  Future<ApiResult> addAddress(Map<String, dynamic> fields) =>
      _post('address/add', fields);
  Future<ApiResult> updateAddress(Map<String, dynamic> fields) =>
      _post('address/update', fields);
  Future<ApiResult> deleteAddress(dynamic id) =>
      _post('address/delete', {'id': id});

  Future<ApiResult> notifications({int limit = 20, int offset = 0}) {
    return _get('notifications', {'limit': limit, 'offset': offset});
  }

  // ---- Haraj ----
  Future<ApiResult> harajCategories() => _get('haraj/categories');
  Future<ApiResult> harajCategoriesAll() => _get('haraj/categories/all');
  Future<ApiResult> harajPosts(Map<String, dynamic> params) =>
      _get('haraj/posts', params);
  Future<ApiResult> harajPost(dynamic id) => _get('haraj/posts/$id');
  Future<ApiResult> harajMyPosts(Map<String, dynamic> params) =>
      _get('haraj/my-posts', params);

  Future<ApiResult> harajCreate(FormData data) =>
      _postRaw('haraj/posts/create', data);
  Future<ApiResult> harajUpdate(dynamic id, FormData data) =>
      _postRaw('haraj/posts/$id/update', data);
  Future<ApiResult> harajDelete(dynamic id) => _post('haraj/posts/$id/delete');
  Future<ApiResult> harajMarkSold(dynamic id) =>
      _post('haraj/posts/$id/mark-sold');
  Future<ApiResult> harajDeleteImage(dynamic postId, dynamic imageId) =>
      _post('haraj/posts/$postId/images/$imageId/delete');

  Future<ApiResult> harajComments(dynamic postId, [Map<String, dynamic>? params]) =>
      _get('haraj/posts/$postId/comments', params);
  Future<ApiResult> harajAddComment(dynamic postId, String comment, {dynamic parentId}) {
    return _post('haraj/posts/$postId/comments', {
      'comment': comment,
      if (parentId != null) 'parent_id': parentId,
    });
  }
  Future<ApiResult> harajUpdateComment(dynamic commentId, String comment) =>
      _post('haraj/comments/$commentId/update', {'comment': comment});
  Future<ApiResult> harajDeleteComment(dynamic commentId) =>
      _post('haraj/comments/$commentId/delete');

  Future<ApiResult> harajUserRatings(dynamic userId) => _get('haraj/users/$userId/ratings');
  Future<ApiResult> harajRate(Map<String, dynamic> fields) =>
      _postJson('haraj/ratings', fields);
  Future<ApiResult> harajReport(dynamic postId,
      {required String reason, String? details}) {
    return _post('haraj/posts/$postId/report', {
      'reason': reason,
      if (details != null && details.isNotEmpty) 'details': details,
    });
  }
  Future<ApiResult> harajBulkImport(List<Map<String, dynamic>> posts) =>
      _postJson('haraj/posts/bulk-import', {'posts': posts});
  Future<ApiResult> harajBlock(dynamic blockedId) =>
      _postJson('haraj/blocks', {'blocked_id': blockedId});
  Future<ApiResult> harajUnblock(dynamic blockedId) =>
      _postJson('haraj/blocks/unblock', {'blocked_id': blockedId});

  // ---- Akhdimni ----
  Future<ApiResult> akhdimniConfig() => _get('akhdimni/config');
  Future<ApiResult> akhdimniCategories() => _get('akhdimni/categories');
  Future<ApiResult> akhdimniEstimate(Map<String, dynamic> fields) {
    // front sends FormData with city_id + lat/lng
    final data = FormData.fromMap(_clean(fields) ?? {});
    return _postRaw('akhdimni/estimate', data);
  }

  Future<ApiResult> akhdimniEstimateRaw(FormData data) => _postRaw('akhdimni/estimate', data);

  Future<ApiResult> akhdimniPlace(Map<String, dynamic> fields, {List<XFile>? images}) async {
    final data = FormData.fromMap(_clean(fields) ?? {});
    if (images != null) {
      for (final img in images) {
        data.files.add(MapEntry(
          'images[]',
          await MultipartFile.fromFile(img.path, filename: img.name),
        ));
      }
    }
    return _postRaw('akhdimni/place', data);
  }

  Future<ApiResult> akhdimniPlaceRaw(FormData data) => _postRaw('akhdimni/place', data);

  Future<ApiResult> akhdimniOrders(Map<String, dynamic> params) =>
      _get('akhdimni/orders', params);
  Future<ApiResult> akhdimniOrder(dynamic id) => _get('akhdimni/orders/$id');
  Future<ApiResult> akhdimniCancel(dynamic id, [Map<String, dynamic>? fields]) {
    if (fields != null && fields.isNotEmpty) {
      final data = FormData.fromMap(fields);
      return _postRaw('akhdimni/orders/$id/cancel', data);
    }
    return _post('akhdimni/orders/$id/cancel');
  }

  /// Raw PDF bytes for akhdimni/orders/{id}/invoice (Backend AkhdimniInvoiceService).
  Future<(bool ok, List<int>? bytes, String message)> akhdimniInvoiceBytes(dynamic id) async {
    try {
      final res = await _dio.get(
        'akhdimni/orders/$id/invoice',
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final contentType = '${res.headers.map['content-type']?.join(',') ?? ''}';
      if ((res.statusCode ?? 0) >= 200 &&
          (res.statusCode ?? 0) < 300 &&
          !contentType.contains('application/json')) {
        final data = res.data;
        if (data is List<int>) return (true, data, '');
        if (data is List) return (true, data.cast<int>(), '');
      }
      return (false, null, 'something_went_wrong');
    } catch (_) {
      return (false, null, 'something_went_wrong');
    }
  }

  // ---- Multi-seller Checkout ----
  Future<ApiResult> checkoutConfig() => _get('settings/checkout_config');
  Future<ApiResult> multiSellerCheckout({
    required double latitude,
    required double longitude,
    List<dynamic> sellerIds = const [],
  }) {
    return _post('checkout/multi_seller', {
      'latitude': latitude,
      'longitude': longitude,
      if (sellerIds.isNotEmpty) 'seller_ids': sellerIds.join(','),
    });
  }

  Future<ApiResult> placeMultiSellerOrder(Map<String, dynamic> orderData) => _post('checkout/place_multi_seller_order', orderData);

  // ---- Admin ----
  Future<ApiResult> adminCheckoutConfig() => _get('admin/settings/checkout_config');
  Future<ApiResult> updateAdminCheckoutConfig(Map<String, dynamic> config) => _postJson('admin/settings/checkout_config', config);
  Future<ApiResult> adminCouriers([Map<String, dynamic>? params]) => _get('admin/couriers', params);
  Future<ApiResult> assignCourierToOrder({required dynamic orderId, required dynamic courierId}) => _postJson('admin/orders/$orderId/assign_courier', {'courier_id': courierId});
  Future<ApiResult> adminSettlements([Map<String, dynamic>? params]) => _get('admin/settlements', params);
  Future<ApiResult> recordSettlementBatch(Map<String, dynamic> batch) => _postJson('admin/settlements/batch', batch);
  Future<ApiResult> adminAdjustments([Map<String, dynamic>? params]) => _get('admin/adjustments', params);
  Future<ApiResult> adminRefunds([Map<String, dynamic>? params]) => _get('admin/refunds', params);
  Future<ApiResult> adminCancellations([Map<String, dynamic>? params]) => _get('admin/cancellations', params);
  Future<ApiResult> adminReturns([Map<String, dynamic>? params]) => _get('admin/returns', params);
  Future<ApiResult> adminDispatch([Map<String, dynamic>? params]) => _get('admin/dispatch', params);
  Future<ApiResult> adminCheckoutGroups({int page = 1}) => _get('admin/checkout-groups', {'page': page});
  Future<ApiResult> adminCheckoutGroup(dynamic id) => _get('admin/checkout-groups/$id');

  // ---- Seller ----
  Future<ApiResult> sellerOrders([Map<String, dynamic>? params]) => _get('seller/orders', params);
  Future<ApiResult> sellerOrderDetails(dynamic orderId) => _get('seller/orders/$orderId');
  Future<ApiResult> sellerSettlement([Map<String, dynamic>? params]) => _get('seller/settlement', params);

  // ---- Courier ----
  Future<ApiResult> courierAssignments([Map<String, dynamic>? params]) => _get('courier/assignments', params);
  Future<ApiResult> courierOrders([Map<String, dynamic>? params]) => _get('courier/orders', params);
  Future<ApiResult> courierCollectFromSeller(dynamic orderId, Map<String, dynamic> data) => _postJson('courier/orders/$orderId/collect', data);
  Future<ApiResult> courierRecordMissingProduct(dynamic orderId, Map<String, dynamic> data) => _postJson('courier/orders/$orderId/missing', data);
  Future<ApiResult> courierDeliverToCustomer(dynamic orderId, Map<String, dynamic> data) => _postJson('courier/orders/$orderId/deliver', data);
  Future<ApiResult> courierCollectCash(dynamic orderId, Map<String, dynamic> data) => _postJson('courier/orders/$orderId/collect_cash', data);
  Future<ApiResult> courierSettlement([Map<String, dynamic>? params]) => _get('courier/settlement', params);
  Future<ApiResult> submitCourierSettlementBatch(Map<String, dynamic> batch) => _postJson('courier/settlement/batch', batch);
  Future<ApiResult> courierAssignmentDetails(dynamic id) => _get('courier/assignments/$id');

  // ---- Home handle ----
  Future<ApiResult> shopBySellers({
    double? latitude,
    double? longitude,
    int limit = 20,
    int offset = 0,
    String? search,
    String? sort,
  }) => sellers(latitude: latitude, longitude: longitude, limit: limit, offset: offset, search: search, sort: sort);
  Future<ApiResult> shopByCountries({int limit = 50, int offset = 0}) => countries(limit: limit, offset: offset);
  Future<ApiResult> shopByBrands({int limit = 50, int offset = 0}) => brands(limit: limit, offset: offset);
}
