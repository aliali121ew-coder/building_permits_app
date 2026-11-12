import { Hono } from 'hono';
import { Env, UserPayload } from '../types';
import { authMiddleware } from '../middleware/auth';

const notifications = new Hono<{ Bindings: Env; Variables: { user: UserPayload } }>();

notifications.use('*', authMiddleware);

notifications.get('/', async (c) => {
  const user = c.get('user');
  const { results } = await c.env.DB.prepare(
    'SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 50'
  ).bind(user.id).all<any>();

  const formatted = results.map(n => ({
    ...n,
    is_read: Boolean(n.is_read),
  }));

  return c.json(formatted);
});

notifications.post('/', async (c) => {
  if (c.get('user').role !== 'admin') {
    return c.json({ error: 'إرسال الإشعارات مخصص للمدير فقط' }, 403);
  }
  const { user_id, title, message } = await c.req.json();
  if (!user_id || !title || !message) {
    return c.json({ error: 'بيانات الإشعار غير مكتملة' }, 400);
  }
  await c.env.DB.prepare(`
    INSERT INTO notifications (id, user_id, title, message)
    VALUES (?, ?, ?, ?)
  `).bind(crypto.randomUUID(), user_id, title, message).run();

  return c.json({ message: 'تم إرسال الإشعار' }, 201);
});

notifications.post('/:id/read', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');
  await c.env.DB.prepare('UPDATE notifications SET is_read = 1 WHERE id = ? AND user_id = ?')
    .bind(id, user.id)
    .run();

  return c.json({ message: 'تم تحديث حالة القراءة' });
});

export default notifications;
