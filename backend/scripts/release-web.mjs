// نشر تطبيق الويب (PWA) على Cloudflare بأمر واحد:
//   node backend/scripts/release-web.mjs      (من مجلد المشروع)
//
// - محرك العرض (CanvasKit) يُخدم من خادمك نفسه بدل Google CDN،
//   فيُحفظ في الجهاز ويفتح التطبيق بدون إنترنت.
// - Service Worker (offline-first) يحفظ ملفات التطبيق بعد أول فتح.
// - بعد النشر: من يفتح التطبيق يرى عدّاد 5 ثوانٍ ثم يتحدّث تلقائياً.

import { execSync } from 'node:child_process';
import { rmSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..', '..');
// أمر نصي واحد (وسائط ثابتة بلا مسافات) — يعمل على ويندوز بدون تحذير DEP0190
const run = (cmd, args) => execSync([cmd, ...args].join(' '), { cwd: ROOT, stdio: 'inherit' });

// كاش البناء القديم قد يحتفظ بحزم محذوفة فيفشل البناء
rmSync(resolve(ROOT, '.dart_tool', 'flutter_build'), { recursive: true, force: true });

console.log('\nبناء تطبيق الويب ...');
run('flutter', ['build', 'web', '--release', '--no-web-resources-cdn', '--pwa-strategy=offline-first']);

console.log('\nالنشر على Cloudflare ...');
run('npx', ['wrangler', 'deploy', '-c', 'wrangler.jsonc']);

console.log('\nتم نشر تطبيق الويب.');
