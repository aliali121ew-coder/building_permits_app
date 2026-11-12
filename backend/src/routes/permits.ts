import { Hono } from 'hono';
import { Env, Permit, UserPayload } from '../types';
import { adminOnlyMiddleware, authMiddleware } from '../middleware/auth';

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

async function canUserWrite(db: D1Database, userId: string, role: string): Promise<boolean> {
  if (role === 'admin') return true;
  const profile = await db.prepare(
    'SELECT is_active, approval_status, license_paused, license_end_at FROM profiles WHERE id = ?'
  ).bind(userId).first<{ is_active: number; approval_status: string; license_paused: number; license_end_at: string | null }>();

  if (!profile) return false;
  if (profile.is_active !== 1 || profile.approval_status !== 'approved' || profile.license_paused === 1) return false;
  if (!profile.license_end_at) return false;
  return new Date(profile.license_end_at).getTime() > Date.now();
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

  query += ' ORDER BY permit_year DESC, permit_number ASC';

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

// 4) إضافة إجازة بناء جديدة (Insert)
permits.post('/', async (c) => {
  const user = c.get('user');
  const allowed = await canUserWrite(c.env.DB, user.id, user.role);
  if (!allowed) {
    return c.json({ error: 'حسابك غير مصرح له بالإضافة (الترخيص غير ساري أو معلق)' }, 403);
  }

  const data = await c.req.json();
  const id = data.id || crypto.randomUUID();
  const permitNumber = parseInt(String(data.permit_number ?? 0), 10);
  const permitYear = parseInt(String(data.permit_year ?? new Date().getFullYear()), 10);
  const attachmentUrls = JSON.stringify(data.attachment_urls || []);
  const nowIso = new Date().toISOString();

  const profile = await c.env.DB.prepare('SELECT full_name FROM profiles WHERE id = ?').bind(user.id).first<{ full_name: string }>();

  await c.env.DB.prepare(`
    INSERT INTO permits (
      id, permit_number, permit_year, full_name, plot_number, permit_date,
      notes, permit_type, name_change_notes, plot_area, building_area,
      name_per_new_registry, attachment_urls, is_deleted, duplicate_flag,
      created_by, created_at, updated_by, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    id,
    permitNumber,
    permitYear,
    data.full_name || '',
    data.plot_number || '',
    data.permit_date || nowIso.split('T')[0],
    data.notes ?? null,
    data.permit_type ?? null,
    data.name_change_notes ?? null,
    data.plot_area ?? null,
    data.building_area ?? null,
    data.name_per_new_registry ?? null,
    attachmentUrls,
    data.is_deleted ? 1 : 0,
    data.duplicate_flag ? 1 : 0,
    user.id,
    nowIso,
    user.id,
    nowIso
  ).run();

  await c.env.DB.prepare(`
    INSERT INTO permits_audit_log (id, permit_id, action, changed_by, changed_by_name, changed_at, new_data)
    VALUES (?, ?, 'insert', ?, ?, ?, ?)
  `).bind(
    crypto.randomUUID(),
    id,
    user.id,
    profile?.full_name || 'مستخدم',
    nowIso,
    JSON.stringify(data)
  ).run();

  const created = await c.env.DB.prepare('SELECT * FROM permits WHERE id = ?').bind(id).first<Permit>();
  return c.json(formatPermit(created), 201);
});

// 5) تعديل إجازة بناء (Update - يدعم التحديث الكلي أو الجزئي مثل الحذف المنطقي)
permits.put('/:id', async (c) => {
  const user = c.get('user');
  const allowed = await canUserWrite(c.env.DB, user.id, user.role);
  if (!allowed) {
    return c.json({ error: 'حسابك غير مصرح له بالتعديل' }, 403);
  }

  const id = c.req.param('id');
  const oldPermit = await c.env.DB.prepare('SELECT * FROM permits WHERE id = ?').bind(id).first<Permit>();
  if (!oldPermit) return c.json({ error: 'الإجازة غير موجودة' }, 404);

  const data = await c.req.json();
  const nowIso = new Date().toISOString();
  const profile = await c.env.DB.prepare('SELECT full_name FROM profiles WHERE id = ?').bind(user.id).first<{ full_name: string }>();

  const permitNumber = data.permit_number !== undefined ? parseInt(String(data.permit_number), 10) : oldPermit.permit_number;
  const permitYear = data.permit_year !== undefined ? parseInt(String(data.permit_year), 10) : oldPermit.permit_year;
  const fullName = data.full_name !== undefined ? data.full_name : oldPermit.full_name;
  const plotNumber = data.plot_number !== undefined ? data.plot_number : oldPermit.plot_number;
  const permitDate = data.permit_date !== undefined ? data.permit_date : oldPermit.permit_date;
  const notes = data.notes !== undefined ? data.notes : oldPermit.notes;
  const permitType = data.permit_type !== undefined ? data.permit_type : oldPermit.permit_type;
  const nameChangeNotes = data.name_change_notes !== undefined ? data.name_change_notes : oldPermit.name_change_notes;
  const plotArea = data.plot_area !== undefined ? data.plot_area : oldPermit.plot_area;
  const buildingArea = data.building_area !== undefined ? data.building_area : oldPermit.building_area;
  const namePerNewRegistry = data.name_per_new_registry !== undefined ? data.name_per_new_registry : oldPermit.name_per_new_registry;
  const attachmentUrls = data.attachment_urls !== undefined ? JSON.stringify(data.attachment_urls) : oldPermit.attachment_urls;
  const isDeleted = data.is_deleted !== undefined ? (data.is_deleted ? 1 : 0) : oldPermit.is_deleted;
  const duplicateFlag = data.duplicate_flag !== undefined ? (data.duplicate_flag ? 1 : 0) : oldPermit.duplicate_flag;

  await c.env.DB.prepare(`
    UPDATE permits SET
      permit_number = ?, permit_year = ?, full_name = ?, plot_number = ?, permit_date = ?,
      notes = ?, permit_type = ?, name_change_notes = ?, plot_area = ?, building_area = ?,
      name_per_new_registry = ?, attachment_urls = ?, is_deleted = ?, duplicate_flag = ?,
      updated_by = ?, updated_at = ?
    WHERE id = ?
  `).bind(
    permitNumber,
    permitYear,
    fullName,
    plotNumber,
    permitDate,
    notes,
    permitType,
    nameChangeNotes,
    plotArea,
    buildingArea,
    namePerNewRegistry,
    attachmentUrls,
    isDeleted,
    duplicateFlag,
    user.id,
    nowIso,
    id
  ).run();

  const action = isDeleted === 1 && oldPermit.is_deleted === 0 ? 'delete'
    : isDeleted === 0 && oldPermit.is_deleted === 1 ? 'restore' : 'update';

  await c.env.DB.prepare(`
    INSERT INTO permits_audit_log (id, permit_id, action, changed_by, changed_by_name, changed_at, old_data, new_data)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    crypto.randomUUID(),
    id,
    action,
    user.id,
    profile?.full_name || 'مستخدم',
    nowIso,
    JSON.stringify(oldPermit),
    JSON.stringify(data)
  ).run();

  const updated = await c.env.DB.prepare('SELECT * FROM permits WHERE id = ?').bind(id).first<Permit>();
  return c.json(formatPermit(updated));
});

// 6) حذف منطقي (Soft Delete)
permits.delete('/:id', async (c) => {
  const user = c.get('user');
  const allowed = await canUserWrite(c.env.DB, user.id, user.role);
  if (!allowed) {
    return c.json({ error: 'حسابك غير مصرح له بالحذف' }, 403);
  }

  const id = c.req.param('id');
  const oldPermit = await c.env.DB.prepare('SELECT * FROM permits WHERE id = ?').bind(id).first<Permit>();
  if (!oldPermit) return c.json({ error: 'الإجازة غير موجودة' }, 404);

  const nowIso = new Date().toISOString();
  const profile = await c.env.DB.prepare('SELECT full_name FROM profiles WHERE id = ?').bind(user.id).first<{ full_name: string }>();

  await c.env.DB.prepare(`
    UPDATE permits SET is_deleted = 1, updated_by = ?, updated_at = ? WHERE id = ?
  `).bind(user.id, nowIso, id).run();

  await c.env.DB.prepare(`
    INSERT INTO permits_audit_log (id, permit_id, action, changed_by, changed_by_name, changed_at, old_data)
    VALUES (?, ?, 'delete', ?, ?, ?, ?)
  `).bind(
    crypto.randomUUID(),
    id,
    user.id,
    profile?.full_name || 'مستخدم',
    nowIso,
    JSON.stringify(oldPermit)
  ).run();

  return c.json({ message: 'تم حذف الإجازة بنجاح' });
});

// 7) حذف فعلي نهائي (Hard Delete - للمدير فقط)
permits.delete('/:id/hard', adminOnlyMiddleware, async (c) => {
  const id = c.req.param('id');
  await c.env.DB.prepare('DELETE FROM permits WHERE id = ?').bind(id).run();
  return c.json({ message: 'تم الحذف النهائي بنجاح' });
});

export default permits;
