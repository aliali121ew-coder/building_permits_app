-- =====================================================================
-- Migration 04: تصلبة أمان قاعدة البيانات (معالجة تحذيرات Supabase Linter)
-- Security hardening: fix mutable search_path + lock down function EXECUTE grants
-- =====================================================================
-- كل ما يلي تحذيرات (WARN) وليست أعطالاً؛ التطبيق يعمل، والبيانات سليمة.
-- هذا الملف Idempotent (آمن لإعادة التشغيل). شغّله من:
-- Supabase Dashboard > SQL Editor > New Query > Run.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) تثبيت search_path للدوال المُبلّغ عنها (يمنع اختطاف مسار البحث)
--    الدوال الأخرى (licensing v2) تملك search_path مثبّتاً أصلاً.
-- ---------------------------------------------------------------------
alter function public.set_updated_at()            set search_path = public;
alter function public.log_permit_change()          set search_path = public;
alter function public.next_permit_number(integer)  set search_path = public;

-- ---------------------------------------------------------------------
-- 2) دوال المشغّلات (Triggers) — يجب ألا تُستدعى عبر REST إطلاقاً
--    نسحب صلاحية التنفيذ من الجميع (تعمل ضمن المشغّل بلا حاجة لصلاحية RPC).
-- ---------------------------------------------------------------------
revoke all on function public.set_updated_at()    from public, anon, authenticated;
revoke all on function public.log_permit_change()  from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) دوال SECURITY DEFINER — سحب صلاحية anon/public، وإبقاء authenticated فقط
--    (النمط: REVOKE من public+anon ثم GRANT لـ authenticated حيث يحتاجها التطبيق)
--    ملاحظة: كل دوال الإدارة تتحقق داخلياً من is_licensing_admin() فتبقى آمنة.
-- ---------------------------------------------------------------------

-- توليد رقم الإجازة (يُستدعى من التطبيق)
revoke all on function public.next_permit_number(integer) from public, anon;
grant execute on function public.next_permit_number(integer) to authenticated;

-- التحقق من صلاحية المدير (تُستخدم داخل بقية الدوال)
revoke all on function public.is_licensing_admin() from public, anon;
grant execute on function public.is_licensing_admin() to authenticated;

-- تفعيل الحساب بالكود
revoke all on function public.consume_activation_code(text) from public, anon;
grant execute on function public.consume_activation_code(text) to authenticated;

-- تسجيل الجهاز الحالي
revoke all on function public.register_current_device(text, text, text) from public, anon;
grant execute on function public.register_current_device(text, text, text) to authenticated;

-- الموافقة على الحساب (أدمن)
revoke all on function public.admin_approve_account(uuid) from public, anon;
grant execute on function public.admin_approve_account(uuid) to authenticated;

-- إيقاف/استئناف الترخيص (أدمن)
revoke all on function public.admin_set_license_paused(uuid, boolean) from public, anon;
grant execute on function public.admin_set_license_paused(uuid, boolean) to authenticated;

-- توليد كود تفعيل (أدمن)
revoke all on function public.admin_create_activation_code(text, integer, text) from public, anon;
grant execute on function public.admin_create_activation_code(text, integer, text) to authenticated;

-- حذف جهاز مرتبط (أدمن)
revoke all on function public.admin_remove_device(uuid) from public, anon;
grant execute on function public.admin_remove_device(uuid) to authenticated;

-- الموافقة على الترخيص لمدة محددة (أدمن) — إن كانت هذه الدالة موجودة لديك
do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'admin_approve_license'
  ) then
    execute 'revoke all on function public.admin_approve_license(uuid, integer) from public, anon';
    execute 'grant execute on function public.admin_approve_license(uuid, integer) to authenticated';
    execute 'alter function public.admin_approve_license(uuid, integer) set search_path = public';
  end if;
end $$;

-- =====================================================================
-- 4) التحقّق بعد التطبيق (شغّلها للتأكّد أن anon لم يعد يملك صلاحية التنفيذ)
-- =====================================================================
-- select p.proname,
--        has_function_privilege('anon',  p.oid, 'execute')          as anon_can,
--        has_function_privilege('authenticated', p.oid, 'execute')  as auth_can
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public'
--    and p.proname in ('set_updated_at','log_permit_change','next_permit_number',
--                      'is_licensing_admin','consume_activation_code','register_current_device',
--                      'admin_approve_account','admin_set_license_paused',
--                      'admin_create_activation_code','admin_remove_device','admin_approve_license')
--  order by p.proname;
-- المتوقّع: anon_can = false للجميع؛ auth_can = true عدا دالتي المشغّلات.

-- =====================================================================
-- 5) تحذير أخير (إعداد لوحة تحكم — ليس SQL):
--    "Leaked Password Protection" — فعّله يدوياً من:
--    Supabase Dashboard > Authentication > Policies/Providers > Password
--    > Enable "Leaked password protection" (فحص HaveIBeenPwned).
-- =====================================================================
