import { Hono } from 'hono';
import { Env, Profile, UserPayload } from '../types';
import { adminOnlyMiddleware, authMiddleware } from '../middleware/auth';
import { formatProfile } from './auth';
import { activityStmt } from '../utils/activity';
import { hashPassword } from '../utils/crypto';

/** اسم صاحب الحساب للسجل (قراءة صف واحد) */
async function nameOf(db: D1Database, id: string): Promise<string> {
  const r = await db.prepare('SELECT full_name FROM profiles WHERE id = ?').bind(id).first<{ full_name: string }>();
  return r?.full_name || 'مستخدم';
}

const licensing = new Hono<{ Bindings: Env; Variables: { user: UserPayload } }>();

licensing.use('*', authMiddleware);

// 1) استهلاك كود التفعيل (Activate Code)
licensing.post('/activate', async (c) => {
  const user = c.get('user');
  const { code } = await c.req.json();

  if (!code) return c.json({ error: 'يرجى إدخال رمز التفعيل' }, 400);

  const cleanCode = code.toUpperCase().trim();
  const codeRow = await c.env.DB.prepare('SELECT * FROM activation_codes WHERE code = ? AND is_used = 0')
    .bind(cleanCode)
    .first<{ code: string; associated_email?: string; duration_days: number }>();

  if (!codeRow) {
    return c.json({ error: 'رمز التفعيل غير صالح أو مستخدم مسبقاً' }, 400);
  }

  const profile = await c.env.DB.prepare('SELECT * FROM profiles WHERE id = ?')
    .bind(user.id)
    .first<Profile>();

  if (!profile) return c.json({ error: 'المستخدم غير موجود' }, 404);

  if (profile.approval_status !== 'approved') {
    return c.json({ error: 'يجب أن تتم الموافقة على حسابك من قبل الإدارة أولاً قبل التفعيل' }, 403);
  }

  if (codeRow.associated_email && codeRow.associated_email.toLowerCase() !== profile.email.toLowerCase()) {
    return c.json({ error: 'رمز التفعيل مخصص لبريد إلكتروني آخر' }, 403);
  }

  const currentEnd = profile.license_end_at ? new Date(profile.license_end_at).getTime() : Date.now();
  const baseTime = Math.max(currentEnd, Date.now());
  const newEnd = new Date(baseTime + codeRow.duration_days * 86400 * 1000).toISOString();

  await c.env.DB.prepare("UPDATE activation_codes SET is_used = 1, used_by_user_id = ?, used_at = datetime('now') WHERE code = ?")
    .bind(user.id, cleanCode)
    .run();

  await c.env.DB.prepare(`
    UPDATE profiles SET
      approval_status = 'approved',
      is_active = 1,
      activated_code = ?,
      license_start_at = COALESCE(license_start_at, datetime('now')),
      license_end_at = ?,
      license_paused = 0,
      license_paused_seconds_left = NULL,
      last_paused_at = NULL
    WHERE id = ?
  `).bind(cleanCode, newEnd, user.id).run();

  await c.env.DB.prepare(`
    INSERT INTO notifications (id, user_id, title, message)
    VALUES (?, ?, 'تم تفعيل الترخيص', 'تم تفعيل ترخيص حسابك بنجاح.')
  `).bind(crypto.randomUUID(), user.id).run();

  return c.json({ message: 'تم تفعيل الترخيص بنجاح', license_end_at: newEnd });
});

// 2) تسجيل جهاز للموظف (حد أقصى جهازان)
licensing.post('/register-device', async (c) => {
  const user = c.get('user');
  const { device_id, device_name, os_platform } = await c.req.json();

  if (!device_id) return c.json({ error: 'معرف الجهاز مطلوب' }, 400);

  const existingDevice = await c.env.DB.prepare(
    'SELECT id FROM user_devices WHERE user_id = ? AND device_id = ?'
  ).bind(user.id, device_id).first<{ id: string }>();

  if (existingDevice) {
    await c.env.DB.prepare(
      "UPDATE user_devices SET device_name = ?, os_platform = ?, last_active = datetime('now') WHERE id = ?"
    ).bind(device_name || 'جهاز', os_platform || 'unknown', existingDevice.id).run();
    return c.json({ message: 'تم تحديث نشاط الجهاز' });
  }

  const deviceCount = await c.env.DB.prepare(
    'SELECT count(*) as count FROM user_devices WHERE user_id = ?'
  ).bind(user.id).first<{ count: number }>();

  if ((deviceCount?.count ?? 0) >= 2) {
    return c.json({ error: 'DEVICE_LIMIT: الحد الأقصى جهازان لكل حساب' }, 403);
  }

  await c.env.DB.prepare(`
    INSERT INTO user_devices (id, user_id, device_id, device_name, os_platform)
    VALUES (?, ?, ?, ?, ?)
  `).bind(crypto.randomUUID(), user.id, device_id, device_name || 'جهاز', os_platform || 'unknown').run();

  return c.json({ message: 'تم تسجيل الجهاز بنجاح' });
});

// 3) تحديث بيانات الملف الشخصي أو الصلاحيات (المستخدم لاسمه، والمدير للصلاحيات)
licensing.put('/profile/:id', async (c) => {
  const caller = c.get('user');
  const targetId = c.req.param('id');
  const data = await c.req.json();

  if (caller.role !== 'admin' && caller.id !== targetId) {
    return c.json({ error: 'غير مصرح بتعديل هذا الحساب' }, 403);
  }

  const existing = await c.env.DB.prepare('SELECT * FROM profiles WHERE id = ?').bind(targetId).first<Profile>();
  if (!existing) return c.json({ error: 'الحساب غير موجود' }, 404);

  // تعديل الملف الشخصي الذاتي: الاسم والصورة والهاتف وتاريخ الميلاد فقط (لا البريد ولا الصلاحيات)
  if (caller.id === targetId && data.role === undefined && data.can_add === undefined) {
    const name = String(data.full_name ?? existing.full_name).trim();
    const avatar = data.avatar_path !== undefined ? data.avatar_path : existing.avatar_path;
    const changes: string[] = [];
    if (name !== existing.full_name) changes.push(`الاسم: «${existing.full_name}» ← «${name}»`);
    if ((avatar ?? null) !== (existing.avatar_path ?? null)) changes.push('غيّر الصورة الشخصية');

    const stmts = [
      c.env.DB.prepare('UPDATE profiles SET full_name = ?, avatar_path = ?, phone_number = ?, birth_date = ? WHERE id = ?').bind(
        name,
        avatar ?? null,
        data.phone_number !== undefined ? data.phone_number : existing.phone_number ?? null,
        data.birth_date !== undefined ? data.birth_date : existing.birth_date ?? null,
        targetId,
      ),
    ];
    if (changes.length) {
      stmts.push(activityStmt(c.env.DB, {
        actorId: caller.id, actorName: name, targetId, targetName: name,
        action: 'profile_update', details: changes.join(' • '),
      }));
    }
    await c.env.DB.batch(stmts);
    return c.json({ message: 'تم تحديث الملف الشخصي' });
  }

  if (caller.role !== 'admin') {
    return c.json({ error: 'غير مصرح بتعديل هذا الحساب' }, 403);
  }

  await c.env.DB.prepare(`
    UPDATE profiles SET
      full_name = ?,
      role = ?,
      is_active = ?,
      can_add = ?,
      can_edit = ?,
      can_delete = ?,
      can_view = ?,
      approval_status = ?,
      license_start_at = ?,
      license_end_at = ?,
      license_paused = ?,
      email = ?
    WHERE id = ?
  `).bind(
    data.full_name ?? existing.full_name,
    data.role ?? existing.role,
    data.is_active !== undefined ? (data.is_active ? 1 : 0) : existing.is_active,
    data.can_add !== undefined ? (data.can_add ? 1 : 0) : existing.can_add,
    data.can_edit !== undefined ? (data.can_edit ? 1 : 0) : existing.can_edit,
    data.can_delete !== undefined ? (data.can_delete ? 1 : 0) : existing.can_delete,
    data.can_view !== undefined ? (data.can_view ? 1 : 0) : existing.can_view,
    data.approval_status ?? existing.approval_status,
    data.license_start_at !== undefined ? data.license_start_at : existing.license_start_at,
    data.license_end_at !== undefined ? data.license_end_at : existing.license_end_at,
    data.license_paused !== undefined ? (data.license_paused ? 1 : 0) : existing.license_paused,
    data.email ?? existing.email,
    targetId
  ).run();

  await activityStmt(c.env.DB, {
    actorId: caller.id, actorName: await nameOf(c.env.DB, caller.id),
    targetId, targetName: existing.full_name,
    action: 'permissions_update', details: 'عدّل صلاحيات الحساب',
  }).run();

  return c.json({ message: 'تم تحديث الصلاحيات بنجاح' });
});

// ===================== لوحة تحكم المدير (Admin Only) =====================

// 4) جلب جميع المستخدمين
licensing.get('/admin/users', adminOnlyMiddleware, async (c) => {
  const { results } = await c.env.DB.prepare('SELECT * FROM profiles ORDER BY full_name').all();
  return c.json(results.map(formatProfile));
});

// 5) جلب جميع الأجهزة المتصلة مع اسم الموظف
licensing.get('/admin/devices', adminOnlyMiddleware, async (c) => {
  const { results } = await c.env.DB.prepare(`
    SELECT d.*, p.full_name
    FROM user_devices d
    LEFT JOIN profiles p ON d.user_id = p.id
    ORDER BY d.last_active DESC
  `).all<any>();

  const formatted = results.map(r => ({
    ...r,
    profiles: { full_name: r.full_name || 'غير معروف' }
  }));

  return c.json(formatted);
});

// 6) حذف جهاز مرتبط
licensing.delete('/admin/devices/:id', adminOnlyMiddleware, async (c) => {
  const id = c.req.param('id');
  await c.env.DB.prepare('DELETE FROM user_devices WHERE id = ?').bind(id).run();
  return c.json({ message: 'تم حذف الجهاز بنجاح' });
});

// 7) جلب جميع أكواد التفعيل
licensing.get('/admin/codes', adminOnlyMiddleware, async (c) => {
  const { results } = await c.env.DB.prepare('SELECT * FROM activation_codes ORDER BY created_at DESC').all<any>();
  const formatted = results.map(r => ({
    ...r,
    is_used: Boolean(r.is_used)
  }));
  return c.json(formatted);
});

// 8) موافقة المدير على تفعيل حساب جديد
licensing.post('/admin/approve-user', adminOnlyMiddleware, async (c) => {
  const { user_id } = await c.req.json();
  await c.env.DB.prepare(
    "UPDATE profiles SET approval_status = 'approved', is_active = 1 WHERE id = ?"
  ).bind(user_id).run();

  await c.env.DB.prepare(`
    INSERT INTO notifications (id, user_id, title, message)
    VALUES (?, ?, 'تمت الموافقة على الحساب', 'تمت الموافقة على حسابك من قبل الإدارة. يرجى إدخال كود التفعيل للبدء.')
  `).bind(crypto.randomUUID(), user_id).run();

  const admin = c.get('user');
  await activityStmt(c.env.DB, {
    actorId: admin.id, actorName: await nameOf(c.env.DB, admin.id),
    targetId: user_id, targetName: await nameOf(c.env.DB, user_id),
    action: 'approve', details: 'وافق على الحساب الجديد',
  }).run();

  return c.json({ message: 'تمت الموافقة على الحساب بنجاح' });
});

// 9) إيقاف أو استئناف ترخيص موظف
licensing.post('/admin/pause-license', adminOnlyMiddleware, async (c) => {
  const { user_id, paused } = await c.req.json();
  const profile = await c.env.DB.prepare('SELECT * FROM profiles WHERE id = ?').bind(user_id).first<Profile>();
  if (!profile) return c.json({ error: 'المستخدم غير موجود' }, 404);

  if (paused) {
    const end = profile.license_end_at ? new Date(profile.license_end_at).getTime() : 0;
    const secondsLeft = Math.max(0, Math.floor((end - Date.now()) / 1000));
    await c.env.DB.prepare(`
      UPDATE profiles SET
        approval_status = 'suspended',
        is_active = 0,
        license_paused = 1,
        license_paused_seconds_left = ?,
        last_paused_at = datetime('now')
      WHERE id = ?
    `).bind(secondsLeft, user_id).run();

    await c.env.DB.prepare(`
      INSERT INTO notifications (id, user_id, title, message)
      VALUES (?, ?, 'تم إيقاف الترخيص', 'تم إيقاف ترخيص حسابك مؤقتاً من قبل الإدارة.')
    `).bind(crypto.randomUUID(), user_id).run();

    await activityStmt(c.env.DB, {
      actorId: c.get('user').id, actorName: await nameOf(c.env.DB, c.get('user').id),
      targetId: user_id, targetName: profile.full_name, action: 'suspend', details: 'أوقف الحساب',
    }).run();
    return c.json({ message: 'تم إيقاف الحساب' });
  } else {
    const secondsLeft = profile.license_paused_seconds_left || 0;
    const newEnd = new Date(Date.now() + secondsLeft * 1000).toISOString();
    await c.env.DB.prepare(`
      UPDATE profiles SET
        approval_status = 'approved',
        is_active = 1,
        license_paused = 0,
        license_end_at = ?,
        license_paused_seconds_left = NULL,
        last_paused_at = NULL
      WHERE id = ?
    `).bind(newEnd, user_id).run();

    await c.env.DB.prepare(`
      INSERT INTO notifications (id, user_id, title, message)
      VALUES (?, ?, 'تم استئناف الترخيص', 'تم استئناف ترخيص حسابك.')
    `).bind(crypto.randomUUID(), user_id).run();

    await activityStmt(c.env.DB, {
      actorId: c.get('user').id, actorName: await nameOf(c.env.DB, c.get('user').id),
      targetId: user_id, targetName: profile.full_name, action: 'activate', details: 'أعاد تفعيل الحساب',
    }).run();
    return c.json({ message: 'تم تفعيل الحساب' });
  }
});

// 10) توليد كود تفعيل جديد
licensing.post('/admin/generate-code', adminOnlyMiddleware, async (c) => {
  const { code, duration_days, associated_email } = await c.req.json();

  if (!code || !duration_days) {
    return c.json({ error: 'الكود وعدد الأيام مطلوبان' }, 400);
  }

  await c.env.DB.prepare(`
    INSERT INTO activation_codes (code, associated_email, duration_days)
    VALUES (?, ?, ?)
  `).bind(code.toUpperCase().trim(), associated_email?.toLowerCase().trim() || null, duration_days).run();

  return c.json({ message: 'تم إنشاء كود التفعيل بنجاح' });
});

// 11) إعادة تعيين كلمة مرور أي مستخدم (المدير) — كلمة المرور نفسها لا تُسجَّل أبداً
licensing.post('/admin/reset-password', adminOnlyMiddleware, async (c) => {
  const admin = c.get('user');
  const { user_id, new_password } = await c.req.json();
  if (!user_id || !new_password || String(new_password).length < 6) {
    return c.json({ error: 'كلمة المرور الجديدة يجب أن لا تقل عن 6 أحرف' }, 400);
  }
  const target = await nameOf(c.env.DB, user_id);
  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE profiles SET password_hash = ? WHERE id = ?').bind(await hashPassword(String(new_password)), user_id),
    activityStmt(c.env.DB, {
      actorId: admin.id, actorName: await nameOf(c.env.DB, admin.id),
      targetId: user_id, targetName: target, action: 'password_reset', details: 'أعاد تعيين كلمة المرور',
    }),
    c.env.DB.prepare(`INSERT INTO notifications (id, user_id, title, message) VALUES (?, ?, 'تغيير كلمة المرور', 'قامت الإدارة بإعادة تعيين كلمة مرور حسابك.')`)
      .bind(crypto.randomUUID(), user_id),
  ]);
  return c.json({ message: 'تم تعيين كلمة المرور الجديدة' });
});

// 12) قفل الحساب لمدة (days > 0) أو فكّ القفل (days = 0)
licensing.post('/admin/lock', adminOnlyMiddleware, async (c) => {
  const admin = c.get('user');
  const { user_id, days } = await c.req.json();
  const n = Math.max(0, Math.min(36500, parseInt(String(days ?? 0), 10) || 0));
  const until = n > 0 ? new Date(Date.now() + n * 86400 * 1000).toISOString() : null;
  const target = await nameOf(c.env.DB, user_id);

  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE profiles SET locked_until = ? WHERE id = ?').bind(until, user_id),
    activityStmt(c.env.DB, {
      actorId: admin.id, actorName: await nameOf(c.env.DB, admin.id),
      targetId: user_id, targetName: target,
      action: n > 0 ? 'lock' : 'unlock',
      details: until ? `قفل الحساب ${n} يوماً حتى ${until.slice(0, 10)}` : 'فكّ قفل الحساب',
    }),
  ]);
  return c.json({ message: n > 0 ? 'تم قفل الحساب' : 'تم فك القفل', locked_until: until });
});

// 13) سجل النشاط الموحد للمدير: نشاط الحسابات + كل إضافة/تعديل/حذف للإجازات.
//     يُقرأ فقط عند فتح المدير للسجل، 50 حدثاً لكل صفحة عبر الفهارس الزمنية.
licensing.get('/admin/activity', adminOnlyMiddleware, async (c) => {
  const before = c.req.query('before') || '9999-12-31';
  const limit = Math.min(100, parseInt(c.req.query('limit') || '50', 10) || 50);

  const { results } = await c.env.DB.prepare(`
    SELECT * FROM (
      SELECT id, actor_name, target_name, action, details, created_at, 'account' AS kind
      FROM activity_log WHERE created_at < ?1
      ORDER BY created_at DESC LIMIT ?2
    )
    UNION ALL
    SELECT * FROM (
      SELECT a.id, a.changed_by_name AS actor_name,
             COALESCE(json_extract(COALESCE(a.new_data, a.old_data), '$.full_name'), '') AS target_name,
             'permit_' || a.action AS action,
             COALESCE(json_extract(COALESCE(a.new_data, a.old_data), '$.permit_year'), '') || '/' ||
             COALESCE(json_extract(COALESCE(a.new_data, a.old_data), '$.permit_number'), '') AS details,
             a.changed_at AS created_at, 'permit' AS kind
      FROM permits_audit_log a WHERE a.changed_at < ?1
      ORDER BY a.changed_at DESC LIMIT ?2
    )
    ORDER BY created_at DESC LIMIT ?2
  `).bind(before, limit).all();

  return c.json(results);
});

// 14) عدد طلبات الحسابات الجديدة بانتظار الموافقة (لشارة الإعدادات)
licensing.get('/admin/pending-count', adminOnlyMiddleware, async (c) => {
  const r = await c.env.DB.prepare("SELECT count(*) AS n FROM profiles WHERE approval_status = 'pending'").first<{ n: number }>();
  return c.json({ count: r?.n ?? 0 });
});

export default licensing;

