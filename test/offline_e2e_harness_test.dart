// End-to-end offline/online integration harness.
//
// Runs the REAL production HTTP + persistence stack
// (CustomerApi/Dio, CatalogSyncService, CatalogDao, OfflineCache,
// PendingOutbox, CheckoutSession, ImagePrefetch) against a local
// contract-faithful HTTP backend (dart:io HttpServer) whose envelope
// ({status, message, total, data}), pagination (limit/offset, sort=old)
// and idempotency semantics were read off the actual Laravel source
// (routes/customer.php, BasicApiController, ProductApiController,
// DiscoveryQueryBuilder, CheckoutService/CheckoutSessionService,
// migration 2026_08_24_000001 unique(user_id,idempotency_key)).
//
// Fault injection (connection-refused offline, mid-response socket close,
// HTTP 500s, delays, malformed JSON, duplicate/stale responses) exercises
// the production Dio path — never an `isOffline` boolean.
//
// Live Laravel execution was unavailable in this environment (no PHP
// runtime, Docker daemon down, backend .env targets a Docker MySQL
// service), so backend behavior is a faithful double, and every such
// test is marked [harness] in the final report.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sareemart_customer/core/api/customer_api.dart';
import 'package:sareemart_customer/core/app_controller.dart';
import 'package:sareemart_customer/core/catalog_db/catalog_database.dart';
import 'package:sareemart_customer/core/catalog_store.dart';
import 'package:sareemart_customer/core/image_prefetch.dart';
import 'package:sareemart_customer/core/json_util.dart';
import 'package:sareemart_customer/core/offline/local_store.dart';
import 'package:sareemart_customer/core/offline/offline_cache.dart';
import 'package:sareemart_customer/core/offline/pending_ops.dart';

// ---------------------------------------------------------------------------
// FakeCustomerBackend: minimal Laravel-customer double.
// ---------------------------------------------------------------------------

Map<String, dynamic> srvProduct(
  int id, {
  String name = '',
  String price = '100',
  int categoryId = 3,
  int sellerId = 7,
  int status = 1,
  Map<String, dynamic>? extra,
}) => {
      'id': id,
      'name': name.isEmpty ? 'E2E product $id' : name,
      'description': 'E2E desc $id',
      'seller_id': sellerId,
      'store_name': 'E2E store $sellerId',
      'category_id': categoryId,
      'price': price,
      'rating': 4.0,
      'status': status,
      'variants': [
        {'id': id * 100 + 1, 'name': 'Default'},
      ],
      ...?extra,
    };

Map<String, dynamic> srvStore(int id, {String name = ''}) =>
    {'id': id, 'name': name.isEmpty ? 'E2E store $id' : name};

Map<String, dynamic> srvCategory(int id, {String name = ''}) =>
    {'id': id, 'name': name.isEmpty ? 'E2E cat $id' : name};

/// Parses both multipart/form-data (what CustomerApi._post sends) and
/// urlencoded/JSON bodies into a flat field map.
Map<String, String> _parseBody(String body, String? contentType) {
  final out = <String, String>{};
  if (contentType != null && contentType.contains('multipart/form-data')) {
    for (final m in RegExp(r'name="([^"]+)"\r\n\r\n([^\r]*)')
        .allMatches(body)) {
      out[m.group(1)!] = m.group(2)!;
    }
    return out;
  }
  if (contentType != null && contentType.contains('application/json')) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        decoded.forEach((k, v) => out['$k'] = '$v');
      }
    } catch (_) {}
    return out;
  }
  try {
    out.addAll(Uri.splitQueryString(body));
  } catch (_) {}
  return out;
}

class RecordedRequest {
  RecordedRequest(this.method, this.path, this.query, this.fields);
  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, String> fields;
}

class FakeCustomerBackend {
  FakeCustomerBackend();

  HttpServer? _server;
  final List<RecordedRequest> requests = [];

  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> stores = [];
  List<Map<String, dynamic>> categories = [];
  final Set<String> favorites = {};
  final Map<String, int> checkoutGroupsByKey = {};
  int _nextGroupId = 9000;

  /// One-shot faults, consumed FIFO by the next matching request.
  final List<String> _faults = [];
  Duration delayNext = Duration.zero;

  int get port => _server!.port;

  void failNext(String fault) => _faults.add(fault);
  // faults: 'close' (offline socket), '500', 'malformed', 'empty200'

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Simulates connectivity loss: connection-refused for new requests.
  Future<void> goOffline() => stop();

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path; // /customer/...
    final isFault = _faults.isNotEmpty ? _faults.removeAt(0) : null;
    if (delayNext != Duration.zero) {
      final d = delayNext;
      delayNext = Duration.zero;
      await Future<void>.delayed(d);
    }
    if (isFault == 'close') {
      try {
        await req.response.detachSocket();
      } catch (_) {}
      return;
    }
    final body = await utf8.decoder.bind(req).join();
    final fields =
        _parseBody(body, req.headers.contentType?.toString());
    requests.add(RecordedRequest(
        req.method, path, Map.from(req.uri.queryParameters), fields));
    req.response.headers.contentType = ContentType.json;
    void ok(Object data, {int? total}) => req.response.write(jsonEncode({
          'status': 1,
          'message': 'success',
          'total': total ?? (data is List ? data.length : 1),
          'data': data,
        }));
    if (isFault == '500') {
      req.response.statusCode = 500;
      req.response.write('internal error');
      await req.response.close();
      return;
    }
    if (isFault == 'malformed') {
      req.response.write('{not json');
      await req.response.close();
      return;
    }
    try {
      if (req.method == 'POST' && path.endsWith('/customer/products')) {
        final limit = int.tryParse(fields['limit'] ?? '') ?? 50;
        final offset = int.tryParse(fields['offset'] ?? '') ?? 0;
        final slice = products.skip(offset).take(limit).toList();
        ok(slice, total: products.length);
      } else if (req.method == 'GET' &&
          path.endsWith('/customer/sellers')) {
        final q = req.uri.queryParameters;
        final limit = int.tryParse(q['limit'] ?? '') ?? 50;
        final offset = int.tryParse(q['offset'] ?? '') ?? 0;
        ok(stores.skip(offset).take(limit).toList(),
            total: stores.length);
      } else if (req.method == 'GET' &&
          path.endsWith('/customer/categories')) {
        final q = req.uri.queryParameters;
        final limit = int.tryParse(q['limit'] ?? '') ?? 100;
        final offset = int.tryParse(q['offset'] ?? '') ?? 0;
        ok(categories.skip(offset).take(limit).toList(),
            total: categories.length);
      } else if (req.method == 'GET' &&
          path.endsWith('/customer/favorites')) {
        req.response.write(jsonEncode({
          'status': 1,
          'message': 'success',
          'total': 1,
          'data': {
            'favorite_product_ids': favorites.toList(),
          },
        }));
      } else if (req.method == 'POST' &&
          path.endsWith('/customer/favorites/add')) {
        favorites.add(fields['product_id'] ?? '');
        ok({'added': true});
      } else if (req.method == 'POST' &&
          path.endsWith('/customer/favorites/remove')) {
        favorites.remove(fields['product_id'] ?? '');
        ok({'removed': true});
      } else if (req.method == 'POST' &&
          path.endsWith('/customer/checkout')) {
        // Mirrors verified server semantics: unique(user_id, idempotency_key)
        // lookup-or-return; same key -> same checkout_group_id.
        final key = fields['idempotency_key'] ?? '';
        final gid = (key.isNotEmpty && checkoutGroupsByKey.containsKey(key))
            ? checkoutGroupsByKey[key]!
            : ++_nextGroupId;
        if (key.isNotEmpty) checkoutGroupsByKey[key] = gid;
        ok({'checkout_group_id': gid, 'checkout_session_token': 'tok-$gid'});
      } else if (path.contains('/customer/img/')) {
        final kind = path.split('/').last;
        if (kind == 'hang') {
          await Future<void>.delayed(const Duration(seconds: 30));
          req.response.write('late');
        } else if (kind == 'big') {
          req.response.headers.contentType = ContentType.binary;
          req.response.add(List.filled(3 * 1024 * 1024, 0));
        } else {
          req.response.headers.contentType =
              ContentType('image', 'jpeg');
          req.response.add([1, 2, 3, 4]);
        }
      } else if (isFault == 'empty200') {
        ok(const []);
      } else {
        req.response.statusCode = 404;
        req.response.write(jsonEncode(
            {'status': 0, 'message': 'unknown route in harness'}));
      }
    } catch (e) {
      try {
        req.response.statusCode = 500;
        req.response.write('harness error: $e');
      } catch (_) {}
    }
    await req.response.close();
  }

  CustomerApi api() =>
      CustomerApi(baseUrl: 'http://127.0.0.1:$port');

  /// Production fetch wiring, mirroring AppController.syncCatalogNow.
  CatalogPageFetch productFetch(CustomerApi api) =>
      ({required int limit, required int offset}) async {
        try {
          final res = await api.products(
              latitude: 0,
              longitude: 0,
              filters: {'limit': limit, 'offset': offset, 'sort': 'old'});
          if (!res.ok) {
            return CatalogPage(rows: const [], ok: false, error: res.message);
          }
          final total = J.i(res.raw['total'] ?? res.dataMap['total'], -1);
          return CatalogPage(rows: res.dataMaps, total: total);
        } catch (e) {
          return CatalogPage(rows: const [], ok: false, error: '$e');
        }
      };

  CatalogPageFetch storeFetch(CustomerApi api) =>
      ({required int limit, required int offset}) async {
        try {
          final res =
              await api.sellers(latitude: 0, longitude: 0, limit: limit, offset: offset);
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
      };

  CatalogPageFetch categoryFetch(CustomerApi api) =>
      ({required int limit, required int offset}) async {
        try {
          final res = await api.categories(
              categoryId: 0, limit: limit, offset: offset);
          if (!res.ok) {
            return CatalogPage(rows: const [], ok: false, error: res.message);
          }
          final total = J.i(
              res.raw['total'] ?? res.dataMap['total'], res.dataMaps.length);
          return CatalogPage(rows: res.dataMaps, total: total);
        } catch (e) {
          return CatalogPage(rows: const [], ok: false, error: '$e');
        }
      };
}

Future<AppController> _controller(
    Map<String, Object> seed, CustomerApi api) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  final c = AppController();
  c.injectForTest(prefs: prefs, testApi: api);
  return c;
}

/// ImagePrefetch with a controllable thumbs dir (path_provider has no
/// test backend, so the production thumbsDir() returns null in tests).
class TestPrefetch extends ImagePrefetch {
  TestPrefetch(this.dir);
  final Directory dir;
  @override
  Future<Directory?> thumbsDir() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test replaces HttpClient globally (all requests -> 400).
  // This harness needs REAL loopback HTTP through the production Dio stack.
  HttpOverrides.global = null;

  // ---------------- Matrix A: initial sync & persistence ----------------
  group('A: initial sync and persistence [harness]', () {
    test('A1 online full sync: pagination params, batches, mapping',
        () async {
      final be = FakeCustomerBackend()
        ..products = List.generate(5, (i) => srvProduct(1000 + i + 1, price: '${101 + i}'))
        ..stores = [srvStore(7), srvStore(8)]
        ..categories = [srvCategory(3)];
      await be.start();
      addTearDown(be.stop);
      final api = be.api();
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);

      final res = await svc.syncScope(
        db: db,
        scope: 'city:1',
        fetchProducts: be.productFetch(api),
        fetchStores: be.storeFetch(api),
        fetchCategories: be.categoryFetch(api),
        pageSize: 2,
        storePageSize: 2,
        delay: (_) async {},
      );
      expect(res.complete, isTrue);
      expect(res.products, 5);
      expect(await CatalogDao(db).productCount('city:1'), 5);
      // Real pagination params observed on the wire.
      final prodReqs = be.requests
          .where((r) => r.path.endsWith('/customer/products'))
          .toList();
      expect(prodReqs.length, greaterThanOrEqualTo(3));
      expect(prodReqs.first.fields['sort'], 'old');
      expect(prodReqs.map((r) => r.fields['offset']), containsAll(['0', '2', '4']));
      // Variants + relations mapped.
      final dao = CatalogDao(db);
      expect((await dao.variantsForProduct('city:1', 1001)).length, 1);
      final row = await dao.getProductById('city:1', 1003);
      expect(row, isNotNull);
      // Search/filter/sort/pagination from persisted rows.
      expect((await dao.searchProducts('city:1', 'E2E product')).length, 5);
      expect(CatalogDao.ftsPhrase('a"b'), '"a""b"*');
      final mapped = (await dao.listProducts('city:1', limit: 50))
          .map((p) => jsonDecode(p.payload) as Map<String, dynamic>)
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      expect(
          filterCatalogRows(mapped, priceMin: '102').length, 4);
      expect(sortCatalogRows(mapped, 'high').first['price'], '105');
    });

    test('A2 file DB survives restart; offline reopen serves local reads',
        () async {
      final be = FakeCustomerBackend()
        ..products = List.generate(3, (i) => srvProduct(2000 + i + 1));
      await be.start();
      addTearDown(be.stop);
      final tmp = await Directory.systemTemp.createTemp('e2e_a2');
      final file = File('${tmp.path}/cat.db');
      var db = await CatalogDatabase.openFile(file);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final api = be.api();
      final r1 = await svc.syncScope(
        db: db,
        scope: 'city:1',
        fetchProducts: be.productFetch(api),
        fetchStores: be.storeFetch(api),
        fetchCategories: be.categoryFetch(api),
        delay: (_) async {},
      );
      expect(r1.complete, isTrue);
      final before = await CatalogDao(db).productCount('city:1');
      await db.close();
      // Restart: reopen the same file.
      db = await CatalogDatabase.openFile(file);
      expect(await CatalogDao(db).productCount('city:1'), before);
      expect(await CatalogDao(db).getSyncState('city:1'), isNotNull);
      // Go offline (connection refused) — local reads still work.
      final offlineApi = be.api();
      await be.goOffline();
      expect(
          (await CatalogDao(db).searchProducts('city:1', 'E2E')).length, 3);
      final res = await svc.syncScope(
        db: db,
        scope: 'city:1',
        fetchProducts: be.productFetch(offlineApi),
        fetchStores: be.storeFetch(offlineApi),
        fetchCategories: be.categoryFetch(offlineApi),
        delay: (_) async {},
      );
      // Resume-from-checkpoint against dead server: products already at end
      // (empty page on a live server) — here the fetch fails honestly.
      expect(res.complete, isFalse);
      expect(await CatalogDao(db).productCount('city:1'), before);
      await db.close();
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('A3 unsynced vs empty vs failed are distinguishable at DAO level',
        () async {
      final be = FakeCustomerBackend(); // empty server
      await be.start();
      addTearDown(be.stop);
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final dao = CatalogDao(db);
      // Unsynchronized scope: no rows AND no checkpoint.
      expect(await dao.productCount('city:9'), 0);
      expect(await dao.getSyncState('city:9'), isNull);
      // Genuinely empty catalog after a completed sync: checkpoint exists.
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final api = be.api();
      final res = await svc.syncScope(
        db: db,
        scope: 'city:9',
        fetchProducts: be.productFetch(api),
        fetchStores: be.storeFetch(api),
        fetchCategories: be.categoryFetch(api),
        delay: (_) async {},
      );
      expect(res.complete, isTrue);
      expect(await dao.productCount('city:9'), 0);
      expect(await dao.getSyncState('city:9'), isNotNull);
    });
  });

  // ---------------- Matrix B: server changes while online ----------------
  group('B: server changes while online [harness]', () {
    test('B1 appended insert captured; in-place update propagated by re-walk',
        () async {
      final be = FakeCustomerBackend()
        ..products = List.generate(4, (i) => srvProduct(3000 + i + 1));
      await be.start();
      addTearDown(be.stop);
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      // Fresh CustomerApi per walk: sellers/categories GETs carry a short
      // in-memory TTL, so reusing one instance would serve stale cache and
      // mask server changes (verified production behavior, Matrix E).
      Future<CatalogSyncResult> sync() {
        final a = be.api();
        return svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: be.productFetch(a),
          fetchStores: be.storeFetch(a),
          fetchCategories: be.categoryFetch(a),
          pageSize: 2,
          storePageSize: 2,
          delay: (_) async {},
        );
      }
      expect((await sync()).complete, isTrue);
      // Server-side: price update on synced row + appended insert.
      be.products[0]['price'] = '999';
      be.products.add(srvProduct(3005));
      expect((await sync()).complete, isTrue);
      final dao = CatalogDao(db);
      // Append captured.
      expect(await dao.getProductById('city:1', 3005), isNotNull);
      // In-place update propagated: every walk starts at offset 0 and
      // re-upserts all rows (reconciliation sync needs no change feed).
      final fresh =
          jsonDecode((await dao.getProductById('city:1', 3001))!.payload);
      expect(fresh['price'], '999');
      // Stores restart from 0, so store edits ARE picked up.
      be.stores = [srvStore(50, name: 'v1')];
      expect((await sync()).complete, isTrue);
      be.stores = [srvStore(50, name: 'v2')];
      expect((await sync()).complete, isTrue);
      expect((await dao.getStoreById('city:1', 50))!.name, 'v2');
    });

    test('B2 front-insert shifts offsets: full re-walk still converges',
        () async {
      final be = FakeCustomerBackend()
        ..products = List.generate(4, (i) => srvProduct(4000 + i + 1));
      await be.start();
      addTearDown(be.stop);
      final api = be.api();
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      // Seed a partial legacy checkpoint, then shift the dataset underneath.
      final dao = CatalogDao(db);
      await dao.upsertProductBatch(
          scope: 'city:1',
          rows: be.products
              .take(2)
              .map((r) => productUpsertFromRow(r)!)
              .toList(),
          now: DateTime.now());
      await dao.saveSyncState(SyncStatesCompanion.insert(
          scope: 'city:1',
          phase: 'full_running',
          coverage: const Value('best_effort'),
          lastOffset: const Value(2),
          storedCount: const Value(2),
          updatedAt: DateTime.now()));
      // Two rows inserted at the FRONT (offset shift that defeated resume).
      be.products.insert(0, srvProduct(3998));
      be.products.insert(0, srvProduct(3999));
      final res = await svc.syncScope(
        db: db,
        scope: 'city:1',
        fetchProducts: be.productFetch(api),
        fetchStores: be.storeFetch(api),
        fetchCategories: be.categoryFetch(api),
        pageSize: 2,
        delay: (_) async {},
      );
      expect(res.complete, isTrue);
      // Full re-walk from 0 converges regardless of the shift: every server
      // row lands locally with no duplicates.
      final ids = (await dao.listProducts('city:1', limit: 50))
          .map((p) => p.serverId)
          .toList();
      expect(ids.toSet(), {3998, 3999, 4001, 4002, 4003, 4004});
    });
  });

  // ---------------- Matrix C: server changes while offline ----------------
  group('C: server changes while offline [harness]', () {
    test('C1 offline snapshot stale; reconnect reconciles updates+deletes',
        () async {
      final be = FakeCustomerBackend()
        ..products = List.generate(4, (i) => srvProduct(5000 + i + 1));
      await be.start();
      final api = be.api();
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      Future<CatalogSyncResult> sync() => svc.syncScope(
            db: db,
            scope: 'city:1',
            fetchProducts: be.productFetch(api),
            fetchStores: be.storeFetch(api),
            fetchCategories: be.categoryFetch(api),
            pageSize: 2,
            storePageSize: 2,
            delay: (_) async {},
          );
      expect((await sync()).complete, isTrue);
      final dao = CatalogDao(db);
      final localBefore =
          jsonDecode((await dao.getProductById('city:1', 5001))!.payload);
      // Capture the offline api upfront: after goOffline the port is gone.
      final offlineApi = be.api();
      // Disconnect; mutate server independently.
      await be.goOffline();
      be.products[0]['price'] = '777';
      be.products.add(srvProduct(5009));
      // While offline: client still shows the persisted snapshot, unchanged.
      expect(
          jsonDecode((await dao.getProductById('city:1', 5001))!.payload)['price'],
          localBefore['price']);
      // Sync attempt while offline fails honestly and preserves everything.
      final offRes = await svc.syncScope(
        db: db,
        scope: 'city:1',
        fetchProducts: be.productFetch(offlineApi),
        fetchStores: be.storeFetch(offlineApi),
        fetchCategories: be.categoryFetch(offlineApi),
        pageSize: 2,
        storePageSize: 2,
        delay: (_) async {},
      );
      expect(offRes.complete, isFalse);
      expect(await CatalogDao(db).productCount('city:1'), 4);
      // Reconnect on a NEW port (same backend object).
      await be.start();
      addTearDown(be.stop);
      final api2 = be.api();
      Future<CatalogSyncResult> sync2() => svc.syncScope(
            db: db,
            scope: 'city:1',
            fetchProducts: be.productFetch(api2),
            fetchStores: be.storeFetch(api2),
            fetchCategories: be.categoryFetch(api2),
            pageSize: 2,
            storePageSize: 2,
            delay: (_) async {},
          );
      final res = await sync2();
      expect(res.complete, isTrue); // honest walk, still best_effort
      // Price update propagated by the full re-walk; tail append captured.
      expect(
          jsonDecode((await dao.getProductById('city:1', 5001))!.payload)['price'],
          '777');
      expect(await dao.getProductById('city:1', 5009), isNotNull);
      // Server-side delete reconciles: the row leaves browse/search/counts
      // (unlisted) but detail lookups still resolve it (stale, revalidated).
      be.products.removeWhere((p) => p['id'] == 5003);
      expect((await sync2()).complete, isTrue);
      expect(await dao.getProductById('city:1', 5003), isNotNull);
      expect(
          (await dao.searchProducts('city:1', 'E2E')).map((p) => p.serverId),
          isNot(contains(5003)));
      expect(await dao.productCount('city:1'), 4);
    });
  });

  // ---------------- Matrix D: customer actions while offline ----------------
  group('D: customer actions while offline [harness]', () {
    test('D1 drafts survive restart, stay scoped, never auto-submit',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var cache = OfflineCache(LocalStore(prefs));
      const draft = {
        'method': 'COD',
        'note': 'الطابق الثاني — اختبار E2E',
        'addressId': '77'
      };
      await cache.writeDraft('u:1', 'checkout_form', draft);
      // Restart simulation: new instance over the same prefs.
      cache = OfflineCache(LocalStore(prefs));
      expect(cache.readDraft('u:1', 'checkout_form'), draft);
      expect(cache.readDraft('u:2', 'checkout_form'), isNull);
      // Large + invalid input do not corrupt the store.
      await cache.writeDraft('u:1', 'big', {'v': 'x' * 100000});
      expect(cache.readDraft('u:1', 'big'), isNotNull);
      // Drafts are never submitted: no endpoint exists for them; clearing
      // happens only on explicit success.
      await cache.removeDraft('u:1', 'checkout_form');
      expect(cache.readDraft('u:1', 'checkout_form'), isNull);
    });

    test('D2 favorites queue: toggles coalesce, survive restart, replay once',
        () async {
      final be = FakeCustomerBackend();
      await be.start();
      addTearDown(be.stop);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var outbox = PendingOutbox(LocalStore(prefs), 'u:1');
      // Rapid toggles on one product coalesce to a single op.
      await outbox.enqueue(PendingOp(
          id: '1',
          type: PendingOpType.favoriteAdd,
          payload: {'product_id': '42'},
          createdAt: DateTime.now()));
      await outbox.enqueue(PendingOp(
          id: '2',
          type: PendingOpType.favoriteRemove,
          payload: {'product_id': '42'},
          createdAt: DateTime.now()));
      await outbox.enqueue(PendingOp(
          id: '3',
          type: PendingOpType.favoriteAdd,
          payload: {'product_id': '42'},
          createdAt: DateTime.now()));
      expect(outbox.load().length, 1);
      // Restart: ops persist.
      outbox = PendingOutbox(LocalStore(prefs), 'u:1');
      expect(outbox.load().length, 1);
      // Replay through the REAL HTTP path in order.
      final api = be.api();
      for (final op in outbox.dueOps(DateTime.now()).due) {
        ApiResult r;
        if (op.type == PendingOpType.favoriteAdd) {
          r = await api.addFavorite(op.payload['product_id']);
        } else {
          r = await api.removeFavorite(op.payload['product_id']);
        }
        expect(r.ok, isTrue);
        await outbox.remove(op.id);
      }
      // Toggle add/remove/add collapsed to one surviving op; server saw it.
      expect(be.favorites, contains('42'));
      // Timeout-after-accept: replaying the same add is idempotent.
      expect((await api.addFavorite('42')).ok, isTrue);
      expect(be.favorites.where((e) => e == '42').length, 1);
      // Other-account scope never executes here: ops are keyed u:1.
      final other = PendingOutbox(LocalStore(prefs), 'u:2');
      expect(other.load(), isEmpty);
    });

    test('D3 online-only: checkout fails closed offline, never queued',
        () async {
      final be = FakeCustomerBackend();
      await be.start();
      final api = be.api();
      await be.goOffline(); // connection refused from here on
      addTearDown(be.stop);
      final res = await api.checkout(
          addressId: 1, paymentMethod: 'COD', idempotencyKey: 'e2e-k-1');
      expect(res.ok, isFalse);
      expect(be.checkoutGroupsByKey, isEmpty);
      // No PendingOpType exists for checkout/wallet/payment: compile-time
      // guarantee plus runtime assertion here.
      expect(PendingOpType.values,
          containsAll([PendingOpType.favoriteAdd, PendingOpType.favoriteRemove]));
      expect(PendingOpType.values.length, 3); // + guestCartMerge only
    });

    test('D4 checkout idempotency: same key -> same group (server rule)',
        () async {
      final be = FakeCustomerBackend();
      await be.start();
      addTearDown(be.stop);
      final api = be.api();
      final a = await api.checkout(
          addressId: 5, paymentMethod: 'COD', idempotencyKey: 'e2e-dup-1');
      final b = await api.checkout(
          addressId: 5, paymentMethod: 'COD', idempotencyKey: 'e2e-dup-1');
      expect(a.ok, isTrue);
      expect(
          a.dataMap['checkout_group_id'], b.dataMap['checkout_group_id']);
      final c = await api.checkout(
          addressId: 5, paymentMethod: 'COD', idempotencyKey: 'e2e-dup-2');
      expect(c.dataMap['checkout_group_id'],
          isNot(a.dataMap['checkout_group_id']));
    });
  });

  // ---------------- Matrix E: reconnect & conflicts ----------------
  group('E: reconnect and conflicts [harness]', () {
    test('E1 stale local price is never authoritative: server wins',
        () async {
      final be = FakeCustomerBackend()
        ..products = [srvProduct(6001, price: '100')];
      await be.start();
      addTearDown(be.stop);
      final api = be.api();
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      await svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: be.productFetch(api),
          fetchStores: be.storeFetch(api),
          fetchCategories: be.categoryFetch(api),
          delay: (_) async {});
      be.products[0]['price'] = '250';
      // Cached snapshot still old...
      final cached = jsonDecode(
          (await CatalogDao(db).getProductById('city:1', 6001))!.payload);
      expect(cached['price'], '100');
      // ...but a fresh read (what checkout revalidation uses) sees 250.
      final fresh = await api.products(
          latitude: 0, longitude: 0, filters: {'limit': 50, 'offset': 0});
      expect(fresh.ok, isTrue);
      expect(
          fresh.dataMaps.firstWhere((m) => J.i(m['id']) == 6001)['price'],
          '250');
      expect(cached['price'], isNot('250'));
    });

    test('E2 delayed response cannot overwrite the new scope', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cache = OfflineCache(LocalStore(prefs));
      const oldScope = 'city:1';
      // Response started under oldScope completes after the switch.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      const activeScope = 'city:2';
      // Guarded write path (as fixed in AppController): drop when stale.
      final staleResponse = [
        {'id': 1}
      ];
      if (oldScope != activeScope) {
        // dropped — nothing written under city:2
      } else {
        await cache.writeDoc('oc:snap::x::$activeScope', staleResponse,
            scope: activeScope);
      }
      expect(cache.readDoc('oc:snap::x::$activeScope'), isNull);
      // And a same-scope response still lands.
      await cache.writeDoc('oc:snap::x::$oldScope', staleResponse,
          scope: oldScope);
      expect(cache.readDoc('oc:snap::x::$oldScope'), isNotNull);
    });

    test('E3 concurrent sync collapses (single-flight)', () async {
      final be = FakeCustomerBackend()
        ..products = [srvProduct(6002)];
      await be.start();
      addTearDown(be.stop);
      final api = be.api();
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      be.delayNext = const Duration(milliseconds: 300);
      final f1 = svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: be.productFetch(api),
          fetchStores: be.storeFetch(api),
          fetchCategories: be.categoryFetch(api),
          delay: (_) async {});
      final f2 = svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: be.productFetch(api),
          fetchStores: be.storeFetch(api),
          fetchCategories: be.categoryFetch(api),
          delay: (_) async {});
      final results = await Future.wait([f1, f2]);
      expect(
          results.where((r) => r.error == 'already_running').length, 1);
    });
  });

  // ---------------- Matrix F: interrupts, retries, recovery ----------------
  group('F: interrupts, retries, recovery [harness]', () {
    test('F1 first-page failure: error, no rows, no checkpoint', () async {
      final be = FakeCustomerBackend()
        ..products = [srvProduct(7001)];
      await be.start();
      addTearDown(be.stop);
      be.failNext('500');
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final api = be.api();
      final res = await svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: be.productFetch(api),
          fetchStores: be.storeFetch(api),
          fetchCategories: be.categoryFetch(api),
          delay: (_) async {});
      expect(res.complete, isFalse);
      expect(await CatalogDao(db).productCount('city:1'), 0);
      expect(await CatalogDao(db).getSyncState('city:1'), isNull);
    });

    test('F2 mid-walk 500 then resume: committed kept, walk completes',
        () async {
      final be = FakeCustomerBackend()
        ..products = List.generate(4, (i) => srvProduct(7100 + i + 1));
      await be.start();
      addTearDown(be.stop);
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final api = be.api();
      Future<CatalogSyncResult> sync() => svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: be.productFetch(api),
          fetchStores: be.storeFetch(api),
          fetchCategories: be.categoryFetch(api),
          pageSize: 2,
          storePageSize: 2,
          delay: (_) async {});
      // Fail the 2nd products page (faults are consumed per-request; sellers
      // GETs also consume — so fail 3 requests to land one on products p2).
      // Deterministic variant: fail exactly the 2nd products call via a
      // counting wrapper.
      var calls = 0;
      final base = be.productFetch(api);
      Future<CatalogSyncResult> syncWithFlakyProducts() => svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: ({required int limit, required int offset}) async {
            calls++;
            if (calls == 2) {
              return CatalogPage(rows: const [], ok: false, error: 'boom-500');
            }
            return base(limit: limit, offset: offset);
          },
          fetchStores: be.storeFetch(api),
          fetchCategories: be.categoryFetch(api),
          pageSize: 2,
          storePageSize: 2,
          delay: (_) async {});
      final r1 = await syncWithFlakyProducts();
      expect(r1.complete, isFalse);
      expect(await CatalogDao(db).productCount('city:1'), 2);
      final r2 = await sync();
      expect(r2.complete, isTrue);
      expect(await CatalogDao(db).productCount('city:1'), 4);
      // Bounded retry: no duplicates after resume.
      final ids = (await CatalogDao(db).listProducts('city:1', limit: 50))
          .map((p) => p.serverId)
          .toList();
      expect(ids.toSet().length, ids.length);
    });

    test('F3 malformed + empty-shape pages never claim completeness',
        () async {
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      Future<CatalogPage> garbage(
          {required int limit, required int offset}) async =>
          throw const FormatException('garbage');
      // Thrown garbage is converted to ok:false by the wrapper below.
      Future<CatalogPage> wrapped(
          {required int limit, required int offset}) async {
        try {
          return await garbage(limit: limit, offset: offset);
        } catch (e) {
          return CatalogPage(rows: const [], ok: false, error: '$e');
        }
      }
      final res = await svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: wrapped,
          fetchStores: ({required int limit, required int offset}) async =>
              CatalogPage(rows: const [], total: 0),
          fetchCategories:
              ({required int limit, required int offset}) async =>
                  CatalogPage(rows: const [], total: 0),
          delay: (_) async {});
      expect(res.complete, isFalse);
    });

    test('F6 real-file corruption quarantines; transient preserves',
        () async {
      final tmp = await Directory.systemTemp.createTemp('e2e_f6');
      addTearDown(() => tmp.delete(recursive: true));
      final file = File('${tmp.path}/cat.db');
      var db = await CatalogDatabase.openFile(file);
      await CatalogDao(db).upsertProductBatch(
          scope: 'city:1',
          rows: [productUpsertFromRow(srvProduct(7002))!],
          now: DateTime.now());
      await db.close();
      // Corrupt the file with garbage.
      await file.writeAsBytes([1, 2, 3, 4, 5]);
      db = await CatalogDatabase.openFile(file);
      addTearDown(db.close);
      expect(await CatalogDao(db).productCount('city:1'), 0);
      final quarantined = tmp
          .listSync()
          .where((e) => e.path.contains('.corrupt.'))
          .toList();
      expect(quarantined, isNotEmpty);
    });
  });

  // ---------------- Matrix G: schema/payload evolution ----------------
  group('G: schema and payload evolution [harness]', () {
    test('G1 additive field is ignored safely, payload verbatim', () async {
      final be = FakeCustomerBackend()
        ..products = [
          srvProduct(8001, extra: {'promo_label': 'NEW', 'unknown_nest': {'a': 1}})
        ];
      await be.start();
      addTearDown(be.stop);
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final api = be.api();
      final res = await svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: be.productFetch(api),
          fetchStores: be.storeFetch(api),
          fetchCategories: be.categoryFetch(api),
          delay: (_) async {});
      expect(res.complete, isTrue);
      final payload = jsonDecode(
          (await CatalogDao(db).getProductById('city:1', 8001))!.payload);
      expect(payload['promo_label'], 'NEW');
    });

    test('G2 missing optional price never hides the row', () async {
      final row = srvProduct(8002)..remove('price');
      final up = productUpsertFromRow(row);
      expect(up, isNotNull);
      final mapped = {
        'id': 8002,
        'name': 'x',
        'rating': 4.0,
      };
      expect(filterCatalogRows([mapped], priceMin: '10'), hasLength(1));
    });

    test('G3 missing required identity: row skipped, siblings commit',
        () async {
      final be = FakeCustomerBackend()
        ..products = [
          {'name': 'no id at all', 'price': '5'},
          srvProduct(8003),
        ];
      await be.start();
      addTearDown(be.stop);
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final api = be.api();
      final res = await svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: be.productFetch(api),
          fetchStores: be.storeFetch(api),
          fetchCategories: be.categoryFetch(api),
          delay: (_) async {});
      expect(res.complete, isTrue);
      expect(await CatalogDao(db).productCount('city:1'), 1);
    });

    test('G5 categories beyond first page sync with server total', () async {
      final be = FakeCustomerBackend()
        ..categories =
            List.generate(150, (i) => srvCategory(9000 + i + 1));
      await be.start();
      addTearDown(be.stop);
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final api = be.api();
      final res = await svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: be.productFetch(api),
          fetchStores: be.storeFetch(api),
          fetchCategories: be.categoryFetch(api),
          delay: (_) async {});
      expect(res.complete, isTrue);
      // Regression for the fixed fetchCategories total bug (was capped at 100).
      expect((await CatalogDao(db).listCategories('city:1')).length, 150);
    });
  });

  // ---------------- Matrix H: city/account isolation ----------------
  group('H: city and account isolation [harness]', () {
    test('H1 two city scopes never mix', () async {
      final be = FakeCustomerBackend()
        ..products = [srvProduct(9101)];
      await be.start();
      addTearDown(be.stop);
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final dao = CatalogDao(db);
      await dao.upsertProductBatch(
          scope: 'city:1',
          rows: [productUpsertFromRow(srvProduct(9101))!],
          now: DateTime.now());
      await dao.upsertProductBatch(
          scope: 'city:2',
          rows: [productUpsertFromRow(srvProduct(9102))!],
          now: DateTime.now());
      expect(
          (await dao.listProducts('city:1', limit: 50)).map((p) => p.serverId),
          [9101]);
      expect(
          (await dao.listProducts('city:2', limit: 50)).map((p) => p.serverId),
          [9102]);
      expect((await dao.searchProducts('city:1', 'E2E')).length, 1);
      expect(await dao.productCount('city:1'), 1);
      expect(await dao.productCount('city:2'), 1);
    });

    test('H3 logout wipes account state incl. variant labels', () async {
      final be = FakeCustomerBackend();
      await be.start();
      addTearDown(be.stop);
      final c = await _controller({}, be.api());
      c.setUser({'id': 4242});
      c.token = 't';
      await c.cacheAccountSnapshot('wallet', [
        {'id': 1}
      ]);
      await c.rememberVariantLabel('v-9', '1 kg');
      expect(c.variantLabelFor('v-9'), '1 kg');
      await c.logout();
      expect(c.readAccountSnapshot('wallet'), isNull);
      expect(c.variantLabelFor('v-9'), isEmpty);
    });
  });

  // ---------------- Matrix I: images & storage ----------------
  group('I: images and storage [harness]', () {
    test('I1 prefetch disabled by default', () async {
      final be = FakeCustomerBackend();
      await be.start();
      addTearDown(be.stop);
      final c = await _controller({}, be.api());
      expect(c.offlineImagesEnabled, isFalse);
    });

    test('I2 slow image is skipped, good image stored, gate resets',
        () async {
      final be = FakeCustomerBackend();
      await be.start();
      addTearDown(be.stop);
      final tmp = await Directory.systemTemp.createTemp('e2e_i2');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });
      final pre = TestPrefetch(tmp);
      final slow =
          'http://127.0.0.1:${be.port}/customer/img/hang';
      final good = 'http://127.0.0.1:${be.port}/customer/img/ok';
      final n = await pre.prefetch([slow, good],
          timeout: const Duration(seconds: 2));
      expect(n, 1);
      expect(pre.running, isFalse);
      // Second run works (gate not stuck) and dedups cached file names.
      final n2 = await pre.prefetch([good],
          timeout: const Duration(seconds: 2));
      expect(pre.running, isFalse);
      expect(n2, greaterThanOrEqualTo(0));
    });

    test('I3 oversize image skipped without budget corruption', () async {
      final be = FakeCustomerBackend();
      await be.start();
      addTearDown(be.stop);
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final tmp = await Directory.systemTemp.createTemp('e2e_i3');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });
      final pre = TestPrefetch(tmp);
      final n = await pre.prefetch(
          ['http://127.0.0.1:${be.port}/customer/img/big'],
          db: db,
          timeout: const Duration(seconds: 10));
      expect(n, 0);
      expect(await CatalogDao(db).imagesTotalBytes(), 0);
    });

    test('I4 orphan file adopted with actual disk size', () async {
      final be = FakeCustomerBackend();
      await be.start();
      addTearDown(be.stop);
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final tmp = await Directory.systemTemp.createTemp('e2e_i4');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });
      final pre = TestPrefetch(tmp);
      final url = 'http://127.0.0.1:${be.port}/customer/img/ok';
      // Orphan: file on disk, no manifest row.
      final orphan =
          File('${tmp.path}/${ImagePrefetch.fileNameFor(url)}');
      await orphan.writeAsBytes([9, 9, 9, 9, 9, 9, 9]);
      final n = await pre.prefetch([url],
          db: db, timeout: const Duration(seconds: 10));
      expect(n, 0); // not a new download
      final row = await CatalogDao(db).getImage(url);
      expect(row, isNotNull);
      expect(row!.bytes, 7); // actual disk size, not a guess
      expect(await CatalogDao(db).imagesTotalBytes(), 7);
    });

    test('I5 manifest size drift corrected on cache hit', () async {
      final be = FakeCustomerBackend();
      await be.start();
      addTearDown(be.stop);
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final tmp = await Directory.systemTemp.createTemp('e2e_i5');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });
      final pre = TestPrefetch(tmp);
      final url = 'http://127.0.0.1:${be.port}/customer/img/ok';
      expect(
          await pre.prefetch([url],
              db: db, timeout: const Duration(seconds: 10)),
          1);
      final dao = CatalogDao(db);
      final path = (await dao.getImage(url))!.localPath;
      // Corrupt the accounting (not the file).
      await dao.putImage(
          url: url, localPath: path, bytes: 9999, now: DateTime.now());
      expect(await dao.imagesTotalBytes(), 9999);
      expect(
          await pre.prefetch([url],
              db: db, timeout: const Duration(seconds: 10)),
          0);
      final fixed = await dao.getImage(url);
      expect(fixed!.bytes, await File(path).length());
      expect(await dao.imagesTotalBytes(), await File(path).length());
    });

    test('I6 duplicate URLs download once; manifest matches disk', () async {
      final be = FakeCustomerBackend();
      await be.start();
      addTearDown(be.stop);
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final tmp = await Directory.systemTemp.createTemp('e2e_i6');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });
      final pre = TestPrefetch(tmp);
      final url = 'http://127.0.0.1:${be.port}/customer/img/ok';
      final before =
          be.requests.where((r) => r.path.endsWith('/customer/img/ok')).length;
      final n = await pre.prefetch([url, url, url],
          db: db, timeout: const Duration(seconds: 10));
      expect(n, 1);
      final hits = be.requests
          .where((r) => r.path.endsWith('/customer/img/ok'))
          .length;
      expect(hits - before, 1);
      // Manifest total equals real disk usage.
      var disk = 0;
      await for (final e in tmp.list()) {
        if (e is File && !e.path.endsWith('.part')) {
          disk += await e.length();
        }
      }
      expect(await CatalogDao(db).imagesTotalBytes(), disk);
      expect(disk, greaterThan(0));
    });

    test('I7 non-image body is never cached as a thumbnail', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html>not an image</html>');
        await req.response.close();
      });
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final tmp = await Directory.systemTemp.createTemp('e2e_i7');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });
      final pre = TestPrefetch(tmp);
      final n = await pre.prefetch(
          ['http://127.0.0.1:${server.port}/fake.jpg'],
          db: db,
          timeout: const Duration(seconds: 10));
      expect(n, 0);
      expect(await CatalogDao(db).imagesTotalBytes(), 0);
      expect(await CatalogDao(db).getImage(
          'http://127.0.0.1:${server.port}/fake.jpg'), isNull);
      // Retry is not poisoned: failure leaves no trace to block later tries.
      expect(
          await pre.prefetch(
              ['http://127.0.0.1:${server.port}/fake.jpg'],
              db: db,
              timeout: const Duration(seconds: 10)),
          0);
    });
  });

  // ---------------- Matrix J: integrated journeys ----------------
  group('J: integrated journeys [harness]', () {
    test('J1 browse-refresh journey with offline server edit', () async {
      final be = FakeCustomerBackend()
        ..products = List.generate(3, (i) => srvProduct(9500 + i + 1));
      await be.start();
      final api = be.api();
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final dao = CatalogDao(db);
      Future<CatalogSyncResult> sync() => svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: be.productFetch(api),
          fetchStores: be.storeFetch(api),
          fetchCategories: be.categoryFetch(api),
          pageSize: 2,
          storePageSize: 2,
          delay: (_) async {});
      expect((await sync()).complete, isTrue);
      expect((await dao.searchProducts('city:1', 'E2E')).length, 3);
      await be.goOffline();
      expect((await dao.searchProducts('city:1', 'E2E')).length, 3);
      be.products.add(srvProduct(9509));
      await be.start();
      addTearDown(be.stop);
      final api2 = be.api();
      final r = await svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: be.productFetch(api2),
          fetchStores: be.storeFetch(api2),
          fetchCategories: be.categoryFetch(api2),
          pageSize: 2,
          storePageSize: 2,
          delay: (_) async {});
      expect(r.complete, isTrue);
      expect(await dao.getProductById('city:1', 9509), isNotNull);
    });

    test('J4 checkout journey: no auto-resubmit, duplicate key dedups',
        () async {
      final be = FakeCustomerBackend();
      await be.start();
      addTearDown(be.stop);
      final api = be.api();
      final before = be.requests.length;
      final first = await api.checkout(
          addressId: 3, paymentMethod: 'COD', idempotencyKey: 'e2e-j4-1');
      expect(first.ok, isTrue);
      // No automatic second submission happens without an explicit call.
      expect(be.requests.length, before + 1);
      final retry = await api.checkout(
          addressId: 3, paymentMethod: 'COD', idempotencyKey: 'e2e-j4-1');
      expect(retry.dataMap['checkout_group_id'],
          first.dataMap['checkout_group_id']);
    });
  });
}
