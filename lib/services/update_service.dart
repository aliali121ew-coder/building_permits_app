import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// اكتشاف نشر نسخة جديدة من تطبيق الويب (PWA):
/// يراقب بصمة (ETag) ملف main.dart.js المنشور على Cloudflare. أي نشر جديد يغيّر
/// البصمة تلقائياً، بدون رفع رقم الإصدار يدوياً، وبدون أي قراءة من D1.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  final Dio _dio = Dio();

  /// بصمة النسخة المنشورة حالياً (null خارج الويب أو إن تعذر الفحص).
  Future<String?> currentWebBuildFingerprint() async {
    if (!kIsWeb) return null;
    try {
      final res = await _dio.head<void>(
        Uri.base.resolve('main.dart.js').toString(),
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
        options: Options(headers: {'Cache-Control': 'no-cache'}),
      );
      return res.headers.value('etag') ?? res.headers.value('last-modified') ?? res.headers.value('content-length');
    } catch (_) {
      return null;
    }
  }
}
