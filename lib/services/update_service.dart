import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'cloudflare_api_service.dart';

/// معلومات إصدار متاح للتحديث
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.build,
    required this.downloadUrl,
    required this.releaseNotes,
  });

  final String version;
  final int build;
  final String downloadUrl;
  final String releaseNotes;
}

/// خدمة التحديث:
/// - أندرويد/ويندوز: تفحص جدول app_updates في D1 (صف واحد) وتنزّل المثبّت وتفتحه.
/// - الويب: تراقب بصمة (ETag) ملف main.dart.js المنشور على Cloudflare؛ أي نشر جديد
///   يغيّر البصمة تلقائياً بدون رفع رقم الإصدار يدوياً، وبدون أي قراءة من D1.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  String get _platform => Platform.isWindows ? 'windows' : 'android';

  /// يعيد معلومات التحديث إن وُجد إصدار أحدث من المثبّت حالياً، وإلا null.
  Future<AppUpdateInfo?> checkForUpdate() async {
    if (kIsWeb) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      final row = await CloudflareApiService.instance.checkUpdate(_platform);
      if (row == null) return null;

      final latestBuild = (row['latest_build'] as num?)?.toInt() ?? 0;
      final url = ((row['download_url'] as String?) ?? '').trim();
      if (latestBuild <= currentBuild || url.isEmpty) return null;

      return AppUpdateInfo(
        version: (row['latest_version'] as String?) ?? '',
        build: latestBuild,
        downloadUrl: url,
        releaseNotes: (row['release_notes'] as String?) ?? '',
      );
    } catch (_) {
      return null; // فشل الفحص لا يعطّل التطبيق
    }
  }

  Future<File> downloadUpdate(AppUpdateInfo update, {void Function(double progress)? onProgress}) async {
    final dir = await getTemporaryDirectory();
    final ext = Platform.isWindows ? 'exe' : 'apk';
    final path = '${dir.path}/permits_update_${update.build}.$ext';
    await Dio().download(
      update.downloadUrl,
      path,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) onProgress(received / total);
      },
    );
    return File(path);
  }

  /// فتح المثبّت (أندرويد: مثبّت النظام، ويندوز: تشغيل ملف الإعداد).
  Future<void> installUpdate(File file) async {
    if (Platform.isAndroid) {
      await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
    } else if (Platform.isWindows) {
      await Process.start(file.path, const [], mode: ProcessStartMode.detached);
    }
  }

  // ===================== الويب =====================

  final Dio _webDio = Dio();

  /// بصمة النسخة المنشورة حالياً من تطبيق الويب (null إن تعذر الفحص).
  Future<String?> currentWebBuildFingerprint() async {
    if (!kIsWeb) return null;
    try {
      final res = await _webDio.head<void>(
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
