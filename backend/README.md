# خادم Cloudflare Workers المتكامل لتطبيق إجازات البناء

تم بناء هذا الخادم كبديل كامل ومستقل عن **Supabase** بالاعتماد كلياً على بيئة **Cloudflare Edge**:
- **قاعدة البيانات**: Cloudflare D1 (SQLite سريعة وموزعة عالمياً).
- **تخزين الملفات**: Cloudflare R2 (متوافق مع S3 وبدون أي رسوم باندويث).
- **إطار العمل**: Hono TypeScript (سريع جداً وخفيف).
- **المصادقة والأمان**: JWT مشفر بـ Web Crypto API المدمجة.

---

## خطوات التشغيل والنشر (في 3 دقائق)

### 1) الانتقال لمجلد الخادم وتثبيت الحزم
افتح موجه الأوامر (PowerShell أو Terminal) واكتب:
```bash
cd backend
npm install
```

### 2) تسجيل الدخول إلى Cloudflare
```bash
npx wrangler login
```

### 3) إنشاء قاعدة بيانات D1 و دلو التخزين R2
```bash
# إنشاء قاعدة بيانات D1
npx wrangler d1 create permits-db

# إنشاء دلو R2 لتخزين المرفقات
npx wrangler r2 bucket create permit-attachments
```
> انسخ قيمة `database_id` التي ستظهر لك في الشاشة وضعها داخل ملف `wrangler.toml` بدلاً من `YOUR_D1_DATABASE_ID_HERE`.

### 4) تطبيق مخطط الجداول على قاعدة البيانات
```bash
npx wrangler d1 execute permits-db --remote --file=./schema.sql
```

### 5) نشر الخادم فوراً (Deploy)
```bash
npm run deploy
```
ستحصل على رابط خادمك العام (مثال: `https://building-permits-backend.yoursubdomain.workers.dev`).
ضعه في تطبيق Flutter في `lib/core/constants/app_constants.dart`!

