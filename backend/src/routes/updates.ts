import { Hono } from 'hono';
import { Env, UserPayload } from '../types';
import { adminOnlyMiddleware, authMiddleware } from '../middleware/auth';

const updates = new Hono<{ Bindings: Env; Variables: { user: UserPayload } }>();

// فحص التحديث متاح للجميع
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

// تعديل التحديث (المدير فقط)
updates.post('/set', authMiddleware, adminOnlyMiddleware, async (c) => {
  const { platform, latest_version, latest_build, download_url, release_notes, mandatory } = await c.req.json();

  await c.env.DB.prepare(`
    INSERT INTO app_updates (id, platform, latest_version, latest_build, download_url, release_notes, mandatory, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
    ON CONFLICT (platform) DO UPDATE SET
      latest_version = excluded.latest_version,
      latest_build = excluded.latest_build,
      download_url = excluded.download_url,
      release_notes = excluded.release_notes,
      mandatory = excluded.mandatory,
      updated_at = datetime('now')
  `).bind(
    crypto.randomUUID(),
    platform.toLowerCase(),
    latest_version,
    latest_build,
    download_url || '',
    release_notes || '',
    mandatory ? 1 : 0
  ).run();

  return c.json({ message: 'تم تحديث معلومات الإصدار بنجاح' });
});

export default updates;

