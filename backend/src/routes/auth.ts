import { Hono } from 'hono';
import { sign } from 'hono/jwt';
import { Env, Profile, UserPayload } from '../types';
import { hashPassword, verifyPassword } from '../utils/crypto';
import { authMiddleware } from '../middleware/auth';

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

// 1) إنشاء حساب جديد (Sign Up)
auth.post('/register', async (c) => {
  const { email, password, full_name } = await c.req.json();

  if (!email || !password || !full_name) {
    return c.json({ error: 'البريد الإلكتروني وكلمة المرور والاسم الثلاثي مطلوبة' }, 400);
  }

  const cleanEmail = email.toLowerCase().trim();
  const existing = await c.env.DB.prepare('SELECT id FROM profiles WHERE email = ?')
    .bind(cleanEmail)
    .first();

  if (existing) {
    return c.json({ error: 'هذا البريد الإلكتروني مسجل مسبقاً' }, 400);
  }

  // التحقق إن كان هذا أول مستخدم أو البريد الرسمي للمدير
  const countResult = await c.env.DB.prepare('SELECT count(*) as count FROM profiles').first<{ count: number }>();
  const isFirstUser = (countResult?.count ?? 0) === 0 || cleanEmail === 'see313see@gmail.com';

  const id = crypto.randomUUID();
  const password_hash = await hashPassword(password);
  const role = isFirstUser ? 'admin' : 'employee';
  const approval_status = isFirstUser ? 'approved' : 'pending';
  const license_end_at = isFirstUser ? new Date(Date.now() + 100 * 365 * 86400 * 1000).toISOString() : null;

  await c.env.DB.prepare(`
    INSERT INTO profiles (
      id, email, password_hash, full_name, role, is_active, approval_status,
      can_add, can_edit, can_delete, can_view, license_start_at, license_end_at
    ) VALUES (?, ?, ?, ?, ?, 1, ?, 1, 1, ?, 1, datetime('now'), ?)
  `).bind(
    id,
    cleanEmail,
    password_hash,
    full_name.trim(),
    role,
    approval_status,
    isFirstUser ? 1 : 0,
    license_end_at
  ).run();

  const token = await sign(
    { id, email: cleanEmail, role, exp: Math.floor(Date.now() / 1000) + 30 * 86400 },
    c.env.JWT_SECRET
  );

  const profile = await c.env.DB.prepare('SELECT * FROM profiles WHERE id = ?').bind(id).first();

  return c.json({ token, user: formatProfile(profile) }, 201);
});

// 2) تسجيل الدخول (Sign In)
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

  const valid = await verifyPassword(password, profile.password_hash);
  if (!valid) {
    return c.json({ error: 'كلمة المرور خطأ' }, 401);
  }

  const token = await sign(
    { id: profile.id, email: profile.email, role: profile.role, exp: Math.floor(Date.now() / 1000) + 30 * 86400 },
    c.env.JWT_SECRET
  );

  return c.json({ token, user: formatProfile(profile) });
});

// 3) جلب الملف الشخصي للمستخدم الحالي (Me)
auth.get('/me', authMiddleware, async (c) => {
  const user = c.get('user');
  const profile = await c.env.DB.prepare('SELECT * FROM profiles WHERE id = ?')
    .bind(user.id)
    .first<Profile>();

  if (!profile) return c.json({ error: 'المستخدم غير موجود' }, 404);

  return c.json(formatProfile(profile));
});

// 4) تغيير كلمة المرور
auth.post('/change-password', authMiddleware, async (c) => {
  const user = c.get('user');
  const { old_password, new_password } = await c.req.json();

  if (!new_password || new_password.length < 6) {
    return c.json({ error: 'كلمة المرور الجديدة يجب أن لا تقل عن 6 أحرف' }, 400);
  }

  if (old_password) {
    const profile = await c.env.DB.prepare('SELECT password_hash FROM profiles WHERE id = ?')
      .bind(user.id)
      .first<{ password_hash: string }>();

    if (!profile || !await verifyPassword(old_password, profile.password_hash)) {
      return c.json({ error: 'كلمة المرور الحالية غير صحيحة' }, 400);
    }
  }

  const newHash = await hashPassword(new_password);
  await c.env.DB.prepare('UPDATE profiles SET password_hash = ? WHERE id = ?')
    .bind(newHash, user.id)
    .run();

  return c.json({ message: 'تم تغيير كلمة المرور بنجاح' });
});

export default auth;
