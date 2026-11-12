/**
 * سجل نشاط الحسابات للمدير. يُرجع جملة D1 جاهزة لتُضاف إلى batch مع العملية نفسها
 * (كتابة واحدة إضافية، بدون قراءات). لا يُمرَّر إليه أي كلمة مرور.
 */
export type Activity = {
  actorId?: string | null;
  actorName?: string | null;
  targetId?: string | null;
  targetName?: string | null;
  action: string;
  details?: string | null;
};

export function activityStmt(db: D1Database, a: Activity) {
  return db.prepare(`
    INSERT INTO activity_log (id, actor_id, actor_name, target_id, target_name, action, details, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    crypto.randomUUID(),
    a.actorId ?? null,
    a.actorName ?? null,
    a.targetId ?? null,
    a.targetName ?? null,
    a.action,
    a.details ?? null,
    new Date().toISOString(),
  );
}

/** هل الحساب مقفل الآن؟ يعيد تاريخ نهاية القفل أو null */
export function activeLock(lockedUntil: string | null | undefined): string | null {
  if (!lockedUntil) return null;
  return new Date(lockedUntil).getTime() > Date.now() ? lockedUntil : null;
}
