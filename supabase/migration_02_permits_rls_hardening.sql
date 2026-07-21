-- =====================================================================
-- Migration 02: إحكام سياسات RLS لجدول الإجازات (permits)
-- Building Permits – Server-Side License Enforcement for permits RLS
-- =====================================================================
-- الهدف من هذا الملف:
--   1) وقف الثغرة التي تسمح لأي مستخدم (is_active=true) بالكتابة على جدول
--      permits مباشرةً عبر الـ API متجاوزاً حاجز الواجهة، حتى لو كان حسابه
--      قيد الانتظار (pending) أو موقوفاً (suspended) أو منتهي الترخيص.
--   2) نقل التحقق من "صلاحية الترخيص" إلى الخادم (بدل الاعتماد على الواجهة).
--   3) جعل إيقاف الترخيص (admin_set_license_paused) يضبط is_active=false
--      ليُلغي صلاحية الكتابة فعلياً على مستوى قاعدة البيانات.
--
-- الملف Idempotent (آمن لإعادة التشغيل) ولا يغيّر سلوك القراءة (SELECT).
-- شغّله بعد schema.sql و migration.sql من: Supabase Dashboard > SQL Editor.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) دالة مركزية تُقرّر صلاحية الكتابة على الإجازات (تعمل على الخادم)
--    تطابق منطق UserModel.isLicenseActive في التطبيق تماماً:
--      - المدير (role='admin')           => مسموح دائماً
--      - الموظف                          => نشط + مقبول + غير موقوف + ترخيص ساري
--    SECURITY DEFINER: تقرأ ملف المستخدم بغضّ النظر عن سياسات profiles،
--    وتستخدم وقت الخادم now() فلا يستطيع العميل تزوير انتهاء الترخيص.
-- ---------------------------------------------------------------------
create or replace function public.can_write_permits()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and (
        p.role = 'admin'
        or (
              p.is_active            = true
          and p.approval_status      = 'approved'
          and coalesce(p.license_paused, false) = false
          and p.license_end_at is not null
          and now() < p.license_end_at
        )
      )
  );
$$;

comment on function public.can_write_permits() is
  'true إذا كان المستخدم الحالي مديراً، أو موظفاً نشطاً ومقبولاً بترخيص ساري وغير موقوف. تُستخدم في سياسات RLS للكتابة على permits.';

revoke all on function public.can_write_permits() from public;
grant execute on function public.can_write_permits() to authenticated;

-- ---------------------------------------------------------------------
-- 2) إعادة بناء سياسات الكتابة على permits لتستخدم الدالة الجديدة
--    نُسقط السياسات القديمة (التي تفحص is_active فقط) بأسمائها الأصلية،
--    ثم ننشئ بدائل مقيّدة على دور authenticated.
--    ملاحظة: سياسة القراءة (SELECT using(true)) تبقى كما هي عمداً حتى لا
--    تتعطّل المزامنة/العرض؛ الإحكام هنا على الكتابة فقط (INSERT/UPDATE).
--    الحذف الفعلي (DELETE) يبقى للمدير فقط كما هو (لم يُمَسّ).
-- ---------------------------------------------------------------------

-- INSERT
drop policy if exists "الموظفون النشطون يضيفون إجازات" on public.permits;
drop policy if exists "permits_insert_licensed"        on public.permits;
create policy "permits_insert_licensed" on public.permits
  for insert
  to authenticated
  with check (public.can_write_permits());

-- UPDATE (يشمل الحذف المنطقي is_deleted=true لأنه تحديث)
--   using      => أي الصفوف يُسمح باختيارها للتعديل
--   with check => قيمة الصف بعد التعديل يجب أن تبقى ضمن الصلاحية
drop policy if exists "الموظفون النشطون يعدّلون الإجازات" on public.permits;
drop policy if exists "permits_update_licensed"          on public.permits;
create policy "permits_update_licensed" on public.permits
  for update
  to authenticated
  using      (public.can_write_permits())
  with check (public.can_write_permits());

-- ---------------------------------------------------------------------
-- 3) إصلاح admin_set_license_paused: ضبط is_active عند الإيقاف/الاستئناف
--    - عند الإيقاف  (p_paused=true) : approval_status='suspended' + is_active=false
--    - عند الاستئناف(p_paused=false): approval_status='approved'  + is_active=true
--    هذا يغلق الثغرة نهائياً حتى لو أُعيدت سياسات قديمة مستقبلاً (دفاع بالطبقات)،
--    ويطابق سلوك التطبيق عند الإيقاف.
-- ---------------------------------------------------------------------
create or replace function public.admin_set_license_paused(p_user_id uuid, p_paused boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  seconds_left integer;
begin
  if not public.is_licensing_admin() then
    raise exception 'غير مصرح بإدارة التراخيص';
  end if;

  if p_paused then
    -- خزّن الوقت المتبقّي (بالثواني) لاستئنافه لاحقاً بدقّة
    select greatest(0, extract(epoch from license_end_at - now())::integer)
      into seconds_left
      from public.profiles
     where id = p_user_id
       for update;

    update public.profiles
       set approval_status             = 'suspended',
           is_active                   = false,   -- ← جديد: يمنع الكتابة على مستوى قاعدة البيانات
           license_paused              = true,
           license_paused_seconds_left = coalesce(seconds_left, 0),
           last_paused_at              = now()
     where id = p_user_id;
    if not found then raise exception 'الحساب غير موجود'; end if;

    insert into public.notifications(user_id, title, message)
    values (p_user_id, 'تم إيقاف الترخيص', 'تم إيقاف ترخيص حسابك مؤقتاً من قبل الإدارة.');

  else
    -- استئناف: أعِد المدة المتبقّية المخزّنة إلى نهاية ترخيص جديدة من الآن
    select coalesce(license_paused_seconds_left, 0)
      into seconds_left
      from public.profiles
     where id = p_user_id
       for update;

    update public.profiles
       set approval_status             = 'approved',
           is_active                   = true,    -- ← جديد: يعيد صلاحية الكتابة عند الاستئناف
           license_paused              = false,
           license_end_at              = now() + make_interval(secs => seconds_left),
           license_paused_seconds_left = null,
           last_paused_at              = null
     where id = p_user_id;
    if not found then raise exception 'الحساب غير موجود'; end if;

    insert into public.notifications(user_id, title, message)
    values (p_user_id, 'تم استئناف الترخيص', 'تم استئناف ترخيص حسابك.');
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 4) (اختياري لكنه موصى به) إحكام رفع المرفقات بنفس البوابة
--    السياسة القديمة كانت تفحص is_active فقط؛ نجعلها تتطلّب can_write_permits()
--    حتى لا يرفع مستخدمٌ موقوف/منتهي الترخيص ملفات إلى دلو الإجازات.
--    (قراءة المرفقات تبقى كما هي لعدم كسر عرض الصور للمستخدمين النشطين.)
-- ---------------------------------------------------------------------
drop policy if exists "الموظفون النشطون يرفعون مرفقات"    on storage.objects;
drop policy if exists "permit_attachments_insert_licensed" on storage.objects;
create policy "permit_attachments_insert_licensed" on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'permit-attachments'
    and public.can_write_permits()
  );

-- =====================================================================
-- 5) التحقّق بعد التطبيق (شغّل هذه الاستعلامات يدوياً للتأكّد — معطّلة كتعليق)
-- =====================================================================
-- -- (أ) عرض سياسات permits الحالية:
-- select policyname, cmd, qual, with_check
--   from pg_policies where schemaname='public' and tablename='permits' order by cmd;
--
-- -- (ب) اختبار الدالة بانتحال هوية مستخدم موقوف (استبدل UUID):
-- --     يجب أن تُرجع false لمستخدم pending/suspended/منتهي، و true لنشط مرخّص/مدير.
-- select public.can_write_permits();  -- ضمن جلسة المستخدم نفسه عبر التطبيق
--
-- -- (ج) التأكد أن الإيقاف يضبط is_active=false:
-- select id, approval_status, is_active, license_paused, license_end_at
--   from public.profiles where id = '<USER_UUID>';
-- =====================================================================
