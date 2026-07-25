-- =====================================================================
-- إزالة تكرارات جدول permits للسنوات 1984-1989 (استيراد مزدوج)
-- Remove exact-duplicate permit rows for years 1984-1989
-- =====================================================================
-- الوضع: بعد استرجاع الجدول، السنوات 1984-1989 تحوي نسختين مطابقتين لكل
--        إجازة (1353 صفاً زائداً)، بينما 1990-2025 نظيفة. هذا السكربت
--        يحذف النسخة الزائدة فقط ويُبقي واحدة لكل إجازة.
--
-- الأمان:
--   • يعمل فقط على السنوات 1984-1989 (لا يمسّ بقية السنوات).
--   • يُميّز الإجازات المتطابقة تماماً (نفس السنة+الرقم+الاسم+القطعة+التاريخ)
--     فيحذف المكرر الحقيقي فقط، ويُبقي الإجازات المختلفة التي تتشارك نفس الرقم
--     (مثل 1984 رقم 72 لشخصين مختلفين — يبقى كلاهما).
--   • Idempotent: تشغيله مرة أخرى لا يحذف شيئاً (لا مزيد من التكرار).
--   • DELETE لا يُفعّل مشغّل التدقيق (فهو on insert/update فقط).
--
-- يُفضّل أخذ نسخة احتياطية قبل التشغيل (اختياري):
--   create table public.permits_backup_before_dedup as table public.permits;
-- =====================================================================

with ranked as (
  select
    id,
    row_number() over (
      partition by permit_year,
                   permit_number,
                   btrim(full_name),
                   btrim(coalesce(plot_number, '')),
                   permit_date
      order by created_at nulls last, id
    ) as rn
  from public.permits
  where permit_year between 1984 and 1989
)
delete from public.permits p
using ranked r
where p.id = r.id
  and r.rn > 1;

-- إعادة تحميل ذاكرة الواجهة
notify pgrst, 'reload schema';

-- =====================================================================
-- التحقّق بعد التشغيل (المتوقّع: total_permits = 7019)
-- =====================================================================
select count(*) as total_permits from public.permits;

-- تفصيل السنوات المتأثرة (المتوقّع: 1984=133, 1985=136, 1986=224,
-- 1987=376, 1988=234, 1989=325):
select permit_year, count(*) as cnt
  from public.permits
 where permit_year between 1984 and 1989
 group by permit_year
 order by permit_year;
