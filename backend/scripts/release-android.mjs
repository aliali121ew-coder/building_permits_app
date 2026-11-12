// نشر إصدار أندرويد جديد على Cloudflare بأمر واحد:
//   1) يرفع app-release.apk إلى R2
//   2) يحدّث صف android في جدول app_updates (D1)
// فتظهر شاشة «التحديث الإلزامي» تلقائياً على كل الأجهزة ذات الإصدار الأقدم.
//
// الاستخدام (من مجلد backend بعد: flutter build apk --release):
//   node scripts/release-android.mjs "ملاحظات الإصدار"
//
// مهم: ارفع رقم البناء في pubspec.yaml قبل كل إصدار (مثلاً 1.0.1+2 ← 1.0.2+3).

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..', '..');
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

const wrangler = (...args) =>
  execFileSync('npx', ['wrangler', ...args], { stdio: 'inherit', shell: process.platform === 'win32' });

console.log(`\n⬆️  رفع ${version}+${build} إلى R2 …`);
wrangler('r2', 'object', 'put', `${BUCKET}/${key}`, '--file', apk,
  '--content-type', 'application/vnd.android.package-archive', '--remote');

console.log('\n📝 تحديث معلومات الإصدار في D1 …');
wrangler('d1', 'execute', DB, '--remote', '--command',
  `UPDATE app_updates SET latest_version='${version}', latest_build=${Number(build)}, ` +
  `download_url='${url}', release_notes='${notes}', mandatory=1, updated_at=datetime('now') ` +
  `WHERE platform='android'`);

console.log(`\n✅ تم. الأجهزة ذات build أقل من ${build} سترى شاشة التحديث الإلزامي.\n${url}`);
