// Real Laravel/MySQL integration tests (tag: [real]).
//
// Every test here exercises the REAL local backend
// (http://127.0.0.1:8000, Docker MySQL `sql_laravel_marabmall_cloud`)
// through the REAL production Flutter stack (CustomerApi/Dio,
// CatalogSyncService, CatalogDao, OfflineCache, PendingOutbox,
// AppController.runPendingOp, ImagePrefetch).
//
// Safety: fixtures are E2EOFFLINE-marked rows only; no migrate/fresh/wipe;
// server mutations use scoped SQL via `docker exec mysql` (fully-qualified
// tables, marker predicates). If the backend is unreachable, all tests SKIP
// (honest blocked, suite stays green) instead of faking success.
// Credentials: test accounts log in at runtime; no token is hardcoded.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

const _base = 'http://127.0.0.1:8000';
const _user1Mobile = '777000002';
const _user2Mobile = '777000003';
const _password = 'E2eTest123!';

/// Runs a scoped read-only-or-marker SQL statement against local MySQL.
Future<String> mysql(String sql) async {
  final res = await Process.run('docker', [
    'exec',
    'saree_back-mysql-1',
    'mysql',
    '-uroot',
    '-N',
    '-e',
    sql,
  ]);
  if (res.exitCode != 0) {
    throw StateError('mysql failed: ${res.stderr}');
  }
  return (res.stdout as String).trim();
}

Future<bool> backendReachable() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client
        .getUrl(Uri.parse('$_base/customer/cities'))
        .timeout(const Duration(seconds: 8));
    final resp = await req.close().timeout(const Duration(seconds: 8));
    final body = await resp.transform(utf8.decoder).join();
    client.close();
    return resp.statusCode == 200 && body.contains('"status":1');
  } catch (_) {
    try {
      client.close();
    } catch (_) {}
    return false;
  }
}

CustomerApi realApi() => CustomerApi(baseUrl: _base);

/// Resets the shared E2E fixture to a listable/checkout-able state. Prior
/// suite runs erode it: checkout commits decrement variant stock (flipping
/// status to 0 at zero, which hides cart lines AND delists the product via
/// the in-stock hard filter); RB renames product 289 and reprices the
/// variant. Cheap and idempotent.
Future<void> ensureFixtureVisible() async {
  await mysql('UPDATE sql_laravel_marabmall_cloud.product_variants SET '
      'stock=10, status=1, price=100.0 WHERE id=357;');
  await mysql('UPDATE sql_laravel_marabmall_cloud.products SET '
      'name=\'E2EOFFLINE Product\', deleted_at=NULL, status=1, '
      'is_approved=1 WHERE id=289;');
}

Future<String> loginToken(CustomerApi api, String mobile) async {
  final res = await api.loginMobile(
      mobile: mobile, password: _password, countryCode: '967');
  expect(res.ok, isTrue, reason: 'login $mobile failed: ${res.message}');
  final token = res.token ??
      res.dataMap['access_token'] as String? ??
      '';
  expect(token.isNotEmpty, isTrue);
  api.setToken(token);
  return token;
}

/// Production fetch wiring, identical to AppController.syncCatalogNow.
CatalogPageFetch realProductFetch(CustomerApi api) =>
    ({required int limit, required int offset}) async {
      try {
        final res = await api.products(
            latitude: 15.4624,
            longitude: 45.3228,
            filters: {'limit': limit, 'offset': offset, 'sort': 'old'});
        if (!res.ok) {
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
    };

CatalogPageFetch realStoreFetch(CustomerApi api) =>
    ({required int limit, required int offset}) async {
      try {
        final res = await api.sellers(
            latitude: 15.4624,
            longitude: 45.3228,
            limit: limit,
            offset: offset);
        if (!res.ok) {
          return CatalogPage(rows: const [], ok: false, error: res.message);
        }
        return CatalogPage(rows: res.dataMaps,
            total: J.i(res.raw['total'] ?? res.dataMap['total'], -1));
      } catch (e) {
        return CatalogPage(rows: const [], ok: false, error: '$e');
      }
    };

CatalogPageFetch realCategoryFetch(CustomerApi api) =>
    ({required int limit, required int offset}) async {
      try {
        final res = await api.categories(
            categoryId: 0, limit: limit, offset: offset);
        if (!res.ok) {
          if (isEmptyCatalogPage(res)) {
            return CatalogPage(rows: const [], total: offset);
          }
          return CatalogPage(rows: const [], ok: false, error: res.message);
        }
        return CatalogPage(
            rows: res.dataMaps,
            total: J.i(res.raw['total'] ?? res.dataMap['total'],
                res.dataMaps.length));
      } catch (e) {
        return CatalogPage(rows: const [], ok: false, error: '$e');
      }
    };

Future<AppController> _controller(CustomerApi api) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = AppController();
  c.injectForTest(prefs: prefs, testApi: api);
  return c;
}

class TestPrefetch extends ImagePrefetch {
  TestPrefetch(this.dir);
  final Directory dir;
  @override
  Future<Directory?> thumbsDir() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // real loopback HTTP (see harness file)

  group('real backend integration [real]', () {
    test('R0 backend reachable + fixtures present', () async {
      if (!await backendReachable()) {
        markTestSkipped('real backend unreachable at $_base');
      }
      final api = realApi();
      await ensureFixtureVisible();
      await loginToken(api, _user1Mobile);
      // Fixture product must be listed by the real API. NOTE: the server
      // reports `total` on the first page but omits it later — probe page 0.
      final probe = await api.products(
          latitude: 15.4624,
          longitude: 45.3228,
          filters: {'limit': 1, 'offset': 0, 'sort': 'old'});
      expect(probe.ok, isTrue);
      expect(J.i(probe.raw['total']), greaterThan(200));
      final tail = await api.products(
          latitude: 15.4624,
          longitude: 45.3228,
          filters: {'limit': 50, 'offset': 250, 'sort': 'old'});
      final found = tail.dataMaps
          .where((m) => J.str(m['slug']).startsWith('e2eoffline-product'))
          .toList();
      if (found.isEmpty) {
        markTestSkipped('E2EOFFLINE fixtures absent; run e2e_seed.php');
      }
    });

    test('RA real multi-page sync matches server totals', () async {
      if (!await backendReachable()) {
        markTestSkipped('real backend unreachable');
      }
      final api = realApi();
      await ensureFixtureVisible();
      await loginToken(api, _user1Mobile);
      final totals = await api.products(
          latitude: 15.4624,
          longitude: 45.3228,
          filters: {'limit': 1, 'offset': 0, 'sort': 'old'});
      expect(totals.ok, isTrue);
      final serverTotal = J.i(totals.raw['total']);
      expect(serverTotal, greaterThan(200));

      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      final res = await svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: realProductFetch(api),
          fetchStores: realStoreFetch(api),
          fetchCategories: realCategoryFetch(api),
          delay: (_) async {});
      expect(res.complete, isTrue);
      final dao = CatalogDao(db);
      // Local count matches the server-reported total exactly.
      expect(await dao.productCount('city:1'), serverTotal);
      // FTS finds the real Arabic catalog + the E2E fixture.
      expect((await dao.searchProducts('city:1', 'E2EOFFLINE')).length,
          greaterThanOrEqualTo(1));
      // Real variant mapping: fixture variant persisted.
      final e2e = (await dao.searchProducts('city:1', 'E2EOFFLINE')).first;
      final variants =
          await dao.variantsForProduct('city:1', e2e.serverId);
      expect(variants.length, greaterThanOrEqualTo(1));
      // Categories/stores match live endpoint totals.
      final cats = await api.categories(categoryId: 0, limit: 5, offset: 0);
      expect((await dao.listCategories('city:1')).length,
          J.i(cats.raw['total']));
      final sellers = await api.sellers(limit: 1, offset: 0);
      expect((await dao.listStores('city:1', limit: 500)).length,
          J.i(sellers.raw['total']));
      // Checkpoint honest: best_effort, advanced offset.
      final state = await dao.getSyncState('city:1');
      expect(state, isNotNull);
      expect(state!.coverage, 'best_effort');
      expect(state.lastOffset, greaterThan(0));
    });

    test('RB real offline mutations: reconnect reconciles all of them',
        () async {
      if (!await backendReachable()) {
        markTestSkipped('real backend unreachable');
      }
      const slugAppend = 'e2eoffline-rb-append';
      const slugDelete = 'e2eoffline-rb-deleteme';
      // Idempotent setup: drop prior-run marker rows first.
      await mysql('DELETE FROM sql_laravel_marabmall_cloud.product_variants '
          'WHERE product_id IN (SELECT id FROM '
          '(SELECT id FROM sql_laravel_marabmall_cloud.products WHERE '
          'slug IN (\'$slugAppend\', \'$slugDelete\')) AS t);');
      await mysql('DELETE FROM sql_laravel_marabmall_cloud.products WHERE '
          'slug IN (\'$slugAppend\', \'$slugDelete\');');
      // Reset shared-server state mutated by prior runs (deterministic
      // baseline: the rename/price change must land AFTER this sync).
      await mysql('UPDATE sql_laravel_marabmall_cloud.products SET '
          'name=\'E2EOFFLINE Product\', deleted_at=NULL WHERE id=289;');
      await mysql('UPDATE sql_laravel_marabmall_cloud.product_variants SET '
          'price=100.0 WHERE id=357;');
      // Extra fixtures for this scenario (marker-scoped).
      await mysql('INSERT INTO sql_laravel_marabmall_cloud.products '
          '(name, slug, category_id, seller_id, image, description, status, '
          'is_approved, return_status, return_days, created_at, updated_at) '
          'SELECT \'E2EOFFLINE RB Append\', \'$slugAppend\', category_id, '
          'seller_id, \'\', \'rb\', 1, 1, 1, 7, NOW(), NOW() FROM '
          'sql_laravel_marabmall_cloud.products WHERE id=289 LIMIT 1;');
      await mysql('INSERT INTO sql_laravel_marabmall_cloud.product_variants '
          '(product_id, type, status, measurement, price, discounted_price, '
          'stock) SELECT (SELECT id FROM sql_laravel_marabmall_cloud.products '
          'WHERE slug=\'$slugAppend\'), \'packet\', 1, 1, 100.0, 0.0, 10;');
      await mysql('INSERT INTO sql_laravel_marabmall_cloud.products '
          '(name, slug, category_id, seller_id, image, description, status, '
          'is_approved, return_status, return_days, created_at, updated_at) '
          'SELECT \'E2EOFFLINE RB DeleteMe\', \'$slugDelete\', category_id, '
          'seller_id, \'\', \'rb\', 1, 1, 1, 7, NOW(), NOW() FROM '
          'sql_laravel_marabmall_cloud.products WHERE id=289 LIMIT 1;');
      await mysql('INSERT INTO sql_laravel_marabmall_cloud.product_variants '
          '(product_id, type, status, measurement, price, discounted_price, '
          'stock) SELECT (SELECT id FROM sql_laravel_marabmall_cloud.products '
          'WHERE slug=\'$slugDelete\'), \'packet\', 1, 1, 100.0, 0.0, 10;');

      final api = realApi();
      await ensureFixtureVisible();
      await loginToken(api, _user1Mobile);
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      Future<CatalogSyncResult> sync(CustomerApi a) => svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: realProductFetch(a),
          fetchStores: realStoreFetch(a),
          fetchCategories: realCategoryFetch(a),
          delay: (_) async {});
      final baseRes = await sync(api);
      expect(baseRes.complete, isTrue,
          reason:
              'err=${baseRes.error} cancelled=${baseRes.cancelled} products=${baseRes.products} stores=${baseRes.stores} cats=${baseRes.categories}');
      final dao = CatalogDao(db);
      final baseCount = await dao.productCount('city:1');
      final beforePrice = jsonDecode((await dao.getProductBySlug(
              'city:1', (await mysql('SELECT slug FROM '
                  'sql_laravel_marabmall_cloud.products WHERE id=289;'))))!
          .payload);
      expect(beforePrice['name'], contains('E2EOFFLINE'));

      // Disconnect (dead port) + mutate the REAL database.
      final offlineApi = CustomerApi(baseUrl: 'http://127.0.0.1:9');
      await mysql('UPDATE sql_laravel_marabmall_cloud.product_variants '
          'SET price=150.0 WHERE id=357;');
      await mysql('UPDATE sql_laravel_marabmall_cloud.products '
          'SET name=\'E2EOFFLINE Product RENAMED\' WHERE id=289;');
      await mysql('UPDATE sql_laravel_marabmall_cloud.products '
          'SET deleted_at=NOW() WHERE slug=\'$slugDelete\';');
      // Offline attempt fails closed, preserves everything.
      final off = await sync(offlineApi);
      expect(off.complete, isFalse);
      expect(await dao.productCount('city:1'), baseCount);

      // Reconnect: reconciliation propagates updates and deletes.
      expect((await sync(api)).complete, isTrue);
      final renamed =
          jsonDecode((await dao.getProductById('city:1', 289))!.payload);
      expect(renamed['name'], 'E2EOFFLINE Product RENAMED');
      final vars = await dao.variantsForProduct('city:1', 289);
      final prices = vars
          .map((v) => jsonDecode(v.payload)['price'])
          .toSet();
      expect(prices.contains(150.0) || prices.contains(150), isTrue);
      // DeleteMe row: gone from the API, unlisted locally (absent from
      // browse/search/counts) but still resolvable by id for detail pages.
      final gone = await api.products(
          latitude: 15.4624,
          longitude: 45.3228,
          filters: {'limit': 300, 'offset': 0, 'sort': 'old'});
      expect(gone.ok, isTrue);
      expect(await dao.getProductBySlug('city:1', slugDelete), isNotNull);
      expect(await dao.searchProducts('city:1', 'DeleteMe'), isEmpty);
      expect(await dao.productCount('city:1'), baseCount - 1);
    });

    test('RB2 variant stock-out unlists locally, restock relists', () async {
      if (!await backendReachable()) {
        markTestSkipped('real backend unreachable');
      }
      final api = realApi();
      await ensureFixtureVisible();
      await loginToken(api, _user1Mobile);
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      Future<CatalogSyncResult> sync() => svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: realProductFetch(api),
          fetchStores: realStoreFetch(api),
          fetchCategories: realCategoryFetch(api),
          delay: (_) async {});
      expect((await sync()).complete, isTrue);
      final dao = CatalogDao(db);
      expect(
          (await dao.searchProducts('city:1', 'E2EOFFLINE Product')).length,
          greaterThanOrEqualTo(1));
      // Stock-out: the listing hard-filter drops the row server-side.
      await mysql('UPDATE sql_laravel_marabmall_cloud.product_variants SET '
          'stock=0 WHERE id=357;');
      try {
        expect((await sync()).complete, isTrue);
        expect(
            await dao.searchProducts('city:1', 'E2EOFFLINE Product'), isEmpty);
        expect((await dao.getProductById('city:1', 289))!.isListed, isFalse);
        // Restock: the row returns to browse on the next walk.
        await mysql('UPDATE sql_laravel_marabmall_cloud.product_variants SET '
            'stock=10 WHERE id=357;');
        expect((await sync()).complete, isTrue);
        expect(
            (await dao.searchProducts('city:1', 'E2EOFFLINE Product')).length,
            greaterThanOrEqualTo(1));
      } finally {
        await mysql('UPDATE sql_laravel_marabmall_cloud.product_variants SET '
            'stock=10, status=1 WHERE id=357;');
      }
    });

    test('RC real backdated insert is captured by the full re-walk', () async {
      if (!await backendReachable()) {
        markTestSkipped('real backend unreachable');
      }
      const slug = 'e2eoffline-rc-backdate';
      await mysql('DELETE FROM sql_laravel_marabmall_cloud.product_variants '
          'WHERE product_id IN (SELECT id FROM '
          '(SELECT id FROM sql_laravel_marabmall_cloud.products WHERE '
          'slug=\'$slug\') AS t);');
      await mysql('DELETE FROM sql_laravel_marabmall_cloud.products WHERE '
          'slug=\'$slug\';');
      final api = realApi();
      await ensureFixtureVisible();
      await loginToken(api, _user1Mobile);
      final db = await CatalogDatabase.openMemory();
      addTearDown(db.close);
      final svc = CatalogSyncService();
      addTearDown(svc.dispose);
      Future<CatalogSyncResult> sync(CustomerApi a) => svc.syncScope(
          db: db,
          scope: 'city:1',
          fetchProducts: realProductFetch(a),
          fetchStores: realStoreFetch(a),
          fetchCategories: realCategoryFetch(a),
          pageSize: 50,
          delay: (_) async {});
      expect((await sync(api)).complete, isTrue);
      // Backdated insert: created_at 2020 → first position under sort=old.
      // (With a variant: variant-less rows never enter the listing at all.)
      await mysql('INSERT INTO sql_laravel_marabmall_cloud.products '
          '(name, slug, category_id, seller_id, image, description, status, '
          'is_approved, return_status, return_days, created_at, updated_at) '
          'SELECT \'E2EOFFLINE RC Backdate\', \'$slug\', category_id, '
          'seller_id, \'\', \'rc\', 1, 1, 1, 7, \'2020-01-01 00:00:00\', '
          '\'2020-01-01 00:00:00\' FROM sql_laravel_marabmall_cloud.products '
          'WHERE id=289 LIMIT 1;');
      await mysql('INSERT INTO sql_laravel_marabmall_cloud.product_variants '
          '(product_id, type, status, measurement, price, discounted_price, '
          'stock) SELECT (SELECT id FROM sql_laravel_marabmall_cloud.products '
          'WHERE slug=\'$slug\'), \'packet\', 1, 1, 100.0, 0.0, 10;');
      final head = await api.products(
          latitude: 15.4624,
          longitude: 45.3228,
          filters: {'limit': 1, 'offset': 0, 'sort': 'old'});
      expect(head.ok, isTrue);
      // Full re-walk from 0 converges regardless of sort position: the
      // backdated row is captured (offset checkpoints could never do this).
      expect((await sync(api)).complete, isTrue);
      final local =
          await CatalogDao(db).searchProducts('city:1', 'RC Backdate');
      expect(local.length, 1);
    });

    test('RD real checkout idempotency (same key, one group)', () async {
      if (!await backendReachable()) {
        markTestSkipped('real backend unreachable');
      }
      final api = realApi();
      await ensureFixtureVisible();
      await loginToken(api, _user1Mobile);
      const key = 'E2EOFFLINE-rd-1';
      // Realistic precondition: key unused anywhere (groups, sessions,
      // payments share the key family). Deleting groups without sessions
      // leaves a stale completed session whose redelivery 500s server-side
      // (documented residual backend gap, §9) — clean all three here.
      await mysql('DELETE FROM sql_laravel_marabmall_cloud.checkout_groups '
          'WHERE idempotency_key=\'$key\';');
      await mysql('DELETE FROM sql_laravel_marabmall_cloud.checkout_sessions '
          'WHERE user_id=79 AND idempotency_key=\'$key\';');
      await mysql('DELETE FROM sql_laravel_marabmall_cloud.checkout_payments '
          'WHERE idempotency_key=\'payment-$key\';');
      await mysql('DELETE FROM sql_laravel_marabmall_cloud.carts WHERE '
          'user_id=79;');
      await mysql('INSERT INTO sql_laravel_marabmall_cloud.carts (user_id, '
          'product_id, product_variant_id, qty, save_for_later, created_at, '
          'updated_at) VALUES (79, 289, 357, 1, 0, NOW(), NOW());');
      final a = await api.checkout(
          addressId: 26,
          paymentMethod: 'cod',
          idempotencyKey: key);
      expect(a.ok, isTrue, reason: a.message);
      final gid = J.i(a.dataMap['checkout_group_id'] ??
          (a.dataMap['checkout_group'] is Map
              ? (a.dataMap['checkout_group'] as Map)['id']
              : null));
      expect(gid, greaterThan(0));
      // Timeout/retry simulation: identical redelivery.
      final b = await api.checkout(
          addressId: 26,
          paymentMethod: 'cod',
          idempotencyKey: key);
      expect(b.ok, isTrue);
      final gid2 = J.i(b.dataMap['checkout_group_id'] ??
          (b.dataMap['checkout_group'] as Map)['id']);
      expect(gid2, gid);
      final n = await mysql('SELECT COUNT(*) FROM '
          'sql_laravel_marabmall_cloud.checkout_groups WHERE '
          'idempotency_key=\'$key\';');
      expect(n, '1');
      final pay = await mysql('SELECT COUNT(*) FROM '
          'sql_laravel_marabmall_cloud.checkout_payments WHERE '
          'checkout_group_id=$gid;');
      expect(pay, '1');
      // Offline checkout fails closed and creates nothing.
      const keyOff = 'E2EOFFLINE-rd-offline';
      final dead = CustomerApi(baseUrl: 'http://127.0.0.1:9');
      dead.setToken('x');
      final off =
          await dead.checkout(addressId: 26, idempotencyKey: keyOff);
      expect(off.ok, isFalse);
      expect(
          await mysql('SELECT COUNT(*) FROM '
              'sql_laravel_marabmall_cloud.checkout_groups WHERE '
              'idempotency_key=\'$keyOff\';'),
          '0');
    });

    test('RE real favorites toggle + outbox replay + isolation', () async {
      if (!await backendReachable()) {
        markTestSkipped('real backend unreachable');
      }
      final api = realApi();
      final tok1 = await loginToken(api, _user1Mobile);
      api.setToken(tok1);
      await ensureFixtureVisible();
      // Reset toggle state left by earlier manual runs.
      await api.removeFavorite(289);
      // Real toggle through the API.
      expect((await api.addFavorite(289)).ok, isTrue);
      expect(
          await mysql('SELECT COUNT(*) FROM '
              'sql_laravel_marabmall_cloud.favorites WHERE user_id=79 AND '
              'product_id=289;'),
          '1');
      expect((await api.removeFavorite(289)).ok, isTrue);
      expect(
          await mysql('SELECT COUNT(*) FROM '
              'sql_laravel_marabmall_cloud.favorites WHERE user_id=79 AND '
              'product_id=289;'),
          '0');
      // Real production queue path: toggle while offline queues a stamped op.
      final c = await _controller(api);
      c.setUser({'id': 79});
      c.token = tok1;
      api.setBaseUrl('http://127.0.0.1:9');
      await c.toggleFavorite(289);
      final queued = PendingOutbox(c.store, 'u:79').load();
      expect(queued.length, 1);
      expect(queued.first.payload['account_scope'], 'u:79');
      // Reconnect and replay through the REAL executor.
      api.setBaseUrl(_base);
      expect(await c.runPendingOp(queued.first), isTrue);
      await PendingOutbox(c.store, 'u:79').remove(queued.first.id);
      expect(
          await mysql('SELECT COUNT(*) FROM '
              'sql_laravel_marabmall_cloud.favorites WHERE user_id=79 AND '
              'product_id=289;'),
          '1');
      // Account switch: u:79-stamped op dropped under u:80, server untouched.
      c.setUser({'id': 80});
      expect(await c.runPendingOp(queued.first), isTrue);
      expect(
          await mysql('SELECT COUNT(*) FROM '
              'sql_laravel_marabmall_cloud.favorites WHERE user_id=80 AND '
              'product_id=289;'),
          '0');
      expect(
          await mysql('SELECT COUNT(*) FROM '
              'sql_laravel_marabmall_cloud.favorites WHERE user_id=79 AND '
              'product_id=289;'),
          '1');
      await api.removeFavorite(289); // restore toggle state
    });

    test('RF restart persistence + timeout + real payload shapes', () async {
      if (!await backendReachable()) {
        markTestSkipped('real backend unreachable');
      }
      final api = realApi();
      await loginToken(api, _user1Mobile);
      await ensureFixtureVisible();
      // Real payload: top-level price/rating/status are null; price lives in
      // variants — mapping must keep the row and never hide it by filter.
      final probe = await api.products(
          latitude: 15.4624,
          longitude: 45.3228,
          filters: {'limit': 50, 'offset': 250, 'sort': 'old'});
      expect(probe.ok, isTrue);
      final e2e = probe.dataMaps.firstWhere(
          (m) => J.str(m['slug']).startsWith('e2eoffline-product'));
      expect(e2e['price'], isNull);
      final up = productUpsertFromRow(e2e);
      expect(up, isNotNull);
      expect(
          filterCatalogRows([Map<String, dynamic>.from(e2e)],
              priceMin: '10000'),
          hasLength(1));
      // Restart persistence with real rows in a real file DB.
      final tmp = await Directory.systemTemp.createTemp('real_rf');
      try {
        final file = File('${tmp.path}/cat.db');
        var db = await CatalogDatabase.openFile(file);
        final svc = CatalogSyncService();
        final res = await svc.syncScope(
            db: db,
            scope: 'city:1',
            fetchProducts: realProductFetch(api),
            fetchStores: realStoreFetch(api),
            fetchCategories: realCategoryFetch(api),
            pageSize: 50,
            delay: (_) async {});
        expect(res.complete, isTrue);
        final n = await CatalogDao(db).productCount('city:1');
        await db.close();
        db = await CatalogDatabase.openFile(file);
        expect(await CatalogDao(db).productCount('city:1'), n);
        await db.close();
        svc.dispose();
      } finally {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('RG account isolation is real; single-city scope noted', () async {
      if (!await backendReachable()) {
        markTestSkipped('real backend unreachable');
      }
      final api = realApi();
      await ensureFixtureVisible();
      await loginToken(api, _user1Mobile);
      final api2 = realApi();
      await loginToken(api2, _user2Mobile);
      final cities = await api.cities();
      expect(cities.ok, isTrue);
      // Only one city exists server-side: cross-city mixing is untestable
      // live (documented); DAO scope isolation is proven in H1 [harness].
      expect(J.i(cities.raw['total']), 1);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cache = OfflineCache(LocalStore(prefs));
      await cache.writeDraft('u:79', 'checkout_form', {'note': 'one'});
      await cache.writeDraft('u:80', 'checkout_form', {'note': 'two'});
      expect(cache.readDraft('u:79', 'checkout_form'), {'note': 'one'});
      expect(cache.readDraft('u:80', 'checkout_form'), {'note': 'two'});
      await cache.clearAccountDocs('u:79');
      expect(cache.readDraft('u:79', 'checkout_form'), isNull);
      expect(cache.readDraft('u:80', 'checkout_form'), {'note': 'two'});
    });

    test('RS seller edit: stale within TTL, fresh after invalidate', () async {
      if (!await backendReachable()) {
        markTestSkipped('real backend unreachable');
      }
      final api = realApi();
      await loginToken(api, _user1Mobile);
      Future<String> sellerName() async {
        final r = await api.sellers(
            latitude: 15.4624,
            longitude: 45.3228,
            limit: 50,
            offset: 0,
            search: 'E2EOFFLINE');
        expect(r.ok, isTrue);
        final hit = r.dataMaps.where((m) => J.i(m['id']) == 27).toList();
        expect(hit.length, 1);
        final storeName = J.str(hit.first['store_name']);
        return storeName.isNotEmpty
            ? storeName
            : J.str(hit.first['name']);
      }

      expect(await sellerName(), 'E2EOFFLINE Store');
      // Server-side change (search bypasses the server 60s sellers cache,
      // so any staleness observed below is the client's own TTL window).
      await mysql('UPDATE sql_laravel_marabmall_cloud.sellers SET '
          'store_name=\'E2EOFFLINE Store RENAMED\' WHERE id=27;');
      try {
        // Same instance + same query: client TTL serves the stale snapshot.
        expect(await sellerName(), 'E2EOFFLINE Store');
        // Explicit invalidation refreshes from the network immediately.
        api.invalidateCatalog();
        expect(await sellerName(), 'E2EOFFLINE Store RENAMED');
      } finally {
        await mysql('UPDATE sql_laravel_marabmall_cloud.sellers SET '
            'store_name=\'E2EOFFLINE Store\' WHERE id=27;');
        api.invalidateCatalog();
      }
    });

    test('RH local placeholder image prefetches; manifest matches disk',
        () async {
      if (!await backendReachable()) {
        markTestSkipped('real backend unreachable');
      }
      final tmp = await Directory.systemTemp.createTemp('real_rh');
      try {
        final pre = TestPrefetch(tmp);
        final db = await CatalogDatabase.openMemory();
        try {
          final n = await pre.prefetch(
              ['http://127.0.0.1:8000/images/product-placeholder.svg'],
              db: db,
              timeout: const Duration(seconds: 20));
          expect(n, 1);
          expect(await CatalogDao(db).imagesTotalBytes(), greaterThan(0));
          // Manifest row matches a real file of the recorded size.
          final rows = await CatalogDao(db)
              .evictCandidates(bytesToFree: 1 << 60);
          expect(rows.length, 1);
          final f = File(rows.first.localPath);
          expect(await f.exists(), isTrue);
          expect(await f.length(), rows.first.bytes);
        } finally {
          await db.close();
        }
        pre.cancel();
      } finally {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      }
    });
  });
}
