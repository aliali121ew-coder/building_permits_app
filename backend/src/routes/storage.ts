import { Hono } from 'hono';
import { Env, UserPayload } from '../types';
import { authMiddleware } from '../middleware/auth';

const storage = new Hono<{ Bindings: Env; Variables: { user: UserPayload } }>();

// رفع ملف إلى Cloudflare R2 (يتطلب تسجيل الدخول)
storage.post('/upload', authMiddleware, async (c) => {
  const body = await c.req.parseBody();
  const file = body['file'] as File | undefined;
  const permitId = (body['permit_id'] as string) || 'general';

  if (!file) {
    return c.json({ error: 'لم يتم إرفاق أي ملف' }, 400);
  }

  const safeFileName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_');
  const safePermitId = permitId.replace(/[^a-zA-Z0-9_-]/g, '_');
  const key = `${safePermitId}/${crypto.randomUUID()}_${safeFileName}`;

  const arrayBuffer = await file.arrayBuffer();
  await c.env.ATTACHMENTS.put(key, arrayBuffer, {
    httpMetadata: {
      contentType: file.type || 'application/octet-stream',
    },
  });

  // رابط مطلق للملف (مسار الملف يحتوي معرّفاً عشوائياً يصعب تخمينه)
  const origin = new URL(c.req.url).origin;
  const url = `${origin}/api/storage/file/${key.split('/').map(encodeURIComponent).join('/')}`;
  return c.json({ key, url });
});

// تنزيل وعرض الملف المخزن في R2
storage.get('/file/:key{.*}', async (c) => {
  const key = c.req.param('key');
  const object = await c.env.ATTACHMENTS.get(key);

  if (!object) {
    return c.json({ error: 'الملف غير موجود' }, 404);
  }

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('etag', object.httpEtag);
  headers.set('cache-control', 'public, max-age=31536000'); // كاش لمدة سنة

  return new Response(object.body, { headers });
});

export default storage;

