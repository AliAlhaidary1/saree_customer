import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'catalog_db/catalog_config.dart';
import 'catalog_db/catalog_database.dart';
import 'json_util.dart';

/// Location scope for the public catalog. Every catalog row belongs to
/// exactly one scope; rows from different scopes never mix.
String catalogScopeForCity(Map<String, dynamic>? city) {
  final id = J.str(city?['id']);
  if (id.isEmpty) return 'global';
  return 'city:$id';
}

/// Opens the catalog file database (creating it if needed). Returns null on
/// any failure — callers always fall back to the JSON/network path, so a
/// broken catalog file can never break browsing.
Future<CatalogDatabase?> openCatalogDbFile() async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/${CatalogDbConfig.dbFileName}');
    return await CatalogDatabase.openFile(file);
  } catch (_) {
    return null;
  }
}

/// Sync progress for one scope. `total` is the server total when the backend
/// reported one, otherwise -1 (indeterminate). `coverage` is always
/// `best_effort`: offset paging cannot prove completeness (no tombstones).
class CatalogSyncProgress {
  CatalogSyncProgress({
    this.phase = CatalogSyncPhase.idle,
    this.scope = '',
    this.completed = 0,
    this.total = -1,
    this.coverage = 'best_effort',
    this.message = '',
  });

  final CatalogSyncPhase phase;
  final String scope;
  final int completed;
  final int total;
  final String coverage;
  final String message;

  CatalogSyncProgress copyWith({
    CatalogSyncPhase? phase,
    String? scope,
    int? completed,
    int? total,
    String? coverage,
    String? message,
  }) => CatalogSyncProgress(
    phase: phase ?? this.phase,
    scope: scope ?? this.scope,
    completed: completed ?? this.completed,
    total: total ?? this.total,
    coverage: coverage ?? this.coverage,
    message: message ?? this.message,
  );
}

enum CatalogSyncPhase { idle, syncing, paused, done, error, cancelled }

/// Honest data state of one catalog scope for empty states and retry
/// controls. Deliberately distinct from row counts: `empty` (synchronized and
/// genuinely empty) must never share UI with `neverSynced`, `failed`, or a
/// disabled database.
enum CatalogScopeStatus {
  /// No checkpoint row: sync never attempted/completed for this scope
  /// (or the catalog database is disabled/unavailable).
  neverSynced,

  /// A walk for this scope is currently running.
  syncing,

  /// Last walk did not complete (interrupted/failed/cancelled). Usable rows
  /// may still exist; retry is offered.
  failed,

  /// Clean full walk completed and the listing is genuinely empty.
  empty,

  /// Clean full walk completed with listed rows.
  ready,
}

/// Resolved [CatalogScopeStatus] plus display hints. `stale` is advisory
  /// (last full completion older than the product-list TTL); it never gates
  /// behavior — prices/stock stay server-authoritative regardless.
  class CatalogScopeState {
    const CatalogScopeState({
      required this.status,
      this.lastSyncAt,
      this.listedCount = 0,
      this.stale = false,
      this.sectionCount = 0,
      this.harajCount = 0,
    });

    final CatalogScopeStatus status;
    final DateTime? lastSyncAt;
    final int listedCount;
    final bool stale;
    final int sectionCount;
    final int harajCount;
  }

/// Empty-state copy for a scope [status]. Pure (takes the translator) so
/// every branch is unit-testable; `ready` with zero items means the current
/// query matched nothing while synchronized data exists.
String catalogEmptyMessage(
  CatalogScopeStatus status,
  String Function(String key) t,
) {
  switch (status) {
    case CatalogScopeStatus.neverSynced:
      return t('not_synced_yet');
    case CatalogScopeStatus.syncing:
      return t('catalog_syncing');
    case CatalogScopeStatus.failed:
      return t('catalog_sync_failed');
    case CatalogScopeStatus.empty:
    case CatalogScopeStatus.ready:
      return t('no_products_found');
  }
}

class CatalogSyncResult {
  CatalogSyncResult({
    required this.complete,
    required this.cancelled,
    required this.products,
    required this.stores,
    required this.categories,
    this.error = '',
  });

  final bool complete;
  final bool cancelled;
  final int products;
  final int stores;
  final int categories;
  final String error;
}

/// Maps the backend's empty-result envelope to a clean end-of-data page.
///
/// The Laravel listing returns HTTP 200 + `{status:0, message:'لم يتم العثور
/// على منتجات'}` (with NO `data` key) when a page is past the end — including
/// offset 0 for genuinely empty catalogs. The same shape covers categories
/// (`... على فئات!`); sellers instead return `{status:1, data:[]}`.
///
/// Treating that signal as a failure parks the walk AND poisons every future
/// resume: after server-side deletes move the tail below the stored
/// checkpoint, each re-sync re-fetches the past-end offset and errors again
/// forever. Only the empty signal with zero rows maps to end-of-data; every
/// other failure stays an error.
bool isEmptyCatalogPage(ApiResult res) {
  if (res.ok || res.dataMaps.isNotEmpty) return false;
  final msg = res.message.toLowerCase();
  return msg.contains('لم يتم العثور على') ||
      msg.contains('no_products_found') ||
      msg.contains('no_categories_found') ||
      msg.contains('no products found') ||
      msg.contains('no categories found') ||
      msg.contains('not found') ||
      msg == 'empty';
}

/// One fetched page: usable rows plus the server total when reported.
class CatalogPage {
  CatalogPage({
    required this.rows,
    this.total = -1,
    this.ok = true,
    this.error = '',
  });

  final List<Map<String, dynamic>> rows;
  final int total;
  final bool ok;
  final String error;
}

typedef CatalogPageFetch =
    Future<CatalogPage> Function({required int limit, required int offset});

/// Best-effort catalog synchronization with full-walk reconciliation.
///
/// Contract (honest, client-only):
/// * every walk starts at offset 0 and every page commits in a single
///   transaction; the checkpoint (`sync_states`) advances after each commit
///   for progress/forensics, and repeats are no-ops via composite keys —
///   interrupts simply re-walk from the start with no partial rows;
/// * failed, error-shaped, or malformed pages never advance anything;
///   previously valid data is preserved and the run parks with an error;
/// * after a clean, uncapped, uncancelled FULL walk, membership is
///   reconciled: products absent from the scan become unlisted (kept for
///   detail pages), missing stores/categories are deleted. Reconciliation
///   never runs after a partial walk, so incomplete scans can never erase
///   live rows. This detects updates, deletes, and backdated inserts as of
///   the walk — without any backend change feed;
/// * coverage stays `best_effort`: concurrent server writes during the walk
///   itself can still lag one cycle; the label means "last reconciled
///   snapshot", never "provably complete";
/// * single-flight per service instance; cancellation keeps committed data.
class CatalogSyncService extends ChangeNotifier {
  CatalogSyncService();

  final ValueNotifier<CatalogSyncProgress> progress = ValueNotifier(
    CatalogSyncProgress(),
  );

  bool _running = false;
  bool _cancelRequested = false;

  /// Requests cancellation of the current run. Committed pages are kept.
  void cancel() {
    _cancelRequested = true;
  }

  Future<CatalogSyncResult> syncScope({
    required CatalogDatabase db,
    required String scope,
    required CatalogPageFetch fetchProducts,
    required CatalogPageFetch fetchStores,
    required CatalogPageFetch fetchCategories,
    int pageSize = CatalogDbConfig.syncPageSize,
    int storePageSize = 48,
    int maxPages = 200,
    Future<void> Function(Duration)? delay,
  }) async {
    if (_running) {
      return CatalogSyncResult(
        complete: false,
        cancelled: false,
        products: 0,
        stores: 0,
        categories: 0,
        error: 'already_running',
      );
    }
    _running = true;
    _cancelRequested = false;
    final sleep = delay ?? ((d) => Future<void>.delayed(d));
    final now = DateTime.now();
    var products = 0;
    var stores = 0;
    var categories = 0;
    try {
      progress.value = CatalogSyncProgress(
        phase: CatalogSyncPhase.syncing,
        scope: scope,
      );
      // Full walks only: every run starts at offset 0 so the id set observed
      // is always complete enough for end-of-walk reconciliation. Partial
      // resume would poison reconciliation (unseen rows would look deleted),
      // so checkpoints are progress/forensics markers, not resume points.
      // Corrupt/negative stored offsets are irrelevant (always start at 0).
      var offset = 0;
      final seenProductIds = <int>{};

      // ---- Products (offset pages, sort=old semantics assumed) ----
      // The verified backend caps product pages below the requested size
      // (48) and omits `total` on later pages. A short page therefore does
      // NOT prove end-of-data: continue while the last known total says
      // more rows exist. `knownTotal` tracks the max reported total.
      var pages = 0;
      var productsTruncated = false;
      var knownTotal = -1;
      while (pages < maxPages) {
        if (_cancelRequested) {
          return await _finish(
            db,
            scope,
            products,
            stores,
            categories,
            phase: CatalogSyncPhase.cancelled,
            cancelled: true,
          );
        }
        final page = await _fetchWithRetry(
          fetchProducts,
          pageSize,
          offset,
          sleep,
        );
        if (_cancelRequested) {
          return await _finish(
            db,
            scope,
            products,
            stores,
            categories,
            phase: CatalogSyncPhase.cancelled,
            cancelled: true,
          );
        }
        if (!page.ok) {
          return await _finish(
            db,
            scope,
            products,
            stores,
            categories,
            phase: CatalogSyncPhase.error,
            error: page.error,
          );
        }
        if (page.total >= 0 && page.total > knownTotal) {
          knownTotal = page.total;
        }
        if (page.rows.isEmpty) break; // Clean end of data.
        final batch = <ProductUpsert>[];
        for (final row in page.rows) {
          final up = productUpsertFromRow(row);
          if (up != null) batch.add(up);
        }
        if (batch.isNotEmpty) {
          final dao = CatalogDao(db);
          await dao.upsertProductBatch(scope: scope, rows: batch, now: now);
          products += batch.length;
          for (final up in batch) {
            seenProductIds.add(up.serverId);
          }
          offset += page.rows.length;
          await dao.saveSyncState(
            SyncStatesCompanion.insert(
              scope: scope,
              phase: 'full_running',
              coverage: const Value('best_effort'),
              lastOffset: Value(offset),
              storedCount: Value(await dao.productCount(scope)),
              updatedAt: now,
            ),
          );
          progress.value = progress.value.copyWith(
            completed: products,
            total: page.total,
          );
        } else {
          // Page carried no usable rows: stop without advancing (the payload
          // shape is unexpected — do not mistake it for completeness).
          return await _finish(
            db,
            scope,
            products,
            stores,
            categories,
            phase: CatalogSyncPhase.error,
            error: 'malformed_page',
          );
        }
        pages++;
        // End of data: short page AND (no known total OR checkpoint covers
        // it). A short page with offset < knownTotal means the server paged
        // smaller than requested (verified 48-cap) — keep walking.
        if (page.rows.length < pageSize &&
            (knownTotal < 0 || offset >= knownTotal)) {
          break;
        }
        if (page.total >= 0 && offset >= page.total) break;
        if (pages >= maxPages) productsTruncated = true;
      }
      if (productsTruncated) {
        return await _finish(
          db,
          scope,
          products,
          stores,
          categories,
          phase: CatalogSyncPhase.error,
          error: 'truncated_max_pages',
        );
      }

      if (_cancelRequested) {
        return await _finish(
          db,
          scope,
          products,
          stores,
          categories,
          phase: CatalogSyncPhase.cancelled,
          cancelled: true,
        );
      }

      // ---- Stores (backend caps seller pages at 48 — a larger limit would
      // stop after the first full page, so 48 is the correct page size) ----
      // A failed stores/categories page keeps previously committed rows but
      // marks the run incomplete (never silent `complete: true`).
      final storesOutcome = await _syncSimpleEntity(
        db: db,
        scope: scope,
        fetch: fetchStores,
        pageSize: storePageSize,
        maxPages: maxPages,
        sleep: sleep,
        apply: (dao, rows) async {
          final companions = <StoresCompanion>[];
          for (final row in rows) {
            final c = storeCompanionFromRow(row, scope, now);
            if (c != null) companions.add(c);
          }
          if (companions.isNotEmpty) {
            await dao.upsertStores(scope: scope, rows: companions);
          }
          return _AppliedBatch(
            count: companions.length,
            ids: {for (final c in companions) c.serverId.value},
          );
        },
      );
      stores = storesOutcome.stored;
      if (_cancelRequested || storesOutcome.cancelled) {
        return await _finish(
          db,
          scope,
          products,
          stores,
          categories,
          phase: CatalogSyncPhase.cancelled,
          cancelled: true,
        );
      }
      if (!storesOutcome.ok) {
        return await _finish(
          db,
          scope,
          products,
          stores,
          categories,
          phase: CatalogSyncPhase.error,
          error: storesOutcome.error,
        );
      }

      // ---- Categories ----
      final categoriesOutcome = await _syncSimpleEntity(
        db: db,
        scope: scope,
        fetch: fetchCategories,
        pageSize: 100,
        maxPages: 10,
        sleep: sleep,
        apply: (dao, rows) async {
          final companions = <CategoriesCompanion>[];
          for (final row in rows) {
            final c = categoryCompanionFromRow(row, scope, now);
            if (c != null) companions.add(c);
          }
          if (companions.isNotEmpty) {
            await dao.upsertCategories(scope: scope, rows: companions);
          }
          return _AppliedBatch(
            count: companions.length,
            ids: {for (final c in companions) c.serverId.value},
          );
        },
      );
      categories = categoriesOutcome.stored;
      if (_cancelRequested || categoriesOutcome.cancelled) {
        return await _finish(
          db,
          scope,
          products,
          stores,
          categories,
          phase: CatalogSyncPhase.cancelled,
          cancelled: true,
        );
      }
      if (!categoriesOutcome.ok) {
        return await _finish(
          db,
          scope,
          products,
          stores,
          categories,
          phase: CatalogSyncPhase.error,
          error: categoriesOutcome.error,
        );
      }
      if (storesOutcome.truncated || categoriesOutcome.truncated) {
        return await _finish(
          db,
          scope,
          products,
          stores,
          categories,
          phase: CatalogSyncPhase.error,
          error: 'truncated_max_pages',
        );
      }

      final dao = CatalogDao(db);
      // Membership reconciliation. This point is reachable only after a
      // clean, uncapped, uncancelled FULL walk (every error/cancel/truncate
      // path returned above), and every walk starts at offset 0 — so the
      // observed id sets are complete and safe to reconcile against. A
      // reconcile failure refuses `done` (retry converges next walk).
      await dao.reconcileListed(scope, seenProductIds);
      await dao.deleteMissingStores(scope, storesOutcome.ids);
      await dao.deleteMissingCategories(scope, categoriesOutcome.ids);
      await dao.saveSyncState(
        SyncStatesCompanion.insert(
          scope: scope,
          phase: 'full_complete',
          coverage: const Value('best_effort'),
          lastOffset: Value(offset),
          storedCount: Value(await dao.productCount(scope)),
          updatedAt: DateTime.now(),
        ),
      );
      return await _finish(
        db,
        scope,
        products,
        stores,
        categories,
        phase: CatalogSyncPhase.done,
      );
    } catch (e) {
      return await _finish(
        db,
        scope,
        products,
        stores,
        categories,
        phase: CatalogSyncPhase.error,
        error: '$e',
      );
    } finally {
      _running = false;
    }
  }

  Future<CatalogSyncResult> _finish(
    CatalogDatabase db,
    String scope,
    int products,
    int stores,
    int categories, {
    required CatalogSyncPhase phase,
    bool cancelled = false,
    String error = '',
  }) async {
    progress.value = progress.value.copyWith(
      phase: phase,
      scope: scope,
      completed: products,
      message: error,
    );
    notifyListeners();
    return CatalogSyncResult(
      complete: phase == CatalogSyncPhase.done,
      cancelled: cancelled,
      products: products,
      stores: stores,
      categories: categories,
      error: error,
    );
  }

  /// Outcome of a stores/categories walk. `ok: false` carries the page
  /// error; `truncated` means `maxPages` was hit on a full page.
  /// Paged fetch for stores/categories: every walk starts at offset 0 and
  /// stops at first short/empty page, failed page, or cancellation (keeps
  /// previously committed rows). Applied ids are collected for end-of-walk
  /// reconciliation by the caller (clean walks only).
  Future<_SimpleSyncOutcome> _syncSimpleEntity({
    required CatalogDatabase db,
    required String scope,
    required CatalogPageFetch fetch,
    required int pageSize,
    required int maxPages,
    required Future<void> Function(Duration) sleep,
    required Future<_AppliedBatch> Function(
      CatalogDao dao,
      List<Map<String, dynamic>> rows,
    )
    apply,
  }) async {
    var stored = 0;
    final ids = <int>{};
    var offset = 0;
    var pages = 0;
    var knownTotal = -1;
    final dao = CatalogDao(db);
    _SimpleSyncOutcome done({
      bool ok = true,
      String error = '',
      bool cancelled = false,
      bool truncated = false,
    }) => _SimpleSyncOutcome(
      stored: stored,
      ids: ids,
      ok: ok,
      error: error,
      cancelled: cancelled,
      truncated: truncated,
    );
    while (pages < maxPages) {
      if (_cancelRequested) {
        return done(cancelled: true);
      }
      final page = await _fetchWithRetry(fetch, pageSize, offset, sleep);
      if (_cancelRequested) {
        return done(cancelled: true);
      }
      if (!page.ok) {
        return done(ok: false, error: page.error);
      }
      if (page.total >= 0 && page.total > knownTotal) {
        knownTotal = page.total;
      }
      if (page.rows.isEmpty) break;
      final applied = await apply(dao, page.rows);
      stored += applied.count;
      ids.addAll(applied.ids);
      offset += page.rows.length;
      pages++;
      // Same short-page rule as products: a short page only ends the walk
      // when no known total contradicts it (server may page below request).
      if (page.rows.length < pageSize &&
          (knownTotal < 0 || offset >= knownTotal)) {
        break;
      }
      if (page.total >= 0 && offset >= page.total) break;
      if (pages >= maxPages) {
        return done(truncated: true);
      }
    }
    return done();
  }

  /// Bounded retry for transient page failures: 2 retries with backoff for
  /// thrown transport errors only. Production fetchers return
  /// `CatalogPage(ok: false)` instead of throwing, so those failures are
  /// returned as-is without retry (see syncScope handling below).
  Future<CatalogPage> _fetchWithRetry(
    CatalogPageFetch fetch,
    int limit,
    int offset,
    Future<void> Function(Duration) sleep,
  ) async {
    var attempt = 0;
    while (true) {
      try {
        return await fetch(limit: limit, offset: offset);
      } catch (e) {
        attempt++;
        if (attempt > 2) {
          return CatalogPage(rows: const [], ok: false, error: '$e');
        }
        await sleep(Duration(milliseconds: 400 * attempt));
      }
    }
  }

  @override
  void dispose() {
    progress.dispose();
    super.dispose();
  }
}

/// Outcome of one stores/categories paged walk (see _syncSimpleEntity).
class _SimpleSyncOutcome {
  _SimpleSyncOutcome({
    required this.stored,
    this.ids = const {},
    required this.ok,
    this.error = '',
    this.cancelled = false,
    this.truncated = false,
  });

  final int stored;

  /// Server ids committed during this walk (for end-of-walk reconciliation).
  final Set<int> ids;
  final bool ok;
  final String error;
  final bool cancelled;
  final bool truncated;
}

/// One applied batch: committed count plus the committed server ids.
class _AppliedBatch {
  _AppliedBatch({required this.count, required this.ids});

  final int count;
  final Set<int> ids;
}

/// Maps a backend product row to a snapshot upsert. Returns null when the row
/// carries no usable identity (never invent ids — the row is skipped and the
/// page still commits its valid siblings).
ProductUpsert? productUpsertFromRow(Map<String, dynamic> row) {
  final id = J.i(row['id'] ?? row['product_id']);
  if (id <= 0) return null;
  final name = J.str(row['name']);
  if (name.isEmpty) return null;
  final storeId = J.i(J.sellerId(row) ?? row['store_id'] ?? row['seller_id']);
  final rawCat = row['category_id'];
  final categoryId = rawCat == null || '$rawCat'.isEmpty ? null : J.i(rawCat);
  final images = row['images'] is List
      ? List<dynamic>.from(row['images'] as List)
      : const [];
  var thumb = J.str(row['thumbnail'] ?? row['image'] ?? row['thumbnail_url']);
  if (thumb.isEmpty && images.isNotEmpty) {
    final first = images.first;
    thumb = first is Map ? J.str(first['url'] ?? first['image']) : J.str(first);
  }
  final description = J.str(row['description'] ?? row['short_description']);
  final tags = row['tags'] is List
      ? (row['tags'] as List)
            .map((e) => J.str(e))
            .where((e) => e.isNotEmpty)
            .join(' ')
      : J.str(row['tags']);
  final blob = [
    name,
    description,
    tags,
    J.str(row['category_name']),
    J.str(row['brand_name']),
  ].where((e) => e.isNotEmpty).join(' ');
  final price = {
    'price': J.str(row['price'] ?? row['selling_price']),
    'old_price': J.str(row['old_price'] ?? row['mrp']),
    'discount': J.str(row['discount'] ?? row['discount_percent']),
    'has_offer': J.flag(row['has_offer'] ?? (row['discount'] != null)) ? 1 : 0,
    'in_stock': J.str(row['in_stock'] ?? row['stock_status']),
    'currency': J.str(row['currency']),
  };
  final variants = <VariantUpsert>[];
  double? minPrice;
  bool? anyInStock;
  bool? anyOffer;
  if (row['variants'] is List) {
    for (final v in (row['variants'] as List)) {
      if (v is! Map) continue;
      final vm = Map<String, dynamic>.from(v);
      final vid = J.i(vm['id'] ?? vm['variant_id']);
      if (vid <= 0) continue;
      variants.add(VariantUpsert(serverId: vid, payload: jsonEncode(vm)));
      // Effective price mirrors the server (discounted when present).
      final base = J.d(vm['price']);
      final disc = J.d(vm['discounted_price']);
      final effective = disc > 0 ? disc : base;
      if (effective > 0) {
        minPrice = minPrice == null || effective < minPrice
            ? effective
            : minPrice;
      }
      if (J.i(vm['stock']) > 0) anyInStock = true;
      if (disc > 0 && disc < base) anyOffer = true;
    }
  }
  // Stock mirrors the listing hard filter (unlimited OR any variant stocked).
  // No variant data at all means unknown (null), never "out of stock".
  bool? inStock;
  if (J.i(row['is_unlimited_stock']) == 1) {
    inStock = true;
  } else if (anyInStock == true) {
    inStock = true;
  } else if (variants.isNotEmpty) {
    inStock = false;
  }
  // Offer signal: variant evidence first, then row-level flags. Explicit
  // "no offer" maps to false; anything else without evidence stays unknown.
  bool? hasOffer;
  if (anyOffer == true) {
    hasOffer = true;
  } else {
    final rowOffer =
        J.flag(row['has_offer']) ||
        J.d(row['discount'] ?? row['discount_percent']) > 0;
    if (rowOffer) {
      hasOffer = true;
    } else if (row.containsKey('has_offer')) {
      hasOffer = false;
    }
  }
  return ProductUpsert(
    serverId: id,
    slug: J.str(row['slug']).isEmpty ? null : J.str(row['slug']),
    name: name,
    storeId: storeId,
    categoryId: categoryId,
    storeName: J.str(row['store_name'] ?? J.map(row['seller'])['name']),
    searchBlob: blob,
    priceSnapshot: jsonEncode(price),
    thumbnailUrl: thumb.isEmpty ? null : thumb,
    rating: J.d(row['rating'] ?? row['avg_rating']),
    status: J.i(row['status'], 1),
    payload: jsonEncode(row),
    variants: variants,
    minPrice: minPrice,
    inStock: inStock,
    hasOffer: hasOffer,
  );
}

StoresCompanion? storeCompanionFromRow(
  Map<String, dynamic> row,
  String scope,
  DateTime now,
) {
  final id = J.i(row['id'] ?? row['seller_id'] ?? row['store_id']);
  if (id <= 0) return null;
  final name = J.str(row['name'] ?? row['store_name'] ?? row['shop_name']);
  if (name.isEmpty) return null;
  return StoresCompanion.insert(
    scope: scope,
    serverId: id,
    name: name,
    slug: Value(J.str(row['slug']).isEmpty ? null : J.str(row['slug'])),
    latitude: Value(double.tryParse('${row['latitude'] ?? row['lat'] ?? ''}')),
    longitude: Value(
      double.tryParse('${row['longitude'] ?? row['lng'] ?? row['lon'] ?? ''}'),
    ),
    rating: Value(J.d(row['rating'])),
    status: Value(J.i(row['status'], 1)),
    payload: jsonEncode(row),
    refreshedAt: now,
    lastSeenAt: now,
  );
}

CategoriesCompanion? categoryCompanionFromRow(
  Map<String, dynamic> row,
  String scope,
  DateTime now,
) {
  final id = J.i(row['id'] ?? row['category_id']);
  if (id <= 0) return null;
  final name = J.str(row['name']);
  if (name.isEmpty) return null;
  final rawParent = row['parent_id'];
  final parentId =
      rawParent == null || '$rawParent'.isEmpty || J.i(rawParent) <= 0
      ? null
      : J.i(rawParent);
  final type = J.str(row['type']).isNotEmpty ? J.str(row['type']) : null;
  return CategoriesCompanion.insert(
    scope: scope,
    serverId: id,
    name: name,
    parentId: Value(parentId),
    slug: Value(J.str(row['slug']).isEmpty ? null : J.str(row['slug'])),
    imageUrl: Value(
      J.str(row['image'] ?? row['image_url']).isEmpty
          ? null
          : J.str(row['image'] ?? row['image_url']),
    ),
    rowOrder: Value(J.i(row['row_order'] ?? row['order'] ?? row['position'])),
    type: Value(type),
    refreshedAt: now,
  );
}

/// Local filtering over snapshot rows. A row that does not carry a field is
/// never hidden by that filter (missing display data must not erase rows).
List<Map<String, dynamic>> filterCatalogRows(
  List<Map<String, dynamic>> rows, {
  String priceMin = '',
  String priceMax = '',
  String minRating = '',
  bool inStock = false,
  bool onlyOffers = false,
  bool canDeliver = false,
  bool isReturnable = false,
}) {
  final min = double.tryParse(priceMin);
  final max = double.tryParse(priceMax);
  final rating = double.tryParse(minRating);
  bool hasNum(dynamic v) =>
      v != null && '$v'.isNotEmpty && double.tryParse('$v') != null;
  return rows.where((row) {
    final priceRaw = row['price'] ?? row['selling_price'];
    if (min != null && hasNum(priceRaw) && J.d(priceRaw) < min) return false;
    if (max != null && hasNum(priceRaw) && J.d(priceRaw) > max) return false;
    if (rating != null && rating > 0) {
      final r = row['rating'] ?? row['avg_rating'];
      if (hasNum(r) && J.d(r) < rating) return false;
    }
    if (onlyOffers) {
      final hasOffer =
          J.flag(row['has_offer']) ||
          J.d(row['discount'] ?? row['discount_percent']) > 0;
      final explicitNoOffer = row.containsKey('has_offer') && !hasOffer;
      if (explicitNoOffer) return false;
    }
    if (inStock) {
      final stock = row['stock'] ?? row['quantity'] ?? row['stock_qty'];
      if (stock != null && '$stock'.isNotEmpty && J.i(stock) <= 0) {
        return false;
      }
      if (J.str(row['stock_status']).toLowerCase() == 'out_of_stock' ||
          J.str(row['in_stock']) == '0') {
        return false;
      }
    }
    // Payload-only booleans: `can_deliver` defaults to true (missing =
    // deliverable), `is_returnable` missing = unknown (never hides).
    if (canDeliver && !J.flag(row['can_deliver'], true)) return false;
    if (isReturnable &&
        row.containsKey('is_returnable') &&
        !J.flag(row['is_returnable'])) {
      return false;
    }
    return true;
  }).toList();
}

/// Local sorting mirror of the backend sort keys. `nearest` needs live
/// coordinates and intentionally falls back to rating (same as the screens).
List<Map<String, dynamic>> sortCatalogRows(
  List<Map<String, dynamic>> rows,
  String sort,
) {
  if (sort.isEmpty) return rows;
  final out = List<Map<String, dynamic>>.from(rows);
  double priceOf(Map<String, dynamic> m) =>
      J.d(m['price'] ?? m['selling_price']);
  switch (sort) {
    case 'low':
      out.sort((a, b) => priceOf(a).compareTo(priceOf(b)));
      break;
    case 'high':
      out.sort((a, b) => priceOf(b).compareTo(priceOf(a)));
      break;
    case 'rating':
    case 'nearest':
      out.sort(
        (a, b) => J
            .d(b['rating'] ?? b['avg_rating'])
            .compareTo(J.d(a['rating'] ?? a['avg_rating'])),
      );
      break;
    case 'new':
      out.sort((a, b) => J.i(b['id']).compareTo(J.i(a['id'])));
      break;
  }
  return out;
}
