-- =====================================================================
-- تحسين استهلاك D1 (قراءات وكتابات أقل)
-- التطبيق: npx wrangler d1 execute permits-db --remote --file=./migrations/0002_perf_indexes.sql
-- =====================================================================

-- السحب التفاضلي (GET /api/permits?since=...) يُنفَّذ كل 30 ثانية من كل جهاز.
-- بدون هذا الفهرس يقرأ D1 الجدول كاملاً في كل مرة؛ معه يقرأ الصفوف المتغيرة فقط.
CREATE INDEX IF NOT EXISTS idx_permits_updated_at ON permits(updated_at);

-- فهارس لا يستخدمها أي استعلام، وكل فهرس يضيف «صف كتابة» محسوباً مع كل إضافة/تعديل:
DROP INDEX IF EXISTS idx_permits_not_deleted;  -- عمود بقيمتين (0/1) لا فائدة منه
DROP INDEX IF EXISTS idx_permits_date;         -- التصفية بالتاريخ تتم داخل التطبيق
