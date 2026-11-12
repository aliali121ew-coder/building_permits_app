-- =====================================================================
-- إدارة الحسابات + سجل النشاط للمدير
-- التطبيق: npx wrangler d1 execute permits-db --remote --file=./migrations/0003_accounts_activity.sql
-- =====================================================================

-- قفل الحساب لمدة محددة (شهر / سنة / عدد أيام)
ALTER TABLE profiles ADD COLUMN locked_until TEXT;

-- سجل نشاط الحسابات (لا يُخزَّن فيه أي كلمة مرور إطلاقاً)
CREATE TABLE IF NOT EXISTS activity_log (
    id TEXT PRIMARY KEY,
    actor_id TEXT,
    actor_name TEXT,
    target_id TEXT,
    target_name TEXT,
    action TEXT NOT NULL,
    details TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_activity_created_at ON activity_log(created_at DESC);
