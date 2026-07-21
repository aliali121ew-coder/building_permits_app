import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../providers/permit_provider.dart';
import '../services/sync_service.dart';

/// يلفّ التطبيق بالكامل ويعرض تبويباً/Banner وسط الشاشة فور ورود تعديل
/// من مستخدم آخر عبر Realtime: "تم التعديل من قبل <الاسم>"
class RemoteChangeListener extends StatefulWidget {
  const RemoteChangeListener({super.key, required this.child});
  final Widget child;

  @override
  State<RemoteChangeListener> createState() => _RemoteChangeListenerState();
}

class _RemoteChangeListenerState extends State<RemoteChangeListener> {
  RemoteChangeEvent? _lastShown;

  @override
  Widget build(BuildContext context) {
    return Consumer<PermitProvider>(
      builder: (context, provider, child) {
        final event = provider.lastRemoteChange;
        if (event != null && event != _lastShown) {
          _lastShown = event;
          WidgetsBinding.instance.addPostFrameCallback((_) => _showBanner(context, event));
        }
        return child!;
      },
      child: widget.child,
    );
  }

  void _showBanner(BuildContext context, RemoteChangeEvent event) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final actionLabel = switch (event.action) {
      'insert' => 'أضاف إجازة جديدة',
      'delete' => 'حذف إجازة',
      _ => 'عدّل على إجازة',
    };

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primaryDark,
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            const Icon(Icons.sync_alt_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'تم التعديل من قبل ${event.actorName} — $actionLabel: ${event.permitLabel}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
