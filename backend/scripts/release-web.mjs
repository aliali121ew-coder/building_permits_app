// نشر تطبيق الويب (PWA) على Cloudflare بأمر واحد:
//   node scripts/release-web.mjs      (من مجلد backend)
//
// - محرك العرض (CanvasKit) يُخدم من خادمك نفسه بدل Google CDN،
//   فيُحفظ في الجهاز ويفتح التطبيق بدون إنترنت.
// - Service Worker (offline-first) يحفظ ملفات التطبيق بعد أول فتح.
// - بعد النشر: من يفتح التطبيق يرى عدّاد 5 ثوانٍ ثم يتحدّث تلقائياً.

import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..', '..');
const isWin = process.platform === 'win32';
const run = (cmd, args) => execFileSync(cmd, args, { cwd: ROOT, stdio: 'inherit', shell: isWin });

console.log('\nبناء تطبيق الويب ...');
run('flutter', ['build', 'web', '--release', '--no-web-resources-cdn', '--pwa-strategy=offline-first']);

console.log('\nالنشر على Cloudflare ...');
run('npx', ['wrangler', 'deploy', '-c', 'wrangler.jsonc']);

console.log('\nتم نشر تطبيق الويب.');
