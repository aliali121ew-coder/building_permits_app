import { Hono } from 'hono';
import { Env, UserPayload } from '../types';

const updates = new Hono<{ Bindings: Env; Variables: { user: UserPayload } }>();

// فحص التحديث: تستدعيه نسخ APK المثبّتة سابقاً (لا يُنشر لها إصدار جديد؛ التطبيق صار PWA)
updates.get('/check/:platform', async (c) => {
  const platform = c.req.param('platform').toLowerCase();
  const updateInfo = await c.env.DB.prepare('SELECT * FROM app_updates WHERE platform = ?')
    .bind(platform)
    .first();

  if (!updateInfo) return c.json({ error: 'المنصة غير مدعومة' }, 404);
  // mandatory كقيمة منطقية: النسخ المثبّتة القديمة تقرأه بـ `as bool?`
  // ورقم (0/1) من D1 كان يُسقط الفحص بصمت فلا يظهر التحديث أبداً.
  return c.json({ ...updateInfo, mandatory: Boolean(updateInfo.mandatory) });
});

export default updates;

