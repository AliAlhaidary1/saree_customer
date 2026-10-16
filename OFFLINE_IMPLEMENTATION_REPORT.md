# SareeMart Customer — Offline-First Implementation Report

Branch: `prod/offline-reliability` · Date: 2026-10-14 · Scope: customer Flutter app only.
No commit/push/deploy was performed. No backend file was changed.

## Verdict: PARTIALLY COMPLETE (customer-feasible scope implemented; see §12)

Every customer-facing route has a deliberate offline behavior. Server-authoritative
actions stay online-only. What is NOT done: verified-completeness sync (needs
backend B1/B2 change feed + tombstones), client-side image downscaling, live
device (airplane-mode) testing — all recorded below with reasons.

## What was implemented

### Foundation (reused, repaired)
- `LocalStore.writeJson` enforces UTF-8 byte size (was `String.length`, ~2x
  under-count for Arabic). New `LocalStore.documentBytes`.
- `PendingOutbox.enqueue` returns bool, refuses >32KB payloads.
- `OfflineCache`: form-draft helpers (`draftKey/writeDraft/readDraft/removeDraft`,
  scope-guarded), generic snapshots (`snapshotKey`), `clearAccountDocs` now also
  wipes drafts + account-scoped snapshots (`oc:snap::<name>::<scope>`), keeps
  global snapshots.
- `AppController`: variant labels capped at 500; guest-cart persists through a
  byte-guarded helper; logout also clears per-account notification-read flags;
  `validateSession()` (extracted, tested): auth failures clear the session,
  offline/transient failures keep token + restore last user snapshot — airplane
  restarts no longer log the user out.

### Catalog (new: `lib/core/catalog_store.dart`, DAO lookups, flag ON)
- `CatalogDbConfig.catalogDbEnabled = true` (rollback: set `false`, restart).
  All reads null-fallback to JSON/network when the DB is unavailable.
- `CatalogSyncService`: best-effort offset paging (`sort=old`, products 50 /
  stores 48 per backend caps, categories 100), one transaction per batch,
  checkpoint-after-commit, resume from last committed offset, idempotent
  replays, bounded per-page retries, cancel/pause-safe, progress notifier,
  coverage ALWAYS `best_effort` (offset paging cannot prove completeness).
- Local reads: scoped list/search (FTS incl. Arabic)/filters/sort/pagination,
  product + store lookup by id/slug (covers never-opened rows), categories,
  stores; filters never hide rows missing a field; `nearest` falls back to
  rating like the screens.
- Screens wired: products list (+offline pagination + `not_synced_yet` empty
  state + sync progress/retry strip), product details (never-opened lookup),
  home catalog (products + stores), search (FTS first + recent searches, max 10),
  sellers list, store header, categories, offers snapshots, home hero snapshot.
- Auto-sync triggers: bootstrap + city switch + pull-to-refresh (debounced 5 min).

### Snapshots for non-catalog domains (stale-badged, scope-checked)
Sellers, store header, offers/campaigns, search, home hero, categories,
CMS pages, FAQ, haraj feed/details, akhdimni home/orders/details,
checkout-groups list/details, wallet/transactions (spend-disabled),
user snapshot, notification list (existing), orders/details/wishlist/addresses
(existing, kept).

### Drafts (local-only, never auto-sent, cleared on success)
Checkout form (method/wallet/slot/note/address, setState + controller
autosave), address dialog, profile text, complaint form, haraj create/edit
(incl. surviving image paths), akhdimni request. Each shows `draft_saved`.
Queued writes: favorites only (existing outbox, preserved + tested). No new
queued operation types — drafts preferred without server idempotency contracts.

### Cart/checkout safety (kept + extended)
Guest cart persists; logged-in cart restores last confirmed snapshot as stale;
`cart_load_failed` instead of misleading empty cart; checkout drafts persist;
place-order/payment/wallet-spend stay online-only; idempotency key +
fingerprint + reconcile unchanged.

### Images (new: `lib/core/image_prefetch.dart`, opt-in toggle in Account)
Default OFF, Wi-Fi recommended in copy. Bounded (100 files/run, 2MB/file,
150MB manifest budget), oldest-first eviction, temp→rename→manifest ordering,
bidirectional orphan reconcile, failures skipped. No downscaling (no codec dep).

### Misc
- `/seller/orders` + `/seller/settlement` moved before `/seller/:id` (shadowing).
- Auth submit explains when offline (credentials never queued).
- Assistant keeps last thread (text-only, account-scoped), honest offline notice,
  never auto-sends. Role routes untouched (uncached, online-only).
- 10 new AR/EN strings (`not_synced_yet`, `draft_saved`, …), validated present.

## Verification (executed)
- `flutter test`: **130/130 pass** (incl. new `test/offline_catalog_test.dart`,
  23 tests: byte guards, drafts/isolation, session keep/clear/restore, caps,
  sync happy/resume/failure/malformed/cancel, mapping/filtering, end-to-end
  sync→browse→search→scope-isolation, manifest hygiene, cart restore).
- `flutter analyze`: 0 errors, 0 warnings (174 infos, pre-existing style).
- `flutter build apk --debug`: success (full compile incl. all screens).
- i18n JSON validated (EN 1258 / AR 1207 entries, new keys present in both).

## Limitations / not implemented (with reasons)
1. No `verified` sync — needs backend B1 (composite keyset) + B2 (change feed +
   tombstones); client stays honest `best_effort` (proposed contracts only).
2. No client downscale — needs image codec dep; bounded originals instead.
3. No live-device airplane testing in this pass (emulator/device testing is the
   recommended next step; unit + build + analyze evidence recorded instead).
4. Haraj comment/report, wallet transfers, photo uploads, role actions:
   online-only by policy (no safe contract).
5. `/seller/orders` runtime route-match not executed (reorder is defensive;
   needs one device deep-link check).

## Rollback
- Catalog reads: `CatalogDbConfig.catalogDbEnabled = false` + restart (JSON paths
  untouched and tested beside the DB).
- Image prefetch: Account toggle OFF (default).
- Drafts/snapshots: additive; logout wipe covers account data.

## Files
New: `lib/core/catalog_store.dart`, `lib/core/image_prefetch.dart`,
`test/offline_catalog_test.dart`, this report.
Edited: `lib/app.dart`, `lib/core/app_controller.dart`,
`lib/core/offline/{local_store,offline_cache,pending_ops}.dart`,
`lib/core/catalog_db/{catalog_config,catalog_database}.dart`,
`lib/features/{home,products,cart,account,more,haraj,akhdimni,assistant,auth,checkout_groups,complaints}/*`,
`assets/i18n/{en,ar}.json`, `test/catalog_db_test.dart` (rollback-test wording).
Unrelated pre-existing staged/untracked work preserved untouched (verified via
`git diff HEAD` + file-backed `git status`).
