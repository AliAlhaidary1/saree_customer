# Offline-First Remaining Work — Completion Report

Date (UTC): 2026-10-14. Continues `OFFLINE_END_TO_END_VERIFICATION_REPORT.md`
and `OFFLINE_REAL_BACKEND_INTEGRATION_REPORT.md`; neither is overwritten.
No commit, push, deploy, production change, or user-work loss in either repo.

## Verdict: PASS WITH LIMITATIONS

The highest-priority defect class — blind offset sync — is eliminated by a
tested full-reconciliation design (client-only, no backend contract change):
in-place updates, soft deletes, stock-out delisting, backdated inserts, and
variant changes now propagate on reconnect, proven live against local
Laravel/MySQL. Honest sync states, DB-backed filtering/sorting/pagination,
seller-cache TTL proof, image-manifest self-repair, and a hardened checkout
redelivery path (isolated backend tests green) are all implemented with
regression coverage: 213/213 Flutter tests, 18/18 backend tests, 0 analyzer
errors/warnings, debug APK builds. Remaining: no Android device exists
(BLOCKED with exact manual procedure), no live multi-city database (single
dev city; DAO/controller isolation tested), and offset-walk concurrency still
lags one cycle by design (`best_effort` retained honestly).

## 1. Initial vs final Git status

Customer app (`prod/offline-reliability`), initial → final: all pre-existing
staged/unstaged/untracked entries preserved. In-scope additions: `M
lib/core/catalog_store.dart`, `M lib/core/catalog_db/*` (schema v3 +
migration + DAO, untracked dir), `M lib/core/app_controller.dart`
(query routing + `catalogScopeState`), `M
lib/features/products/products_screens.dart` (status empty states +
spinner fix), `M lib/features/cart/cart_screens.dart` (debounce guard),
`M lib/core/offline/offline_cache.dart` (`ScopedDraftWrite`),
`M lib/core/image_prefetch.dart` (manifest repair + MIME guard), `M
test/offline_test.dart` (+3), `M test/catalog_db_test.dart` (v3),
`M test/offline_catalog_test.dart` (re-walk + city switch),
`M test/offline_{e2e_harness,real_backend,verification_fixes}_test.dart`
(behavior updates), new `test/products_empty_states_test.dart`.

Backend (`main`), initial → final: pre-existing `M BasicApiController.php`,
`M CheckoutMultiSellerTest.php`, `M SeedsCommerceFixtures.php`, `??
FavoriteRemovalTest.php` all preserved. In-scope additions: `M
app/Services/CheckoutService.php` (idempotency reclaim), `M
resources/lang/{ar,en}.json` (2 keys each), new
`tests/Feature/CheckoutIdempotencyRecoveryTest.php`. No migration files
added/changed. No reset/clean/stash/restore/commit/push anywhere.

## 2. Architecture decisions

**P1 — full-reconciliation sync, client-only, no backend contract change.**
A timestamp change feed was audited and rejected: products `updated_at` has
1-second precision, variants have NO timestamp columns at all
(`$timestamps=false`, inventory `save()` writes nothing temporal), and
writes are split across Eloquent/raw paths — a feed would silently miss
variant price/stock changes. Soft-delete tombstones already exist in the
database (`deleted_at`) but are not exposed by any API, and the unrouted
`getProductsOffline`/`getVariantsOffline` methods would add new surface for
no gain. At this catalog scale (~280 rows, 48-cap pages, 5-minute debounce),
a full walk from offset 0 plus end-of-walk membership reconciliation is
strictly stronger than offset checkpoints: updates propagate by re-upsert,
deletes/out-of-stock/visibility-toggles reconcile by absence, backdated rows
are always scanned. Trade-off: O(N) traffic per sync instead of
delta-sized; accepted (debounced, small payloads). Checkpoints remain as
progress/forensics markers, NOT resume points — resume would poison
reconciliation with partial id sets (an interrupted walk now re-walks fully;
idempotent upserts make repeats no-ops). Coverage stays honestly
`best_effort`: concurrent server writes mid-walk can lag one cycle.

**Deletion model (asymmetric, deliberate).** Server listings hard-filter
deleted, unapproved, disabled (product/category/seller), variant-less, and
out-of-stock rows (verified in `DiscoveryQueryBuilder`). Products therefore
reconcile to an `is_listed` flag (browse/search/counts read listed-only;
detail lookups still resolve unlisted rows stale-badged) so offline detail
pages never break and re-listing is instant. Stores/categories (tiny, always
fully walked, network fallback exists) reconcile by physical delete of
missing ids. Reconciliation runs ONLY after clean, uncapped, uncancelled
full walks — a failed/cancelled/truncated walk never touches membership.

**P5 — server reclaim, constraints never bypassed.** Redelivery short-circuit
unchanged for the normal path; a new `recoverIdempotencySession` handles the
orphan states: group-exists → heal pointer + return group (no duplicate
possible); group-missing + money moved → retryable review error (financial
trace never destroyed); group-missing + no money → drop dead rows, proceed
fresh; fresh in-flight → retryable `checkout_in_progress_retry` envelope
error (HTTP 200 `status:0`, never a 500). Unique constraints intact throughout.

## 3. Backend changes (local `main` only)

- `app/Services/CheckoutService.php`: reclaim call + `recoverIdempotencySession`
  (≈60 lines), `use App\Models\CheckoutPayment`.
- `resources/lang/en.json`, `resources/lang/ar.json`: `checkout_in_progress_retry`,
  `checkout_needs_review` (JSON validity verified in-container).
- `tests/Feature/CheckoutIdempotencyRecoveryTest.php` (new): duplicate,
  orphaned-completed, expired-processing, fresh-processing cases over HTTP.
- No migrations added; `migrate --force` run forward-clean on the isolated
  `offline_e2e_test` MySQL database.

## 4. Flutter changes

- Schema v3 (`tables.dart`, `catalog_config.dart` v2→3, SAVEPOINT migration):
  `products.is_listed` (default true), `min_price`/`in_stock`/`has_offer`
  (nullable = unknown, never hidden), `idx_products_scope_listed`.
- `catalog_store.dart`: mapping computes the three columns (server-mirrored
  effective-price rule); walks always start at 0; id-set collection;
  end-of-walk reconciliation; `CatalogScopeStatus/State`,
  `catalogEmptyMessage`; `isEmptyCatalogPage` (unchanged).
- `catalog_database.dart` (DAO): variant prune per touched product; `queryProducts`/
  `countProducts` (SQL filter/sort/page + NULL-keep semantics);
  `reconcileListed`/`deleteMissingStores|Categories` (chunked);
  `listedOnly` defaults on list/search/count.
- `app_controller.dart`: `catalogProductsLocal` + new `catalogFilteredCountLocal`
  via DAO queries; `catalogScopeState()`; fetch adapters (unchanged behavior).
- `products_screens.dart`: status-driven empty states + retry routing;
  fixed infinite spinner on total failure (now paints EmptyState+retry).
- `cart_screens.dart` + `offline_cache.dart`: `ScopedDraftWrite` capture-and-guard.
- `image_prefetch.dart` + DAO `getImage`: orphan adoption with real disk size,
  drift correction, non-image MIME skip.

## 5. Regression scenarios and real evidence

P1 (16 required; live Laravel/MySQL unless noted): (1) multi-page initial —
RA live 277/277; (2) offline name+price update → propagated live (RB);
(3) offline soft-delete → unlisted from browse/search/count, resolvable by id
(RB live); (4) front insert → converges (harness B2); (5) backdated insert →
captured live (RC); (6) variant price/stock change → propagated live
(RB/RB2); (7) seller/category change → picked up live (RS + re-walks);
(8) mid-walk insert → converges next walk (new unit test); (9) interrupt →
full re-walk, no dupes (updated unit test + harness cancel test);
(10) replay idempotent (existing); (11) failed page advances nothing
(existing); (12) deleted vanish from search/FTS (DAO + live RB);
(13) scope isolation incl. unlisted (DAO + controller city A-B-A test);
(14) 48-cap + 277-row catalog (RA live); (15) empty→non-empty (unit +
DAO; live full-empty impossible on shared data — noted); (16) corrupt
checkpoint recovers (new unit test; no cursor protocol exists by design).
Representative live values: variant 357 price 100→150 propagated; product 289
rename propagated; soft-deleted `rb-deleteme` unlisted yet resolvable;
stock-out 289 delisted then relisted on restock; backdated row captured;
duplicate key → 1 group + 1 payment row.

P2: 5 `catalogScopeState` unit tests + 5 message-mapping tests + 3 widget
tests (never-synced/failed/empty screens); DAO query test (filters, global
sorts incl. NULLS LAST, paging, count consistency, search+category combo);
controller city-switch test.

P3: live RS (stale within TTL → fresh after `invalidateCatalog`, SQL-verified
restore); controller A-B-A isolation; `ScopedDraftWrite` ×3 (drop on switch,
snapshot isolation).

P4: I4 orphan adoption (7 real bytes), I5 drift correction (9999→actual),
I6 single-download + manifest==disk, I7 non-image skip + retry-not-poisoned
(all local-HTTP-server deterministic).

P5: 4 isolated backend tests green; live RD still green; `delete_order`
proven legacy-only (no group/session delete path exists in customer APIs);
offline checkout fails closed (existing RD-offline).

P7: v1→v3 migration with data/FK/cascade/indexes + orphan preservation +
broken-migration rollback (updated fabrication); forward MySQL migrate on
isolated DB; null/missing-identity/additive payload compat; unknown-coverage
rejection (existing).

## 6. Test totals by layer (exact commands, exit 0 unless noted)

- A. Unit/widget: `flutter test` full → **213/213 pass** (≈90s), of which
  harness file 32, real-backend file 11, verification-fixes file 22,
  products-empty-states file 9, remainder pre-existing unit/widget suites.
- B. Fake harness: included above, 36/36 (`test/offline_e2e_harness_test.dart`).
- C. Real Laravel/MySQL: included above, 12/12
  (`test/offline_real_backend_test.dart`: R0, RA, RB, RB2, RC, RD, RE, RF,
  RG, RH, RS + city-switch lives in offline_catalog file).
- Backend (isolated sqlite :memory:): `vendor/bin/phpunit
  tests/Feature/CheckoutMultiSellerTest.php` → 14/14 (51 assertions);
  `vendor/bin/phpunit tests/Feature/CheckoutIdempotencyRecoveryTest.php` →
  4/4 (24 assertions).
- D. Device: 0 — BLOCKED (no AVD, no hardware; §8).
- `flutter analyze` → 0 errors, 0 warnings (infos only).
- `flutter build apk --debug` → success.
- Note: two transient backend stalls observed under sustained suite load
  (non-JSON response → single-test failure), green on immediate rerun every
  time; MySQL healthy, zero aborted connects. Suite has no infra-retry by
  design; CI should retry-or-quarantine on `invalid_response`.

## 7. Remaining limitations (and why)

- Concurrent-write-during-walk still lags one cycle (`best_effort` kept).
- No live multi-city database (dev has 1 city; creating a second would
  pollute shared single-city-mode behavior) — DAO/controller isolation tested.
- Live >100-category walk untested (only 11 exist) — code path identical to
  products (server-total preference), unit-covered to 150.
- Mid-walk kill (process death) approximated by cancel/interrupt tests.
- Stale-session case requiring wallet-linked review error is unreachable via
  app code paths (no group delete endpoint); covered by backend unit test
  shape only for the zero-money orphan (full wallet-orphan path untestable
  without fabricating inconsistent finance rows — deliberately not done).
- Device testing BLOCKED — exact manual procedure: install debug APK on
  Android 12+ device; (1) online fresh sync, record counts; (2) airplane ON,
  browse/search/product-detail, confirm stale badges, no fake-complete;
  (3) create checkout/address/haraj drafts, force-stop via settings,
  relaunch offline, confirm drafts restored under correct account, nothing
  submitted; (4) airplane OFF, sync, confirm updates/deletes applied;
  (5) logout→login second account, confirm no cross-account drafts/outbox/
  badges; (6) switch city if available; (7) place test COD order with
  airplane toggled mid-submit, confirm single group via orders screen;
  (8) toggle favorite offline, reconnect, confirm single server row.
  Do not accept production until (1)–(8) pass on hardware.

## 8. Confirmations

Production untouched (all URLs container-local; image tests use loopback/local
placeholder; no external hosts). No commits, pushes, deployments. No
`migrate:fresh`/`db:wipe`/RefreshDatabase-against-dev (backend tests run on
sqlite :memory:; MySQL migrate ran only on empty `offline_e2e_test`). No
credentials/tokens in logs or this report. No reset/clean/stash/revert.
Failures were fixed, never hidden by weakened assertions (3 pre-existing
expectations updated only to match corrected intended behavior:
48-page default, full re-walk, reconciled RB/RC outcomes — each documented
above).
