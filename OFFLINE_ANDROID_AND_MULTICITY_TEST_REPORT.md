# Offline Android + Multi-City Test Report

Date (UTC+3, Asia/Aden): 2026-10-15, approx 06:00–09:00. Continues
`OFFLINE_FINAL_GAP_CLOSURE_REPORT.md` (which left device testing BLOCKED on
production-API risk and shared-DB mutation risk). This report records the
first real physical-device campaign against the local development backend,
plus the defects it uncovered. No commit, push, deploy, production change,
`git reset/clean/restore`, stash operation, `migrate:fresh`, or `db:wipe`
occurred in either repository.

## 0. Preflight verification (all checks passed before any mutation)

Initial Git status recorded in both repos and compared byte-identical at the
end (see §9): Flutter branch `prod/offline-reliability` HEAD `e1b0e44`,
backend branch `main` HEAD `d1d26b2`. All staged/unstaged/untracked entries
preserved; one pre-existing backend stash entry untouched.

- Docker Compose (`saree_back/docker-compose.yml`): `app` serves port 8000
  with `DB_HOST=mysql`, `DB_DATABASE=sql_laravel_marabmall_cloud`;
  `mysql` is `mysql:8.0` with `MYSQL_ALLOW_EMPTY_PASSWORD=yes` and a Docker
  volume (`mysql_data`), port-mapped `3307:3306`. Host listeners confirmed:
  `0.0.0.0:8000` and `0.0.0.0:3307` owned by the Docker backend proxy.
- Laravel `.env` (keys only, no values printed): `APP_ENV=local`,
  `APP_DEBUG=true`, `APP_URL=http://127.0.0.1:8000`, `DB_CONNECTION=mysql`,
  `DB_HOST=mysql`, `DB_PORT=3306`, `DB_DATABASE=sql_laravel_marabmall_cloud`,
  `DB_USERNAME=root`, `QUEUE_CONNECTION=sync`, `SESSION_DRIVER=file`,
  `DEMO_MODE=0`, `DEV_MODE=0`, `WHATSAPP_OTP_ENABLED=true`.
- Actual database identity (queried over `127.0.0.1:3307`): server
  `@@hostname=39658ae75a9b` (a Docker container id, not a cloud host),
  port 3306-in-container, `MySQL 8.0.46`, database
  `sql_laravel_marabmall_cloud`, 149 tables. Verdict: genuinely local
  development infrastructure — `APP_ENV=local` was NOT the sole evidence.
- External side effects: Stripe secret/public keys are empty and
  `stripe_payment_method=0` (only `cod_payment_method=1`); PayPal/Razorpay/
  Paystack/Midtrans/PhonePe/Cashfree/Paytm methods are all `0`. The Flutter
  app uses the modern `POST customer/checkout` (`customer_api.dart:826-846`,
  called from `cart_screens.dart:1464`), whose controller path dispatches
  only an in-app panel notification (`notifyNewCheckout`, `OrderApiController
  .php:676-682`) — no SMS, no email, no courier auto-dispatch
  (assignments require admin/courier claim via `DispatchService`). Twilio
  and WhatsApp/Evolution sends are configuration-gated and were never
  invoked (no `send_sms`/OTP call was made during this campaign). COD is
  courier-collected cash, so test checkouts cannot trigger real charges.
- Shared dev data present and preserved: 80 users, 292 products, 27 sellers,
  11 checkout groups, 1 city (Marib, id 1), 0 favorites at start. All test
  records created are additive and identifiable (`ANDROIDEV42*`, users
  id 81/82, address id 27, checkout groups 29/30, favorites for user 81).
  Nothing pre-existing was modified or deleted.

## 1. Device connectivity and APK configuration

- Device: Samsung SM-G950U (dreamqltesq), Android 9 (API 28), build
  `PPR1.180610.011.G950USQU8DZE4`, ADB id `988964374b36334b46`, device IP
  `172.17.4.247/16`. Host LAN IP `172.17.3.192/16` (same subnet).
  Device→host ping: 0% loss (~10–16 ms).
- Backend target for the phone: `http://172.17.3.192:8000` (never
  `127.0.0.1`; the app itself flags loopback as device-unreachable,
  `config.dart:23-28`). No firewall/proxy change was needed (Docker already
  publishes 8000 on `0.0.0.0`); nothing was exposed to the public internet.
- Build: `flutter build apk --debug
  --dart-define=API_URL=http://172.17.3.192:8000` → exit 0,
  `build/app/outputs/flutter-apk/app-debug.apk` (199,573,396 bytes).
  Binary verification: the dev URL string is present in
  `assets/flutter_assets/kernel_blob.bin` (count 1); the production default
  (`https://admin.marabmall.cloud`) remains only as the dead
  `defaultValue` literal. Runtime proof: the installed app's More →
  server-address row displays `http://172.17.3.192:8000`, and the home feed
  renders dev-only rows (e.g. the `E2EOFFLINE` category).
  `adb install -r …app-debug.apk` → `Success`.
- Connectivity control note: `adb shell settings put global
  airplane_mode_on 1` plus the `AIRPLANE_MODE` broadcast was denied
  (`SecurityException`, uid 2000), so radios were cut/restored with
  `svc wifi disable|enable` + `svc data disable|enable`. Every offline/online
  transition used here was verified by device-side ping (`Network is
  unreachable` vs 0% loss), which is the same network condition the app
  observes. One stale-setting incident (setting value 1 lingering, Wi‑Fi
  re-asserted later) is documented in the timeline but did not contaminate
  any verdict — each phase was ping-gated.

## 2. Physical-device test results

Test accounts: two additive email-type users created by direct SQL (no OTP
path touched): id 81 `ANDROIDEV42 A` (mobile `780000001`) and id 82
`ANDROIDEV42 B` (mobile `780000002`), status active. Passwords are
test-only and are not recorded in this report.

| # | Step | Verdict | Evidence |
|---|------|---------|----------|
| 1 | Online initial catalog sync; record counts | PASS | Device Drift DB pulled via `run-as`: products **279**, categories **11**, stores **25**, variants **337**, FTS rows **279**; `sync_states=(scope city:1, phase full_complete, coverage best_effort, last_offset 279, stored_count 279)`. Server API counts: products total 279, categories 11, brands 16, sellers 25, cities 1, offers 18. Sliders endpoint returns status 0 (empty in dev). |
| 2 | Airplane/offline browse, search, detail, stale indicators | PASS WITH LIMITATION | Offline home renders fully from cache (categories incl. `E2EOFFLINE`, product cards with closed badges + hearts) with amber stale banners; offline product detail renders full content (title, seller, price 6591.80, stock 179, variants, reviews, add-to-cart) with stale banner. Search: offline FTS index verified present on device (279 rows) but Arabic query typing over ADB was not feasible, so interactive search was not executed — limitation, not a failure. |
| 3 | Offline checkout/address/other drafts | PARTIAL | Checkout submit while offline is refused by design with an explicit dialog (“requires internet… cart is saved — reconnect and retry”); verified no group was created (group count unchanged, §4 evidence). In-app new-address creation was not completed on device (see defect D2); haraj drafts not attempted. |
| 4 | Force-stop, restart offline, draft persistence + scoping | PASS | After `am force-stop` + relaunch with no network: catalog repainted from cache, offline favorite heart persisted RED, scope keys intact (`oc:favs::u:81=[37]`, `oc:pending::u:81` with the queued op, guest keys untouched). No cross-scope data. |
| 5 | Reconnect, catalog re-sync | PASS | Post-reconnect device DB: same counts, `sync_states.updated_at` advanced (03:15:15Z → 05:34:00Z), UI shows refreshed prices/stock (6444.60, stock 33), outbox retry attempted (attempts 1→2). |
| 6 | Logout → second account, no leakage | PARTIAL | Logout on device wiped account scope keys (`oc:addrs::u:1`, `oc:favs::u:1` removed; 20→18 prefs keys) while guest keys were retained — PASS for the logout wipe. Login **as the second account on device** is BLOCKED by defect D1 (login screen never completes). Server-side isolation verified: user 82 has 0 favorites, 0 addresses, 0 checkout groups. |
| 7 | City switch | BLOCKED | Only one city exists (Marib, id 1). Adding a second city would mutate shared single-city behavior for all consumers — not attempted (see §5). |
| 8 | COD checkout with interrupted connectivity; exactly one group + payment/order records | PASS | (a) Offline submit refused, zero groups created. (b) Device online submit → “order sent successfully”, exactly one new group (id 30, COD 6444.60, seller order 30, cart cleared, user 81 groups = {29,30}). (c) API double-submit with idempotency key `ANDROIDEV42-K1` → same group id 29 twice; DB: 1 group, 1 seller order (524.40 pending), 1 completed idempotency session → group 29, zero wallet/financial movements. No courier auto-dispatch (assignment requires claim). |
| 9 | Offline favorite toggle → reconnect → exactly one server row | PASS (with defect D3 noted) | Offline toggle queued `favoriteAdd(37)` scoped `u:81` (attempts/backoff tracked); add/remove coalescing observed live (add+remove collapsed to a single remove op); toggle-ON synced exactly one server row `(43,81,37)`. API add/remove/add sequence → exactly 1 row; duplicate add rejected; user 82 has 0 rows. The stale-op replay issue found during this step is defect D3. |

## 3. Checkout idempotency + favorite-sync evidence (API/DB)

- Idempotency: `POST customer/checkout` (address 27, COD, key
  `ANDROIDEV42-K1`) twice → both responses `checkout_group_id=29`
  (`public_id CG-UERKV1OC-81`). DB: `checkout_groups` row 29 (COD,
  `payment_status pending`, `final_total 524.40`, `cod_amount_due 524.40`,
  `paid_online_total 0`, `wallet_applied 0`, key stored, session 21);
  exactly one `seller_orders` row (seller 1, 524.40 pending); session
  `ANDROIDEV42-K1` completed → group 29; `transactions`/`wallet_transactions`
  for user 81 empty. Device order created group 30 (`CG-YMF478SO-81`, COD
  6444.60, seller 4, session 22, device key `checkout-u:81-…`).
- Favorites: user 81 `favorites` = exactly `(42,81,1)` after add/remove/add
  + duplicate rejection; device toggle-ON of product 37 produced exactly
  `(43,81,37)`; user 82 = 0 rows throughout.

## 4. Multi-city testing: BLOCKED (not forced)

`GET customer/cities` → total 1 (Marib). The app supports city picking
(`CityPickerSheet`, `resolveCity`), and city isolation is unit-covered
(A-B-A), but provisioning a second city would require inserting city rows,
city configuration, and city-scoped sellers/products into the single shared
dev database, changing delivery-city resolution and default-city behavior
for every consumer (admin panel, seller app, other developers). Per the
safety rules this was not done. An isolated two-city database (or a
restorable MySQL dump + second city fixture) is the prerequisite; the exact
fixture surface is: `cities` + city config + ≥1 seller + ≥1 product per
city. No city rows were added, modified, or deleted.

## 5. Defects discovered (no code changed; fixes not applied)

- **D1 (severe): login succeeds server-side but the app never signs in on
  the login screen.** Five consecutive `login_mobile` taps each created a
  valid server token (8 active tokens for user 81), yet the UI stayed on
  the login form with no error and no navigation. Session material does
  persist (token in secure vault; after restart `validateSession` restores
  user 81 — scope `u:81` ops, cart badge, and authenticated calls all work),
  so only the post-login completion/navigation is broken. Reproduced 5/5
  times on the debug build / Android 9 device.
- **D2: creating a NEW address fails server-side when `landmark` is absent**
  (`SQLSTATE HY000 1364 Field 'landmark' doesn't have a default value`).
  `user_addresses.landmark` is `TEXT NOT NULL` without default, while the
  API validator does not require it and the app strips empty strings before
  sending — so in-app new-address creation hits this. Verified with and
  without `landmark` (address 27 created only with it). One-line
  server-side defaulting is the likely fix; not applied because the backend
  suite cannot be executed in this environment.
- **D3: a stale queued favorite-remove can delete a newer favorite.**
  Sequence observed: offline add(37) queued → online toggle-OFF coalesced to
  remove(37) → online toggle-ON succeeded directly (row 43 created) while
  the stale remove stayed queued → after restart replay deleted row 43,
  silently undoing the user's last intent (UI later converged to
  unfavorited). The outbox needs contradiction-cancellation when a direct
  toggle succeeds.
- **D4 (single occurrence): opening the cart from product detail red-screened**
  (`navigator.dart` assertion `!keyReservation.contains(key)`). Back
  recovered; cart from home works. Possibly navigation-stack state after the
  auth anomalies; needs a clean-build retest before judging severity.

## 6. Key commands and exit codes

- `flutter build apk --debug --dart-define=API_URL=http://172.17.3.192:8000`
  → exit 0 (`Built build\app\outputs\flutter-apk\app-debug.apk`).
- `adb install -r …/app-debug.apk` → `Success`.
- Device pings to `172.17.3.192`: 0% loss online / `Network is unreachable`
  offline (each phase gated).
- `flutter test test\zz_tmp_login_probe_test.dart` (temporary, deleted
  afterwards) → `All tests passed` — and it proved `ApiResult.token` is
  null for login responses (token lives at `data.access_token`; callers
  already carry a fallback).
- API campaign scripts in `C:\laragon\tmp\opencode\` (outside both repos):
  favorite exactly-once + isolation PASS; checkout double-submit PASS
  (exit 0); final evidence queries exit 0. No repo test suites were rerun
  (no code changed).

## 7. Remaining limitations

- Interactive search typing, second-account device login, and city
  switching were not executed (input limits, D1, single shared city).
- The mid-submit radio cut was approximated by offline-submit refusal +
  online resubmit + API double-submit; a true mid-POST kill was not
  deterministically staged (LAN POSTs complete in milliseconds).
- D4 needs a clean-session retest to determine whether it is systematic.
- No code fixes were applied; D1–D4 await triage.

## 8. Change preservation and fixtures

- No file in either repo was created, edited, staged, or deleted for
  testing (the temporary probe test was removed; `git status` identical
  before/after — see §9).
- Database fixtures created (all additive, all marked): users 81
  (`ANDROIDEV42 A`) and 82 (`ANDROIDEV42 B`); address 27 (user 81, Marib);
  favorites rows for user 81 (`(42,81,1)`; `(43,81,37)` created then removed
  by the D3 replay — final: only row 42); checkout groups 29 (API key test,
  524.40 COD) and 30 (device order, 6444.60 COD) with their seller orders
  and idempotency sessions; login tokens for the test logins. No
  pre-existing row was updated or deleted; no destructive cleanup performed.
- Device left with the debug app installed, Wi‑Fi on, airplane off.

## 9. Initial vs final Git status

- Flutter (`prod/offline-reliability`, HEAD `e1b0e44`): identical before and
  after — all pre-existing staged (`A`), modified (`M`), and the one
  untracked report preserved; no new files remain.
- Backend (`main`, HEAD `d1d26b2`, in sync with `origin/main`): identical
  before and after — modified controllers/services/lang/tests plus the two
  untracked test files preserved; pre-existing stash entry untouched.

## 10. Production and safety confirmation

- Production (`https://admin.marabmall.cloud`) received zero requests: the
  installed build targets `http://172.17.3.192:8000` (verified in binary
  and on-screen); all mutations went to the Docker-local MySQL dev
  database identified in §0.
- No real payments (COD-only dev setup, empty gateway keys, zero wallet
  movements), no courier dispatch (no assignments created), no SMS/WhatsApp
  sends (no OTP/send endpoints invoked), no notifications beyond in-app rows.
- No commits, pushes, deployments, branch operations, resets, cleans,
  stashes, `migrate:fresh`, or `db:wipe` in either repository.
- No credentials, tokens, secrets, or device PINs are recorded in this
  report.
