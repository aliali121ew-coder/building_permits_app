-- =====================================================================
-- Migration 05: جدول تحديثات التطبيق (In-App Update)
-- =====================================================================
-- يخزّن أحدث إصدار متاح لكل منصّة؛ يقرؤه التطبيق ليعرض إشعار التحديث.
-- شغّله من: Supabase Dashboard > SQL Editor > New Query > Run.
-- =====================================================================

create table if not exists public.app_updates (
  id uuid primary key default uuid_generate_v4(),
  platform text not null check (platform in ('android', 'windows')),
  latest_version text not null,          -- ما يراه المستخدم، مثل 1.0.1
  latest_build integer not null,          -- رقم البناء (يقارنه التطبيق)
  download_url text not null default '',  -- رابط ملف APK/المثبّت (Supabase Storage)
  release_notes text,                      -- ملاحظات الإصدار (تظهر في نافذة التحديث)
  mandatory boolean not null default false,-- تحديث إجباري؟
  updated_at timestamptz not null default now(),
  unique (platform)
);

comment on table public.app_updates is 'أحدث إصدار متاح لكل منصّة لفحص التحديث داخل التطبيق';

alter table public.app_updates enable row level security;

-- القراءة متاحة للجميع (التطبيق يفحص التحديث)
drop policy if exists "قراءة تحديثات التطبيق للجميع" on public.app_updates;
create policy "قراءة تحديثات التطبيق للجميع" on public.app_updates
  for select using (true);

-- الكتابة للمدير فقط
drop policy if exists "المدير فقط يعدّل تحديثات التطبيق" on public.app_updates;
create policy "المدير فقط يعدّل تحديثات التطبيق" on public.app_updates
  for all using (public.is_licensing_admin()) with check (public.is_licensing_admin());

-- بذرة أولية (رقم البناء = 1 مثل الإصدار الحالي؛ لن يظهر إشعار حتى ترفعه)
insert into public.app_updates (platform, latest_version, latest_build, download_url, release_notes, mandatory)
values
  ('android', '1.0.0', 1, '', 'الإصدار الأول', false),
  ('windows', '1.0.0', 1, '', 'الإصدار الأول', false)
on conflict (platform) do nothing;

notify pgrst, 'reload schema';

-- =====================================================================
-- كيفية إصدار تحديث لاحقاً:
--   1) ارفع ملف APK/المثبّت إلى Supabase Storage (bucket عام) واحصل على الرابط.
--   2) حدّث الصف:
--   update public.app_updates
--     set latest_version='1.0.1', latest_build=2,
--         download_url='https://.../permits-1.0.1.apk',
--         release_notes='إصلاحات وتحسينات', mandatory=false, updated_at=now()
--   where platform='android';
--   3) سيظهر إشعار التحديث تلقائياً لكل المستخدمين عند فتح التطبيق.
-- =====================================================================
