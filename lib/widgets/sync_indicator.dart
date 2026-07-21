import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../l10n/app_strings.dart';
import '../providers/permit_provider.dart';
import '../services/sync_service.dart';

class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.watch<PermitProvider>().syncStatus;

    final (color, label, icon) = switch (status) {
      SyncStatus.idle => (AppColors.synced, context.tr('synced'), Icons.cloud_done_rounded),
      SyncStatus.syncing => (AppColors.syncing, context.tr('syncing'), Icons.sync_rounded),
      SyncStatus.offline => (AppColors.offline, context.tr('offline'), Icons.cloud_off_rounded),
      SyncStatus.error => (AppColors.syncError, context.tr('sync_error'), Icons.error_outline_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == SyncStatus.syncing)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
