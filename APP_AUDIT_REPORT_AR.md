# تقرير فحص تطبيق «سريع مارت» للعملاء

> نوع التقرير: مراجعة كود واختبارات (بدون تعديل أي كود).
> النطاق: `lib/` بالكامل + Android/iOS + الاختبارات + إعدادات التشغيل.
> التاريخ: 2026-10-22.

---

## 1) الملخص التنفيذي

التطبيق مكتمل وظيفياً وواسع النطاق: متجر، حراج، «أخدمني»، محفظة، طلبات، إشعارات، مساعد ذكي، دفع، وعمل دون اتصال. البنية منظمة (Feature-first) والتحليل الساكن نظيف، لكن الفحص كشف **مشاكل حرجة تمس سلامة البيانات والدفع** خصوصاً في:

1. **الكاتالوج المحلي (Drift):** منطق المزامنة والحذف يمكن أن يمحو الكاتالوج بالكامل عند خطأ صفحة أو عند تجاوز 500 معرّف.
2. **الدفع:** إمكانية إنشاء طلبين متزامنين (race) عند النقر المزدوج، وقفل دفع دائم بعد نتيجة غير مؤكدة.
3. **تبديل الحساب:** بقاء سلة/عناوين الحساب السابق في الذاكرة عند الفشل الشبكي.
4. **سلة الضيف:** مرآة Drift تُعيد إحياء السلة المحذوفة بعد إعادة التشغيل.
5. **الجلسة:** 401 لا يُصنَّف auth، وفشل حذف التوكن من secure storage يُتجاهل.
6. **تفاصيل الطلب:** انهيار `TypeError` عند وجود حالة تتبع.
7. **البوابة:** فشل تهيئة الدفع بعد نجاح الطلب يمسح الجلسة ويسمح بطلب مكرر عند إعادة المحاولة.

الحصيلة: **10 حرجة، 8 عالية، 13 متوسطة، 5 منخفضة** (تقديري)، مع اختبارين قديمين و11 اختبار تكامل بيئي.

---

## 2) المنهجية وحدود الفحص

- قراءة كاملة للكود عبر وكلاء فرعيين متخصصين (Auth/OTP، Cart/Checkout، Browse، Account/Notifications/Assistant/Complaints، Core/Offline/Catalog/Push).
- تحقق يدوي سطر بسطر من كل نتيجة حرجة/عالية.
- تشغيل `flutter analyze --no-pub` و`flutter test --no-pub`.
- لم يتوفر باكند حقيقي على `127.0.0.1:8000`، لذلك اختبارات التكامل الحقيقية لم تُنفَّذ فعلياً.
- لم يُجرَّب التطبيق على جهاز فعلي في هذه الجولة؛ أحكام الواجهة مبنية على قراءة الكود.

---

## 3) فهم التطبيق

- **Flutter/Dart:** `pubspec.yaml` الإصدار `1.0.3+3`، SDK `^3.12.2`، Flutter المثبت `3.47.1` / Dart `3.13.1`.
- **الباكند:** `https://admin.sreamart.com` + `x-access-key` + `API_SUBURL=/customer`، كود الدولة `967`.
- **الحالة:** `AppController` (ChangeNotifier) + Riverpod للـ bootstrap.
- **التخزين:** `SharedPreferences` للتفضيلات، `flutter_secure_storage` للتوكن، Drift/SQLite للكاتالوج والسلة المحلية، ملفات JSON مؤقتة للجلسات والعمل دون اتصال.
- **Offline-first:** `OfflineCache` + `PendingOutbox` (مفضلات فقط) + `SyncEngine` + `CatalogSyncService` + صور مصغّرة.
- **الدفع:** `CheckoutSession` بمفتاح idempotency ثابت، ثم `/checkout`، ثم بوابة إن كانت طريقة الدفع إلكترونية.
- **الإشعارات:** FCM من إعدادات الباكند (`settings.firebase`) لعدم وجود ملفات Firebase أصلية، مع fallback إلى التخزين المؤقت.

---

## 4) جرد الصفحات والمسارات

| المسار | الشاشة/الصف | الوظيفة |
|---|---|---|
| `Splash` | `BrandSplashScreen` | شاشة بدء وتهيئة قبل بناء الراوتر |
| `/login` | `LoginScreen` | دخول + «نسيت كلمة المرور» + إعادة تعيين OTP (views داخلية) |
| `/register` | `RegisterScreen` | تسجيل + OTP + هاتف بديل + شروط |
| `/change-password` | `ChangePasswordScreen` | تغيير كلمة المرور |
| `/` | `HomeScreen` | الرئيسية: بانرات، تصنيفات، عروض، منتجات، متاجر |
| `/products` | `ProductsScreen` | قائمة/بحث/فلاتر/فرز/lazy load |
| `/product/:slug` | `ProductDetailsScreen` | تفاصيل المنتج والمتغيرات والتقييمات |
| `/category/:slug` | `CategoryScreen` | منتجات تصنيف |
| `/offers` | `OffersScreen` | العروض |
| `/sellers` | `SellersScreen` / Stores | المتاجر |
| `/seller/:id`, `/store/:slug` | `SellerPageScreen` | صفحة متجر |
| `/search` | `SearchScreen` | بحث + بحث حديث + تحميل المزيد |
| `/cart` | `CartScreen` | سلة (ضيف/مسجل) |
| `/checkout` | `CheckoutScreen` | عنوان، دفع، وقت توصيل، ملاحظات، كوبون |
| `/account` | `AccountScreen` | حساب (مغلّف داخل AppShell) |
| `/orders` | `OrdersScreen` | تبويبا «نشطة/سابقة» + طلبات أخدمني |
| `/orders/:id` | `OrderDetailsScreen` | تفاصيل طلب/مجموعة طلبات + تتبع/إلغاء/إرجاع |
| `/checkout-groups` | `CheckoutGroupsScreen` | مجموعات الدفع |
| `/checkout-groups/:id` | `CheckoutGroupDetailsScreen` | تفاصيل المجموعة |
| `/addresses` | `AddressesScreen` | العناوين + خريطة/حقول ديناميكية |
| `/wishlist` | `WishlistScreen` | المفضلة |
| `/profile` | `ProfileScreen` | الملف الشخصي |
| `/wallet`, `/transactions` | `WalletScreen` / `TransactionsScreen` | المحفظة والحركات |
| `/notifications` | `NotificationsScreen` | إشعارات + عدّاد غير مقروء |
| `/haraj` | `HarajListScreen` | الحراج |
| `/haraj/:id` | `HarajDetailsScreen` | تفاصيل إعلان |
| `/haraj/create`, `/haraj/edit/:id` | `HarajFormScreen` | إنشاء/تعديل إعلان |
| `/haraj/mine` | `HarajMineScreen` | إعلاناتي |
| `/akhdimni` | `AkhdimniHomeScreen` | خدمة أخدمني |
| `/akhdimni/create` | `AkhdimniCreateScreen` | طلب خدمة |
| `/akhdimni/orders`, `/akhdimni/orders/:id` | `AkhdimniOrdersScreen` / `AkhdimniOrderDetailsScreen` | طلبات الخدمة وتفاصيلها |
| `/assistant` | `AssistantScreen` | المساعد الذكي + اقتراح منتجات/إجراءات |
| `/faq` | `FaqScreen` | الأسئلة الشائعة |
| `/complaints` | `ComplaintsScreen` | الشكاوى + مسودات |
| `/privacy`, `/terms`, `/about`, `/contact` | `CmsScreen` | صفحات CMS |
| `/policy/:type` | `CmsScreen` | سياسات الخصوصية/الإرجاع/الشحن/الإلغاء |

عناصر مشتركة: `BrandHeader` (بحث/سلة/إشعارات/حساب)، `AppShell` (تبويبات سفلية)، `NotificationBell`، `ProductCard`، `ProductVariantSheet`، `DynamicAddressFields`، `OrderTracker`.

**ملاحظة على التبويبات:** التبويبات السفلية هي: الرئيسية، الحراج، أخدمني (اختياري)، طلباتي. السلة والحساب تُفتحان من الهيدر. `AppShell.index` يعيد 0 لأي مسار غير معروف، لذا `/account` و`/cart` تُظهران «الرئيسية» محددة (تجميلي).

---

## 5) حالة البناء والاختبارات

- `flutter analyze --no-pub`: **No issues found**.
- `flutter test --no-pub`: **250 ناجح / 13 فاشل** (إجمالي 263).
- الفشل غير البيئي (اختبارات قديمة تحتاج تحديثاً):
  1. `test/cart_navigation_test.dart` — أيقونة الحساب صارت `person_outline_rounded` بعد تحديث الهيدر، والاختبار يبحث عن `person_outline`.
  2. `test/offline_verification_fixes_test.dart` — يتوقع احترام امتداد الصورة الأصلي، بينما `ImagePrefetch` يعيد الترميز JPEG دائماً (تصميم حالي، الاختبار متأخر).
- الفشل البيئي: 11 اختباراً في `test/offline_real_backend_test.dart` تحتاج باكنداً على `127.0.0.1:8000` (Timeout/عدم توفر fixtures).
- توجد تعديلات staged سابقة (هيدر/تنقل/إشعارات/شاشة حساب/مساعد) لم تُراجع كـ diff في هذه الجولة، لكنها مشمولة بالفحص الحالي.

---

## 6) المشاكل مرتبة بالخطورة

### 6.1 حرجة (Critical)

#### C-01 — مزامنة الكاتالوج تمحو كل الصفوف عند تجاوز 500 معرّف
- **الموقع:** `lib/core/catalog_db/catalog_database.dart:820-831` و`:863-874`، تُستدعى من `lib/core/catalog_store.dart:513-515`.
- **الوصف:** كل chunk ينفّذ `NOT IN (chunk)` على حدة:
  - `reconcileListed`: chunk الأول يضع `is_listed=0` لكل ما ليس في النصف الأول، ثم chunk الثاني يضع 0 لكل ما ليس في النصف الثاني → **كل الصفوف تصبح 0** (لأن التحديث لا يعيد أي صف إلى 1).
  - `_deleteMissingIds`: chunk الأول يحذف كل ما ليس في النصف الأول، ثم الثاني يحذف كل ما ليس في النصف الثاني → **حذف كل المتاجر/التصنيفات**.
- **الأثر:** فقدان الكاتالوج المحلي بالكامل في أي مزامنة كاملة > 500 معرّف (منتجات، متاجر، تصنيفات). هذا يضرب العمل دون اتصال والبحث المحلي.
- **الإصلاح:** استخدام جدول مؤقت للمعرّفات أو `DELETE/UPDATE WHERE server_id NOT IN (SELECT ...)` على مجموعة واحدة، أو تنفيذ `NOT IN` مرة واحدة مع معالجة حد SQLite (تجزئة عبر `temp table`)، أو عكس المنطق: `UPDATE ... SET is_listed=1 WHERE id IN (...)`, ثم تعليم/حذف غير الموجود بعد اكتمال كل الـ chunks.

#### C-02 — «صفحة فارغة» مضللة تعني اكتمال المشي ثم تمسح الكاتالوج
- **الموقع:** `lib/core/catalog_store.dart:167-177`، والاستخدام في `lib/core/app_controller.dart:1643-1648` و`:1695-1699`، والمصالحة في `catalog_store.dart:323`/`:513-515`.
- **الوصف:** `isEmptyCatalogPage` يعتبر أي استجابة غير ناجحة رسالتها تحتوي `not found` أو `لم يتم العثور على` نهايةَ بيانات، **حتى عند offset=0**. رسائل مثل «المدينة غير موجودة» أو 404 لمسار خاطئ أو خطأ خادم عام تُترجم إلى صفحة نظيفة فارغة، فيُعدّ المشي كاملاً، ثم حسب نوع الجولة:
  - **المنتجات:** `reconcileListed(scope, {})` يضع كل المنتجات `is_listed=0` (`catalog_store.dart:513`).
  - **التصنيفات:** `deleteMissingCategories(scope, {})` يحذف كل التصنيفات (`catalog_store.dart:515`).
  - (المتاجر لها مسار رفض مستقل، لكن نجاحها مع فشل المنتجات/التصنيفات هو ما يسمح بوصول المصالحة.)
- **الأثر:** مسح كامل للمنتجات المحلية أو التصنيفات بسبب خطأ عابر واحد، مع استمرار التطبيق كأن المزامنة نجحت.
- **الإصلاح:** اشتراط `offset == 0` + مطابقة رسائل محددة جداً (`no_products_found` / `no_categories_found` فقط)، وعدم السماح بحذف/إلغاء إدراج عند offset=0 إلا بعد تأكيد استجابة ناجحة فارغة (`status=1` + `data=[]`)، وعدم اعتبار 404/5xx/أخطاء الشبكة نهاية بيانات.

#### C-03 — إمكانية إنشاء طلبين عند النقر المزدوج على «تأكيد الطلب»
- **الموقع:** `lib/features/cart/cart_screens.dart:1694-1733` و`lib/core/offline/checkout_session.dart:54-70`.
- **الوصف:** `placing` يُضبط بعد `await app.hasInternetAccess()` (حتى 8 ثوان)، والزر لا يُعطّل قبل `setState`. نقرتان متتاليتان تستدعيان `_placeOrder` مرتين. عند عدم وجود جلسة سابقة، كل استدعاء `begin()` يرى `key == null`، ينفّذ `clear()` ثم يولّد مفتاحاً مختلفاً ويكتبه (آخر كتابة تفوز). الطلبان يُرسلان بمفتاحين مختلفين → لا يوجد dedupe على الخادم.
- **الأثر:** طلب مزدوج وخصم مزدوج (خصوصاً مع المحفظة/البوابة).
- **الإصلاح:** حارس متزامن في أول الدالة: `if (_placing) return; setState(() => placing = true);` قبل أي await؛ وجعل `CheckoutSession.begin` متسلسلاً (mutex/قفل) أو توليد المفتاح مرة واحدة لكل fingerprint قبل السماح بالطلب.

#### C-04 — قفل دفع دائم بعد نتيجة دفع غير مؤكدة
- **الموقع:** `lib/core/app_controller.dart:1319-1335` و`:1342-1350`، والواجهة `lib/features/cart/cart_screens.dart:1703-1724`.
- **الوصف:** عند timeout/انقطاع، تُحفظ جلسة الدفع. في بدء التشغيل التالي:
  - `hasRecentOrderForSession` يفحص **آخر 5 طلبات نشطة فقط** (`api.orders(limit:5)` بنوعه الافتراضي 1)، ويرجع `false` عند أي خطأ شبكة.
  - لا يوجد زر «تحقق/إلغاء الجلسة» في الواجهة؛ زر «عرض الطلبات» لا يصفّر `unresolvedCheckout`.
- **الأثر:** المستخدم يُمنع من أي دفع لاحق (حتى لسلة جديدة)، وربما إلى الأبد، لمجرد timeout أو فشل شبكة عند الإقلاع، أو لأن الطلب أصبح «سابقاً» أو خارج آخر 5.
- **الإصلاح:** فحص الطلبات النشطة والسابقة (وصفحات إضافية) بمفتاح idempotency كمرشّح، وإذا فشل الفحص الشبكي إظهار خيار «إعادة المحاولة/إلغاء الجلسة» بدل القفل النهائي، وربط `unresolvedCheckout` بالحساب ومسحه عند تسجيل الخروج/تبديل الحساب.

#### C-05 — تسريب سلة/عناوين الحساب السابق عند تبديل الحساب دون اتصال
- **الموقع:** `lib/core/app_controller.dart:2287-2310` (`_persistAuth`)، `:2380-2409` (`_clearSession`)، `:2533-2553` (فشل `refreshCart`).
- **الوصف:** `_persistAuth` لا يمسح `cartProducts` و`addresses` و`selectedAddress` و`sellerGroups` عند الدخول بحساب جديد. إذا فشل `refreshCart` (أو كان المستخدم دون اتصال)، تبقى سلة وعناوين الحساب السابق معروضة، وتُستخدم عند إعادة الاتصال/الدفع. كذلك `logout` لا يمسحها.
- **الأثر:** كشف بيانات حساب لآخر (سلة/عنوان)، واحتمال إرسال طلب لعنوان الحساب السابق.
- **الإصلاح:** في `_persistAuth` و`_clearSession`: تصفير `cart/cartProducts/cartSubTotal/addresses/selectedAddress/sellerGroups/promoCode` قبل أي شيء، ثم تحميل بيانات النطاق الجديد فقط (سلة/عناوين) بشكل متزامن أو مع شاشة تحميل.

#### C-06 — فشل حذف التوكن + سوء تصنيف 401 = جلسة ميتة تُعرض كمسجّلة
- **الموقع:** `lib/core/auth/token_vault.dart:75-84`، `lib/core/api/customer_api.dart:23` و`:261-269`، `lib/core/app_controller.dart:550-575` و`:385-388`.
- **الوصف:** `TokenVault.clear` يبتلع فشل الحذف من secure storage، فيبقى التوكن على القرص. من جهة أخرى `validateStatus: status < 500` + `_parse` يجعل استجابة 401/403/404 جسماً عادياً (`ok=false` و`classifiedError=null`)، و`_guard` يسجّل `recordSuccess()`. لذلك `validateSession` لا يدخل فرع `auth`، ويُعيد المستخدم من الكاش عند وجوده، ويستمر التطبيق بجلسة منتهية. كذلك تفشل تصنيفات 401/404/429 في `ApiErrorCategory`.
- **الأثر:** المستخدم يظهر مسجّلاً بينما كل الطلبات تفشل، وبعد logout قد يعود التوكن القديم بعد إعادة التشغيل.
- **الإصلاح:** اعتبار 401/403 خطأ auth صريحاً (قبل `_parse`)، وعدم تسجيل نجاح للـ 4xx، وإعادة رمي/معالجة فشل `vault.clear()` (أو على الأقل مسح الذاكرة + منع الاستعادة)، ومسح الجلسة عند 401 في `validateSession`.

#### C-07 — سلة الضيف «الشبح» تعود بعد الحذف/الدمج وتتضاعف
- **الموقع:** `lib/core/app_controller.dart:456-468` (استرجاع Drift عند الإقلاع)، `:194-207` (`persistGuestCart`)، `:2344-2346` (دمج السلة)، `:2949-2953` (`clearAllCart`)، و`lib/core/offline/local_cart.dart:151-159` (`addItem` تجميعي).
- **الوصف:** Drift مرآة للسلة، لكن:
  - `clearAllCart` يفرّغ `guestCart` ويحذف prefs فقط، دون `_localCart.clear()`؛ بعد إعادة التشغيل تُعاد السلة من Drift.
  - بعد دمج سلة الضيف بنجاح في الحساب، تُمسح prefs والذاكرة فقط، ويبقى Drift؛ عند إعادة التشغيل (والحساب مسجل) تُسترجع السلة إلى `guestCart`، ثم تُدمج مرة أخرى عند الدخول التالي → كميات مضاعفة.
  - عند الإقلاع مع وجود prefs، يضيف الكود كل عنصر بـ `addItem` (تجميعي) فوق صفوف Drift الموجودة، ما يضاعف الكميات في المرآة.
- **الأثر:** سلة محذوفة تعود، وكميات خاطئة، ودمج متكرر لطلبات قديمة.
- **الإصلاح:** جعل `persistGuestCart` هي المسار الوحيد (يستدعي `clear()` ثم إعادة الإدراج)، واستدعاؤها بعد أي تصفير (دمج/حذف الكل/الخروج)، واستخدام `clear()+insert` لا `addItem` عند الهيدرة، ومسح Drift في `_clearSession`/`clearAllCart`.

#### C-08 — انهيار شاشة تفاصيل الطلب عند وجود حالة تتبع
- **الموقع:** `lib/features/account/account_screens.dart:1903-1923`.
- **الوصف:** بسبب أولوية `??` أعلى من `?:`، يصبح الشرط:
  `tracking_status ?? delivery_status ?? (address_snapshot is Map)`، وهو `dynamic` وليس `bool`. عند وجود `tracking_status` نصي (وهو الوضع الطبيعي) يرمي `TypeError` أثناء البناء.
- **الأثر:** شاشة تفاصيل الطلب تنهار لأي طلب له حالة تتبع/توصيل نصية.
- **الإصلاح:** إضافة أقواس حول شرط `is Map`، وقراءة الحالة أولاً في متغير بسيط (`final status = ...;` ثم `status.isNotEmpty ? status : city`).

#### C-09 — تصنيف OTP الخاطئ يعرض «تم الإرسال» ويقفل الإعادة
- **الموقع:** `lib/core/otp_resend.dart:63-67`، `lib/features/auth/auth_screens.dart:845-908` و`:1825-1853`.
- **الوصف:** `extractOtpRetryAfter` يلتقط **أول رقم** في رسالة الفشل (حتى لو كان رمز خطأ مثل 500 أو رقم هاتف)، ويُعتبر أي `retryAfter > 0` «cooldown». النتيجة: فشل حقيقي → `_forgotSuccess` + الانتقال إلى `forgot_reset` + قفل الإعادة لثوانٍ/دقائق، دون إرسال SMS.
- **الأثر:** المستخدم يظن أن الرمز أُرسل، يدخل OTP لا exists، ويُمنع من إعادة المحاولة.
- **الإصلاح:** الاعتماد على `retry_after` المهيكل أو `Retry-After` header فقط؛ وعدم استخراج أرقام من نص الرسالة إلا بأنماط صريحة («انتظر N ثانية/دقيقة») وربطها بـ cooldown، وإلا `error`.

#### C-10 — فشل تهيئة البوابة بعد نجاح الطلب يمسح الجلسة ويسمح بطلب ثانٍ
- **الموقع:** `lib/features/cart/cart_screens.dart:1813-1855`.
- **الوصف:** بعد `result.ok` تُمسح `CheckoutSession` وdraft **قبل** `initiateTransactionForCheckoutGroup`. إذا فشلت التهيئة، يظهر snackbar بالخطأ ويُعاد `placing=false`، مع بقاء السلة كما هي. إعادة المحاولة تنشئ مفتاح idempotency جديداً → طلب آخر على الخادم.
- **الأثر:** طلب غير مدفوع يبدو فاشلاً؛ وقد ينشئ المستخدم طلباً مكرراً (أو عدة) عند إعادة المحاولة.
- **الإصلاح:** عدم مسح الجلسة/المفتاح حتى تأكيد الدفع أو إلغائه؛ فتح صفحة الطلب مع «إعادة محاولة الدفع» بنفس `checkout_group_id`؛ ومنع الزر أثناء وجود طلب غير مدفوع لنفس الجلسة.

### 6.2 عالية (High)

#### H-01 — تعديلات سلة المسجّل أثناء انقطاع الشبكة لا تُطابَق لاحقاً
- **الموقع:** `lib/core/app_controller.dart:2734-2768` و`:2866-2892`؛ `lib/core/offline/pending_ops.dart:15`.
- **الوصف:** إضافة/حذف/تعديل السلة offline تُحدّث الذاكرة/اللقطة فقط، ولا تُضاف إلى `PendingOutbox` (الذي يدعم المفضلة ونوع `guestCartMerge` غير المستخدم). عند أول `refreshCart` ناجح تُستبدل السلة بسلة الخادم وتختفي تعديلات المستخدم.
- **الأثر:** المستخدم يرى منتجات في سلته ثم لا يجدها في الدفع، أو يظن أنه أضافها.
- **الإصلاح:** إما إضافة عمليات سلة idempotent إلى outbox (تعيين كمية نهائية لا زيادة)، أو منع التعديل offline للمسجّل برسالة واضحة وإرجاع الحالة البصرية.

#### H-02 — عدّاد الإشعارات يمحو «المقروء» عند أي فشل شبكة
- **الموقع:** `lib/features/notifications/notifications_screen.dart:466-482` مع `lib/core/notification_read.dart:56-67`.
- **الوصف:** `NotificationBell._refresh` لا يتحقق من `res.ok`؛ عند فشل الطلب يكون `total=0`، فيُنفَّذ `prune(uid, 0)` الذي يقصّ كل المعرّفات المقروءة إلى قائمة فارغة. (شاشة الإشعارات نفسها محمية، لذا المشكلة في العدّاد فقط.)
- **الأثر:** بعد كل فشل شبكة/إقلاع دون اتصال تظهر كل الإشعارات غير مقروءة، وتُفقد حالة القراءة المحلية.
- **الإصلاح:** التحقق من `res.ok` قبل `prune`، وعدم استدعاء `prune` عند total=0 إلا إذا كانت الاستجابة ناجحة فعلاً، والاحتفاظ بالمعرّفات عند الفشل.

#### H-03 — تهيئة الإشعارات المحلية غائبة في معالج الخلفية (data-only)
- **الموقع:** `lib/core/push_notifications.dart:26-33` و`:266-293`، `lib/main.dart:30-40`.
- **الوصف:** المعالج الخلفي يهيّئ Firebase فقط ثم يستدعي `showFromMessage`، دون `_local.initialize` أو إنشاء قناة في الـ isolate الجديد، ودون معالجة `getNotificationAppLaunchDetails` عند النقر. الاستثناءات تُبتلع.
- **الأثر (مشروط):** إشعارات data-only (شائعة في Laravel/FCM) قد تُفقد أو لا تفتح المسار الصحيح عند إغلاق التطبيق، خصوصاً على iOS أو عند عدم تسجيل plugin في الـ isolate الخلفي. إشعارات `notification` يعرضها النظام تلقائياً، لذا لا تتأثر بنفس الدرجة. القناة موجودة بعد أول تشغيل ناجح، لذا أول تثبيت بلا إعدادات Firebase لا يستقبل شيئاً أصلاً.
- **الإصلاح:** دالة `initBackground` تهيّئ local notifications وتنشئ القناة قبل `show`، وفحص `getNotificationAppLaunchDetails` عند الإقلاع لتوجيه النقر، مع عدم ابتلاع الأخطاء في debug.

#### H-04 — `total` التصنيفات يسقط لطول الصفحة → حذف تصنيفات حقيقية
- **الموقع:** `lib/core/app_controller.dart:1702-1707`، والمصالحة في `lib/core/catalog_store.dart:507-515`.
- **الوصف:** إذا لم يُرجع الخادم `total`، يُستخدم `res.dataMaps.length` كإجمالي. عند وجود أكثر من 100 تصنيف جذري، تنتهي الجولة «بنظافة» بعد الصفحة الأولى، ثم `deleteMissingCategories` يحذف ما لم يُرَ.
- **الأثر:** فقدان تصنيفات محلية (والمنتجات المرتبطة تبقى بلا تصنيف).
- **الإصلاح:** عند غياب total: عدم إجراء مصالحة حذف، أو الاستمرار حتى صفحة قصيرة/فارغة، أو تعطيل الحذف للتصنيفات نهائياً والاكتفاء بالإخفاء.

#### H-05 — ترقيم صفحات المنتجات يقفز/يكرر بسبب offset بعد إزالة التكرار
- **الموقع:** `lib/features/products/products_screens.dart:319-321` و`:365-367` و`:399-402`.
- **الوصف:** بعد `J.appendUnique` يُحسب `offset = items.length`، بينما الخادم استهلك `next.length` صفاً. عند وجود صفوف مكررة يصبح offset أقل من الحقيقي، فتُعاد نفس الصفحات، وقد لا تصل القائمة للنهاية. (شاشة الرئيسية تستخدم `_offset += rows.length` وهي الطريقة الصحيحة.)
- **الأثر:** تكرار منتجات، طلبات لا نهائية، ومنتجات مفقودة في نهاية القائمة.
- **الإصلاح:** تتبع `_offset += next.length` قبل الدمج، أو استخدام `total` من الخادم، وإعادة تعيين offset عند تغيير الفلاتر.

#### H-06 — ترقيم صفحات الطلبات معطّل
- **الموقع:** `lib/features/account/account_screens.dart:528-622` و`:712-736`.
- **الوصف:** `_load(more: true)` موجود لكن لا يوجد أي مستدعٍ (لا scroll listener ولا زر «المزيد»)؛ `page` يبقى 1، و`totalActive` محسوب ولا يُستخدم.
- **الأثر:** المستخدم يرى أول 10 طلبات نشطة + أول 10 سابقة فقط، ولا يمكنه الوصول لما بعدها.
- **الإصلاح:** إضافة `ScrollController`/`NotificationListener` يستدعي `_load(more: true)` عند الاقتراب من النهاية، مع حالة تحميل ومنع التكرار.

#### H-07 — غياب بيانات ساعات العمل يمنع الدفع بلا رسالة
- **الموقع:** `lib/core/business_hours.dart:135-144`، `lib/features/cart/cart_screens.dart:916` و`:924-940` و`:1647-1665`.
- **الوصف:** `canPlaceOrderFromBusinessHours(null)` يرجع `allowed=false, reason=unavailable`؛ لكن لافتة السبب تُعرض فقط عند `bh != null`، و`buildSellerClosedMessage` تُرجع نصاً فارغاً لحالة null. النتيجة زر دفع معطّل دون تفسير.
- **الأثر:** إذا فشل endpoint ساعات العمل أو لم يُحمّل بعد، يظن المستخدم أن التطبيق معطل.
- **الإصلاح:** عرض رسالة صريحة لحالة `unavailable` («تعذر التحقق من أوقات العمل، أعد المحاولة»)، أو السماح بالمحاولة والاعتماد على الخادم.

#### H-08 — أي خطأ عمل في `GET /cart` يُفسَّر كسلة فارغة
- **الموقع:** `lib/core/app_controller.dart:2506-2532`.
- **الوصف:** إذا كانت الاستجابة قابلة للوصول (`classifiedError == null`) وغير ناجحة، يتم تصفير السلة وحذف اللقطة، بافتراض أنها `no_items_found`. أي status:0 آخر (عطل مؤقت، تحقق فاشل) يمحو السلة محلياً.
- **الأثر:** اختفاء السلة وعناصرها من الواجهة/الكاش مع أول خطأ عمل.
- **الإصلاح:** التحقق من رسالة/كود «لا توجد عناصر» تحديداً قبل التفريغ، وإلا الاحتفاظ بالحالة السابقة.

### 6.3 متوسطة (Medium)

#### M-01 — تفاصيل الطلب تعلق في التحميل عند فشل الجلب بلا كاش
- **الموقع:** `lib/features/account/account_screens.dart:1152-1156`.
- **الوصف:** `loading = order == null`، وعند عدم وجود كاش يبقى `true` بلا أي مسار خطأ/إعادة محاولة.

#### M-02 — تعديل العنوان يستبدل المدينة بمدينة التصفح ويحتفظ بإحداثيات قديمة
- **الموقع:** `lib/features/account/account_screens.dart:2804-2817`.
- **الوصف:** `city/city_id` يُؤخذان دائماً من `app.city` (مدينة التصفح الحالية)، لا من عنوان موجود. وعند تغيير المدينة تبقى `latitude/longitude` القديمة. العنوان الجديد يستخدم مركز المدينة لا موقعاً محدداً.

#### M-03 — البحث: «بحث حديث» لا يملأ الحقل، وسبينر «المزيد» يعلق
- **الموقع:** `lib/features/more/more_screens.dart:1957-1985` و`:2130-2135`.
- **الوصف:** النقر على بحث حديث يستدعي `_search(q)` فقط دون `controller.text = q`، لذا يفشل `_loadMore` (يعتمد على `controller.text`). وإذا بدأ بحث جديد أثناء `_loadMore`، يعود الـ continuation عند `mySeq != _seq` دون تصفير `_loadingMore`، فيبقى زر «كل النتائج» معطلاً.

#### M-04 — فلاتر المتاجر/الحراج تفشل في إبقاء نتائج قديمة تحت فلتر جديد
- **الموقع:** `lib/features/more/more_screens.dart:204-235`، `lib/features/haraj/haraj_screens.dart:147-152`.
- **الوصف:** عند فشل الشبكة بعد تغيير الفلتر، لا تُمسح العناصر ولا يُعرض خطأ، فتبقى نتائج الفلتر السابق معروضة وكأنها نتائج الفلتر الجديد. (المتاجر تُحدّث `total` فقط عند وجود نتائج محلية.)

#### M-05 — `promo_price`: سعر الفلاش/الخصم قد يتجاوز السعر الأصلي
- **الموقع:** `lib/core/promo_price.dart:28-47`.
- **الوصف:** `flash_price` و`discounted_price` يُستخدمان دون التحقق من كونهما أقل من `price`؛ يعرض الكارد سعراً أعلى من الأصلي بينما `hasDiscount=false` (لا شطب)، ما يربك المستخدم. `promo_price` وحده محمي.

#### M-06 — «تحديد الكل كمقروء» لا يعلّم إلا المحمّل، والعدّاد يطرح كل السجل
- **الموقع:** `lib/features/notifications/notifications_screen.dart:397-404`، `lib/core/notification_read.dart:10` و`:42` و`:50-53`.
- **الوصف:** الزر يمرّر `items` الحالية فقط (10/20...) بينما `total` أكبر، فتبقى شارة «غير مقروء» لبقية الإشعارات. `computeUnreadCount = total - readIds.length` مع سقف 500 قد يعطي رقماً خاطئاً إذا تغيّرت الإشعارات أو تجاوز المقروء 500.

#### M-07 — رسائل Auth مضللة عند فشل حفظ التوكن/نجاح إعادة التعيين
- **الموقع:** `lib/features/auth/auth_screens.dart:750-777` و`:802-805` و`:810`، و`lib/core/app_controller.dart:2287-2305`.
- **الوصف:** أي `StateError(missing_token)` أو `TokenVaultException` من `_persistAuth` يصل إلى catch العام فيظهر `network_error`، رغم أن الشبكة قد تكون سليمة. ورسالة نجاح إعادة تعيين كلمة المرور تُوضع في `error` وتُعرض بتنسيق الخطأ الأحمر.

#### M-08 — إعادة إرسال OTP الخلفية تقرأ رقم الجوال وقت الإطلاق
- **الموقع:** `lib/features/auth/auth_screens.dart:936-940` و`:1848-1854` و`:1765-1774`.
- **الوصف:** المؤقت المجدول بعد نجاح الإرسال يستدعي `_backgroundForgotSend`/`_requestRegisterOtp` التي تقرأ `mobile.text` الحالي. إذا عدّل المستخدم الرقم، يُرسل الرمز إلى رقم جديد أو يُبطل الرمز الأول دون علمه.

#### M-09 — `apiUrl` يُعاد إلى الافتراضي في كل إقلاع
- **الموقع:** `lib/core/app_controller.dart:382-383`.
- **الوصف:** `setApiUrl` يحفظ القيمة، لكن `bootstrap` يفرض `AppConfig.defaultApiUrl` ويكتبها فوق المحفوظ. الميزة (المتاحة في debug فقط) بلا أثر دائم.

#### M-10 — `Accessibility/UX`: تبويب الرئيسية يظهر محدداً في الحساب/السلة
- **الموقع:** `lib/app.dart:429-439` و`:230-240`.
- **الوصف:** `/account` و`/cart` تُغلَّف داخل `AppShell` لكنها ليست وجهات تبويب؛ `index` يرجع 0 لأي مسار غير معروف.

#### M-11 — السماح بـ HTTP غير المشفر في release
- **الموقع:** `android/app/src/main/AndroidManifest.xml` (`android:usesCleartextTraffic="true"`).
- **الوصف:** حتى مع استخدام HTTPS افتراضياً، يسمح التطبيق بأي HTTP (مثلاً رابط صورة/بوابة/API بديل) مما يفتح باب MITM. يُفضّل إزالته أو حصره في manifest الـ debug عبر `networkSecurityConfig`.

#### M-12 — «تفريغ السلة» للضيف لا يعمل دون اتصال
- **الموقع:** `lib/core/app_controller.dart:2929`.
- **الوصف:** `if (isGuest && !await hasInternetAccess()) return;` يجعل حذف سلة الضيف عملية صامتة لا تفعل شيئاً دون اتصال، رغم أن سلة الضيف محلية بالكامل. كما أن الفرع يمسح `guestCart` وprefs أيضاً عند مسح سلة حساب مسجّل (`:2952-2953`) بلا سبب واضح.

#### M-13 — إجمالي سلة الضيف يظهر 0 دون اتصال/بعد إعادة التشغيل
- **الموقع:** `lib/core/app_controller.dart:133` و`:2570-2594`، `lib/features/cart/cart_screens.dart:279`.
- **الوصف:** `guestCartTotal` لا يُحسب محلياً عند الإضافة/الاستعادة، بل يُحدَّث فقط من استجابة `guest-cart` الناجحة. مع انقطاع الشبكة (أو إعادة تشغيل دون اتصال) تظهر المنتجات بإجمالي 0، وتصبح حسابات الحد الأدنى/الخصم/الدفع خاطئة.
- **الإصلاح:** احتساب الإجمالي من `guestCart` (price × qty) فور التحميل/التعديل، أو تخزينه مع السلة والتحقق منه عند وجود استجابة خادم.

### 6.4 منخفضة (Low)

- **L-01** `lib/core/offline/sync_orchestrator.dart:85,139,175` — الملف غير مستورد في التطبيق، ويحتوي `if (!response is Map) break;` (أولوية `!` على `is` تجعل الشرط دائماً false عملياً). كود ميت لكنه فخ إن أُعيد استخدامه.
- **L-02** `lib/core/offline/pending_ops.dart:138` — `if (ops.isEmpty || true) {}` كود ميت بلا أثر.
- **L-03** `lib/core/image_prefetch.dart:96-109` — كل الملفات `.jpg` حتى لو كان المصدر SVG/PNG؛ التصميم يعيد الترميز، لكن الصور النقطية تُعاد معالجتها بلا داعٍ. اختبار الامتداد القديم يحتاج تحديثاً.
- **L-04** `lib/core/app_controller.dart:524` — `bootstrapError` لا يُصفَّر عند نجاح إعادة المحاولة؛ لا يظهر للمستخدم لأن الراوتر يُبنى عند نجاح المدن، لكنه يترك حالة قديمة.
- **L-05** `lib/features/more/more_screens.dart:2098-2099` و`:1854` — `item['slug'] ?? item['id']` مع slug فارغ ينتج `/product/` (رابط مكسور).

---

## 7) ملاحظات ليست أخطاء (لتفادي العمل غير الضروري)

1. **ترميز الاسم العربي:** `android:label` و`CFBundleDisplayName` قيمتهما UTF-8 صحيحة (`سريع`)؛ الظهور المشوّه في PowerShell سببه ترميز الكونسول فقط. لا تُعدّل.
2. **`settings(withAuth)`:** المعامل يُتجاهل، لكن `Dio` يضيف `Authorization` تلقائياً عند وجود توكن، فلا أثر وظيفياً.
3. **توقيع release:** `build.gradle.kts` يحتوي حارس `GradleException` عند غياب `key.properties`، لذا فرع الرجوع إلى debug غير قابل للوصول. ليس خطأً.
4. **`NotificationRead.prune` في شاشة الإشعارات:** محمي بـ `serverTotal > 0 ? serverTotal : reads.length`. الخطأ في `NotificationBell` فقط.
5. **ترقيم الرئيسية:** `HomeScreen` يستخدم `_offset += rows.length` (نافذة خادم خام) وهو السلوك الصحيح؛ لا تُغيّره إلى `items.length` كما في المنتجات.
6. **`ImagePrefetch` JPEG:** سلوك مقصود وفق تعليق الكود، والاختبار القديم هو المتأخر.
7. **اختبارات `offline_real_backend_test`:** فشلها بيئي (لا باكند محلي)، وليست أخطاء تطبيق.
8. **`ACCOUNT` داخل AppShell:** مقصود لتفادي تعارض مفاتيح go_router؛ فقط مؤشر التبويب تجميلي.

---

## 8) خطة إصلاح مقترحة (بالترتيب)

**المرحلة 1 — سلامة البيانات (قبل أي إصدار):**
1. إصلاح `reconcileListed` و`_deleteMissingIds` (C-01).
2. تشديد `isEmptyCatalogPage` ومنع المصالحة عند offset=0/404/5xx (C-02).
3. إصلاح total التصنيفات أو تعطيل حذفها عند غياب total (H-04).
4. توحيد مسار سلة الضيف/Drift: `persistGuestCart` بعد كل تصفير + مسح Drift عند logout (C-07).
5. تصفير سلة/عناوين الحساب عند تبديل الحساب (C-05).
6. تصنيف 401/403 + معالجة فشل `TokenVault.clear` (C-06).

**المرحلة 2 — الدفع:**
7. حارس reentrancy + قفل `CheckoutSession.begin` (C-03).
8. إعادة تصميم `unresolvedCheckout`: فحص نشط/سابق، خيار تحقق/إلغاء، وربطه بالحساب (C-04).
9. عدم مسح الجلسة قبل نجاح البوابة + خيار إعادة الدفع (C-10).
10. عدم تفريغ السلة عند أي status:0 غير معروف (H-08).

**المرحلة 3 — العمل دون اتصال والإشعارات:**
11. outbox لتعديلات سلة المسجّل أو منعها بوضوح (H-01).
12. إصلاح عدّاد الإشعارات (H-02) و«تحديد الكل»/العدّ (M-06).
13. تهيئة local notifications في المعالج الخلفي (H-03).

**المرحلة 4 — الواجهات والترقيم:**
14. crash تفاصيل الطلب (C-08)، ترقيم المنتجات (H-05)، ترقيم الطلبات (H-06)، رسالة ساعات العمل (H-07).
15. OTP (C-09/M-08)، البحث (M-03)، الفلاتر (M-04)، العنوان (M-02)، السعر (M-05)، رسائل Auth (M-07).
16. تنظيف `sync_orchestrator`/الكود الميت (L-01/L-02)، وتحديث الاختبارين القديمين.

**التحقق بعد كل مرحلة:** `flutter analyze --no-pub` + `flutter test --no-pub` + اختبار يدوي لسيناريوهات: ضيف→تسجيل، تبديل حساب، دفعة مزدوجة، timeout دفع، إعادة تشغيل بعد حذف السلة، مزامنة >500 منتج، فشل شبكة عند الإقلاع.

---

## 9) الملفات الأساسية المرجعية

- المزامنة/الكاتالوج: `lib/core/catalog_store.dart`, `lib/core/catalog_db/catalog_database.dart`, `lib/core/app_controller.dart`
- الدفع/السلة: `lib/features/cart/cart_screens.dart`, `lib/core/offline/checkout_session.dart`, `lib/core/offline/local_cart.dart`
- الحساب/الطلبات: `lib/features/account/account_screens.dart`
- المصادقة: `lib/core/auth/token_vault.dart`, `lib/core/api/customer_api.dart`, `lib/core/otp_resend.dart`, `lib/features/auth/auth_screens.dart`
- الإشعارات/الدفع: `lib/features/notifications/notifications_screen.dart`, `lib/core/notification_read.dart`, `lib/core/push_notifications.dart`, `lib/main.dart`
- التصفح/البحث: `lib/features/products/products_screens.dart`, `lib/features/home/home_screen.dart`, `lib/features/more/more_screens.dart`, `lib/features/haraj/haraj_screens.dart`
- الإعداد/المنصات: `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts`, `ios/Runner/Info.plist`
- الاختبارات: `test/cart_navigation_test.dart`, `test/offline_verification_fixes_test.dart`, `test/offline_real_backend_test.dart`
