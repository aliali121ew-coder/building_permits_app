import { Hono } from 'hono';
import { Env, Permit, UserPayload } from '../types';
import { adminOnlyMiddleware, authMiddleware } from '../middleware/auth';
import { activeLock } from '../utils/activity';

const permits = new Hono<{ Bindings: Env; Variables: { user: UserPayload } }>();

permits.use('*', authMiddleware);

export function formatPermit(row: any) {
  if (!row) return null;
  let urls: string[] = [];
  if (typeof row.attachment_urls === 'string') {
    try {
      urls = JSON.parse(row.attachment_urls || '[]');
    } catch {
      urls = [];
    }
  } else if (Array.isArray(row.attachment_urls)) {
    urls = row.attachment_urls;
  }
  return {
    ...row,
    attachment_urls: urls,
    is_deleted: Boolean(row.is_deleted),
    duplicate_flag: Boolean(row.duplicate_flag),
  };
}

type Writer = { allowed: boolean; name: string };

/**
 * قراءة واحدة فقط من D1 لكل عملية كتابة: صلاحية الكتابة + اسم المستخدم معاً
 * (سابقاً استعلامان منفصلان).
 */
async function getWriter(db: D1Database, user: UserPayload): Promise<Writer> {
  const p = await db.prepare(
    'SELECT full_name, is_active, approval_status, license_paused, license_end_at, locked_until FROM profiles WHERE id = ?'
  ).bind(user.id).first<{ full_name: string; is_active: number; approval_status: string; license_paused: number; license_end_at: string | null; locked_until: string | null }>();

  const name = p?.full_name || 'مستخدم';
  if (user.role === 'admin') return { allowed: true, name };
  if (!p || p.is_active !== 1 || p.approval_status !== 'approved' || p.license_paused === 1 || !p.license_end_at || activeLock(p.locked_until)) {
    return { allowed: false, name };
  }
  return { allowed: new Date(p.license_end_at).getTime() > Date.now(), name };
}

function auditStmt(db: D1Database, permitId: string, action: string, user: UserPayload, name: string, nowIso: string, oldData: unknown, newData: unknown) {
  return db.prepare(`
    INSERT INTO permits_audit_log (id, permit_id, action, changed_by, changed_by_name, changed_at, old_data, new_data)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    crypto.randomUUID(), permitId, action, user.id, name, nowIso,
    oldData == null ? null : JSON.stringify(oldData),
    newData == null ? null : JSON.stringify(newData),
  );
}

// 1) جلب قائمة الإجازات (مع دعم since للمزامنة التفاضلية والبحث والسنة)
permits.get('/', async (c) => {
  const year = c.req.query('year');
  const search = c.req.query('search');
  const since = c.req.query('since');

  let query = 'SELECT * FROM permits WHERE 1=1';
  const params: any[] = [];

  if (since) {
    query += ' AND updated_at > ?';
    params.push(since);
  } else {
    query += ' AND is_deleted = 0';
  }

  if (year) {
    query += ' AND permit_year = ?';
    params.push(parseInt(year, 10));
  }

  if (search) {
    query += ' AND (full_name LIKE ? OR plot_number LIKE ?)';
    params.push(`%${search}%`, `%${search}%`);
  }

  // الترتيب مطلوب للتحميل الكامل فقط؛ السحب التفاضلي يمر عبر فهرس updated_at
  if (!since) query += ' ORDER BY permit_year DESC, permit_number ASC';

  const { results } = await c.env.DB.prepare(query).bind(...params).all<Permit>();
  return c.json(results.map(formatPermit));
});

// 2) توليد رقم الإجازة التالي لسنة معينة
permits.get('/next-number/:year', async (c) => {
  const year = parseInt(c.req.param('year'), 10);
  const result = await c.env.DB.prepare(
    'SELECT COALESCE(MAX(permit_number), 0) + 1 AS next_number FROM permits WHERE permit_year = ? AND is_deleted = 0'
  ).bind(year).first<{ next_number: number }>();

  return c.json({ next_number: result?.next_number ?? 1 });
});

// 3) جلب إجازة واحدة عبر الـ ID
permits.get('/:id', async (c) => {
  const id = c.req.param('id');
  const permit = await c.env.DB.prepare('SELECT * FROM permits WHERE id = ? AND is_deleted = 0')
    .bind(id)
    .first<Permit>();

  if (!permit) return c.json({ error: 'إجازة البناء غير موجودة' }, 404);
  return c.json(formatPermit(permit));
});

// 4) إضافة إجازة بناء جديدة — قراءة واحدة + دفعة كتابة واحدة (الإدراج + سجل التدقيق) مع RETURNING
permits.post('/', async (c) => {
  const user = c.get('user');
  const writer = await getWriter(c.env.DB, user);
  if (!writer.allowed) {
    return c.json({ error: 'حسابك غير مصرح له بالإضافة (الترخيص غير ساري أو معلق)' }, 403);
  }

  const data = await c.req.json();
  const id = data.id || crypto.randomUUID();
  const nowIso = new Date().toISOString();

  const [inserted] = await c.env.DB.batch<Permit>([
    c.env.DB.prepare(`
      INSERT INTO permits (
        id, permit_number, permit_year, full_name, plot_number, permit_date,
        notes, permit_type, name_change_notes, plot_area, building_area,
        name_per_new_registry, attachment_urls, is_deleted, duplicate_flag,
        created_by, created_at, updated_by, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      RETURNING *
    `).bind(
      id,
      parseInt(String(data.permit_number ?? 0), 10),
      parseInt(String(data.permit_year ?? new Date().getFullYear()), 10),
      data.full_name || '',
      data.plot_number || '',
      data.permit_date || nowIso.split('T')[0],
      data.notes ?? null,
      data.permit_type ?? null,
      data.name_change_notes ?? null,
      data.plot_area ?? null,
      data.building_area ?? null,
      data.name_per_new_registry ?? null,
      JSON.stringify(data.attachment_urls || []),
      data.is_deleted ? 1 : 0,
      data.duplicate_flag ? 1 : 0,
      user.id, nowIso, user.id, nowIso,
    ),
    auditStmt(c.env.DB, id, 'insert', user, writer.name, nowIso, null, data),
  ]);

  return c.json(formatPermit(inserted.results[0]), 201);
});

// 5) تعديل إجازة (كلي أو جزئي مثل الحذف المنطقي) — قراءتان + دفعة كتابة واحدة مع RETURNING
permits.put('/:id', async (c) => {
  const user = c.get('user');
  const writer = await getWriter(c.env.DB, user);
  if (!writer.allowed) {
    return c.json({ error: 'حسابك غير مصرح له بالتعديل' }, 403);
  }

  const id = c.req.param('id');
  const old = await c.env.DB.prepare('SELECT * FROM permits WHERE id = ?').bind(id).first<Permit>();
  if (!old) return c.json({ error: 'الإجازة غير موجودة' }, 404);

  const data = await c.req.json();
  const nowIso = new Date().toISOString();
  const pick = <T,>(key: string, fallback: T): T => (data[key] !== undefined ? data[key] : fallback);

  const isDeleted = data.is_deleted !== undefined ? (data.is_deleted ? 1 : 0) : old.is_deleted;
  const action = isDeleted === 1 && old.is_deleted === 0 ? 'delete'
    : isDeleted === 0 && old.is_deleted === 1 ? 'restore' : 'update';

  const [updated] = await c.env.DB.batch<Permit>([
    c.env.DB.prepare(`
      UPDATE permits SET
        permit_number = ?, permit_year = ?, full_name = ?, plot_number = ?, permit_date = ?,
        notes = ?, permit_type = ?, name_change_notes = ?, plot_area = ?, building_area = ?,
        name_per_new_registry = ?, attachment_urls = ?, is_deleted = ?, duplicate_flag = ?,
        updated_by = ?, updated_at = ?
      WHERE id = ?
      RETURNING *
    `).bind(
      data.permit_number !== undefined ? parseInt(String(data.permit_number), 10) : old.permit_number,
      data.permit_year !== undefined ? parseInt(String(data.permit_year), 10) : old.permit_year,
      pick('full_name', old.full_name),
      pick('plot_number', old.plot_number),
      pick('permit_date', old.permit_date),
      pick('notes', old.notes),
      pick('permit_type', old.permit_type),
      pick('name_change_notes', old.name_change_notes),
      pick('plot_area', old.plot_area),
      pick('building_area', old.building_area),
      pick('name_per_new_registry', old.name_per_new_registry),
      data.attachment_urls !== undefined ? JSON.stringify(data.attachment_urls) : old.attachment_urls,
      isDeleted,
      data.duplicate_flag !== undefined ? (data.duplicate_flag ? 1 : 0) : old.duplicate_flag,
      user.id, nowIso, id,
    ),
    auditStmt(c.env.DB, id, action, user, writer.name, nowIso, old, data),
  ]);

  return c.json(formatPermit(updated.results[0]));
});

// 6) حذف منطقي (Soft Delete)
permits.delete('/:id', async (c) => {
  const user = c.get('user');
  const writer = await getWriter(c.env.DB, user);
  if (!writer.allowed) {
    return c.json({ error: 'حسابك غير مصرح له بالحذف' }, 403);
  }

  const id = c.req.param('id');
  const old = await c.env.DB.prepare('SELECT * FROM permits WHERE id = ?').bind(id).first<Permit>();
  if (!old) return c.json({ error: 'الإجازة غير موجودة' }, 404);

  const nowIso = new Date().toISOString();
  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE permits SET is_deleted = 1, updated_by = ?, updated_at = ? WHERE id = ?').bind(user.id, nowIso, id),
    auditStmt(c.env.DB, id, 'delete', user, writer.name, nowIso, old, null),
  ]);

  return c.json({ message: 'تم حذف الإجازة بنجاح' });
});

// 7) حذف فعلي نهائي (Hard Delete - للمدير فقط)
permits.delete('/:id/hard', adminOnlyMiddleware, async (c) => {
  const id = c.req.param('id');
  await c.env.DB.prepare('DELETE FROM permits WHERE id = ?').bind(id).run();
  return c.json({ message: 'تم الحذف النهائي بنجاح' });
});

export default permits;
