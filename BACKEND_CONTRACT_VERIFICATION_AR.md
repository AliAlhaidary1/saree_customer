# تقرير التحقق النهائي من عقد الواجهة الخلفية — SareeMart Customer

> **دور:** مراجع هندسي مستقل (Frontend/Backend Contract & Mobile Reliability).
> **تاريخ التحقق:** 2026-10-14
> **الواجهة الخلفية:** `D:\myproject\review\saree_back` — الفرع `main` (Laravel 8.83.29).
> **تطبيق العملاء:** `D:\myproject\review\saree_customer` — الفرع `prod/offline-reliability` (Flutter).
> **النطاق:** التحقق من مسارات العقد المستخدمة فعليًا من التطبيق: المفضلة، الدفع متعدد البائعين، ودمج سلة الضيف. الخارج عن ذلك (Laravel admin) خارج النطاق.

---

## 1. ملخص التوصية

**النتيجة: جاهز بشكل مشروط للاختبار المضبوط (CONDITIONALLY READY FOR CONTROLLED TESTING).**

- **عقد مسار المفضلة `favorites/remove`:** تم تأكيد وجود عيب حرج (حذف كل المفضلة) وإصلاحه مع اختبارات انحدار خضراء.
- **عقد الدفع متعدد البائعين:** تم التحقق من الصحة الوظيفية والذرّية (atomicity) بنجاح — لم يُعثر على خلل سلامة بيانات.
- **قيد معالجة التكرار (idempotency):** يعمل فعليًا عند إعادة المحاولة المتتالية، لكن هناك سلوك حدّي عند التزامن يُرجع رسالة خطأ خام.
- **دمج سلة الضيف:** الخادم **غير** idempotent — يوجد خطر تكرار بنود عند إعادة المحاولة/انتهاء المهلة.

**لا يمكن اعتماد "READY FOR RELEASE CANDIDATE"** لأن مجموعة اختبارات الواجهة الخلفية على `main` ليست خضراء (79 فشلًا سابقًا/قائمًا مستقلًا عن تغييراتي)، وتوجد مخاطر متبقية في مسار السلة والسجل. تُوصى دورة اختبار مضبوط على بيئة CI/staging مطابقة قبل أي إصدار.

---

## 2. منهجية التحقق

- قراءة الشيفرة الفعلية على الفرع الحالي (لا الاعتماد على تقارير سابقة).
- تشغيل مجموعة الاختبارات الكاملة على بيئة اختبار معزولة (`sqlite :memory:` عبر `phpunit.xml`).
- إنشاء **خط أساس (baseline)** بمقارنة الشجرة قبل/بعد تغييراتي لإثبات عدم إدخال انحدارات.
- اختبارات انحدار مخصّصة لكل عيب خلفي تم إصلاحه.
- لم يُلمس أي بيانات إنتاج، ولم يُنفّذ أي أمر نشر أو دفع (push).

**بيئة التنفيذ (قيد مهم):** `php` غير موجود على `PATH`. استُخدم `D:\xampp\php\php.exe` (PHP 8.2.4) مع تصحيح `extension_dir` (الملف `php.ini` يشير خطأً إلى `C:\xampp\php\ext`). شُغّل PHPUnit مباشرة:
`php -n -d memory_limit=1536M -d extension_dir="D:\xampp\php\ext" -d extension=<set> vendor\phpunit\phpunit\phpunit`
هذا قد يختلف عن بيئة CI (نسخة PHP، الامتدادات). Docker غير متاح (الخادم غير مشغّل).

---

## 3. التحقق من عقد عزل المفضلة (Task 1) — إصلاح مؤكد

### 3.1 السبب الجذري

في `app/Http/Controllers/API/Customer/BasicApiController.php::removeFromFavorite`:

```php
$favorite = Favorite::where('user_id', auth()->user()->id);
if (isset($request->product_id)) {
    $favorite->where('product_id', $request->product_id)->first(); // النتيجة مُهمَلة!
    ...
}
```

استُدعي `first()` ثم أُهمِلت نتيجته، فأُكمل العمل على كائن الاستعلام (Query Builder) لا على صف واحد. عندها `$favorite->delete()` ينفّذ `DELETE ... WHERE user_id = ?` على **كل** مفضلة المستخدم بدلًا من المنتج المطلوب.

### 3.2 الإصلاح

- فرع المنتج الواحد: جلب الصف عبر `first()` ثم حذفه، مع التحقق من قيم `product_id` الفارغة.
- فرع "حذف الكل": عدّ صفوف المستخدم ثم `Favorite::where('user_id', $userId)->delete()` (مقيّد بمعرّف المستخدم فقط).

### 3.3 اختبارات الانحدار

ملف جديد: `tests/Feature/FavoriteRemovalTest.php` — **5 اختبارات / 70 تأكيدًا، كلها خضراء**:
حذف منتج واحد يُبقي البقية، العزل بين المستخدمين، خطأ عند منتج غير موجود في المفضلة، تكرار الحذف آمن، و"حذف الكل بدون product_id" يؤثر على المستخدم المُصادق فقط.

---

## 4. التحقق من الدفع متعدد البائعين والجرد (Task 2)

### 4.1 الصحة الوظيفية

- مسار HTTP الكامل `/customer/checkout` ينشئ **طلبات بائع منفصلة** لكل بائع: اختبار `CommerceCoreFeatureTest::test_multi_seller_checkout_creates_separate_seller_orders` ينجح.
- حدود البائعين: `CheckoutMultiSellerTest` بالكامل (**14 اختبارًا / 51 تأكيدًا، خضراء**) بما فيها اختبار قيد `maximum_sellers_exceeded`.

### 4.2 الذرّية والسلامة الجردية (`CheckoutService` + `InventoryService`)

- الدفع معلَّف في **معاملة واحدة** (`DB::transaction`): إنشاء جلسة `processing` → حجز الجرد → `CheckoutGroup` → طلبات/بنود البائعين → الدفع → `commit` للجرد → تفريغ السلة → تعليم الجلسة `completed`. أي فشل في الدفع يردّ كل شيء بما فيه خصم الجرد.
- `InventoryService::reserveForCheckout` يستخدم `lockForUpdate()` على صف الـ variant، ويحسب `available = stock - reservedByOthers` (باستثناء رمز الحجز الحالي)، ويرمي خطأ أعمال عند عدم كفاية المخزون. الحجز لا يخصم المخزون؛ الخصم يحدث في `commit` فقط، لذا `release/expire` لا يحتاج استرجاعًا (تصميم صحيح).
- اختبار `CommerceCoreFeatureTest::test_concurrent_checkout_on_last_stock_unit_only_one_succeeds` ينجح.
- **قيد بيئي مهم:** `lockForUpdate()` **لا أثر له على SQLite**، لذا اختبارات التزامن في `:memory:` لا تُثبت قفل الصف فعليًا؛ السلامة التزامنية تعتمد على قاعدة الإنتاج (MySQL/Postgres). يجب تأكيد ذلك في CI على نفس نوع قاعدة الإنتاج.

### 4.3 معالجة التكرار (Idempotency)

- يوجد فهرس فريد `(user_id, idempotency_key)` في `checkout_sessions`، والفحص المسبق يعيد الطلب المكتمل عند إعادة المحاولة المتتالية (سلوك سليم).
- **سلوك حدّي عند التزامن بنفس المفتاح:** يقع تعارض الفهرس الفريد → `QueryException` (يمتد من `PDOException` ← `RuntimeException`) فيلتقطه `catch (\RuntimeException)` في المتحكم ويُرجع **رسالة الخطأ الخام** — احتمال كشف معلومات + تجربة خطأ رديئة (ليس خلل سلامة بيانات). التوصية: التمييز بين استثناء تعارض التكرار واستثناء الأعمال، وإرجاع الطلب القائم عند التعارض.

---

## 5. تحليل دمج سلة الضيف / `bulkAddToCartItems` (Task 3)

- الخادم `BulkAddToCartItems` **غير idempotent**: البنود القائمة تُحدَّث (SET qty)، والجديدة تُدرَج بعد فحص `isItemAvailableInUserCart` (حالة سباق TOCTOU)، ولا يوجد مفتاح idempotency.
- تطبيق Flutter: `_mergeGuestCartOnLogin` (`lib/core/app_controller.dart` ~1027–1041) يستدعي `bulkAddToCart` **مرة واحدة** عند تسجيل الدخول؛ عند الفشل يُبقي سلة الضيف ولا يُدرج إعادة محاولة. و`runPendingOp` يستنزف عمليات `guestCartMerge` دون استدعاء الـ API مجددًا (~1403).
- **الخطر المتبقي:** إذا انتهت مهلة الاستدعاء الواحد بعد أن عالجه الخادم فعلًا، فإن تسجيل دخول لاحق يُعيد محاولة دمج غير موثوقة على خادم غير idempotent → احتمال **بنود مكرّرة**.
- **التوصية:** إمّا upsert/مفتاح idempotency على الخادم، أو تُ reconciles العميل سلة الخادم قبل إعادة المحاولة.

---

## 6. نتائج الاختبارات الفعلية

### 6.1 الواجهة الخلفية — مجموعة كاملة (442 اختبارًا)

مقارنة خط الأساس (HEAD `main` قبل تغييراتي) بالمخرجات بعد الإصلاح:

| الاختبار | خط الأساس | الحالي |
|---|---:|---:|
| ApiEndpointTest | 29 | 28 |
| CheckoutMultiSellerTest | 1 | **0** |
| CheckoutServiceFeatureTest | 1 | 1 |
| CommerceAuthorizationTest | 2 | 2 |
| CommerceCoreFeatureTest | 17 | **10** |
| CommerceLifecycleFlowTest | 11 | **3** |
| CustomerRatingAffordanceTest | 1 | 1 |
| FavoriteRemovalTest | 3 | **0** |
| FinancialArchitectureTest | 2 | 2 |
| PromotionOffersTest | 4 | 4 |
| RankingIntegrationTest | 15 | 15 |
| ReturnRefundServiceTest | 1 | 1 |
| SellerReceivableTest | 6 | 6 |
| CustomerOrderStatusPresenterTest (Unit) | 6 | 6 |
| **الإجمالي الفاشل** | **99** | **79** |

- الإجمالي الحالي: `Tests: 442, Assertions: 1558, Errors: 11, Failures: 68`.
- **لا يوجد أي صنف زاد عدد فشله** → تغييراتي أدخلت **صفر انحدارات**، وحسّنت 20 فشلًا.
- الفشل الـ79 الـمتبقي **سابق لعملي** (على `main`) وخارج نطاق العقد: انحراف نطاقات مصادقة في الاختبارات (رموز admin بدون نطاق `admin` → رفض `token.audience`)، واختبار Unit يلمس جدولًا غير مُهاجَر (`order_items`)، وعدم تطابق قيم رقميّة في SellerReceivable/RankingIntegration/ReturnRefund. تحتاج فرزًا في CI (ليست بالضرورة عيوب منتج).

### 6.2 اختبارات الهدف (عقد المفضلة + الدفع متعدد البائعين)

`--filter "FavoriteRemovalTest|CheckoutMultiSellerTest"` → **OK (19 اختبارًا، 70 تأكيدًا)**.

### 6.3 تطبيق العملاء (Flutter)

| الفحص | النتيجة |
|---|---|
| `flutter test --no-pub` | **39 ناجحًا، 0 فاشل** |
| `flutter analyze --no-pub` | 148 ملاحظة (`info`) — **0 أخطاء** |

---

## 7. الملفات المتغيرة + اختبارات الانحدار

**الواجهة الخلفية (تغييرات ضيّقة، مبرَّرة):**
- `app/Http/Controllers/API/Customer/BasicApiController.php` — إصلاح `removeFromFavorite` (العيب الحرج).
- `tests/Feature/FavoriteRemovalTest.php` — **جديد**: اختبارات انحدار المفضلة (5).
- `tests/SeedsCommerceFixtures.php` — `checkoutAsUser` يستخدم النطاق `['customer']` (كان `[]` فيرفضه middleware الواجهة).
- `tests/Feature/CheckoutMultiSellerTest.php` — تصحيح تأكيد الترجمة `__('maximum_sellers_exceeded', ...)` (كان مفتاحًا خامًا يفشل دائمًا بسبب `APP_LOCALE=ar`).

**تطبيق العملاء (سابق، ضمن نطاق الموثوقية):**
- `lib/core/offline/checkout_session.dart` — إصلاح توليد مفتاح idempotency (كان `millisecondsSinceEpoch` → تصادم خلال نفس المللي ثانية؛ أصبح `microsecondsSinceEpoch` + entropy).
- ملفات الموثوقية/عدم الاتصال الأخرى (راجع `ENGINEERING_REPORT_AR.md`).

> لم يُنفّذ أي `commit`/`push`/نشر.

---

## 8. المخاطر/الحواجز المتبقية قبل الإصدار

1. **مجموعة اختبارات الواجهة الخلفية ليست خضراء (79 فشلًا قائمًا)** — يجب فرزها وتشغيلها في بيئة CI مطابقة (نوع قاعدة بيانات الإنتاج) قبل قبول الإصدار.
2. **قفل الصفوف غير مُثبَت في اختبارات SQLite** (`lockForUpdate` لا أثر له) — يجب إثبات سلامة التزامن على قاعدة الإنتاج.
3. **سلوك التكرار المتزامن** يُرجع رسالة DB خام (كشف معلومات) — يحتاج تحسين معالجة الاستثناء.
4. **دمج سلة الضيف غير idempotent** — خطر تكرار بنود عند إعادة المحاولة.
5. **اختلاف بيئة الاختبار** (PHP 8.2.4 + امتدادات يدوية) عن بيئة CI.

---

## 9. الخطوة المطلوبة قبل الاعتماد

1. تشغيل مجموعة الاختبارات الكاملة في CI على نفس إصدار PHP و**قاعدة بيانات الإنتاج**، وفرز 79 فشلًا (تمييز انحراف الاختبارات عن عيوب المنتج).
2. إصلاح معالجة التكرار المتزامن في الدفع، ومعالجة idempotency لدمج السلة.
3. إعادة اختبار تدفّق المفضلة على staging للتأكد من سلوك الحذف العازل بعد النشر.
