# SareeMart Customer — Offline/Online End-to-End Verification Report

Date (UTC): 2026-10-14. Branch (customer app): `prod/offline-reliability`.
New file; no existing report was overwritten. No commit/push/deploy performed.

## 1. Overall verdict: PASS WITH LIMITATIONS

The offline-first stack verifiably does what it claims through the real
production HTTP + persistence path (see §4): checkpoint-after-commit sync,
honest incomplete states, scoped drafts that never auto-submit, favorites-only
queueing, online-only money actions, scoped isolation, bounded image caching.
One real client defect was found and fixed during this pass (categories
pagination total, §8); prior-verification fixes were confirmed working.

Not production-ready: offset pagination provably misses in-place updates,
deletes, and shifted rows (demonstrated, §5 B/C); there is no backend change
feed/tombstone API to fix that client-side; live Laravel execution and live
device testing were unavailable in this environment (§2, §11). Safe for
controlled internal testing.

## 2. Exact environment and safety

- Customer app: `D:\myproject\review\saree_customer`, branch
  `prod/offline-reliability` (verified via `git branch --show-current`).
- Backend source (read-only): `D:\myproject\review\saree_back`, branch `main`.
  Backend working tree contains unrelated in-progress work
  (`M app/Http/Controllers/API/Customer/BasicApiController.php`,
  `M tests/Feature/CheckoutMultiSellerTest.php`,
  `M tests/SeedsCommerceFixtures.php`,
  `?? tests/Feature/FavoriteRemovalTest.php`) — preserved untouched.
- Configured API base in setup: `http://127.0.0.1:8000/customer/`.
  Effective backend `.env`: `APP_ENV=local`,
  `DB_CONNECTION=mysql`, `DB_HOST=mysql` (Docker service),
  `DB_DATABASE=sql_laravel_marabmall_cloud`. Secrets present in `.env`
  (mail/Stripe-test/Twilio/LLM keys) are NOT reproduced here.
- Toolchain: Flutter 3.47.1, Dart 3.13.1, Windows x64.
- Limiting facts: no PHP runtime in PATH, Docker daemon down
  (`docker ps` → cannot connect to engine), backend `.env` targets a Docker
  MySQL service, `curl http://127.0.0.1:8000/customer/cities` → no listener,
  no Android emulator (`flutter emulators` → none), `flutter devices` →
  Windows/Chrome/Edge only.
- Safeguards honored: no production endpoint/database touched; no backend file
  modified; no database created/dropped/migrated/seeded (none was reachable);
  no `reset/clean/stash/revert/commit/push`; test data lives only in ephemeral
  loopback servers, in-memory/temp-file Drift DBs, and mocked
  SharedPreferences. Test identifiers use `E2E`/9000-range ids, disjoint from
  dev data.

## 3. Data lifecycle inventory (condensed)

Source: actual Flutter + Laravel sources (representative paths).

| Entity | Source of truth | Local storage | Endpoints (customer prefix) | Offline policy | Reconnect | Conflicts/retry | Deletion/scope | Schema deps |
|---|---|---|---|---|---|---|---|---|
| Products/variants/prices/stock | Server (`products`, `product_variants`, SoftDeletes) | Drift `products`/`product_variants`/`products_fts`, scope `city:<id>`/`global` | `POST products` (limit/offset/sort), `POST product_by_id` | Read local; no local mutation | Offset resume from checkpoint; `best_effort` only | Bounded thrown-only retry; replay idempotent via composite PK | No tombstone feed → deletes invisible; scoped by city | Drift v2; additive JSON ignored |
| Categories | Server (`categories`, `row_order`) | Drift `categories` scoped | `GET categories` (limit/offset) | Read local | Full re-walk from 0 each run | Same as above | Scoped; no feed | same |
| Stores/sellers | Server (`sellers`) | Drift `stores` scoped | `GET sellers` (limit/offset, cap 48) | Read local | Full re-walk from 0 | Same | Scoped; no feed | same |
| Offers/campaigns/sliders/FAQs/CMS/policies | Server | Scoped JSON snapshots, stale-badged | `GET offers/sliders/faqs/privacy_policy/...` | Read stale snapshot | Refresh on open (TTL) | Retry via `_guard` | Global or scoped snapshots | none local |
| Cart (account) | Server | Last-confirmed snapshot `oc:snap::cart::<scope>`, stale-badged | `GET cart`, `POST cart/add|remove|...` | Browse snapshot; commit online-only, revalidated | Refresh; checkout uses live data | Server wins | Account-scoped; logout wiped | — |
| Guest cart | Device (+ server at login) | `guest_cart` prefs | `GET cart/guest_cart`, `POST cart/bulk_add_to_cart_items` (login merge only) | Local edits allowed | Merge is NOT a safe queued op (drained, not replayed) | No idempotency claimed | Guest scope | — |
| Favorites | Server authoritative; pending intent overlaid | `oc:favs::<scope>` + outbox `oc:pending::<scope>` | `GET favorites`, `POST favorites/add|remove` | Toggle offline allowed → queued, coalesced | Bounded replay, converged states treated as success | Dedupe by product; idempotent replay | Account-scoped; scope-checked at replay | — |
| Addresses | Server | `oc:addrs::<scope>` + `address_form` draft | `GET address`, `POST address/add|update|delete` | Draft local-only, never auto-sent | Explicit submit only | Server wins | Account-scoped | — |
| Orders/checkout-groups | Server | `oc:orders/odetail::<scope>` snapshots; `checkout_session::<scope>` | `POST checkout` (+ `idempotency_key`), `GET orders/checkout-groups...`, `POST .../cancel` | Online-only commit; uncertain state reconciled, never blindly resent | `hasRecentOrderForSession` reconcile | Server-enforced idempotency (unique `user_id+idempotency_key`; §12) | Account-scoped | `checkout_*` tables |
| Wallet/transactions | Server | Snapshots, spend-disabled offline | `GET get_user_transactions`, wallet recharge endpoints | Read stale; spend online-only | Refresh | Server wins | Account-scoped | ledger tables |
| Notifications | Server | `oc:notifs::<scope>` + per-account read flags | `GET notifications` | Read stale | Refresh; 2-min poll when open | — | Account-scoped; flags cleared on logout | — |
| Haraj | Server | Feed/detail snapshots + create/edit drafts (image paths survive) | `GET haraj/...`, `POST haraj/posts/create|...` | Draft local-only; publish online-only | Explicit submit | Server wins | Scoped snapshots; comments/reports online-only | haraj tables |
| Akhdimni | Server | Home/orders/detail snapshots + request draft | `GET/POST akhdimni/...` | Draft local-only; dispatch online-only | Explicit submit | Server wins | Account-scoped | akhdimni tables |
| Complaints | Server | List snapshot + form draft | `POST complaints` (public), `GET complaints/mine` | Draft local-only; submit online-only | Explicit submit | Server wins | Scoped | `complaints` table |
| Assistant thread | Device | Account snapshot (30 text turns) | `POST assistant/ask|act` | Offline notice, never auto-sent | Manual resend only | — | Account-scoped; deleted on "new chat" | — |
| Auth token | Secure storage | `flutter_secure_storage` (+ one-time legacy migration); throws, never plaintext fallback | `POST login*|register`, `GET user_details`, `POST logout` | Submit explains offline; credentials never queued | `validateSession`: 401/403 clears, transient keeps + restores snapshot | — | Cleared on logout | — |
| Role (seller/courier/admin) screens | Server | NONE (no cache keys, no drafts, no outbox) | role endpoints | Online-only | — | — | Auth enforced per screen | — |

Backend contract facts (static, file:line): envelope
`{status:1/0,message,total,data}` (`saree_back/app/Helpers/CommonHelper.php:61-100`,
HTTP 200 always); pagination is `limit/offset` (`DiscoveryQueryBuilder.php:98-99`,
products cap 50, sellers 48; `sort` raw); orders `limit=12,offset=0`
(`OrderApiController.php:1665`); favorites/addresses/transactions/notifications
`limit=10,offset=0`; Haraj uses `per_page` paginator instead; no
`/sync|changes|since|tombstone|ETag` API (grep: zero customer-surface hits);
SoftDeletes exist (`Product, ProductVariant, Order, Seller, User,
CheckoutGroup, HarajPost, ...`) but deletions are invisible to clients.

## 4. Test harness (reproducible, deterministic)

New: `test/offline_e2e_harness_test.dart` (28 tests, all passing).
`FakeCustomerBackend` (dart:io HttpServer on 127.0.0.1:ephemeral) implements
the verified envelope/pagination/idempotency semantics (same-key `POST
checkout` → same `checkout_group_id`, mirroring the unique constraint).
Fault injection: connection-refused offline (`goOffline`), mid-response socket
close, HTTP 500, delays, malformed JSON, duplicate/stale responses — all
through the REAL `CustomerApi`/Dio stack (multipart POST parsing verified on
the wire), REAL `CatalogSyncService`, REAL `CatalogDao` (memory + temp-file
DBs), REAL `OfflineCache`/`PendingOutbox`/`CheckoutSession`/`ImagePrefetch`.
`HttpOverrides.global = null` was required because flutter_test hijacks
HttpClient (all requests → 400). IDs use `E2E`/9000-range; no dev data touched.

Coverage map: A1–A3, B1–B2, C1, D1–D4, E1–E3, F1–F3/F6, G1–G3/G5, H1/H3,
I1–I3, J1/J4. Matrices B/C demonstrate backend-limitation outcomes (not
silently passed). G4/G-migration-file upgrades rely on existing
`test/catalog_db_test.dart` R3/SAVEPOINT coverage (re-ran green); backend
migration *execution* was impossible (no PHP/MySQL) — §11.

## 5. Executed scenario matrix (expected → actual)

PASS = ran green. LIMIT = ran, demonstrates a backend-contract limitation
(by design, not a client bug). All rows executed via §4 unless noted.

| ID | Scenario | Expected | Actual | Status |
|---|---|---|---|---|
| A1 | Online full sync (5 prod/2 stores/1 cat, pages of 2) | batches persist scoped; wire shows `sort=old`, offsets 0/2/4; variants/FTS/filter/sort OK | products=5, count=5, offsets observed, variants=1, FTS=5, filter/sort correct | PASS |
| A2 | File DB restart; offline reopen | rows+checkpoint survive reopen; offline reads work; offline sync attempt fails honestly, preserves data | count preserved across `openFile` reopen; 3/3 FTS hits offline; `complete:false`, count intact | PASS |
| A3 | Unsynced vs empty vs failed | unsynced: count 0 + no checkpoint; empty-after-sync: count 0 + checkpoint; failed: no rows/checkpoint | DAO-distinguishable as specified (UI conflation remains, §9) | PASS |
| B1 | Price edit + appended insert, re-sync | append captured; in-place edit refreshed | append (3005) captured; price edit MISSED (offset resume skips page 0); store edit picked up (stores re-walk) | LIMIT |
| B2 | Front-insert offset shift | honest walk, no crash | one server row skipped locally (demonstrated), `complete:true` + `best_effort` (coverage gate holds) | LIMIT |
| C1 | Offline: price change + append; offline sync; reconnect | stale snapshot offline; offline attempt fails closed; append captured; price stale; delete never learned | offline reads unchanged; offline `complete:false`, count=4; after reconnect 5009 present, price stale, deleted 5003 still local | PASS (docs limits) |
| D1 | Checkout draft edit offline → restart → reconnect | restored scoped; never auto-submitted; cleared only explicitly | Arabic/large drafts round-trip per scope; no mutation endpoint exists; explicit `removeDraft` clears | PASS |
| D2 | Fav toggles offline → restart → replay | coalesce; survive restart; replay once; idempotent; scoped | 3 toggles → 1 op; replay via real HTTP; server has single entry; `u:2` empty | PASS |
| D3 | Checkout while offline | fail closed, nothing queued | `ok:false` (NETWORK/connection-refused), zero server state, no checkout op type exists | PASS |
| D4 | Duplicate `idempotency_key` | same group id; new key → new group | same-key ids equal; different-key ids differ (harness mirrors verified server rule) | PASS [harness] |
| E1 | Stale price vs server | cached 100, fresh 250, server wins | confirmed; checkout revalidates live (code path cited) | PASS |
| E2 | Delayed response after scope switch | stale write dropped | dropped under new scope; same-scope write lands | PASS |
| E3 | Concurrent sync | single-flight | one `already_running` | PASS |
| F1 | First-page 500 | error, 0 rows, no checkpoint | confirmed | PASS |
| F2 | Mid-walk failure then resume | 2 kept + checkpoint; resume completes 4, no dupes | confirmed | PASS |
| F3 | Malformed/empty-shape pages | never complete | `complete:false` | PASS |
| F6 | Real-file corruption | quarantine + recreate, rows reset, quarantine file kept | confirmed (transient-preserve covered by existing R1 tests) | PASS |
| G1 | Additive `promo_label` field | ignored safely, payload verbatim | confirmed | PASS |
| G2 | Missing optional price | row kept, filter never hides | confirmed | PASS |
| G3 | Missing id row | skipped, sibling commits, walk completes | count=1, `complete:true` | PASS |
| G5 | 150 categories | all 150 sync (regression for §8 fix) | 150/150, `complete:true` | PASS |
| H1 | Two city scopes | no mixing in list/search/count | `city:1=[9101]`, `city:2=[9102]`, FTS per scope | PASS |
| H3 | Logout | snapshots/drafts gone, variant labels cleared | `wallet` null, `v-9` label empty | PASS |
| I1 | Prefetch default | OFF | `offlineImagesEnabled==false` | PASS |
| I2 | Hanging + good image | hang skipped, good stored, gate resets, rerun works | n=1, `running==false` throughout | PASS |
| I3 | 3MB image | skipped, manifest 0 bytes | confirmed | PASS |
| J1 | Browse→offline→server append→reconnect | end-to-end coherent | 9509 captured after reconnect | PASS |
| J4 | Checkout no-auto-resubmit + dedup | 1 request; same-key retry dedups | request count +1 only; ids equal | PASS [harness] |

Representative mutations (C1): server 5001 price `100→777` while offline;
local stayed `100` offline and after reconnect (stale, LIMIT); appended 5009
captured after reconnect; deleted 5003 remains local (no tombstones, LIMIT).
B1: server 3001 price `→999`; local kept old value after re-sync (LIMIT).

## 6. Offline-to-online behavior

Refreshed: tail-appended products (offset resume), all stores/categories
(full re-walk), snapshots/TTLs on open, favorites outbox (coalesced, bounded).
Retained as drafts (never auto-sent): checkout/address/profile/complaint/haraj/
akhdimni forms; assistant thread (until "new chat" deletes it).
Rejected offline: checkout/payment/wallet-spend/transfers, auth submits,
haraj publish, uploads, role actions (fail closed with messaging).
Left stale (honest `best_effort`): in-place product edits, deletes, backdated/
front-inserted rows shifting offsets, prices/stock in snapshots (checkout
revalidates live; E1 proves server-wins).

## 7. Schema compatibility results

| Backend state | App/schema | Expected | Actual |
|---|---|---|---|
| Existing schema | Current (Drift v2) | Normal | PASS (A1/file-DB/migration suites green) |
| Additive API field | Current | Compatible | PASS (G1) |
| Missing optional field | Current | Safe fallback | PASS (G2) |
| Missing required identity | Current | Controlled skip | PASS (G3) |
| 150 categories (server total honored) | Current + §8 fix | Full walk | PASS (G5) |
| Fresh install (v2 create) | Current | Init OK | PASS (existing `catalog_db_test` schema-lifecycle) |
| v1→v2 upgrade | Current | Data-preserving (SAVEPOINT rollback on failure) | PASS (existing R3 migration tests, re-ran) |
| Failed backend migration / rollback | Current | N/A (no PHP/MySQL to execute) | NOT EXECUTED (§11) |
| Removed/renamed server field | Current | Staged-compat per API review | NOT EXECUTED live; mapping is null-safe by construction |

No Drift schema change was needed for additive server fields (payloads stored
verbatim; indexed columns default safely).

## 8. Confirmed defects and fixes (this pass)

1. **Categories pagination capped at ~100 (real defect, fixed).**
   `AppController.fetchCategories` set `total = res.dataMaps.length`
   (current page length), so `_syncSimpleEntity`'s `offset >= total` break
   always fired after page one; >100 categories silently stayed `complete:true`.
   Fix: prefer envelope `raw['total'] ?? dataMap['total']`, fallback to page
   length (`lib/core/app_controller.dart`). Regression: G5 (150 categories →
   150 synced). Found via harness; existing unit tests used closures that never
   exercised this line.
2. **Prior-verification fixes confirmed working, not re-fixed:**
   stores/categories-failure honesty + `truncated_max_pages` + cancel-during-
   stores (`lib/core/catalog_store.dart`, covered by
   `test/offline_verification_fixes_test.dart` 9 tests); scope guards on
   `reloadSettings`/`loadAddresses`/`refreshCart`/`validateSession` +
   `OrderDetailsScreen`; `_variantLabels` cleared on logout;
   `removeAccountSnapshot`/`removeDoc` + assistant-thread delete;
   `ImagePrefetch` dual-hash filenames, path-only extension, per-chunk stall
   timeout (`lib/core/image_prefetch.dart`); `syncCatalogSoon` gate
   (`enabledForUse`). Harness re-proves H3/I2/J-behaviors end to end.
3. **Test-harness bugs fixed during the pass (not app bugs):** flutter_test
   HttpClient hijack (fixed with `HttpOverrides.global = null`), ApiCache TTL
   masking server edits across re-syncs (fixed with fresh `CustomerApi` per
   walk — itself a documented production behavior, §9), `be.api()` after
   `goOffline` (capture api first), `path_provider` absence in tests
   (`TestPrefetch` dir override), arithmetic slips in expectations.

Backend changes: none (none justified without a live backend; §11).

## 9. Unfixed defects / known limitations (severity order)

1. High — No change feed/tombstones → updates/deletes/shifted rows missed
   (B1/B2/C1 demonstrated). Client is honest (`best_effort` + checkpoints);
   needs backend B1/B2 or an explicit ship-best-effort decision.
2. High — `catalogProductCountLocal()==0` conflates disabled/error/empty/
   unsynced; UI `not_synced_yet` can mislabel empty/error catalogs
   (`lib/core/app_controller.dart:1408`, `products_screens.dart:548`).
3. Medium — Local filter/sort-then-paginate windows (`limit+offset` fetched by
   serverId/rank, then filtered/sorted) can miss global matches.
4. Medium — Sellers/categories GETs served from short-TTL memory cache
   (2/10 min) with stale-while-revalidate: rapid server edits can lag one
   cycle; harness had to use fresh instances to observe edits.
5. Medium — Image manifest tracks DB bytes, not disk reality; full-manifest
   loads for reconcile; opt-in toggle can run 100 downloads on the tap path;
   `cancel()` can't abort an active stream (mitigated by stall timeout).
6. Low — Global `shop_cache`/`cats_cache` one-round-trip city lag; checkout
   draft 800ms debounce scope race; `buildIdempotencyKey()` legacy minter must
   stay unused; notification allowlist reaches privileged prefixes (per-screen
   auth still applies); bootstrap error echoes backend text.

## 10. Commands executed (exact, exit codes)

- `flutter test test/offline_e2e_harness_test.dart` → exit 0, **28/28 pass**.
- `flutter test` (full) → exit 0, **167/167 pass**
  (139 pre-existing + verification + 28 harness).
- `flutter analyze` → exit 0, **0 errors, 0 warnings, 174 infos**
  (all pre-existing style/deprecation notes).
- `flutter build apk --debug` → exit 0,
  `√ Built build\app\outputs\flutter-apk\app-debug.apk` (only Firebase KGP note).
- `flutter devices` / `flutter emulators` → exit 0; no Android targets.
- Backend: no `php`/`artisan`/migration/test command was runnable
  (no PHP runtime; Docker daemon down). No database command executed.

## 11. Live-device / live-backend coverage (explicit)

- Live Laravel/MySQL: NOT executed (environment lacks PHP runtime and Docker
  daemon; `.env` targets an unreachable Docker MySQL service; no listener on
  127.0.0.1:8000). Backend claims in this report are static-source findings
  (§3) plus a contract-faithful double (§4) — every affected test is tagged
  [harness]. Not claimed as live-backend proof.
- Physical device/emulator: NOT executed (no AVD images, no devices).
  Device-only remainder: airplane/force-stop/city-switch/reconnect on hardware,
  `/seller/orders` deep-link reorder at runtime, Keystore behavior, battery/
  polling, image cache on slow storage, staging duplicate-key proof against the
  real `checkout` endpoint.
- What DID run on real stacks: real Dio HTTP over loopback (timeouts, refused
  connections, 500s, socket closes, malformed bodies), real Drift (memory +
  temp files, real corruption quarantine), real SharedPreferences-backed
  stores, real sync/queue/draft/image classes.

## 12. Remaining backend contracts

1. **Change feed + tombstones: MISSING** (verified absent by source grep; no
   `/sync|since` API). Impact: §5 B/C misses. Client fallback (current):
   offset resume + full stores/categories re-walk + honest `best_effort`.
   Proposal only: composite keyset (`after_created_at`,`after_id`) + deleted-
   row feed; do not mark sync `verified` until then (typed gate already
   refuses it).
2. **Checkout idempotency: PRESENT in source, unexecuted live.**
   `OrderApiController.php:634-643,662` accepts body `idempotency_key`;
   `CheckoutService.php:60-69` returns the completed group on key match;
   `CheckoutSessionService.php:10-36` lookup; migration
   `2026_08_24_000001:...:50,98` enforces `unique(user_id,idempotency_key)`
   and `unique(checkout_payments.idempotency_key)`; backend tests
   (`CheckoutMultiSellerTest.php:192,294-320`, `e2e_03.php:172-181`) assert
   same-group redelivery. Client sends the key and reconciles instead of
   blind-resending. Remaining: one staging duplicate-key run against the real
   endpoint before production claims.

## 13. Git preservation

Customer app branch `prod/offline-reliability` throughout. Final
`git status --porcelain=v1` shows only: pre-existing staged/unstaged work
intact (reports, i18n, `app.dart`, api, controllers, features, tests) plus
in-scope modifications (`lib/core/app_controller.dart` categories-total fix)
and two untracked test files (`test/offline_e2e_harness_test.dart`,
`test/offline_verification_fixes_test.dart`). Backend tree untouched
(in-progress `M`/`??` entries preserved). No destructive command used.

## 14. Release recommendation

Safe for **controlled internal testing** (QA lab + dogfood) including the §5
journeys. Before production: (a) staging proof of duplicate-key checkout
against real Laravel; (b) device-backed airplane/kill/switch suite (§11
checklist); (c) product decision on best-effort catalog vs backend B1/B2;
(d) fix or explicitly accept §9 items 2–4. Do not represent offset sync as
complete.
