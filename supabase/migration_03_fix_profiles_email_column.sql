-- =====================================================================
-- Migration 03: إصلاح خطأ تسجيل الدخول PGRST204 (عمود email مفقود)
-- Fix: Could not find the 'email' column of 'profiles' in the schema cache
-- =====================================================================
-- السبب المؤكّد (بعد فحص قاعدة البيانات مباشرةً):
--   عمود public.profiles.email غير موجود فعلاً (خطأ 42703)، بينما
--   activated_code وبقية أعمدة التراخيص موجودة. أي أن القسم 8 من
--   migration.sql توقّف بين السطرين، فنجح activated_code وفشل email.
--
--   التطبيق ينهار لأن UserModel.toSupabaseMap() يُرسل مفتاح 'email' عند
--   إنشاء/تحديث الملف الشخصي (createProfile) في التسجيل وأول تسجيل دخول،
--   وPostgREST يرفض المفتاح لعدم وجود العمود في مخطط الجدول.
--
-- هذا الملف آمن لإعادة التشغيل (Idempotent) ولا يحذف أي بيانات.
-- شغّله من: Supabase Dashboard > SQL Editor > New Query.
-- (مستقلّ تماماً عن migration_02 الخاص بصلاحيات الكتابة RLS.)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) إضافة العمود المفقود (الإصلاح الأساسي)
--    'if not exists' يجعله آمناً حتى لو كان موجوداً في بيئة أخرى.
-- ---------------------------------------------------------------------
alter table public.profiles add column if not exists email text;

-- تأمين إضافي: هذا العمود موجود لديك بالفعل، لكن نبقيه للاكتمال والأمان
-- (لن يفعل شيئاً إن كان موجوداً).
alter table public.profiles add column if not exists activated_code text;

comment on column public.profiles.email is 'بريد المستخدم (نسخة من auth.users.email لتسهيل العرض والفلترة)';

-- ---------------------------------------------------------------------
-- 2) (موصى به) تعبئة البريد للمستخدمين الحاليين من جدول auth.users
--    يعمل هنا لأن SQL Editor يُنفّذ كمالك يتجاوز RLS. يملأ الصفوف
--    التي بريدها فارغ أو غير مطابق فقط.
-- ---------------------------------------------------------------------
update public.profiles p
   set email = u.email
  from auth.users u
 where u.id = p.id
   and (p.email is null or p.email is distinct from u.email);

-- ---------------------------------------------------------------------
-- 3) إعادة تحميل ذاكرة PostgREST المؤقتة فوراً
--    (Supabase يعيد التحميل تلقائياً بعد DDL عادةً، لكن هذا يضمن الفورية
--     ويُزيل رسالة "schema cache" نهائياً.)
-- ---------------------------------------------------------------------
notify pgrst, 'reload schema';

-- =====================================================================
-- 4) التحقّق بعد التطبيق (شغّل هذه الاستعلامات للتأكّد)
-- =====================================================================
-- (أ) تأكيد وجود العمود الآن:
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public' and table_name = 'profiles'
   and column_name in ('email', 'activated_code')
 order by column_name;

-- (ب) استعراض المستخدمين مع بريدهم بعد التعبئة:
-- select id, full_name, email, approval_status, is_active
--   from public.profiles order by created_at;
-- =====================================================================
