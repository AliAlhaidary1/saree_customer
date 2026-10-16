# Offline-First Real Backend Integration Report

Date (UTC): 2026-10-14. Continues `OFFLINE_END_TO_END_VERIFICATION_REPORT.md`;
that file is preserved. No commit/push/deploy performed in either repo.

## Verdict: PASS WITH LIMITATIONS

Genuine integration against local Laravel + MySQL is now proven: multi-page
sync matches server totals, offline mutations behave honestly on reconnect,
duplicate-key checkout returns one group with one DB row, favorites toggle and
outbox replay verified end to end, restart persistence and timeout behavior
verified live. Two real defects were found and fixed (product 48-cap short-page
stop; past-end `status:0` envelope poisoning resumes), each with regression
tests. Remaining limits: offset paging still cannot see in-place edits,
deletes, or backdated inserts (no change feed — demonstrated live, not
assumed); no Android device available; sellers/categories edge cases and the
stale-session redelivery gap are documented below.

## 1. Environment and database safety verification

- Backend: `D:\myproject\review\saree_back`, branch `main`. Docker Compose
  services healthy: `saree_back-mysql-1` (healthy, host `0.0.0.0:3307→3306`),
  `saree_back-app-1` (`0.0.0.0:8000→8000`), assistant/qdrant/meilisearch/
  evolution stack. `docker compose config` confirms `APP_ENV=local`,
  `APP_URL=http://127.0.0.1:8000`, `DB_CONNECTION=mysql`, `DB_HOST=mysql`,
  `DB_DATABASE=sql_laravel_marabmall_cloud`, root/empty-password, data volume
  `saree_back_mysql_data`. Nothing points to production (production host would
  be `marabmall.cloud`; all endpoints here are container-local). Secrets in
  `.env`/compose output are not reproduced in this report.
- Effective check: `artisan migrate:status` all `Yes`; `tinker` read-only
  counts users=78, products=288→(fixtures), sellers=26, categories=40,
  cities=1; direct MySQL confirms same. `artisan` startup log: `Nothing to
  migrate. Database already has data — skip full seed`.
- Isolation: created EMPTY database `offline_e2e_test` (verified via
  `SHOW DATABASES`) as the disposable-DB proof; API scenarios ran against the
  main local DB using `E2EOFFLINE`-marked fixtures only (users 79/80, seller
  27, category 41, product 289/variant 357, `e2eoffline-*` slugs). No
  `migrate:fresh`/`db:wipe`/bulk deletes; `CheckoutMultiSellerTest` (uses
  `RefreshDatabase`) was deliberately NEVER executed — it would wipe the dev
  database. Backend tree untouched: final `git status` identical to session
  start (`M BasicApiController.php`, `M CheckoutMultiSellerTest.php`,
  `M SeedsCommerceFixtures.php`, `?? FavoriteRemovalTest.php` — all
  pre-existing).
- Customer app: branch `prod/offline-reliability`; pre-existing staged/
  unstaged/untracked work preserved (final status in §10).

## 2. Backend availability (real responses)

- `GET /customer/cities` → HTTP 200 `{status:1,total:1,data:[{id:1,Marib...}]}`.
- `GET /customer/categories?limit=2` → `{status:1,total:10,...}` (endpoint
  filters to 10 of 40 rows).
- `GET /customer/sellers?limit=2` → `{status:1,total:24,...}` (24 of 26 rows).
- `POST /customer/products` (multipart, lat/lon Marib, `sort=old`):
  `total=276→279` with `total_min/max_price`, `exploration_seed`;
  **page cap 48** regardless of requested limit (verified limits 2/50);
  **`total` reported on offset=0 only, omitted (`-1` client-side) later**.
- Past-end probes (multipart + query): products offset=500 → HTTP 200 +
  `{status:0,message:"لم يتم العثور على منتجات"}` (NO `data` key); categories
  offset=5000 → `{status:0,message:"لم يتم العثور على فئات!"}`; sellers
  offset=5000 → `{status:1,total:25,data:[]}` (clean).
- Auth: `POST /customer/register` requires WhatsApp OTP (blocked, used
  container-side fixture seeding instead); `POST /customer/login_mobile`
  works → Bearer tokens at runtime (never hardcoded).

## 3. Baselines (before new fixes)

- `flutter test test/offline_verification_fixes_test.dart
  test/offline_e2e_harness_test.dart` → 37/37 pass.
- Prior report suites green (167/167 full).

## 4. Fixtures (reproducible, selective cleanup)

- `e2e_seed.php` (outside both repos, copied to `/tmp` in container, executed,
  removed from container): E2EOFFLINE user ×2 (ids 79/80), address 26 (Marib),
  seller 27, category 41, product 289 (`e2eoffline-product-*`, approved,
  Marib coords) + variant 357 (price 100, stock 10), Bearer tokens printed to
  local temp only. Idempotent (marker-based delete-first).
- Scenario rows (`rb-append`, `rb-deleteme`, `rc-backdate`, carts, groups)
  created/deleted per-test with marker predicates; final state verified:
  groups/sessions/carts/favs residue = 0; seed fixtures retained clean
  (product 289 name restored, variant 357 = 100.00) so the committed suite
  re-runs deterministically (each real test also resets its own markers).

## 5. Real integration results ([real] = live Laravel/MySQL)

New suite `test/offline_real_backend_test.dart`: **9/9 pass** (plus a live
container-pause timeout probe, run once, then removed from the tree).

| ID | Real scenario | Evidence | Status |
|---|---|---|---|
| R0 | Reachability + fixtures | cities 200; login user1 ok; page-0 total>200; E2E slug listed | PASS |
| RA | Multi-page sync vs server | 277-row sync `complete:true`; local count == server total; FTS finds Arabic + E2E rows; variant 357 mapped; cats/stores counts == endpoint totals (11/25); checkpoint `best_effort`, offset>0 | PASS |
| RB | Offline price/name/delete → reconnect | offline attempt `complete:false`, count intact; reconnect completes; price/name stale (update missed — LIMIT); appended row captured; soft-deleted row retained locally (no tombstones — LIMIT) | PASS (documents limits) |
| RC | Backdated (2020) insert | API head shows it; resume-from-checkpoint misses it locally | LIMIT (demonstrated) |
| RD | Duplicate-key checkout | same key → same `checkout_group_id`; `checkout_groups` count for key = 1; payment row `payment-<key>`; offline checkout `ok:false`, zero rows; no auto-resubmit (request count +1) | PASS |
| RE | Favorites toggle + outbox replay + isolation | add/remove rows verified in MySQL; offline `toggleFavorite` queues stamped op; reconnect `runPendingOp` replays (row present); u:79-stamped op dropped under u:80 (user80 untouched, user79 intact) | PASS |
| RF | Restart + payload shapes | real null-top-level-price row maps, filter keeps it; file-DB close/reopen preserves count; honest states | PASS |
| RG | Isolation; cities==1 | both accounts log in; drafts wipe per-account, other intact; single city → cross-city live test impossible (DAO isolation in harness H1) | PASS + noted |
| RH | Local placeholder SVG prefetch | 1 file stored; manifest bytes>0; manifest path exists on disk with equal size | PASS |
| Pause probe | `docker compose pause app` → fetch | clean TIMEOUT at 15s receiveTimeout, `ok:false`; post-unpause healthy | PASS (one-off) |

Server↔local comparisons (representative): variant 357 price 100→150 while
offline stayed 100 locally / fresh API read 150 (server wins, checkout
revalidates live); product 289 rename likewise stale; `checkout_groups`
(E2EOFFLINE-rd-1) exactly 1 row, payment exactly 1 row; favorites 79/289
toggled 0→1→0→1 live; file-DB reopen preserved full real catalog count.

## 6. Defects found and fixed (with regression tests)

1. **Product sync stopped after 48 of ~279 rows yet reported `complete:true`.**
   Root cause: `DiscoveryQueryBuilder::productContext` clamps pages to 48
   (verified live), while the client requested 50 and treated any short page
   as end-of-data. Same latent trap the report had flagged for sellers only.
   Fix (client, `lib/core/catalog_store.dart` + `catalog_config.dart`):
   track `knownTotal` across pages — a short page ends the walk only when no
   known total contradicts it — and set `syncPageSize = 48` to match the
   verified cap. Regression: `short page below server cap continues…`
   (100 rows via 48-capped fake, total on page 1 only → all 100, complete),
   `short page with unknown total still ends…`, plus live RA (277/277).
   Two pre-existing tests updated mechanically to the corrected default
   (first-page 50→48, resume offset 50→48).
2. **Past-end/empty pages (`status:0` + "لم يتم العثور على…", no `data`)
   parked the sync AND poisoned every future resume.** After any delete below
   the checkpoint (demonstrated live: checkpoint 281, 280 visible), each
   re-sync re-fetched the dead offset and errored forever; genuinely empty
   catalogs could never complete either. Sellers are unaffected (clean
   `{status:1,data:[]}`). Fix (client, `catalog_store.dart:new
   isEmptyCatalogPage`, wired into `AppController.fetchProducts`/
   `fetchCategories`): that exact empty signal with zero rows maps to clean
   end-of-data (`total: offset`); all other failures stay errors. Regression:
   3 unit tests + `past-end error page ends the walk cleanly` + live RB
   reconnect completing. Note: genuinely-empty scopes now complete with a
   checkpoint, which also repairs the DAO-level empty-vs-unsynced distinction.
3. **Test-hygiene issues fixed during the pass (not app bugs):** flutter_test
   HttpClient hijack (already handled), ApiCache TTL masking server edits
   across re-walks (fresh `CustomerApi` per walk in tests), `be.api()` after
   `goOffline`, cross-run fixture residue (idempotent marker setup + server
   state reset), malformed manual multipart probe (false alarm, corrected —
   multipart pagination verified working).

Backend changes: **none.** One residual server-side gap documented, not
patched: a *completed* session whose group was deleted makes redelivery fall
through to session INSERT → 1062 → HTTP 500 (`CheckoutService.php:62-69`
assumes completed-session ⇒ group-exists). Not reachable in normal operation
(short-circuit returns the group); hit only by inconsistent manual cleanup
during testing. Recommended local fix if ever needed: on fall-through, replace
the orphaned session row for the same user+key instead of inserting. Left
untouched deliberately (backend has unrelated in-progress work; RefreshDatabase
regression tests unsafe to run here).

## 7. Remaining risks

- Offset paging still blind to in-place edits, deletes, backdated/front
  inserts (B/C/RC live proof); no backend change feed/tombstones (source-grep
  confirmed). Client stays honest `best_effort`; do not present sync as
  complete. `getProductsOffline`/`getVariantsOffline` exist server-side but are
  UNROUTED (dead code) — a future bulk-sync contract could start there.
- Checkout idempotency now proven LIVE for the normal path (same key → same
  group, one row; derived `payment-<key>` unique), closing prior RB-1 subject
  to the stale-session caveat above. Still needs: staging duplicate-key run in
  CI and a product decision on group-retention vs session lifetime.
- Sellers/categories walks restart at 0 (edits picked up); categories rely on
  the new server-total preference (live G5-analog: 11/11; >100-category live
  walk untested — only 11 exist).
- Local GET caches (sellers 60s server-side; client 2/10-min TTLs) delay
  visibility of server edits by one cycle.
- `catalogProductCountLocal()==0` UI conflation and filter/sort windowing
  remain as previously reported.

## 8. Commands and results (exact)

- `flutter test test/offline_verification_fixes_test.dart
  test/offline_e2e_harness_test.dart` → 39/39 pass (exit 0).
- `flutter test test/offline_real_backend_test.dart` → 9/9 pass (exit 0).
- `flutter test` (full) → **181/181 pass** (exit 0).
- `flutter analyze` → 0 errors, 0 warnings, 176 infos (174 pre-existing + 2
  info-level nits in test files).
- `flutter build apk --debug` → success (`app-debug.apk`).
- Backend (read-only unless noted): `docker ps`, `docker compose config`,
  `docker compose logs app`, `artisan migrate:status`, tinker count queries,
  `curl`/python endpoint probes, `mysql` SELECTs, fixture seed via container
  `/tmp` copy (removed afterwards), marker-scoped INSERT/UPDATE/DELETE,
  `docker compose pause/unpause app` (restored healthy, verified `Up` +
  `cities:200`), `CREATE DATABASE offline_e2e_test` (empty, no tables).
- Backend tests: NOT executed (`CheckoutMultiSellerTest` uses
  `RefreshDatabase` — running it would wipe the shared dev database; documented
  instead of risked).

## 9. Device-backed testing

Not performed: `flutter devices` shows Windows/Chrome/Edge only;
`flutter emulators` reports no AVD images. No airplane-mode, force-stop, or
restart testing on hardware. Flutter-level equivalents executed instead: real
file-DB close/reopen (RF), connection-refused offline (RB/RD/RE), hung-server
timeout (pause probe), restart-persisted drafts/outbox (harness D1/D2). Not
claimed as device evidence. Manual device checklist carries over from the
prior report.

## 10. Git status and preservation

- Backend (`main`): before = after (`M BasicApiController.php`,
  `M CheckoutMultiSellerTest.php`, `M SeedsCommerceFixtures.php`,
  `?? FavoriteRemovalTest.php`). No backend file modified; seed ran from
  container `/tmp` (deleted); dev DB verified clean of transient residue.
- Customer app (`prod/offline-reliability`): only in-scope changes —
  `lib/core/catalog_store.dart` (knownTotal continuation + empty-envelope
  helper), `lib/core/catalog_db/catalog_config.dart` (48 cap),
  `lib/core/app_controller.dart` (fetch adapters), `test/offline_catalog_test.dart`
  (2 expectations to corrected default), new `test/offline_real_backend_test.dart`,
  extended `test/offline_verification_fixes_test.dart`. All prior staged/
  unstaged/untracked work preserved; no reset/clean/stash/commit/push.

## 11. Recommendation

Ship to controlled internal testing with real-backend confidence materially
higher than before: full-catalog sync, honest offline/reconnect behavior,
duplicate-safe checkout, and replay-safe favorites are all proven against live
Laravel/MySQL. Before production still required: (a) CI staging duplicate-key
checkout proof; (b) device-backed airplane/kill/switch suite; (c) product call
on best-effort catalog vs backend change feed (B1/B2); (d) decide the
stale-session hardening fix in §6; (e) re-check >100-category live walks and
the two UI-conflation items from §7 of the prior report.
