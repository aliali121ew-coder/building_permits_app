// وظائف المتصفح (إعادة التحميل، فتح رابط) — لا تفعل شيئاً على أندرويد/ويندوز
export 'page_reload_stub.dart' if (dart.library.js_interop) 'page_reload_web.dart';
