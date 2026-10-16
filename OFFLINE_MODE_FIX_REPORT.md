# Offline-First Architecture Report — SareeMart Customer App

## A. Executive Summary

**What was implemented (two work passes on branch `prod/offline-reliability`):**

1. *Prior pass* (verified present in the working tree): SharedPreferences/JSON
   offline layer (`LocalStore`, `OfflineCache`, `CachePolicy`, `PendingOutbox`,
   `CheckoutSession`, `SyncEngine`, `TokenVault`, `OfflineBanner`), cache-first
   screens with stale badges, account-scoped persistence, favorites restoration
   wiring, view-separated product cache keys, and `test/offline_repair_test.dart`
   (22 tests).
2. *This mission pass*: central operation policy (`OperationPolicy`) with
   online-only classification; API-result-based reachability tracking
   (`CustomerApi.likelyOffline`) with offline checkout dialogs (en/ar localized)
   plus service-layer guards; cart estimate labeling (`StalePriceNote` on stale
   totals); bounded LRU eviction for catalog pages (60) and details (100);
   favorite-removal convergence via guarded replay (+ pending-remove filtering);
   cross-account outbox execution guard; pagination dedupe (`J.appendUnique`);
   race/account-switch guards (`_seq` + captured scope) on orders, wishlist,
   notifications; sellers-screen failure preservation; `test/offline_mission_test.dart`
   (15 tests) and strengthened `test/app_controller_test.dart`.

**Database decision: no local database adopted.** The existing
SharedPreferences/JSON document store is retained (evidence in §C). The gaps
found were rendering-path, policy, bounding, and concurrency bugs — not
storage-engine limits — and all were fixed within the current architecture.
No Drift/SQLite dependency was added.

**Offline-readiness: `READY FOR CONTROLLED OFFLINE TESTING`.**
80/80 automated tests pass, `flutter analyze` is clean (0 errors, 0 warnings),
release APK builds (63.0 MB). No physical-device verification was performed;
the manual checklist from the previous report still applies (re-stated in §J).

## B. Initial State

- Project: `D:\myproject\review\saree_customer`, branch `prod/offline-reliability`,
  Flutter 3.47.1 stable / Dart 3.13.1 / Windows x64.
- Working tree at mission start: prior offline layer staged (`A`), prior
  screen/i18n/test fixes unstaged (`M`/`MM`), `OFFLINE_MODE_FIX_REPORT.md` and
  `test/offline_repair_test.dart` untracked. All preserved; final diff touches
  only the files listed in §D plus the two test files. No destructive Git
  command was run; nothing was committed, pushed, or deployed.
- Existing offline components and actual behavior (all verified by reading
  source, not assumed): `LocalStore` (per-key quarantine, 400 KB guard),
  `OfflineCache` (envelopes, legacy bare-doc support), `CachePolicy`
  (TTL = refresh trigger), `PendingOutbox` (200 ops / 8 attempts / backoff /
  coalescing), `SyncEngine` (single-flight), `CheckoutSession` (stable key,
  fingerprint rotation, history reconcile), `TokenVault` (no plaintext
  fallback), `ApiCache` (in-memory stale-while-revalidate, public catalog
  only), `OfflineBanner`/`SavedStatusChip`/`StalePriceNote`.
- **New defects confirmed this mission** (evidence: code + backend inspection):
  - B1. `runPendingOp` never replayed favorite removals, so an offline removal
    reappeared after the next settings refresh (server snapshot overwrote local
    intent). The old comment blaming a backend "deletes ALL" bug was
    re-verified against `BasicApiController::removeFromFavorite` (lines
    337–358): with a valid `product_id` exactly one row is deleted; mass-delete
    happens only when `product_id` is absent — a path the app never sends, but
    which a blind replay must still guard against.
  - B2. Queued ops carried no account identity: account A's favorite op could
    replay under account B's credentials after a switch-then-reconnect.
  - B3. Product pages/details grew without bound (no eviction; only per-document
    size guards).
  - B4. Offset-page appends (`products`, home catalog, notifications, sellers)
    could duplicate rows when backend insertions shift pages (backend uses
    offset/limit over live data; `updated_at`/`deleted_at` are hidden from
    product responses, so no client change detection is possible).
  - B5. Orders/wishlist/notifications had no stale-response or
    account-switch guards (late response could paint account A's data into B's
    session or overwrite newer state).
  - B6. Checkout had no offline-specific UX: timeouts produced a generic
    snackbar; cart totals after failed refresh were not labeled estimates.

## C. Architecture

**Final storage architecture (unchanged engine, hardened policy):**
SharedPreferences-backed JSON documents via `LocalStore` + typed
`OfflineCache` envelopes. Evaluation against the requirements:

| Requirement | Evidence / handling |
|---|---|
| Document sizes & growth | First pages only (12 items/page); per-doc guards (shop 400 KB, cats/cities 200 KB, envelope 400 KB); **new** LRU bounds: 60 product pages, 100 product details; estimated steady-state catalog cache ≈ 1–4 MB (estimate: 12-item pages ≈ 15–60 KB JSON), theoretical worst case 60 × 400 KB ≈ 24 MB (labeled estimate, not measured) |
| Record counts/types | ~10 key families (§D); no relational queries needed anywhere |
| Local filter/sort/search/pagination | Done in memory over cached pages; offline search honestly covers only downloaded pages |
| Relational queries/joins | None required; identity by stable server ids (`J.rowKey`) |
| Whole-document write perf/consistency | Docs are small; writes are single-slot `setString` (atomic at the plugin level); no multi-key transactions needed |
| Atomicity | Single-document writes; outbox save is one slot; no cross-document invariants |
| Corruption recovery | Per-key quarantine (tested); legacy bare docs displayable-as-stale; index corruption degrades to recency-loss only |
| Account scoping | `scope` in every envelope + read-time `scope == accountScope` checks + logout wipe + new replay-time scope guard |
| Incremental sync & bounded storage | Backend offers **no** sync primitive (see §E) → per-query first-page refresh + LRU bound; sufficient and minimal |
| Migrations | No schema change: all keys backward compatible; new `view` key segment causes one self-healing cache miss per view |

Drift/SQLite was evaluated and **rejected**: it would add native migration risk,
codegen, and APK weight with no query benefit (no joins, no FTS, no relations,
no cursors to store). Revisit only if full-catalog offline search or
relational order modeling is ever required.

**Source of truth:** backend-authoritative — availability, prices, store
status, delivery fees, stock, discounts, checkout validation, order/payment
status, refunds, permissions. Local data classes: (1) reconstructible catalog
display copies (evictable, badged stale); (2) local user intent (cart edits,
favorite toggles — optimistic, queued, server-reconciled); (3) server-confirmed
state (order success, wallet/payment outcomes — never fabricated offline).

**Cache keys:** `shop_cache`, `cats_cache`, `cities_cache` (global);
`oc:products::<hash(view, city, category, search, filters, sort, limit)>`;
`oc:pdetail::<server id>`; per-scope `oc:favs/wishlist/notifs/addrs/orders`,
`oc:odetail::<scope>::<id>`, `oc:pending::<scope>`,
`checkout_session::<scope>`; LRU indexes `oc:index:products/pdetails`.

**Sync flow:** paint persisted → badge stale → refresh (seq-guarded,
scope-captured) → validate (`result.ok` + non-empty where required) → bounded
persist → repaint; failures preserve prior data. Outbox: favorites only,
coalesced, backoff, blocked-vs-due, scope-stamped. Reachability from API
results (`likelyOffline`: last terminal result is network-class and < 2 min
old, no success since); no interface-flag reliance, no polling (60–120 s
notification poll only, lifecycle-aware).

**Storage/eviction:** §D item 4; images via `cached_network_image` disk cache
(80 MB RAM cap set in `main.dart`); pending ops, sessions, guest cart, account
docs are never evicted.

**Migration strategy:** none required (no schema version change). Guarantees:
existing keys untouched, old product-page keys absorbed as eviction-first
candidates, corrupt index rebuilds safely. Covered by preservation tests.

**Outbox/operation-safety rules:** `OperationPolicy` (8 online-only ops incl.
checkout, order create, payment init/verify, cancel/modify, refunds, wallet
transfers); checkout/payment/order-creation never queued; bulk cart merge never
auto-replayed; removals replay only with valid id; poison ops dropped, never
executed.

## D. Implementation Details

1. **Favorite-removal convergence** — `lib/core/app_controller.dart`
   (`runPendingOp`, `toggleFavorite`, `reloadSettings`).
   Before: removals queued but never replayed → offline removals reappeared.
   Root cause: over-cautious never-retry rule based on a stale backend reading.
   Change: replay removal when `product_id` valid (repeat `no_product_found`
   = converged = done); drop when empty/`null` (mass-delete guard);
   `reloadSettings` filters pending removes from the server snapshot; ops
   stamped with `account_scope` and dropped on mismatch. Safe: each backend
   behavior verified in source; poison path can never execute. Tests: 5 in
   `app_controller_test.dart` + 2 in mission suite.
2. **Bounded catalog storage** — `lib/core/offline/offline_cache.dart`
   (`writeProductPage/writeProductDetails/_trackBounded`), `LocalStore.keysWithPrefix`,
   controller writers rerouted. Before: unbounded page/detail accumulation.
   Safe: eviction limited to reconstructible prefixes; everything else exempt
   by construction. Tests: 60/100 caps, newest-survive, exemption test.
3. **Pagination dedupe** — `lib/core/json_util.dart` (`J.rowKey/appendUnique`),
   applied in `products_screens.dart`, `home_screen.dart` (both views),
   `notifications_screen.dart`, `more_screens.dart` (sellers).
   Before: shifted offset pages duplicated rows. Safe: first-seen row wins,
   stable display. Tests: id/slug/no-id cases.
4. **Race + account-switch guards** — orders (`_seq`, captured scope, drop +
   no-persist on mismatch, deduped appends), wishlist/notifications (scope
   capture, drop late responses). Before: B5. Safe: strictly drops stale
   cross-scope paints. Tests: isolation tests (logout-offline, guest-vs-user).
5. **Offline checkout UX + cart estimates** — `lib/features/cart/cart_screens.dart`:
   `likelyOffline` pre-check dialog (cart kept), network-failure dialog
   replacing the generic snackbar on the failure path, `_staleTotals` →
   `OfflineBanner` + estimate semantics in cart; new i18n keys
   `checkout_needs_internet(_title)` (en/ar). Service layer unchanged as the
   real guard (API result). Safe: UX-only fast path; cannot allow success.
6. **Reachability evidence** — `lib/core/api/customer_api.dart`
   (`lastSuccessAt/lastFailureAt/lastFailure/recordSuccess/recordFailure/likelyOffline`,
   hooked into `_guard`). Server/auth failures never count as offline; hint
   expires after 2 min. Tests: fresh/false, failure/true, success/clears.
7. **Sellers failure preservation** — `lib/features/more/more_screens.dart`:
   failed refresh keeps rows (was cleared). Safe, display-only.
8. **Prior-pass fixes retained and re-verified**: stale-while-revalidate
   shop/cats/cities, bootstrap pre-paint, favorites restore + pending-add
   merge, orders/wishlist/categories/notifications cache-first, view-separated
   keys, legacy-doc support, cities persistence, empty-snapshot refusal.

## E. Backend Compatibility (read-only inspection of `D:\myproject\review\saree_back`)

- Endpoints inspected: `routes/customer.php` (categories, shop, products
  POST + filter/search/similar, favorites add/remove/get, cart + guest_cart,
  orders, `checkout`, checkout-groups, refunds, manual-payments);
  `OrderApiController::checkout` (validates `idempotency_key`, nullable ≤ 64 —
  our keys ≈ 47 chars, tested ≤ 64); `CheckoutService` (dedupes via
  `findCompletedByIdempotency` — our stable-key strategy is genuinely
  supported); `ProductApiController::getProducts` (offset/limit over live
  query, soft-delete filter, `updated_at`/`deleted_at` hidden, `total`
  returned); `BasicApiController` favorites (add idempotent-error on
  duplicates; remove single-row iff `product_id` present, else mass-delete).
- Pagination: offset/limit, no cursors/totals-guarantee → client dedupes, never
  deletes on absence. Deletions: no tombstones/feeds → removed products stop
  appearing only via validated full first-page refresh; no local purge on
  partial data.
- Missing guarantees (no backend change made): no incremental sync
  endpoint/cursor/version feed; no deletion signaling; in-flight duplicate
  checkout dedupe unverified (covered client-side by reconcile-before-retry).
- Recommended backend changes (approval required, NOT implemented): (1)
  `GET customer/sync?since=<ts>&limit=` returning changed/deleted
  product ids with tombstones; (2) unique constraint + in-flight dedupe on
  (`user_id`, `idempotency_key`); (3) require `product_id` on
  `favorites/remove` (refuse empty instead of mass-delete). Smallest safe
  frontend behavior without them is implemented and documented above.

## F. Security and Transaction Safety

- Account isolation: envelope `scope` + read-time checks + logout/switch wipe
  (`clearAccountDocs` incl. new wishlist/notifications keys) + replay-time
  scope stamp/drop + in-flight scope capture/drop. Public catalog survives
  logout; guest vs authenticated scopes never share private docs (all tested).
- Logout offline: safe — local wipe needs no network; logout API failure does
  not block session clearing (tested).
- Tokens: `TokenVault` only (secure storage, throws instead of plaintext
  fallback, legacy slot migrated/deleted); never in catalog DB/logs/report.
- Checkout/payment: online-only (policy + UI dialog + API-result guard);
  stable idempotency key ≤ 64 chars; fingerprint rotation; uncertain outcomes
  keep the session and reconcile via order history before resubmission;
  `unresolvedCheckout` blocks new attempts; offline can never report success
  (tested); cart preserved on every failure path; no sensitive op queued.

## G. Migration and Recovery

- Schema versions: no database exists; SharedPreferences key schema unchanged
  (v1 envelopes). No migration to run.
- Legacy data: pre-envelope bare docs display as stale (tested); old
  view-less product keys gracefully miss once then repopulate; corrupt index
  rebuilds; corrupt docs quarantined per key.
- Failure recovery: failed/interrupted writes keep prior values (size-guard
  refusal, write-then-index ordering); refresh failures never erase;
  outbox survives restart with backoff caps and blocked surfacing.
- Preservation guarantees: account wipe is scope-limited; eviction is
  catalog-only; pending ops/sessions/guest cart exempt from all cleanup.
- Tested paths: quarantine, oversized refusal, legacy display, LRU caps +
  exemptions, logout-offline, scope isolation. Limitation: no on-device
  kill-during-write test (manual checklist).

## H. Testing Evidence

| Command | Exit / result |
|---|---|
| `flutter pub get` | success (deps resolved) |
| `flutter test test/offline_mission_test.dart` | **15/15 pass** (new: policy, reachability, key length, LRU caps + exemptions, dedupe, fav convergence + scope, guest cart, logout-offline, isolation) |
| `flutter test test/offline_repair_test.dart` | **22/22 pass** (prior pass, unchanged behavior) |
| `flutter test` (full) | **80/80 pass**, exit 0 — 39 pre-existing + 41 offline-related (22 repair + 15 mission + 4 strengthened fav-remove in `app_controller_test.dart`) |
| `flutter analyze` | **0 errors, 0 warnings** (147 pre-existing infos: deprecation/style lints, untouched) |
| `flutter build apk --release` | **success** — `build\app\outputs\flutter-apk\app-release.apk` (63.0 MB); only pre-existing firebase KGP informational notice |

No test was weakened: the one updated test (`favoriteRemove is never retried`)
was replaced by five tests asserting the new verified contract (replay,
already-removed convergence, transient retry, empty-id drop, cross-scope
drop). No real API calls in tests (scripted fakes). No device verification
performed — stated explicitly, not claimed.

## I. Storage and Performance

- Measured: release APK 63.0 MB; test/code additions are negligible at runtime.
- Catalog cache (estimates, labeled): 12-item pages ≈ 15–60 KB JSON each;
  steady state ≈ 1–4 MB for 60 pages + 100 details + shop/cats/cities;
  hard worst case 60 × 400 KB ≈ 24 MB (per-doc guard enforced before indexing).
- Limits: pages 60, details 100 (LRU); shop 400 KB, cats/cities 200 KB,
  envelope 400 KB; outbox 200 ops / 8 attempts; `ApiCache` 80 entries;
  image RAM 80 MB + `cached_network_image` disk cache (no offline-completeness
  claim for images).
- Performance: whole-document reads/writes of small docs; no joins/polling;
  seq/scoped guards prevent duplicate network work; backoff caps sync traffic.

## J. Remaining Risks

1. No physical-device verification (radio-off, process death, upgrade from
   store build) — manual checklist: install online → visit products/stores/
   categories/details → force-stop → airplane mode → relaunch (saved content +
   badges) → browse + edit cart (estimate note) → checkout blocked, cart kept
   → reconnect (refresh, op replay, badges clear) → account switch/logout
   isolation → failed-refresh preservation → storage sanity.
2. Partial offline catalog only (visited first pages); unvisited/search/images
   beyond disk cache unavailable — UI does not claim completeness.
3. Backend gaps (§E): no incremental sync/tombstones; in-flight checkout
   dedupe unverified; `favorites/remove` mass-delete branch still exists
   server-side (client never sends empty id; server-side require recommended).
4. Notifications cache = last confirmed first page; auth cart not durable
   across restart (server truth by design); sliders/flash/haraj in-memory only.
5. Stale badges are honest but require user refresh discipline before acting
   on prices/status.

## K. Final Assessment

**`READY FOR CONTROLLED OFFLINE TESTING`**

Justification: the complete data flow was inspected including the backend
(read-only); all confirmed defects were fixed with regression tests (80/80
green); storage is explicitly bounded; account isolation, checkout safety, and
migration/recovery are tested; static analysis is clean and the release APK
builds. Production readiness is NOT claimed: on-device radio testing (§J) must
pass first, and backend hardening (§E) needs approval. No commits, pushes,
deploys, backend edits, or production-data changes were made.
