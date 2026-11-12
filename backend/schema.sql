-- =====================================================================
-- Cloudflare D1 (SQLite) Schema for Building Permits Management System
-- =====================================================================

-- 1) جدول المستخدمين والملفات الشخصية (Profiles)
CREATE TABLE IF NOT EXISTS profiles (
    id TEXT PRIMARY KEY,                       -- UUID
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'employee' CHECK (role IN ('admin', 'employee')),
    is_active INTEGER NOT NULL DEFAULT 1,
    approval_status TEXT NOT NULL DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'suspended')),
    can_add INTEGER NOT NULL DEFAULT 1,
    can_edit INTEGER NOT NULL DEFAULT 1,
    can_delete INTEGER NOT NULL DEFAULT 0,
    can_view INTEGER NOT NULL DEFAULT 1,
    license_start_at TEXT,
    license_end_at TEXT,
    license_paused INTEGER NOT NULL DEFAULT 0,
    license_paused_seconds_left INTEGER,
    last_paused_at TEXT,
    activated_code TEXT,
    phone_number TEXT,
    birth_date TEXT,
    avatar_path TEXT,
    locked_until TEXT,                         -- قفل مؤقت للحساب حتى هذا التاريخ
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 2) جدول إجازات البناء (Permits)
CREATE TABLE IF NOT EXISTS permits (
    id TEXT PRIMARY KEY,
    permit_number INTEGER NOT NULL,
    permit_year INTEGER NOT NULL,
    full_name TEXT NOT NULL,
    plot_number TEXT NOT NULL,
    permit_date TEXT NOT NULL,
    notes TEXT,
    permit_type TEXT,
    name_change_notes TEXT,
    plot_area REAL,
    building_area REAL,
    name_per_new_registry TEXT,
    attachment_urls TEXT DEFAULT '[]',         -- JSON array of URLs or keys
    is_deleted INTEGER NOT NULL DEFAULT 0,
    duplicate_flag INTEGER NOT NULL DEFAULT 0,
    created_by TEXT REFERENCES profiles(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_by TEXT REFERENCES profiles(id),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_permits_year_number ON permits(permit_year, permit_number);
CREATE INDEX IF NOT EXISTS idx_permits_updated_at ON permits(updated_at); -- للسحب التفاضلي

-- 3) سجل التدقيق (Audit Log)
CREATE TABLE IF NOT EXISTS permits_audit_log (
    id TEXT PRIMARY KEY,
    permit_id TEXT NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('insert', 'update', 'delete', 'restore')),
    changed_by TEXT REFERENCES profiles(id),
    changed_by_name TEXT,
    changed_at TEXT NOT NULL DEFAULT (datetime('now')),
    old_data TEXT,                             -- JSON representation
    new_data TEXT                              -- JSON representation
);

CREATE INDEX IF NOT EXISTS idx_audit_permit_id ON permits_audit_log(permit_id);
CREATE INDEX IF NOT EXISTS idx_audit_changed_at ON permits_audit_log(changed_at DESC); -- لسجل نشاط المدير

-- 4) رموز التفعيل والاشتراكات (Activation Codes)
CREATE TABLE IF NOT EXISTS activation_codes (
    code TEXT PRIMARY KEY,
    associated_email TEXT,
    duration_days INTEGER NOT NULL,
    is_used INTEGER NOT NULL DEFAULT 0,
    used_by_user_id TEXT REFERENCES profiles(id),
    used_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 5) الأجهزة المعتمدة (User Devices)
CREATE TABLE IF NOT EXISTS user_devices (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    device_name TEXT,
    os_platform TEXT,
    last_active TEXT NOT NULL DEFAULT (datetime('now')),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (user_id, device_id)
);

-- 6) الإشعارات (Notifications)
CREATE TABLE IF NOT EXISTS notifications (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    is_read INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);

-- 7) سجل نشاط الحسابات (تسجيل، تغيير كلمة مرور، صلاحيات، قفل...) — يظهر للمدير
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

-- 8) تحديثات التطبيق (In-App Updates)
CREATE TABLE IF NOT EXISTS app_updates (
    id TEXT PRIMARY KEY,
    platform TEXT UNIQUE NOT NULL CHECK (platform IN ('android', 'windows')),
    latest_version TEXT NOT NULL,
    latest_build INTEGER NOT NULL,
    download_url TEXT NOT NULL DEFAULT '',
    release_notes TEXT,
    mandatory INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- بذور أولية لجدول التحديثات
INSERT OR IGNORE INTO app_updates (id, platform, latest_version, latest_build, download_url, release_notes, mandatory)
VALUES
    ('1', 'android', '1.0.0', 1, '', 'الإصدار الأول', 0),
    ('2', 'windows', '1.0.0', 1, '', 'الإصدار الأول', 0);

