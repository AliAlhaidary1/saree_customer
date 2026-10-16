# Offline Catalog Migration & Implementation Plan — SareeMart Customer App

**Status: REVISED PROPOSAL (Rev 2) — awaiting approval. No storage-engine
change has been made by this document.**
**Constraints observed:** no backend file modified, no screen/account/checkout
code touched, no commit/push/deploy. All backend findings are read-only.
Sizes marked *(est.)* are estimates, not measurements.

Branch: `prod/offline-reliability` · Flutter 3.47.1 / Dart 3.13.1 ·
Backend: `D:\myproject\review\saree_back` (Laravel, read-only).

---

## §0 Response to mandatory corrections (Rev 1 → Rev 2)

| # | Correction required | Design change in Rev 2 |
|---|---|---|
| 1 | Count-vs-total is not proof of completeness; `sort=new` delta-pass cannot guarantee recovery | Two-tier coverage model: `best_effort` (today's endpoints, honestly labeled, partial possible) vs `verified` (requires composite-cursor backend B1). Count check demoted to sanity signal; delta-pass redefined as bounded best-effort re-scan that still cannot set the verified flag |
| 2 | Scope-aware identity for all keys | Composite natural keys `(scope, server_id)` for every scope-varying entity (products, stores, categories, variants); global keys only for cities (`server_id`) and images (URL). Full uniqueness table in §2.2; normalized core+membership alternative recorded and rejected |
| 3 | `(created_at, id)` ordering cannot use `after_id` alone | Composite cursor `(last_created_at, last_id)` specified exactly, consistent with `ORDER BY created_at ASC, id ASC`; exact B1 contract (params/response); per-operation capture rules for inserts/updates/deletes |
| 4 | Images decoupled from data sync; budget by actual bytes; safe cleanup | Separate image pipeline with own state machine; data-`complete` never waits for images; budget enforced from filesystem stats; write/delete ordering + orphan sweeps; graceful fallback rule |
| 5 | Full recovery/migration test matrix | §7 matrix now names: legacy preservation, interrupted migration, kill-mid-sync, scope switch, failed batch commit, storage exhaustion, corrupt DB, JSON rollback — each mapped to a Phase 1 test case |
| 6 | No premature cutover in Phase 0/1 | Hard boundary restated in §7: new files only (`lib/core/catalog_db/*`, tests, deps); screens, JSON keys, checkout/payment, backend all frozen until plan + Phase 1 review |

### Phase 0 findings (static, no backend execution)

- **P0-1 Ordering:** `sort=old` ⇒ `created_at ASC, id ASC` (`RankingService.php:267`);
  explicit `sort` disables exploration injection (`DiscoveryQueryBuilder.php:295`).
  Deterministic total order confirmed in source. Default (unpinned) order is
  randomized on page 0 — unusable for sync.
- **P0-2 Caps/totals:** product pages hard-capped at limit 50
  (`DiscoveryQueryBuilder.php:208`); sellers at 48; `total` returned by both.
- **P0-3 Images:** list/detail payloads carry full-size `image_url` arrays
  (`CommonHelper::getImages`, `ProductApiController.php:224,306`); **no
  thumbnail/resize endpoint exists**. Implication: client-side downscale at
  prefetch time (512 px JPEG) — no backend change needed for the image plan.
- **P0-4 Toolchain:** `pub.dev` reachable; Flutter default `minSdkVersion = 24`
  (SDK `FlutterExtension.kt`) satisfies `sqlite3_flutter_libs` (≥21);
  `path_provider` already a dependency; Drift codegen via `build_runner` to be
  added in Phase 1.
- **P0-5 Scope:** listings are city/GPS-scoped (`discoverySellerIds`); there is
  no global catalog — sync baselines are per location scope (§2.2, §4.1).

---

## Deliverable 1 — Current architecture assessment

### 1.1 What exists today (verified in source)

`LocalStore` (SharedPreferences JSON, per-key quarantine, 400 KB guard) ·
`OfflineCache` (versioned envelopes, LRU 60 pages / 100 details) ·
`CachePolicy` (TTL = refresh trigger) · favorites-only idempotent
`PendingOutbox`/`SyncEngine` · `CheckoutSession` (stable ≤64-char key, history
reconcile) · `TokenVault` (secure storage only) · in-memory `ApiCache` ·
`OperationPolicy` + API-result reachability · cache-first screens with stale
badges and `_seq`/scope-captured writes. 80/80 tests green, analyze clean,
release APK builds.

### 1.2 Why a catalog database is now required

Visit-scoped page blobs cannot provide unvisited-product browsing, local
search/filter/sort, completion signaling, or change tracking; widening them
means unbounded RAM and wrong results. The current layer stays as the
fallback/account/mutation store; **Drift over SQLite is adopted for the
catalog only** — typed queries incl. FTS5, per-batch transactions with
checkpoint-after-commit, reactive streams, versioned migrations — with a
single engine and no second database system.

---

## Deliverable 2 — Proposed schema and data ownership matrix

### 2.1 Data ownership matrix (unchanged principle)

Backend-authoritative: availability, prices, stock, store status, fees,
discounts, checkout validation, order/payment/refund state, permissions.
Local catalog rows are display snapshots, badged stale, revalidated on
view/checkout. Account data (favorites ids, cart, orders, outbox, sessions,
tokens, addresses) **never enters the catalog DB** (existing JSON/secure
stores unchanged).

### 2.2 Uniqueness rules (correction #2)

Rule: **any entity whose membership or display data can vary by location
scope is keyed `(scope, server_id)`** — rows from different scopes never
collide even if prices/availability/delivery context differ. Global reference
data uses global keys.

| Table | Primary key / unique | Rationale |
|---|---|---|
| `cities` | `server_id` UNIQUE | Global reference data |
| `categories` | **(`scope`, `server_id`)** | Listing is city-scoped (`row_order` may vary) |
| `stores` | **(`scope`, `server_id`)** | Availability/rating/delivery context varies by scope |
| `products` | **(`scope`, `server_id`)** | Price snapshot/availability vary by scope |
| `product_variants` | **(`scope`, `variant_id`)** + index (`scope`, `product_id`) | Variant of a scoped product |
| `products_fts` (FTS5) | App-enforced identity: scoped delete-then-insert inside the batch transaction (FTS5 virtual tables support no UNIQUE/PK constraint) + `scope` filter on every query | Search never leaks across scopes; repeats absorbed |
| `cached_images` | `url` UNIQUE (global) | Same file reusable across scopes |
| `sync_state` | `scope` UNIQUE | One checkpoint row per baseline |

**Corrections (remediation review):** (a) no database-enforced uniqueness
exists or can exist on `products_fts` — identity is enforced by the DAO, not
the schema; (b) `store_name` is denormalized into FTS rows at product-write
time, so a store rename leaves stale FTS text until the affected product rows
are re-upsert (Phase 2 refreshes or drops that column); (c) enforced
relationship: composite `FOREIGN KEY (scope, product_id) REFERENCES
products (scope, server_id) ON DELETE CASCADE` on `product_variants`
(schema v2), active only with `PRAGMA foreign_keys = ON` (set in
`beforeOpen` on every connection); FTS rows cannot participate in FKs and
stay explicitly maintained. Orphan audit (`orphanCounts`) must read zero
after every DAO path.

Rejected alternative: normalized global core + per-scope membership join.
Reason: join complexity on every read path, FTS scoping harder, marginal
storage saving (1–2 hot scopes). Composite keys are auditable and make
scope-sweeps trivial (`DELETE WHERE scope=?`).

`sync_state` columns: `scope`, `phase`, `coverage` (`best_effort|verified`),
`last_offset`, **`last_created_at`, `last_id`** (composite cursor, correction
#3), `server_total`, `stored_count`, `checkpoint` (opaque, reserved for B2),
`updated_at`. Indexes: `products(scope,category_id)`,
`products(scope,store_id)`, `products(scope,status)`,
`variants(scope,product_id)`, `stores(scope,status)`,
`categories(scope,parent_id,row_order)`, `cached_images(last_used_at)`.

### 2.3 Versioning, account policy

Drift `schemaVersion = 2` (v1: initial tables; v2: composite FK on
`product_variants` + §2.2 index set + per-connection FK pragma). Every later
change uses additive versioned migrations; the v1 → v2 step rebuilds only the
variants table with verbatim data copy inside a SAVEPOINT (failure rolls the
file back to pre-migration state — retryable, no partial DDL).
Delete-and-recreate is forbidden except as last-resort repair of the
reconstructible catalog. Catalog is location-scoped: **logout/account switch
keeps it**; in-flight writes stamp scope; city change opens a separate scope
row (old scopes trimmed by age under budget).

---

## Deliverable 3 — Backend compatibility and required API changes

### 3.1 Inspection (unchanged from Rev 1, still valid)

Deterministic `sort=old` total order; caps 50/48; `total` returned; default
order randomized (unusable); offset-only paging; `updated_at`/`deleted_at`
hidden; no cursor/feed/tombstones; categories/cities full-fetchable; details
endpoint heavy (details stay visit-cached); favorites/checkout compatible.

### 3.2 Coverage classification (correction #1)

- **`best_effort` (today's endpoints):** `sort=old` + limit 50 + id-keyed
  upserts + count-vs-`total` **sanity signal** + bounded delta re-scan. Dupes
  absorbed by upserts; skips *possible* under mid-sync mutation and
  *undetectable in principle* by counting a moving target. The re-scan
  (`sort=new` tail, upsert-only) reduces the gap but **cannot promote the
  baseline to verified** — the flag stays `best_effort` and the UI says so
  ("catalog may be incomplete").
- **`verified` (requires B1):** gap-free insert capture via composite cursor
  (§3.3) + tombstones for deletes; only then may `coverage=verified` be set.
- **Backdated inserts (remediation correction):** keyset paging ordered by
  `(created_at, id)` cannot capture late-arriving rows that sort *before* the
  current cursor (backfills, imports, clock corrections). Covering them
  requires the periodic full re-baseline cadence and, ultimately, the B2
  change feed — cursor advance alone is insufficient by construction.
- **B1 scope limit (remediation correction):** cursor pagination captures
  inserts only. It does not capture updates (rows don't move), does not
  capture deletes (rows vanish silently), and therefore never proves
  continuous synchronization. `verified` additionally requires
  cursor-completion **plus** tombstone reconciliation, enforced in code by the
  `VerifiedEvidence` gate (all three flags), which no Phase 1 path can satisfy.

### 3.3 Backend proposals (unchanged endpoints until approved)

- **B1 — composite-keyset paging (revised per correction #3):** accept
  `after_created_at` (UTC, nullable) + `after_id` (default 0) with fixed
  `ORDER BY created_at ASC, id ASC` (== existing `sort=old`); return
  `{rows, next_created_at, next_id, has_more}`.
  *Capture argument:* every insert has `(ct,id)` greater than some cursor
  position (equal-`ct` ties broken by increasing `id`), so advancing
  `(last_ct,last_id)` after each committed row cannot skip inserts. Updates
  don't move rows (need B2/§4.2); deletes remove rows (need tombstones).
- **B2 — change feed:** `GET customer/sync/changes?scope=&since=<cursor>&limit=`
  → `{upserts, deleted_ids, next_cursor, server_time}` (needs `updated_at`
  exposure or monotonic `catalog_version` + deletion tombstones).
- **B3 — snapshot meta:** `GET customer/sync/meta?scope=` →
  `{total_products, total_stores, catalog_version, server_time}`.
- **B4 — `favorites/remove`:** reject empty `product_id` instead of mass-delete.

---

## Deliverable 4 — Full-sync and incremental-sync protocols

### 4.1 Full sync

Scope resolved (city/GPS) → data-consent check (§6) → `OPEN`
(`full_running`, cursor `(NULL,0)`) → `PAGE`: fetch (B1 cursor if available,
else `sort=old` offset), **one transaction per batch** (products + variants +
FTS) → persist cursor/offset **only after commit** → `NEXT` until
`has_more=false` (B1) or `offset ≥ serverTotal` (offset mode) → `VERIFY`
(count sanity; delta re-scan bounded; sets `best_effort` at best) →
`COMPLETE` (sets `coverage` per §3.2 evidence, never `verified` on offset
mode) → `RESUME` from persisted cursor/offset after kill/loss (committed
batches skipped; repeats absorbed by upserts) → single-flight per scope;
newer totals extend, never truncate; batch failure → backoff ×5 → park with
reason, prior rows untouched, empty/error pages never committed.

### 4.2 Incremental

- **With B2:** `changes?since=checkpoint` → apply upserts + tombstone deletes
  (row + FTS entry, scoped) in one transaction → advance checkpoint-after-commit.
  Deletes hitting favorited/carted products raise a notice; carts never
  silently mutated.
- **Without B2 (interim, labeled):** refresh-window (`sort=new` head pages,
  upsert-only) + daily categories/stores/cities + weekly full re-baseline. No
  deletion tracking claimed.

### 4.3 State machine

`idle → full_running ⇄ full_paused → full_complete ⇄ incremental`
(`incremental` only with B2). Persisted `phase + coverage + counts` drive an
honest progress UI; partial is never shown as complete.

---

## Deliverable 5 — Migration, recovery, rollback

- **Coexistence:** DB ships beside JSON behind `catalogDbEnabled` (default
  OFF). JSON writers keep running through transition. **Phase 0/1 changes no
  screen, no JSON key, no checkout/payment, no backend file (correction #6).**
- **Legacy disposition:** account/outbox/session/cart/settings JSON stays
  permanently; catalog JSON keys are *superseded, not row-migrated* (unscoped
  partials would poison scope integrity), retired only after verified-complete
  + one release, oldest-first.
- **Recovery (remediation correction):** quarantine (`catalog.db.corrupt.<ts>`)
  + recreate happens ONLY on confirmed corruption (`SQLITE_CORRUPT` /
  `SQLITE_NOTADB`); transient and operational failures (busy/locked/readonly/
  perm/io/full/nomem/cantopen, migration-time resource failures, unknown
  errors) preserve the file and rethrow — never silently replace. Migration
  steps run inside a SAVEPOINT (failure rolls back, retryable). Failed batch
  → rollback to persisted cursor; image manifest/FS mismatch → bidirectional
  orphan sweep (§6); quarantine bytes always retained for forensics.
- **Rollback:** kill-switch returns all screens to JSON within one restart;
  DB retained for forensics; drill is a Phase 1 exit test.

---

## Deliverable 6 — Storage and initial-download strategy (correction #4)

Data sync and image prefetch are **independent pipelines with separate state**:
`full_complete` never waits for images. Rules: `localImagePath == NULL` ⇒
placeholder + online-images note (never claim offline availability otherwise);
thumbnails = first `image_url`, client-downscaled to ≤512 px JPEG q70 at
prefetch (≈25–60 KB *(est.)*); prefetch starts only after data-complete,
Wi-Fi-gated by default with metered opt-in; order by display recency.

Budget from **actual bytes**: `CachedImages.bytes` accumulated on write;
startup `stat` reconciles manifest vs directory; combined ceiling 250 MB with
pre-flight free-space check; LRU eviction by `last_used_at`. Safe file order:
write temp → rename → insert manifest row; delete = remove manifest row →
delete file → periodic sweeps (manifest-without-file → NULL the path;
file-without-manifest in app-private dir → delete). Pending ops/sessions/account
docs are files-independent and never evicted.

Initial download: 50-row batches, ~1–3 s *(est.)*, resumable across sessions,
backoff, pause on weak/metered links, cancellable, no background-sync promise;
large scopes split by category; Phase 0 dry-run converts *(est.)* to measured
constants before Phase 2.

---

## Deliverable 7 — Phased plan, tests, acceptance (corrections #5, #6)

**Phase 0 (done — findings in §0).** Entry: read-only. Exit: this revised plan.

**Phase 1 — foundation + tests ONLY (approved scope for implementation).**
New files: `lib/core/catalog_db/` (`catalog_database.dart` schema v2 +
DAOs, `sync_cursor.dart` composite cursor, `sync_coverage.dart` typed
coverage gate, `db_recovery.dart` error classification,
`catalog_config.dart` flag OFF + budgets), `drift`/`sqlite3_flutter_libs`/
`sqlite3` + `drift_dev`/`build_runner`, codegen committed,
`test/catalog_db_test.dart`. **Explicitly out:** screens, JSON keys,
checkout/payment, backend, Phase 2. Test matrix (§7.1) must be green; then
**stop for review**.

### 7.1 Phase 1 test matrix (correction #5 — each a named test case)

1. Fresh open creates v2 schema with FK pragma on; reopen idempotent.
2. Upsert idempotency: same batch twice ⇒ no dupes (composite keys).
3. Cross-scope independence: same `server_id` in two scopes coexist, queries
   never leak across scopes (products + FTS).
4. Checkpoint-after-commit: simulated failed batch ⇒ cursor/offset unchanged,
   prior rows intact.
5. Kill-mid-sync resume: pre-seeded partial `sync_state` ⇒ run continues at
   persisted cursor, no rework of committed batches (logic-level, fake pages).
6. Scope switch: second scope syncs independently; first scope rows retained.
7. Failed batch commit atomicity: no partial rows visible.
8. Storage exhaustion: write failure surfaces gracefully, DB still opens,
   prior data intact.
9. Corrupt DB recovery: garbage file (confirmed `SQLITE_NOTADB`) ⇒ quarantine
   + recreate + resync-ready; quarantine file retained.
10. Transient recovery: simulated busy/locked/readonly/full/perm failures ⇒
    file preserved byte-identical, original error rethrown, no quarantine.
11. Legacy preservation: DB init/sync touches no SharedPreferences key and no
    account doc (prefs snapshot comparison).
12. Interrupted migration: fabricated populated v1 ⇒ v2 upgrade preserves
    rows/identity, enforces FK + cascade, creates indexes, `foreign_key_check`
    clean; broken migration (missing table) fails transiently with version
    and rows intact, retryable.
13. Rollback: flag OFF ⇒ existing JSON catalog path reads/writes exactly as
    before (requests no DB).
14. Composite cursor unit: ordering/tie/advance semantics incl. equal-`ct`
    ties and empty-cursor start.
15. FTS search returns scoped ranked rows; deletes remove FTS entries;
    `orphanCounts` audit reads zero after every DAO path.
16. Coverage gate: unknown strings rejected; `verified` without complete
    `VerifiedEvidence` refused with nothing written; typed read fails loudly
    on unknown stored values.

**Phases 2–6** (not started; gated on Phase 1 review): 2 sync engine + progress
UI; 3 flagged per-screen cutover; 4 image pipeline; 5 incremental (needs B2);
6 JSON catalog retirement + final report. Final gates: verified-counts fresh
sync; airplane-mode browsing of unvisited products incl. thumbnails; failure
preservation; isolation; budget compliance; rollback drill. Backend stays
authoritative for prices/stock/checkout/payment/orders throughout.
