# دليل إعداد قاعدة بيانات Supabase — الترتيب الصحيح

نظام إدارة إجازات البناء / بلدية الهاشمية. شغّل الملفات **بالترتيب** التالي من:
**Supabase Dashboard ← SQL Editor ← New Query**. بعد كل ملف، شغّل استعلام «التحقّق» للتأكد قبل الانتقال للتالي.

> ⚠️ **أهم سبب للأخطاء:** في محرّر SQL، إن كان هناك **نص مُظلَّل (محدَّد)** فسيُنفَّذ الجزء المحدَّد فقط! تأكّد أن لا شيء محدَّد، والصق الملف **كاملاً** (انزل لآخر سطر للتأكيد)، ثم Run.

---

## 0) قبل البدء
- أنشئ مشروع Supabase جديد.
- انسخ **Project URL** و**publishable key** إلى:
  `lib/core/constants/app_constants.dart` (الحقلان `supabaseUrl` و`supabaseAnonKey`).

---

## 1) `schema.sql` — الأساس
يُنشئ: جداول `profiles` و`permits` و`permits_audit_log`، دالة `next_permit_number`، سجل التدقيق (Triggers)، سياسات RLS الأساسية، تفعيل Realtime، ودلو التخزين `permit-attachments`.

**تحقّق:**
```sql
select tablename from pg_tables where schemaname='public' order by 1;
-- متوقّع: permits, permits_audit_log, profiles
select id from storage.buckets;   -- متوقّع: permit-attachments
```

## 2) `migration.sql` — نظام التراخيص (v2)
يُضيف أعمدة التراخيص إلى `profiles` (ومنها **`email`** و`activated_code`)، وجداول `activation_codes` و`user_devices` و`notifications`، ودوال `security definer` الآمنة (تفعيل/موافقة/إيقاف/تسجيل جهاز)، وسياسات RLS المحكمة.

**تحقّق (مهم جداً — هنا يُضاف عمود `email`):**
```sql
select column_name from information_schema.columns
 where table_schema='public' and table_name='profiles'
   and column_name in ('email','activated_code','approval_status');
-- متوقّع: 3 صفوف. إن نقص 'email' فالملف لم يُشغَّل كاملاً → صحّحه بالخطوة 4.
select proname from pg_proc
 where proname in ('consume_activation_code','admin_approve_account','is_licensing_admin');
-- متوقّع: 3 دوال
```

## 3) `migration_02_permits_rls_hardening.sql` — إحكام صلاحيات الكتابة
ينقل التحقق من صلاحية الترخيص إلى الخادم عبر `can_write_permits()`، ويعيد بناء سياسات الكتابة على `permits`، ويجعل الإيقاف يضبط `is_active=false`.
> يعتمد على الخطوتين 1 و2 (يستخدم أعمدة التراخيص و`is_licensing_admin`)، فلا تشغّله قبلهما.

**تحقّق:**
```sql
select policyname, cmd from pg_policies
 where schemaname='public' and tablename='permits' order by cmd;
-- متوقّع ضمنها: permits_insert_licensed, permits_update_licensed
```

## 4) `migration_03_fix_profiles_email_column.sql` — شبكة أمان لعمود `email`
يضيف عمود `email` **إن كان مفقوداً** (idempotent — آمن حتى لو كان موجوداً) ويعيد تحميل ذاكرة PostgREST. شغّله دائماً كخطوة أخيرة لضمان عدم تكرار خطأ `PGRST204`.

**تحقّق:**
```sql
select column_name from information_schema.columns
 where table_schema='public' and table_name='profiles' and column_name='email';
-- متوقّع: صف واحد (email)
```

---

## 5) ترقية أول مستخدم إلى مدير (Bootstrap)
دوال الإدارة تتطلّب `role='admin'` في قاعدة البيانات. بعد إنشاء أول حساب (عبر شاشة «إنشاء حساب» في التطبيق أو Auth ← Add user):
```sql
update public.profiles
   set role='admin', approval_status='approved', is_active=true,
       license_start_at=now(), license_end_at=now()+interval '100 years'
 where email='see313see@gmail.com';   -- أو: where id='<USER_UUID>'
```

## 6) اختبار نهائي سريع
1. أنشئ حساباً جديداً من التطبيق → يجب أن يعمل بلا خطأ `email` (يظهر أنه «قيد الموافقة»).
2. من حساب المدير: وافق على الحساب وأنشئ كود تفعيل.
3. فعّل الحساب بالكود → يجب أن يتحوّل إلى «مُفعّل».

---

## ملخص الترتيب
```
schema.sql  →  migration.sql  →  migration_02_permits_rls_hardening.sql  →  migration_03_fix_profiles_email_column.sql  →  (ترقية المدير)
```

## نصائح تجنّب الأخطاء
- شغّل كل ملف **مرة واحدة كاملاً**؛ كل الملفات idempotent وآمنة لإعادة التشغيل.
- لا تُظلّل نصاً داخل المحرّر (يُنفَّذ المحدَّد فقط).
- اقرأ رسالة النتيجة بعد كل تشغيل: «Success» أو خطأ صريح — لا تتجاهلها.
- على مشروع **جديد** يُشغَّل كامل `migration.sql`، فيكون `migration_03` مجرد تأكيد (لن يغيّر شيئاً).
