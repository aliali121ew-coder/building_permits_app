-- =====================================================================
-- نظام إدارة إجازات البناء - مخطط قاعدة بيانات Supabase
-- Building Permits Management System - Supabase Schema
-- =====================================================================
-- شغّل هذا الملف كاملاً من: Supabase Dashboard > SQL Editor > New Query
-- =====================================================================

-- تفعيل الإضافات المطلوبة
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- =====================================================================
-- 1) جدول ملفات تعريف المستخدمين (يمتد من auth.users)
-- =====================================================================
create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    full_name text not null,
    role text not null default 'employee' check (role in ('admin', 'employee')),
    is_active boolean not null default true,
-- إضافة أعمدة الصلاحيات لجدول profiles في حال عدم وجودها
alter table public.profiles add column if not exists can_add boolean not null default true;
alter table public.profiles add column if not exists can_edit boolean not null default true;
alter table public.profiles add column if not exists can_delete boolean not null default false;
alter table public.profiles add column if not exists can_view boolean not null default true;

comment on table public.profiles is 'ملفات تعريف الموظفين وصلاحياتهم (admin / employee)';

-- =====================================================================
-- 2) جدول إجازات البناء (الجدول الرئيسي)
-- =====================================================================
create table if not exists public.permits (
    id uuid primary key default uuid_generate_v4(),

    -- الرقم يعيد تسلسله من 1 كل سنة (رقم الإجازة + السنة = مفتاح فريد مركّب)
    permit_number integer not null,
    permit_year integer not null,

    full_name text not null,                       -- الاسم الثلاثي
    plot_number text not null,                      -- رقم القطعة (نص حر، يقبل صيغ غير قياسية)
    permit_date date not null,                       -- التاريخ (ميلادي)
    notes text,                                      -- الملاحظات
    permit_type text,                                 -- نوع الإجازة: اجازة جديدة / اضافة بناء / بناء اضافي ...

    name_change_notes text,                           -- عمود "التغيرات" (تغيير اسم لاحقاً + سبب/قرار)
    plot_area numeric(12,2),                           -- مساحة العرصة
    building_area numeric(12,2),                       -- مساحة البناء
    name_per_new_registry text,                        -- الاسم الثلاثي حسب صورة القيد الجديدة

    attachment_urls text[] default '{}',                -- روابط صور/PDF مرفقة (Supabase Storage)

    is_deleted boolean not null default false,          -- حذف منطقي فقط (Soft Delete)

    -- علامة على السجلات المستوردة من الأرشيف القديم التي تشارك نفس رقم الإجازة
    -- ضمن نفس السنة مع سجل آخر (بسبب تداخل مصدرين تاريخيين). راجعها يدوياً وصحّح رقمها عند التفرغ،
    -- ثم يمكن حذف هذا العمود لاحقاً بأمان بعد إتمام التنظيف.
    duplicate_flag boolean not null default false,

    created_by uuid references public.profiles(id),
    created_at timestamptz not null default now(),
    updated_by uuid references public.profiles(id),
    updated_at timestamptz not null default now()
);

create index if not exists idx_permits_year on public.permits(permit_year);
create index if not exists idx_permits_name on public.permits using gin (to_tsvector('simple', full_name));
create index if not exists idx_permits_plot on public.permits(plot_number);
create index if not exists idx_permits_date on public.permits(permit_date);
create index if not exists idx_permits_not_deleted on public.permits(is_deleted) where is_deleted = false;
-- فهرس عادي (وليس قيد UNIQUE) لتسريع البحث عن رقم الإجازة ضمن سنة معينة
-- بدون رفض السجلات القديمة المكررة فعلياً في الأرشيف التاريخي
create index if not exists idx_permits_year_number on public.permits(permit_year, permit_number);

comment on table public.permits is 'سجل إجازات البناء الرئيسي - رقم الإجازة فريد ضمن السنة الواحدة فقط';

-- تحديث updated_at تلقائياً
create or replace function public.set_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

drop trigger if exists trg_permits_updated_at on public.permits;
create trigger trg_permits_updated_at
    before update on public.permits
    for each row execute function public.set_updated_at();

-- =====================================================================
-- 3) جدول سجل التدقيق (Audit Log) - من أضاف/عدّل/حذف وماذا تغيّر
-- =====================================================================
create table if not exists public.permits_audit_log (
    id uuid primary key default uuid_generate_v4(),
    permit_id uuid not null,
    action text not null check (action in ('insert', 'update', 'delete', 'restore')),
    changed_by uuid references public.profiles(id),
    changed_by_name text,                   -- نسخة نصية من الاسم وقت التغيير (تظهر في تنبيه "تم التعديل من قبل ...")
    changed_at timestamptz not null default now(),
    old_data jsonb,
    new_data jsonb
);

create index if not exists idx_audit_permit_id on public.permits_audit_log(permit_id);
create index if not exists idx_audit_changed_at on public.permits_audit_log(changed_at desc);

comment on table public.permits_audit_log is 'سجل تدقيق كامل لكل عملية إضافة/تعديل/حذف على الإجازات';

-- تسجيل تلقائي لكل عملية على جدول permits
create or replace function public.log_permit_change()
returns trigger as $$
declare
    v_actor_name text;
begin
    if (tg_op = 'INSERT') then
        select full_name into v_actor_name from public.profiles where id = new.created_by;
        insert into public.permits_audit_log(permit_id, action, changed_by, changed_by_name, new_data)
        values (new.id, 'insert', new.created_by, v_actor_name, to_jsonb(new));
        return new;
    elsif (tg_op = 'UPDATE') then
        select full_name into v_actor_name from public.profiles where id = new.updated_by;
        insert into public.permits_audit_log(permit_id, action, changed_by, changed_by_name, old_data, new_data)
        values (new.id,
                case when new.is_deleted and not old.is_deleted then 'delete'
                     when old.is_deleted and not new.is_deleted then 'restore'
                     else 'update' end,
                new.updated_by, v_actor_name, to_jsonb(old), to_jsonb(new));
        return new;
    end if;
    return null;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_permits_audit on public.permits;
create trigger trg_permits_audit
    after insert or update on public.permits
    for each row execute function public.log_permit_change();

-- =====================================================================
-- 4) دالة توليد رقم الإجازة التالي ضمن سنة معينة (تُستدعى من التطبيق)
-- =====================================================================
create or replace function public.next_permit_number(p_year integer)
returns integer as $$
declare
    v_next integer;
begin
    select coalesce(max(permit_number), 0) + 1 into v_next
    from public.permits
    where permit_year = p_year and is_deleted = false;
    return v_next;
end;
$$ language plpgsql security definer;

-- =====================================================================
-- 5) تفعيل Row Level Security
-- =====================================================================
alter table public.profiles enable row level security;
alter table public.permits enable row level security;
alter table public.permits_audit_log enable row level security;

-- ---- profiles ----
create policy "المستخدم يقرأ كل الملفات الشخصية" on public.profiles
    for select using (auth.uid() is not null);

create policy "الأدمن فقط يعدّل الملفات الشخصية" on public.profiles
    for update using (
        exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
    );

create policy "الأدمن فقط يضيف ملفات شخصية" on public.profiles
    for insert with check (
        exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
        or auth.uid() = id  -- يسمح للمستخدم بإنشاء ملفه الشخصي عند أول تسجيل دخول
    );

-- ---- permits: أي مستخدم يقرأ الإجازات، الإضافة والتعديل للموظفين النشطين، الحذف الفعلي للأدمن فقط ----
drop policy if exists "الموظفون النشطون يقرأون الإجازات" on public.permits;
create policy "الجميع يقرأ الإجازات" on public.permits
    for select using (true);

create policy "الموظفون النشطون يضيفون إجازات" on public.permits
    for insert with check (
        exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_active = true)
    );

create policy "الموظفون النشطون يعدّلون الإجازات" on public.permits
    for update using (
        exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_active = true)
    );

-- الحذف الفعلي (DELETE) محصور بالأدمن فقط - الموظف العادي يستخدم is_deleted (تحديث فقط)
create policy "الأدمن فقط يحذف حذفاً فعلياً" on public.permits
    for delete using (
        exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
    );

-- ---- audit log: قراءة فقط، وللأدمن فقط ----
create policy "الأدمن فقط يقرأ سجل التدقيق" on public.permits_audit_log
    for select using (
        exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
    );

-- =====================================================================
-- 6) تفعيل Realtime على جدول الإجازات (للمزامنة اللحظية بين كل الأجهزة)
-- =====================================================================
alter publication supabase_realtime add table public.permits;

-- =====================================================================
-- 7) دلو تخزين (Storage Bucket) للمرفقات (صور / PDF)
-- =====================================================================
insert into storage.buckets (id, name, public)
values ('permit-attachments', 'permit-attachments', false)
on conflict (id) do nothing;

create policy "الموظفون النشطون يرفعون مرفقات" on storage.objects
    for insert with check (
        bucket_id = 'permit-attachments'
        and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_active = true)
    );

create policy "الموظفون النشطون يقرأون المرفقات" on storage.objects
    for select using (
        bucket_id = 'permit-attachments'
        and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_active = true)
    );

-- =====================================================================
-- ملاحظة: بعد إنشاء أول مستخدم عبر Supabase Auth، رقّه إلى admin يدوياً:
-- update public.profiles set role = 'admin' where id = '<USER_UUID>';
-- =====================================================================