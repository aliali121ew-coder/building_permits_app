import { Hono } from 'hono';
import { sign } from 'hono/jwt';
import { Env, Profile, UserPayload } from '../types';
import { hashPassword, verifyPassword } from '../utils/crypto';
import { authMiddleware } from '../middleware/auth';
import { activeLock, activityStmt } from '../utils/activity';

const auth = new Hono<{ Bindings: Env; Variables: { user: UserPayload } }>();

export function formatProfile(p: any) {
  if (!p) return null;
  const { password_hash: _, ...rest } = p;
  return {
    ...rest,
    is_active: Boolean(p.is_active),
    can_add: Boolean(p.can_add),
    can_edit: Boolean(p.can_edit),
    can_delete: Boolean(p.can_delete),
    can_view: Boolean(p.can_view),
    license_paused: Boolean(p.license_paused),
  };
}

// 1) إنشاء حساب جديد (Sign Up) — يظهر للمدير في «طلبات الحسابات» وسجل النشاط
auth.post('/register', async (c) => {
  const { email, password, full_name } = await c.req.json();

  if (!email || !password || !full_name) {
    return c.json({ error: 'البريد الإلكتروني وكلمة المرور والاسم الثلاثي مطلوبة' }, 400);
  }

  const cleanEmail = email.toLowerCase().trim();
  const existing = await c.env.DB.prepare('SELECT id FROM profiles WHERE email = ?').bind(cleanEmail).first();
  if (existing) {
    return c.json({ error: 'هذا البريد الإلكتروني مسجل مسبقاً' }, 400);
  }

  // أول مستخدم أو البريد الرسمي للمدير يصبح مديراً
  const countResult = await c.env.DB.prepare('SELECT count(*) as count FROM profiles').first<{ count: number }>();
  const isFirstUser = (countResult?.count ?? 0) === 0 || cleanEmail === 'see313see@gmail.com';

  const id = crypto.randomUUID();
  const name = full_name.trim();
  const role = isFirstUser ? 'admin' : 'employee';
  const licenseEnd = isFirstUser ? new Date(Date.now() + 100 * 365 * 86400 * 1000).toISOString() : null;

  const [inserted] = await c.env.DB.batch([
    c.env.DB.prepare(`
      INSERT INTO profiles (
        id, email, password_hash, full_name, role, is_active, approval_status,
        can_add, can_edit, can_delete, can_view, license_start_at, license_end_at
      ) VALUES (?, ?, ?, ?, ?, 1, ?, 1, 1, ?, 1, datetime('now'), ?)
      RETURNING *
    `).bind(id, cleanEmail, await hashPassword(password), name, role,
      isFirstUser ? 'approved' : 'pending', isFirstUser ? 1 : 0, licenseEnd),
    activityStmt(c.env.DB, {
      actorId: id, actorName: name, targetId: id, targetName: name,
      action: 'register', details: `حساب جديد بالبريد ${cleanEmail}`,
    }),
  ]);

  const token = await sign(
    { id, email: cleanEmail, role, exp: Math.floor(Date.now() / 1000) + 30 * 86400 },
    c.env.JWT_SECRET
  );
  return c.json({ token, user: formatProfile(inserted.results[0]) }, 201);
});

// 2) تسجيل الدخول — رسائل قصيرة، ومنع الحسابات الموقوفة أو المقفلة مؤقتاً
auth.post('/login', async (c) => {
  const { email, password } = await c.req.json();

  if (!email || !password) {
    return c.json({ error: 'يرجى إدخال البريد الإلكتروني وكلمة المرور' }, 400);
  }

  const profile = await c.env.DB.prepare('SELECT * FROM profiles WHERE email = ?')
    .bind(email.toLowerCase().trim())
    .first<Profile>();

  if (!profile || !profile.password_hash) {
    return c.json({ error: 'البريد الإلكتروني غير مسجل' }, 401);
  }
  if (!(await verifyPassword(password, profile.password_hash))) {
    return c.json({ error: 'كلمة المرور خطأ' }, 401);
  }

  if (profile.role !== 'admin') {
    if (profile.is_active === 0) {
      return c.json({ error: 'الحساب موقوف، راجع الإدارة' }, 403);
    }
    const lock = activeLock(profile.locked_until);
    if (lock) {
      return c.json({ error: `الحساب مقفل حتى ${lock.slice(0, 10)}` }, 403);
    }
  }

  const token = await sign(
    { id: profile.id, email: profile.email, role: profile.role, exp: Math.floor(Date.now() / 1000) + 30 * 86400 },
    c.env.JWT_SECRET
  );
  await activityStmt(c.env.DB, {
    actorId: profile.id, actorName: profile.full_name, action: 'login',
  }).run();

  return c.json({ token, user: formatProfile(profile) });
});

// 3) الملف الشخصي للمستخدم الحالي
auth.get('/me', authMiddleware, async (c) => {
  const profile = await c.env.DB.prepare('SELECT * FROM profiles WHERE id = ?')
    .bind(c.get('user').id)
    .first<Profile>();

  if (!profile) return c.json({ error: 'المستخدم غير موجود' }, 404);
  return c.json(formatProfile(profile));
});

// 4) تغيير كلمة المرور — يشترط كلمة المرور الحالية دائماً
auth.post('/change-password', authMiddleware, async (c) => {
  const user = c.get('user');
  const { old_password, new_password } = await c.req.json();

  if (!old_password) {
    return c.json({ error: 'أدخل كلمة المرور الحالية' }, 400);
  }
  if (!new_password || new_password.length < 6) {
    return c.json({ error: 'كلمة المرور الجديدة يجب أن لا تقل عن 6 أحرف' }, 400);
  }

  const profile = await c.env.DB.prepare('SELECT full_name, password_hash FROM profiles WHERE id = ?')
    .bind(user.id)
    .first<{ full_name: string; password_hash: string }>();

  if (!profile || !(await verifyPassword(old_password, profile.password_hash))) {
    return c.json({ error: 'كلمة المرور الحالية خطأ' }, 400);
  }

  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE profiles SET password_hash = ? WHERE id = ?').bind(await hashPassword(new_password), user.id),
    activityStmt(c.env.DB, {
      actorId: user.id, actorName: profile.full_name, targetId: user.id, targetName: profile.full_name,
      action: 'password_change', details: 'غيّر كلمة المرور الخاصة به',
    }),
  ]);

  return c.json({ message: 'تم تغيير كلمة المرور بنجاح' });
});

// 5) تأكيد هوية المدير بكلمة مروره قبل فتح شاشات الإدارة
auth.post('/verify-password', authMiddleware, async (c) => {
  const user = c.get('user');
  const { password } = await c.req.json();
  if (!password) return c.json({ error: 'أدخل كلمة المرور' }, 400);

  const profile = await c.env.DB.prepare('SELECT password_hash FROM profiles WHERE id = ?')
    .bind(user.id)
    .first<{ password_hash: string }>();

  if (!profile || !(await verifyPassword(password, profile.password_hash))) {
    return c.json({ error: 'رمز التأكيد خطأ' }, 401);
  }
  return c.json({ ok: true });
});

export default auth;
