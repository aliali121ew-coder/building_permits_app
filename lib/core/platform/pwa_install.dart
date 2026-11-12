// تثبيت التطبيق كـ PWA من داخل المتصفح (لا يفعل شيئاً خارج الويب)
export 'pwa_install_stub.dart' if (dart.library.js_interop) 'pwa_install_web.dart';
