import { Context, Next } from 'hono';
import { verify } from 'hono/jwt';
import { Env, UserPayload } from '../types';

export async function authMiddleware(c: Context<{ Bindings: Env; Variables: { user: UserPayload } }>, next: Next) {
  const authHeader = c.req.header('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return c.json({ error: 'غير مصرح: يجب تسجيل الدخول' }, 401);
  }

  const token = authHeader.substring(7);
  try {
    const payload = await verify(token, c.env.JWT_SECRET, 'HS256') as unknown as UserPayload;
    if (!payload || !payload.id) {
      return c.json({ error: 'جلسة الدخول غير صالحة' }, 401);
    }
    c.set('user', payload);
    await next();
  } catch {
    return c.json({ error: 'جلسة الدخول منتهية أو غير صالحة' }, 401);
  }
}

export async function adminOnlyMiddleware(c: Context<{ Bindings: Env; Variables: { user: UserPayload } }>, next: Next) {
  const user = c.get('user');
  if (!user || user.role !== 'admin') {
    return c.json({ error: 'غير مصرح: هذه العملية مخصصة للمدير فقط' }, 403);
  }
  await next();
}

