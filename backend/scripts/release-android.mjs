// نشر إصدار أندرويد جديد على Cloudflare بأمر واحد:
//   1) يرفع app-release.apk إلى R2
//   2) يحدّث صف android في جدول app_updates (D1)
// فتظهر نافذة التحديث تلقائياً على كل الأجهزة ذات الإصدار الأقدم.
//
// الاستخدام (من مجلد backend بعد: flutter build apk --release):
//   node scripts/release-android.mjs "ملاحظات الإصدار"
//
// مهم: ارفع رقم البناء في pubspec.yaml قبل كل إصدار (مثلاً 1.0.1+2 ← 1.0.2+3).

import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..', '..');
const BACKEND = resolve(ROOT, 'backend');
const API_URL = 'https://building-permits-backend.aliali121ew.workers.dev';
const BUCKET = 'permit-attachments';
const DB = 'permits-db';

const pubspec = readFileSync(resolve(ROOT, 'pubspec.yaml'), 'utf8');
const m = pubspec.match(/^version:\s*([\d.]+)\+(\d+)/m);
if (!m) throw new Error('تعذر قراءة version من pubspec.yaml (الصيغة المطلوبة 1.0.0+1)');
const [, version, build] = m;

const apk = resolve(ROOT, 'build/app/outputs/flutter-apk/app-release.apk');
if (!existsSync(apk)) throw new Error(`لم يُعثر على ${apk}\nشغّل أولاً: flutter build apk --release`);

const notes = (process.argv[2] || `الإصدار ${version}`).replace(/'/g, "''");
const key = `releases/permits-${build}.apk`;
const url = `${API_URL}/api/storage/file/${key}`;

// على ويندوز يلزم shell لتشغيل npx، فنقتبس أي وسيط فيه مسافات
const isWin = process.platform === 'win32';
const quote = (a) => (isWin && /[\s"]/.test(a) ? `"${a.replaceAll('"', '\\"')}"` : a);
const wrangler = (...args) =>
  execFileSync('npx', ['wrangler', ...args, '-c', 'wrangler.toml'].map(quote), {
    cwd: BACKEND,
    stdio: 'inherit',
    shell: isWin,
  });

console.log(`\nرفع ${version}+${build} إلى R2 ...`);
wrangler('r2', 'object', 'put', `${BUCKET}/${key}`, '--file', apk,
  '--content-type', 'application/vnd.android.package-archive', '--remote');

// جملة SQL في ملف: النص العربي والمسافات لا تمر عبر سطر الأوامر
console.log('\nتحديث معلومات الإصدار في D1 ...');
const sqlDir = resolve(BACKEND, '.wrangler');
mkdirSync(sqlDir, { recursive: true });
const sqlFile = resolve(sqlDir, 'release.sql');
writeFileSync(
  sqlFile,
  `UPDATE app_updates SET latest_version='${version}', latest_build=${Number(build)}, ` +
    `download_url='${url}', release_notes='${notes}', mandatory=1, updated_at=datetime('now') ` +
    `WHERE platform='android';\n`,
  'utf8',
);
try {
  wrangler('d1', 'execute', DB, '--remote', '--yes', `--file=${sqlFile}`);
} finally {
  rmSync(sqlFile, { force: true });
}

console.log(`\nتم. الأجهزة ذات build أقل من ${build} سترى نافذة التحديث.\n${url}`);
