import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { Env, UserPayload } from './types';
import auth from './routes/auth';
import permits from './routes/permits';
import licensing from './routes/licensing';
import storage from './routes/storage';
import notifications from './routes/notifications';
import updates from './routes/updates';

const app = new Hono<{ Bindings: Env; Variables: { user: UserPayload } }>();

// Middlewares
app.use('*', logger());
app.use('*', cors({
  origin: '*',
  allowHeaders: ['Content-Type', 'Authorization'],
  allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
}));

// Health check endpoint
app.get('/', (c) => c.json({
  message: 'نظام إدارة إجازات البناء - خادم Cloudflare Edge شغال بنجاح',
  version: '1.0.0',
  status: 'online',
  timestamp: new Date().toISOString()
}));

// Mount Routes
app.route('/api/auth', auth);
app.route('/api/permits', permits);
app.route('/api/licensing', licensing);
app.route('/api/storage', storage);
app.route('/api/notifications', notifications);
app.route('/api/updates', updates);

// 404 Handler
app.notFound((c) => c.json({ error: 'المسار غير موجود' }, 404));

// Error Handler
app.onError((err, c) => {
  console.error('Error occurred:', err);
  return c.json({ error: 'حدث خطأ في الخادم', details: err.message }, 500);
});

export default app;

