-- =====================================================================
-- استرجاع جدول الإجازات — إعادة تسمية permits_duplicate2 إلى permits
-- Recovery: rename permits_duplicate2 back to public.permits + restore structure
-- =====================================================================
-- السبب: عند حذف الجدول واستيراد الـ CSV/النسخ، صار الاسم permits_duplicate2،
-- فتعطّلت مزامنة التطبيق (يبحث عن public.permits).
-- هذا السكربت غير مُتلِف للبيانات (إعادة تسمية فقط) وIdempotent.
-- شغّله من: Supabase Dashboard > SQL Editor > New Query > Run.
-- =====================================================================

-- 1) إعادة تسمية الجدول إلى الاسم الصحيح
alter table if exists public.permits_duplicate2 rename to permits;

-- 2) التأكد من الإضافات والقيم الافتراضية للأعمدة الأساسية (احتياطاً)
create extension if not exists "uuid-ossp";
alter table public.permits alter column id set default uuid_generate_v4();

alter table public.permits add column if not exists notes text;
alter table public.permits add column if not exists permit_type text;
alter table public.permits add column if not exists name_change_notes text;
alter table public.permits add column if not exists plot_area numeric(12,2);
alter table public.permits add column if not exists building_area numeric(12,2);
alter table public.permits add column if not exists name_per_new_registry text;
alter table public.permits add column if not exists attachment_urls text[] default '{}';
alter table public.permits add column if not exists is_deleted boolean not null default false;
alter table public.permits add column if not exists duplicate_flag boolean not null default false;
alter table public.permits add column if not exists created_by uuid;
alter table public.permits add column if not exists created_at timestamptz not null default now();
alter table public.permits add column if not exists updated_by uuid;
alter table public.permits add column if not exists updated_at timestamptz not null default now();

-- 3) الفهارس
create index if not exists idx_permits_year        on public.permits(permit_year);
create index if not exists idx_permits_plot        on public.permits(plot_number);
create index if not exists idx_permits_date        on public.permits(permit_date);
create index if not exists idx_permits_not_deleted on public.permits(is_deleted) where is_deleted = false;
create index if not exists idx_permits_year_number on public.permits(permit_year, permit_number);

-- 4) المشغّلات (updated_at التلقائي + سجل التدقيق)
drop trigger if exists trg_permits_updated_at on public.permits;
create trigger trg_permits_updated_at
  before update on public.permits
  for each row execute function public.set_updated_at();

drop trigger if exists trg_permits_audit on public.permits;
create trigger trg_permits_audit
  after insert or update on public.permits
  for each row execute function public.log_permit_change();

-- 5) تفعيل RLS + السياسات (قراءة للجميع، إضافة/تعديل للنشطين، حذف فعلي للأدمن)
alter table public.permits enable row level security;

drop policy if exists "الجميع يقرأ الإجازات" on public.permits;
create policy "الجميع يقرأ الإجازات" on public.permits
  for select using (true);

drop policy if exists "الموظفون النشطون يضيفون إجازات" on public.permits;
drop policy if exists "permits_insert_licensed" on public.permits;
create policy "الموظفون النشطون يضيفون إجازات" on public.permits
  for insert with check (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_active = true)
  );

drop policy if exists "الموظفون النشطون يعدّلون الإجازات" on public.permits;
drop policy if exists "permits_update_licensed" on public.permits;
create policy "الموظفون النشطون يعدّلون الإجازات" on public.permits
  for update using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_active = true)
  );

drop policy if exists "الأدمن فقط يحذف حذفاً فعلياً" on public.permits;
create policy "الأدمن فقط يحذف حذفاً فعلياً" on public.permits
  for delete using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- 6) تفعيل Realtime على الجدول (مع تجاهل الخطأ إن كان مُضافاً)
do $$
begin
  alter publication supabase_realtime add table public.permits;
exception when duplicate_object then null;
end $$;

-- 7) إعادة تحميل ذاكرة الواجهة
notify pgrst, 'reload schema';

-- =====================================================================
-- 8) التحقّق بعد التشغيل
-- =====================================================================
select count(*) as total_permits from public.permits;
-- وتأكّد أن الجدول ظهر في القائمة باسم permits، ثم أعد تشغيل التطبيق.
