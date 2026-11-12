import { Hono } from 'hono';
import { Env, Profile, UserPayload } from '../types';
import { adminOnlyMiddleware, authMiddleware } from '../middleware/auth';
import { formatProfile } from './auth';

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

  if (caller.role !== 'admin') {
    await c.env.DB.prepare('UPDATE profiles SET full_name = ?, email = ? WHERE id = ?')
      .bind(data.full_name ?? existing.full_name, data.email ?? existing.email, targetId)
      .run();
    return c.json({ message: 'تم تحديث الاسم بنجاح' });
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

    return c.json({ message: 'تم إيقاف الترخيص' });
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

    return c.json({ message: 'تم استئناف الترخيص' });
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

export default licensing;
