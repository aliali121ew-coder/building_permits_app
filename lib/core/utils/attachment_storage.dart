import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../platform/page_reload.dart';

/// تخزين دائم للمرفقات (صور/PDF).
///
/// المشكلة: مكتبة ImagePicker/FilePicker تُعيد ملفاً داخل مجلد مؤقت (Cache)
/// يقوم نظام التشغيل بتنظيفه بعد إغلاق التطبيق، فيختفي المرفق ولا يظهر في
/// تصدير PDF لاحقاً (existsSync() = false).
///
/// الحل: ننسخ الملف فور اختياره من المجلد المؤقت إلى مجلد دائم داخل
/// getApplicationDocumentsDirectory ونخزّن المسار الدائم بدل المؤقت.
class AttachmentStorage {
  AttachmentStorage._();

  static const String _folder = 'permit_attachments';

  /// نسخ ملف واحد إلى المجلد الدائم وإرجاع المسار الجديد.
  /// - إن كان الملف داخل المجلد الدائم أصلاً، يُعاد مساره كما هو (لا نسخ مكرر).
  /// - إن كان المصدر غير موجود أو رابطاً بعيداً (http)، يُعاد المسار كما هو.
  static Future<String> persist(String sourcePath) async {
    if (kIsWeb) return sourcePath;

    // الروابط البعيدة (مثل روابط السيرفر أو R2) تُترك كما هي.
    if (sourcePath.startsWith('http://') || sourcePath.startsWith('https://')) {
      return sourcePath;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(p.join(docsDir.path, _folder));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    // إن كان الملف محفوظاً بالفعل داخل المجلد الدائم فلا داعي لإعادة نسخه.
    if (p.isWithin(targetDir.path, sourcePath)) {
      return sourcePath;
    }

    final source = File(sourcePath);
    if (!await source.exists()) {
      // الملف المصدر غير موجود؛ نُعيد المسار كما هو دون رمي استثناء.
      return sourcePath;
    }

    final ext = p.extension(sourcePath);
    final fileName = 'att_${DateTime.now().microsecondsSinceEpoch}$ext';
    final targetPath = p.join(targetDir.path, fileName);
    await source.copy(targetPath);
    return targetPath;
  }

  /// نسخ عدة ملفات إلى المجلد الدائم مع الحفاظ على الترتيب.
  static Future<List<String>> persistAll(Iterable<String> paths) async {
    final result = <String>[];
    for (final path in paths) {
      result.add(await persist(path));
    }
    return result;
  }

  static bool isRemote(String path) => path.startsWith('http://') || path.startsWith('https://');

  /// اسم مقروء للمرفق (روابط الخادم تبدأ بمعرّف عشوائي: <uuid>_name.pdf)
  static String displayName(String path) {
    var name = path.split('/').last.split('\\').last;
    try {
      name = Uri.decodeComponent(name);
    } catch (_) {}
    final m = RegExp(r'^[0-9a-fA-F-]{36}_(.+)$').firstMatch(name);
    return m?.group(1) ?? name;
  }

  /// بايتات المرفق من الخادم أو من الجهاز (null إن تعذر)
  static Future<Uint8List?> readBytes(String path) async {
    try {
      if (isRemote(path)) {
        final res = await Dio().get<List<int>>(path, options: Options(responseType: ResponseType.bytes));
        return res.data == null ? null : Uint8List.fromList(res.data!);
      }
      if (kIsWeb) return null;
      final f = File(path);
      return f.existsSync() ? await f.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  /// فتح المرفق: في المتصفح بتبويب جديد، وعلى الهاتف/الكمبيوتر بالتطبيق المناسب
  static Future<void> open(String path) async {
    if (isRemote(path)) {
      if (kIsWeb) {
        openInNewTab(path);
        return;
      }
      final dir = await getTemporaryDirectory();
      final local = p.join(dir.path, displayName(path));
      if (!File(local).existsSync()) await Dio().download(path, local);
      path = local;
    }
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) throw Exception(result.message);
  }
}
