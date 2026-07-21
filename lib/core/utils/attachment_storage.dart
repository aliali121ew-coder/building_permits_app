import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
    // الروابط البعيدة (مثل روابط Supabase الموقّعة) تُترك كما هي.
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
}
