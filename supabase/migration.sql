-- =====================================================================
-- نظام إدارة إجازات البناء - تحديث التراخيص والأجهزة والإشعارات
-- =====================================================================

-- 1) إضافة أعمدة التراخيص وتفعيل الحسابات إلى جدول profiles
alter table public.profiles 
add column if not exists approval_status text not null default 'pending' check (approval_status in ('pending', 'approved', 'suspended')),
add column if not exists license_start_at timestamptz,
add column if not exists license_end_at timestamptz,
add column if not exists license_paused boolean not null default false,
add column if not exists license_paused_seconds_left integer,
add column if not exists last_paused_at timestamptz;

comment on column public.profiles.approval_status is 'حالة تفعيل الحساب: pending (انتظار)، approved (مقبول)، suspended (موقوف مؤقتاً)';

-- جعل حساب المدير الافتراضي see313see@gmail.com مقبولاً ومفعلاً دائماً
update public.profiles 
set approval_status = 'approved',
    license_start_at = now(),
    license_end_at = now() + interval '100 years'
where role = 'admin';

-- 2) جدول رموز/أكواد التفعيل (Activation Codes)
create table if not exists public.activation_codes (
    code text primary key,
    associated_email text,                        -- البريد الإلكتروني المرتبط بالكود (اختياري)
    duration_days integer not null,               -- مدة التفعيل بالأيام (مثلاً 30، 90، 365)
    is_used boolean not null default false,
    used_by_user_id uuid references public.profiles(id) on delete set null,
    used_at timestamptz,
    created_at timestamptz not null default now()
);

comment on table public.activation_codes is 'أكواد تفعيل الحسابات وسيريالات الاشتراك';

-- 3) جدول الأجهزة المرتبطة (User Devices)
create table if not exists public.user_devices (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade not null,
    device_id text not null,                       -- معرف فريد للجهاز محلياً
    device_name text,                              -- اسم الجهاز (مثال: Galaxy S21, My-PC)
    os_platform text,                              -- نظام التشغيل (Android / Windows)
    last_active timestamptz not null default now(),
    created_at timestamptz not null default now(),
    unique (user_id, device_id)
);

comment on table public.user_devices is 'سجل الأجهزة المرتبطة بحساب كل موظف لتتبع تسجيل الدخول';

-- 4) جدول الإشعارات (Notifications)
create table if not exists public.notifications (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid references public.profiles(id) on delete cascade not null,
    title text not null,
    message text not null,
    is_read boolean not null default false,
    created_at timestamptz not null default now()
);

comment on table public.notifications is 'سجل إشعارات الموظفين (مثل إشعار قبول الحساب)';

-- =====================================================================
-- 5) تفعيل Row Level Security (RLS) للجدوال الجديدة
-- =====================================================================
alter table public.activation_codes enable row level security;
alter table public.user_devices enable row level security;
alter table public.notifications enable row level security;

-- سياسات أكواد التفعيل:
-- أي مستخدم مسجل دخول يمكنه قراءة الأكواد للتحقق منها وتحديث الكود عند تفعيله
create policy "قراءة أكواد التفعيل للجميع" on public.activation_codes
    for select using (auth.uid() is not null);

create policy "تحديث كود التفعيل عند استخدامه" on public.activation_codes
    for update using (auth.uid() is not null);

create policy "المدير فقط يولد أكواد تفعيل جديدة" on public.activation_codes
    for insert with check (
        exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
    );

create policy "المدير فقط يحذف أكواد التفعيل" on public.activation_codes
    for delete using (
        exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
    );

-- سياسات الأجهزة المرتبطة:
-- الموظف يقرأ ويكتب أجهزته الخاصة فقط، والمدير يقرأ أجهزة الجميع
create policy "الجميع يقرأ أجهزته والمدير يقرأ الكل" on public.user_devices
    for select using (
        auth.uid() = user_id 
        or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
    );

create policy "الموظف يسجل أجهزته الخاصة" on public.user_devices
    for insert with check (auth.uid() = user_id);

create policy "الموظف يحدث تاريخ نشاط أجهزته الخاصة" on public.user_devices
    for update using (auth.uid() = user_id);

create policy "المدير فقط يحذف الأجهزة المرتبطة" on public.user_devices
    for delete using (
        exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
    );

-- سياسات الإشعارات:
-- الموظف يقرأ ويحدّث إشعاراته الخاصة فقط، والمدير يرسل إشعارات للجميع
create policy "الموظف يقرأ إشعاراته" on public.notifications
    for select using (auth.uid() = user_id);

create policy "الموظف يحدّث حالة قراءة إشعاره" on public.notifications
    for update using (auth.uid() = user_id);

create policy "إرسال الإشعارات من النظام أو المدير" on public.notifications
    for insert with check (true);

create policy "المدير فقط يحذف الإشعارات" on public.notifications
    for delete using (
        exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
    );

-- =====================================================================
-- 6) تفعيل Realtime لمزامنة التراخيص والإشعارات لحظياً
-- =====================================================================
alter publication supabase_realtime add table public.profiles;
alter publication supabase_realtime add table public.notifications;

-- =====================================================================
-- 7) Atomic, server-time activation and administrator licensing actions
-- Run this section with the migration.  It deliberately replaces the broad
-- activation-code policies above: clients must never be able to mark a code
-- used or choose their own licence expiry.
-- =====================================================================
drop policy if exists "قراءة أكواد التفعيل للجميع" on public.activation_codes;
drop policy if exists "تحديث كود التفعيل عند استخدامه" on public.activation_codes;

create or replace function public.consume_activation_code(p_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code public.activation_codes;
  v_email text;
  v_end timestamptz;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  select email into v_email from auth.users where id = auth.uid();
  select * into v_code from public.activation_codes
    where code = upper(trim(p_code)) and is_used = false
    for update;
  if not found then raise exception 'رمز التفعيل غير صالح أو مستخدم مسبقاً'; end if;
  if v_code.associated_email is not null
     and lower(trim(v_code.associated_email)) <> lower(trim(coalesce(v_email, ''))) then
    raise exception 'رمز التفعيل مخصص لبريد إلكتروني آخر';
  end if;

  v_end := now() + make_interval(days => v_code.duration_days);
  update public.activation_codes
    set is_used = true, used_by_user_id = auth.uid(), used_at = now()
    where code = v_code.code;
  update public.profiles
    set approval_status = 'approved', is_active = true,
        license_start_at = now(), license_end_at = v_end,
        license_paused = false, license_paused_seconds_left = null,
        last_paused_at = null
    where id = auth.uid();
  insert into public.notifications(user_id, title, message)
    values (auth.uid(), 'تم تفعيل الحساب', 'تم تفعيل ترخيص حسابك بنجاح.');
end;
$$;

revoke all on function public.consume_activation_code(text) from public;
grant execute on function public.consume_activation_code(text) to authenticated;

-- =====================================================================
-- 8) Secure licensing v2. All state-changing actions go through these
-- RPCs, use database time, and validate the caller's role server-side.
-- =====================================================================
create or replace function public.is_licensing_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- Remove the broad first-version rules. The functions below run as definer;
-- clients only retain read access appropriate to their role.
do $$
declare rule record;
begin
  for rule in select policyname, tablename from pg_policies
    where schemaname = 'public' and tablename in ('activation_codes', 'user_devices', 'notifications')
  loop
    execute format('drop policy if exists %I on public.%I', rule.policyname, rule.tablename);
  end loop;
end $$;

create policy "activation_codes_admin_read" on public.activation_codes
  for select using (public.is_licensing_admin());
create policy "devices_owner_or_admin_read" on public.user_devices
  for select using (user_id = auth.uid() or public.is_licensing_admin());
create policy "notifications_owner_read" on public.notifications
  for select using (user_id = auth.uid());
create policy "notifications_owner_update" on public.notifications
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function public.admin_create_activation_code(
  p_code text, p_duration_days integer, p_associated_email text default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_licensing_admin() then raise exception 'غير مصرح بإدارة التراخيص'; end if;
  if upper(trim(p_code)) !~ '^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$' then
    raise exception 'صيغة رمز التفعيل غير صحيحة';
  end if;
  if p_duration_days not in (30, 90, 180, 365) then raise exception 'مدة الترخيص غير مدعومة'; end if;
  insert into public.activation_codes(code, duration_days, associated_email)
  values (upper(trim(p_code)), p_duration_days, nullif(lower(trim(p_associated_email)), ''));
end;
$$;

alter table public.profiles add column if not exists activated_code text;
alter table public.profiles add column if not exists email text;

create or replace function public.consume_activation_code(p_code text)
returns void language plpgsql security definer set search_path = public as $$
declare code_row public.activation_codes; account_email text; base_end timestamptz;
begin
  if auth.uid() is null then raise exception 'يجب تسجيل الدخول'; end if;
  select email into account_email from auth.users where id = auth.uid();
  select * into code_row from public.activation_codes
    where code = upper(trim(p_code)) and is_used = false for update;
  if not found then raise exception 'رمز التفعيل غير صالح أو مستخدم مسبقاً'; end if;
  if code_row.associated_email is not null and code_row.associated_email <> lower(trim(coalesce(account_email, ''))) then
    raise exception 'رمز التفعيل مخصص لبريد إلكتروني آخر';
  end if;
  
  -- التحقق من الموافقة أولاً
  if not exists (select 1 from public.profiles where id = auth.uid() and approval_status = 'approved') then
    raise exception 'يجب أن تتم الموافقة على حسابك من قبل مدير النظام أولاً قبل تفعيله';
  end if;

  select greatest(coalesce(license_end_at, now()), now()) into base_end from public.profiles where id = auth.uid() for update;
  update public.activation_codes set 
    is_used = true, 
    used_by_user_id = auth.uid(), 
    used_at = now(),
    associated_email = coalesce(associated_email, account_email)
    where code = code_row.code;
    
  update public.profiles set 
    approval_status = 'approved', 
    is_active = true,
    email = coalesce(email, account_email),
    activated_code = code_row.code,
    license_start_at = coalesce(license_start_at, now()), 
    license_end_at = base_end + make_interval(days => code_row.duration_days),
    license_paused = false, 
    license_paused_seconds_left = null, 
    last_paused_at = null 
    where id = auth.uid();
    
  insert into public.notifications(user_id, title, message)
    values (auth.uid(), 'تم تفعيل الترخيص', 'تم تحديث ترخيص حسابك بنجاح.');
end;
$$;

create or replace function public.admin_approve_account(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_licensing_admin() then raise exception 'غير مصرح بإدارة الحسابات'; end if;
  update public.profiles set approval_status = 'approved', is_active = true where id = p_user_id;
  if not found then raise exception 'الحساب غير موجود'; end if;
  insert into public.notifications(user_id, title, message)
    values (p_user_id, 'تمت الموافقة على الحساب', 'تمت الموافقة على حسابك من قبل الإدارة. يرجى إدخال رمز التفعيل للبدء.');
end;
$$;

create or replace function public.admin_set_license_paused(p_user_id uuid, p_paused boolean)
returns void language plpgsql security definer set search_path = public as $$
declare seconds_left integer;
begin
  if not public.is_licensing_admin() then raise exception 'غير مصرح بإدارة التراخيص'; end if;
  if p_paused then
    select greatest(0, extract(epoch from license_end_at - now())::integer) into seconds_left from public.profiles where id = p_user_id for update;
    update public.profiles set approval_status = 'suspended', license_paused = true, license_paused_seconds_left = coalesce(seconds_left, 0), last_paused_at = now() where id = p_user_id;
    insert into public.notifications(user_id, title, message) values (p_user_id, 'تم إيقاف الترخيص', 'تم إيقاف ترخيص حسابك مؤقتاً من قبل الإدارة.');
  else
    select coalesce(license_paused_seconds_left, 0) into seconds_left from public.profiles where id = p_user_id for update;
    update public.profiles set approval_status = 'approved', license_paused = false, license_end_at = now() + make_interval(secs => seconds_left), license_paused_seconds_left = null, last_paused_at = null where id = p_user_id;
    insert into public.notifications(user_id, title, message) values (p_user_id, 'تم استئناف الترخيص', 'تم استئناف ترخيص حسابك.');
  end if;
end;
$$;

create or replace function public.register_current_device(p_device_id text, p_device_name text, p_os_platform text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'يجب تسجيل الدخول'; end if;
  update public.user_devices set device_name = left(coalesce(p_device_name, 'غير معروف'), 160), os_platform = left(coalesce(p_os_platform, 'غير معروف'), 80), last_active = now()
    where user_id = auth.uid() and device_id = left(trim(p_device_id), 255);
  if found then return; end if;
  if (select count(*) from public.user_devices where user_id = auth.uid()) >= 2 then
    raise exception 'DEVICE_LIMIT: الحد الأقصى جهازان لكل حساب';
  end if;
  insert into public.user_devices(user_id, device_id, device_name, os_platform, last_active)
    values (auth.uid(), left(trim(p_device_id), 255), left(coalesce(p_device_name, 'غير معروف'), 160), left(coalesce(p_os_platform, 'غير معروف'), 80), now());
end;
$$;

create or replace function public.admin_remove_device(p_device_row_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_licensing_admin() then raise exception 'غير مصرح بإدارة الأجهزة'; end if;
  delete from public.user_devices where id = p_device_row_id;
  if not found then raise exception 'الجهاز غير موجود'; end if;
end;
$$;

revoke all on function public.is_licensing_admin() from public;
grant execute on function public.is_licensing_admin() to authenticated;
revoke all on function public.consume_activation_code(text) from public;
grant execute on function public.consume_activation_code(text), public.register_current_device(text, text, text) to authenticated;
grant execute on function public.admin_create_activation_code(text, integer, text), public.admin_approve_account(uuid), public.admin_set_license_paused(uuid, boolean), public.admin_remove_device(uuid) to authenticated;
