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

// 1) Ø¥Ù†Ø´Ø§Ø¡ Ø­Ø³Ø§Ø¨ Ø¬Ø¯ÙŠØ¯ (Sign Up)
auth.post('/register', async (c) => {
  const { email, password, full_name } = await c.req.json();

  if (!email || !password || !full_name) {
    return c.json({ error: 'Ø§Ù„Ø¨Ø±ÙŠØ¯ Ø§Ù„Ø¥Ù„ÙƒØªØ±ÙˆÙ†ÙŠ ÙˆÙƒÙ„Ù…Ø© Ø§Ù„Ù…Ø±ÙˆØ± ÙˆØ§Ù„Ø§Ø³Ù… Ø§Ù„Ø«Ù„Ø§Ø«ÙŠ Ù…Ø·Ù„ÙˆØ¨Ø©' }, 400);
  }

  const cleanEmail = email.toLowerCase().trim();
  const existing = await c.env.DB.prepare('SELECT id FROM profiles WHERE email = ?')
    .bind(cleanEmail)
    .first();

  if (existing) {
    return c.json({ error: 'Ù‡Ø°Ø§ Ø§Ù„Ø¨Ø±ÙŠØ¯ Ø§Ù„Ø¥Ù„ÙƒØªØ±ÙˆÙ†ÙŠ Ù…Ø³Ø¬Ù„ Ù…Ø³Ø¨Ù‚Ø§Ù‹' }, 400);
  }

  // Ø§Ù„ØªØ­Ù‚Ù‚ Ø¥Ù† ÙƒØ§Ù† Ù‡Ø°Ø§ Ø£ÙˆÙ„ Ù…Ø³ØªØ®Ø¯Ù… Ø£Ùˆ Ø§Ù„Ø¨Ø±ÙŠØ¯ Ø§Ù„Ø±Ø³Ù…ÙŠ Ù„Ù„Ù…Ø¯ÙŠØ±
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

// 2) ØªØ³Ø¬ÙŠÙ„ Ø§Ù„Ø¯Ø®ÙˆÙ„ (Sign In)
auth.post('/login', async (c) => {
  const { email, password } = await c.req.json();

  if (!email || !password) {
    return c.json({ error: 'ÙŠØ±Ø¬Ù‰ Ø¥Ø¯Ø®Ø§Ù„ Ø§Ù„Ø¨Ø±ÙŠØ¯ Ø§Ù„Ø¥Ù„ÙƒØªØ±ÙˆÙ†ÙŠ ÙˆÙƒÙ„Ù…Ø© Ø§Ù„Ù…Ø±ÙˆØ±' }, 400);
  }

  const profile = await c.env.DB.prepare('SELECT * FROM profiles WHERE email = ?')
    .bind(email.toLowerCase().trim())
    .first<Profile>();

  if (!profile || !profile.password_hash) {
    return c.json({ error: 'Ø§Ù„Ø¨Ø±ÙŠØ¯ Ø§Ù„Ø¥Ù„ÙƒØªØ±ÙˆÙ†ÙŠ Ø£Ùˆ ÙƒÙ„Ù…Ø© Ø§Ù„Ù…Ø±ÙˆØ± ØºÙŠØ± ØµØ­ÙŠØ­Ø©' }, 401);
  }

  const valid = await verifyPassword(password, profile.password_hash);
  if (!valid) {
    return c.json({ error: 'Ø§Ù„Ø¨Ø±ÙŠØ¯ Ø§Ù„Ø¥Ù„ÙƒØªØ±ÙˆÙ†ÙŠ Ø£Ùˆ ÙƒÙ„Ù…Ø© Ø§Ù„Ù…Ø±ÙˆØ± ØºÙŠØ± ØµØ­ÙŠØ­Ø©' }, 401);
  }

  const token = await sign(
    { id: profile.id, email: profile.email, role: profile.role, exp: Math.floor(Date.now() / 1000) + 30 * 86400 },
    c.env.JWT_SECRET
  );

  return c.json({ token, user: formatProfile(profile) });
});

// 3) Ø¬Ù„Ø¨ Ø§Ù„Ù…Ù„Ù Ø§Ù„Ø´Ø®ØµÙŠ Ù„Ù„Ù…Ø³ØªØ®Ø¯Ù… Ø§Ù„Ø­Ø§Ù„ÙŠ (Me)
auth.get('/me', authMiddleware, async (c) => {
  const user = c.get('user');
  const profile = await c.env.DB.prepare('SELECT * FROM profiles WHERE id = ?')
    .bind(user.id)
    .first<Profile>();

  if (!profile) return c.json({ error: 'Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù… ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯' }, 404);

  return c.json(formatProfile(profile));
});

// 4) ØªØºÙŠÙŠØ± ÙƒÙ„Ù…Ø© Ø§Ù„Ù…Ø±ÙˆØ±
auth.post('/change-password', authMiddleware, async (c) => {
  const user = c.get('user');
  const { old_password, new_password } = await c.req.json();

  if (!new_password || new_password.length < 6) {
    return c.json({ error: 'ÙƒÙ„Ù…Ø© Ø§Ù„Ù…Ø±ÙˆØ± Ø§Ù„Ø¬Ø¯ÙŠØ¯Ø© ÙŠØ¬Ø¨ Ø£Ù† Ù„Ø§ ØªÙ‚Ù„ Ø¹Ù† 6 Ø£Ø­Ø±Ù' }, 400);
  }

  if (old_password) {
    const profile = await c.env.DB.prepare('SELECT password_hash FROM profiles WHERE id = ?')
      .bind(user.id)
      .first<{ password_hash: string }>();

    if (!profile || !await verifyPassword(old_password, profile.password_hash)) {
      return c.json({ error: 'ÙƒÙ„Ù…Ø© Ø§Ù„Ù…Ø±ÙˆØ± Ø§Ù„Ø­Ø§Ù„ÙŠØ© ØºÙŠØ± ØµØ­ÙŠØ­Ø©' }, 400);
    }
  }

  const newHash = await hashPassword(new_password);
  await c.env.DB.prepare('UPDATE profiles SET password_hash = ? WHERE id = ?')
    .bind(newHash, user.id)
    .run();

  return c.json({ message: 'ØªÙ… ØªØºÙŠÙŠØ± ÙƒÙ„Ù…Ø© Ø§Ù„Ù…Ø±ÙˆØ± Ø¨Ù†Ø¬Ø§Ø­' });
});

export default auth;
