import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../services/update_service.dart';

/// يفحص وجود تحديث، وإن وُجد يعرض نافذة التحديث.
/// آمن للاستدعاء تلقائياً عند فتح التطبيق (silent=true لا يزعج المستخدم إن لم يوجد تحديث).
Future<void> checkAndPromptUpdate(BuildContext context, {bool silent = true}) async {
  final update = await UpdateService.instance.checkForUpdate();
  if (update == null) {
    if (!silent && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('التطبيق محدّث لآخر إصدار.', style: TextStyle(fontFamily: 'Cairo')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }
  if (!context.mounted) return;
  await _showUpdateDialog(context, update);
}

Future<void> _showUpdateDialog(BuildContext context, AppUpdateInfo update) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: !update.mandatory,
    builder: (ctx) {
      bool downloading = false;
      double progress = 0;
      String? error;

      return StatefulBuilder(
        builder: (dialogCtx, setState) {
          Future<void> startUpdate() async {
            setState(() {
              downloading = true;
              error = null;
            });
            try {
              final file = await UpdateService.instance.downloadUpdate(
                update,
                onProgress: (p) => setState(() => progress = p),
              );
              await UpdateService.instance.installUpdate(file);
              if (dialogCtx.mounted) Navigator.pop(ctx);
            } catch (_) {
              setState(() {
                downloading = false;
                error = 'تعذّر تنزيل التحديث. تحقّق من اتصالك بالإنترنت وأعد المحاولة.';
              });
            }
          }

          return PopScope(
            canPop: !update.mandatory && !downloading,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  const Icon(Icons.system_update_rounded, color: AppColors.info, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'يتوفّر تحديث جديد (${update.version})',
                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (update.mandatory)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('هذا التحديث إلزامي للمتابعة.',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.bold)),
                    ),
                  if (update.releaseNotes.isNotEmpty)
                    Text(update.releaseNotes,
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, height: 1.6)),
                  if (downloading) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: progress == 0 ? null : progress),
                    const SizedBox(height: 6),
                    Text('جارٍ التنزيل... ${(progress * 100).toStringAsFixed(0)}%',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey)),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.danger)),
                  ],
                ],
              ),
              actions: [
                if (!update.mandatory && !downloading)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('لاحقاً', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                  ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.info,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: downloading ? null : startUpdate,
                  child: Text(downloading ? 'جارٍ التنزيل...' : 'تحديث الآن',
                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
