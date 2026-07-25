# توقيع تطبيق أندرويد (Android Signing)

لكي تعمل **تحديثات APK** (يُثبَّت الإصدار الجديد فوق القديم)، يجب توقيع **كل** الإصدارات
بنفس المفتاح (keystore). بدون ذلك يرفض أندرويد التثبيت برسالة تعارض توقيع.

يتم هذا **مرة واحدة** فقط، ثم كل `flutter build apk --release` يوقّع تلقائياً.

## 1) أنشئ مفتاح التوقيع (مرة واحدة)
```bash
keytool -genkey -v -keystore permits-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias permits
```
- احفظ الملف `permits-release.jks` في مكان آمن **خارج المستودع** (مثل `C:/Users/اسمك/keys/`).
- ⚠️ **احتفظ بنسخة احتياطية منه ومن كلمات السر** — فقدانه يعني عدم القدرة على إصدار تحديثات مستقبلاً.

## 2) أنشئ ملف `android/key.properties`
انسخ `android/key.properties.example` إلى `android/key.properties` واملأ القيم:
```properties
storePassword=كلمة_سر_المخزن
keyPassword=كلمة_سر_المفتاح
keyAlias=permits
storeFile=C:/Users/اسمك/keys/permits-release.jks
```
> استخدم `/` في المسار حتى على ويندوز. الملف **مُستبعد من Git** فلن يُرفع.

## 3) ابنِ الإصدار
```bash
flutter build apk --release
```
سيُوقَّع تلقائياً بمفتاحك. الناتج: `build/app/outputs/flutter-apk/app-release.apk`.

## كيف يعمل الإعداد؟
في `android/app/build.gradle.kts`:
- إن وُجد `key.properties` → يُستخدم مفتاح الإصدار (release).
- إن لم يوجد (مثلاً على جهاز مطوّر آخر بلا مفتاح) → يعود لمفتاح debug تلقائياً حتى لا يتعطّل البناء.

## ملاحظات أمان
- لا تُشارك `key.properties` ولا ملف `.jks` مع أحد ولا ترفعهما إلى Git.
- استخدم نفس المفتاح لكل الإصدارات القادمة.
