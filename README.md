# تطبيق عملاء سريع مارت

تطبيق Flutter لنظامي أندرويد وiOS يستهلك نفس واجهة `/customer` التي يستخدمها الموقع في `saree_front`.

## المتطلبات

- Flutter 3.44 (مثبت على الجهاز الحالي في `/home/ali/flutter`)
- أندرويد SDK و JDK 17

## التشغيل

من محاكي أندرويد (الخادم المحلي على الجهاز المضيف):

```bash
cd /media/ali/805CB43B5CB42E322/myproject/review/saree_customer
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:8000
```

من هاتف حقيقي على نفس الشبكة، ضع IP جهازك بدل `10.0.2.2`، مثلاً:

```bash
flutter run --dart-define=API_URL=http://192.168.1.10:8000
```

للإنتاج:

```bash
flutter run --release --dart-define=API_URL=https://admin.marabmall.cloud
```

تأكد أن الباكند يعمل وأن `x-access-key` هو `903361` كما في الفرونت.

## ما يطابقه التطبيق من منطق الموقع

- تسجيل الدخول بالجوال وكلمة المرور، والتسجيل، واستعادة كلمة المرور بـ OTP
- مدينة واحدة تلقائياً / ضيف يختار المدينة / مسجّل يعتمد على العنوان
- سلة الضيف ثم دمجها بعد الدخول عبر `bulk_add_to_cart_items`
- بائع واحد في السلة (`one_seller_error_code`)
- سعر العرض: فلاش ثم promo ثم discounted ثم السعر الأصلي
- إتمام الشراء للمستخدم فقط (COD / المحفظة)
- حراج وأخدمني والعروض والمتاجر والطلبات والمفضلة والعناوين

## هيكل المشروع

```
lib/core/           الإعداد، API، المدينة، الأسعار، الحالة
lib/features/       الشاشات حسب الدور الوظيفي
assets/i18n/        نفس ملفات ar.json و en.json من الفرونت
```
