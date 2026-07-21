import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../l10n/app_strings.dart';
import '../../models/permit_model.dart';
import '../../services/pdf_service.dart';
import '../../services/excel_service.dart';
import 'permit_form_screen.dart';

class PermitDetailScreen extends StatelessWidget {
  const PermitDetailScreen({super.key, required this.permit, this.canEdit = false});
  final PermitModel permit;
  final bool canEdit;

  /// فتح تفاصيل الإجازة في نافذة 3D متطورة مع خلفية ضبابية (Glassmorphic 3D Dialog)
  static Future<void> show(BuildContext context, PermitModel permit, {bool canEdit = false}) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'إغلاق',
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (ctx, anim1, anim2) => PermitDetailScreen(permit: permit, canEdit: canEdit),
      transitionBuilder: (ctx, anim1, anim2, child) {
        final scale = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack).value;
        return Transform.scale(
          scale: scale.clamp(0.85, 1.0),
          child: FadeTransition(
            opacity: anim1,
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 580),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xEC1E293B) : const Color(0xF7FFFFFF),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 36,
                spreadRadius: 4,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 24,
                spreadRadius: -4,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ---- 1. الهيدر 3D الجذاب ----
                _buildHeader(context, isDark),

                // ---- 2. المحتوى والتفاصيل المنظمة ----
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // كروت البيانات الأساسية (شبكية 3D)
                        _buildInfoGrid(context, isDark),

                        const SizedBox(height: 16),

                        // كروت الملاحظات وتغييرات الأسماء (إن وجدت)
                        if (permit.notes.isNotEmpty ||
                            permit.nameChangeNotes.isNotEmpty ||
                            permit.namePerNewRegistry.isNotEmpty) ...[
                          _buildNotesSection(context, isDark),
                          const SizedBox(height: 16),
                        ],

                        // سجل التدقيق وتاريخ التعديل
                        _buildAuditSection(context, isDark),

                        // قسم المرفقات والوثائق
                        _buildAttachmentsSection(context, isDark),
                      ],
                    ),
                  ),
                ),

                // ---- 3. أزرار الإجراءات السفلية ----
                _buildFooterActions(context, isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // باج رقم الإجازة والسنة
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.assignment_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'إجازة رقم ${permit.permitYear} / ${permit.permitNumber}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),

              // زر الإغلاق X
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // اسم صاحب الإجازة
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  permit.fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoGrid(BuildContext context, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 380;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _infoTile(
              context,
              icon: Icons.grid_view_rounded,
              label: context.tr('plot_number'),
              value: permit.plotNumber,
              color: AppColors.primary,
              width: isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth,
            ),
            _infoTile(
              context,
              icon: Icons.calendar_month_rounded,
              label: context.tr('permit_date'),
              value: AppDateUtils.formatDate(permit.permitDate),
              color: AppColors.secondary,
              width: isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth,
            ),
            if (permit.permitType.isNotEmpty)
              _infoTile(
                context,
                icon: Icons.apartment_rounded,
                label: context.tr('permit_type'),
                value: permit.permitType,
                color: AppColors.info,
                width: isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth,
              ),
            if (permit.plotArea != null)
              _infoTile(
                context,
                icon: Icons.square_foot_rounded,
                label: context.tr('plot_area'),
                value: '${permit.plotArea} م²',
                color: AppColors.accent,
                width: isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth,
              ),
            if (permit.buildingArea != null)
              _infoTile(
                context,
                icon: Icons.domain_rounded,
                label: context.tr('building_area'),
                value: '${permit.buildingArea} م²',
                color: AppColors.secondary,
                width: isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth,
              ),
          ],
        );
      },
    );
  }

  Widget _infoTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required double width,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.12) : color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.grey[400] : Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesSection(BuildContext context, bool isDark) {
    return Column(
      children: [
        if (permit.notes.isNotEmpty)
          _noteCard(
            context,
            title: context.tr('notes'),
            content: permit.notes,
            icon: Icons.note_alt_rounded,
            color: AppColors.info,
          ),
        if (permit.nameChangeNotes.isNotEmpty) ...[
          const SizedBox(height: 10),
          _noteCard(
            context,
            title: context.tr('name_change_notes'),
            content: permit.nameChangeNotes,
            icon: Icons.published_with_changes_rounded,
            color: AppColors.accent,
          ),
        ],
        if (permit.namePerNewRegistry.isNotEmpty) ...[
          const SizedBox(height: 10),
          _noteCard(
            context,
            title: context.tr('name_per_new_registry'),
            content: permit.namePerNewRegistry,
            icon: Icons.badge_rounded,
            color: AppColors.secondary,
          ),
        ],
      ],
    );
  }

  Widget _noteCard(
    BuildContext context, {
    required String title,
    required String content,
    required IconData icon,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.1) : color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditSection(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: isDark ? Colors.grey[400] : Colors.grey[700]),
              const SizedBox(width: 6),
              Text(
                context.tr('audit_log'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.grey[300] : Colors.grey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person_add_alt_1_rounded, size: 16, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'المُدخل: ${permit.createdByName ?? '-'} · ${AppDateUtils.formatDateTime(permit.createdAt)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.edit_note_rounded, size: 16, color: AppColors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تعديل بواسطة: ${permit.updatedByName ?? '-'} · ${AppDateUtils.formatDateTime(permit.updatedAt)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooterActions(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // زر تعديل الإجازة أو زر حسناً
          Expanded(
            child: canEdit
                ? ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        context.tr('edit'),
                        maxLines: 1,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => PermitFormScreen(existing: permit)),
                      );
                    },
                  )
                : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'حسناً',
                        maxLines: 1,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
          ),
          const SizedBox(width: 10),

          // زر طباعة PDF
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.print_rounded, size: 18, color: AppColors.primary),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  context.tr('export_pdf'),
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    fontSize: 12,
                  ),
                ),
              ),
              onPressed: () => _printPermit(context),
            ),
          ),
          const SizedBox(width: 10),

          // زر تصدير Excel
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                side: BorderSide(color: AppColors.secondary.withValues(alpha: 0.5), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.table_view_rounded, size: 18, color: AppColors.secondary),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  context.tr('export_excel'),
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    fontSize: 12,
                  ),
                ),
              ),
              onPressed: () async {
                final file = await ExcelService.instance.exportPermits([permit]);
                await OpenFilex.open(file.path);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printPermit(BuildContext context) async {
    final file = await PdfService.instance.buildSinglePermitPdf(permit);
    await OpenFilex.open(file.path);
  }

  Widget _buildAttachmentsSection(BuildContext context, bool isDark) {
    if (permit.attachmentUrls.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            const Icon(Icons.attach_file_rounded, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'المرفقات والوثائق (${permit.attachmentUrls.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Cairo'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...permit.attachmentUrls.asMap().entries.map((entry) {
          final path = entry.value;
          final isPdf = path.toLowerCase().endsWith('.pdf');
          final fileName = path.split('/').last.split('\\').last;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2),
              ),
            ),
            child: ListTile(
              leading: Icon(
                isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                color: isPdf ? AppColors.danger : AppColors.secondary,
              ),
              title: Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
              ),
              subtitle: Text(
                isPdf ? 'مستند PDF رسمي' : 'صورة مرفقة',
                style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'Cairo'),
              ),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await OpenFilex.open(path);
                } catch (_) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('تعذر فتح الملف المرفق')),
                  );
                }
              },
            ),
          );
        }),
      ],
    );
  }
}
