import 'dart:io';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'supabase_service.dart';

/// معلومات إصدار متاح للتحديث
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.build,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.mandatory,
  });

  final String version;
  final int build;
  final String downloadUrl;
  final String releaseNotes;
  final bool mandatory;
}

/// خدمة «التحديث داخل التطبيق»:
/// - تفحص أحدث إصدار من جدول public.app_updates حسب المنصّة.
/// - تنزّل ملف التحديث (APK لأندرويد / مثبّت لويندوز) مع تقدّم.
/// - تفتح الملف لبدء التثبيت.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  String get _platform => Platform.isWindows ? 'windows' : 'android';

  /// يعيد معلومات التحديث إن وُجد إصدار أحدث من الحالي، وإلا null.
  Future<AppUpdateInfo?> checkForUpdate() async {
    if (!SupabaseService.isConfigured) return null;
    final client = SupabaseService.instance.client;
    if (client == null) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      final row = await client
          .from('app_updates')
          .select()
          .eq('platform', _platform)
          .maybeSingle();
      if (row == null) return null;

      final latestBuild = (row['latest_build'] as num?)?.toInt() ?? 0;
      final url = ((row['download_url'] as String?) ?? '').trim();

      if (latestBuild > currentBuild && url.isNotEmpty) {
        return AppUpdateInfo(
          version: (row['latest_version'] as String?) ?? '',
          build: latestBuild,
          downloadUrl: url,
          releaseNotes: (row['release_notes'] as String?) ?? '',
          mandatory: (row['mandatory'] as bool?) ?? false,
        );
      }
    } catch (_) {
      // فشل الفحص (شبكة/غيره) يُتجاهَل بأمان حتى لا يعطّل التطبيق.
    }
    return null;
  }

  /// تنزيل ملف التحديث مع دالة تقدّم (قيمة بين 0.0 و1.0).
  Future<File> downloadUpdate(
    AppUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
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

  /// فتح ملف التحديث لبدء التثبيت.
  /// - أندرويد: يفتح الـ APK عبر مثبّت النظام (يتطلب صلاحية REQUEST_INSTALL_PACKAGES).
  /// - ويندوز: يشغّل المثبّت المنزّل.
  Future<void> installUpdate(File file) async {
    if (Platform.isAndroid) {
      await OpenFilex.open(file.path);
    } else if (Platform.isWindows) {
      await Process.start(file.path, const [], mode: ProcessStartMode.detached);
    }
  }
}
