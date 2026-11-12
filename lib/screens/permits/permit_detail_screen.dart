import 'package:barcode/barcode.dart' as bc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:open_filex/open_filex.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../l10n/app_strings.dart';
import '../../models/permit_model.dart';
import '../../services/pdf_service.dart';
import '../../services/excel_service.dart';
import 'permit_form_screen.dart';

class PermitDetailScreen extends StatefulWidget {
  const PermitDetailScreen({super.key, required this.permit, this.canEdit = false});
  final PermitModel permit;
  final bool canEdit;

  /// فتح تفاصيل الإجازة في نافذة وسط الصفحة (Glassmorphic 3D Dialog)
  static Future<void> show(BuildContext context, PermitModel permit, {bool canEdit = false}) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'إغلاق',
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (ctx, anim1, anim2) => PermitDetailScreen(permit: permit, canEdit: canEdit),
      transitionBuilder: (ctx, anim1, anim2, child) {
        if (MediaQuery.sizeOf(ctx).width < _phoneBreakpoint) {
          return SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
            child: child,
          );
        }
        final scale = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack).value;
        return Transform.scale(
          scale: scale.clamp(0.88, 1.0),
          child: FadeTransition(
            opacity: anim1,
            child: child,
          ),
        );
      },
    );
  }

  /// أقل من هذا العرض = هاتف (عرض كـ Bottom Sheet)
  static const double _phoneBreakpoint = 600;

  @override
  State<PermitDetailScreen> createState() => _PermitDetailScreenState();
}

class _PermitDetailScreenState extends State<PermitDetailScreen> {
  bool _exportingPdf = false;
  bool _exportingExcel = false;
  bool _printingBarcode = false;

  PermitModel get permit => widget.permit;

  /// 200.0 ← 200 ، و 248.66 تبقى كما هي
  static String _area(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  void _showBarcodeDialog() {
    final qrSvg = bc.Barcode.qrCode().toSvg(
      'PERMIT:${permit.permitYear}/${permit.permitNumber}',
      width: 200,
      height: 200,
      drawText: false,
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'باركود إجازة ${permit.permitYear} / ${permit.permitNumber}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
              ),
              child: SvgPicture.string(qrSvg, width: 190, height: 190),
            ),
            const SizedBox(height: 12),
            Text(
              permit.fullName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
            ),
            Text(
              'قطعة: ${permit.plotNumber}',
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _handlePrintBarcode();
            },
            icon: const Icon(Icons.print_rounded, size: 18),
            label: const Text('طباعة الباركود', style: TextStyle(fontFamily: 'Cairo')),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  void _copyPermitSummary() {
    final summary = [
      'مديرية بلدية الهاشمية - قسم الإجازات',
      'إجازة رقم: ${permit.permitYear} / ${permit.permitNumber}',
      'الاسم الثلاثي: ${permit.fullName}',
      'رقم القطعة / العقار: ${permit.plotNumber}',
      'التاريخ: ${AppDateUtils.formatDate(permit.permitDate)}',
      if (permit.permitType.isNotEmpty) 'نوع الإجازة: ${permit.permitType}',
      if (permit.plotArea != null) 'مساحة العرصة: ${_area(permit.plotArea!)} م²',
      if (permit.buildingArea != null) 'مساحة البناء: ${_area(permit.buildingArea!)} م²',
      if (permit.notes.isNotEmpty) 'الملاحظات: ${permit.notes}',
    ].join('\n');

    Clipboard.setData(ClipboardData(text: summary));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('تم نسخ بيانات الإجازة إلى الحافظة بنجاح', style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.secondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _handleExportPdf() async {
    if (_exportingPdf) return;
    setState(() => _exportingPdf = true);
    try {
      await PdfService.instance.exportOrOpenSinglePermitPdf(permit);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تصدير ملف PDF: $e', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _handlePrintBarcode() async {
    if (_printingBarcode) return;
    setState(() => _printingBarcode = true);
    try {
      await PdfService.instance.printPermitBarcode(permit);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر طباعة الباركود: $e', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _printingBarcode = false);
    }
  }

  Future<void> _handleExportExcel() async {
    if (_exportingExcel) return;
    setState(() => _exportingExcel = true);
    try {
      await ExcelService.instance.exportAndOpenPermits([permit]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تصدير ملف Excel: $e', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingExcel = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final isPhone = size.width < PermitDetailScreen._phoneBreakpoint;
    final radius = isPhone ? const BorderRadius.vertical(top: Radius.circular(28)) : BorderRadius.circular(28);

    return Dialog(
      backgroundColor: Colors.transparent,
      alignment: isPhone ? Alignment.bottomCenter : Alignment.center,
      insetPadding: isPhone ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      elevation: 0,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: isPhone ? double.infinity : 640,
          // على الهاتف: لا يتجاوز 90% من الشاشة (لا يصعد تحت شريط الحالة)
          maxHeight: isPhone ? size.height * 0.9 : double.infinity,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xF21E293B) : const Color(0xFAFFFFFF),
          borderRadius: radius,
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.16) : AppColors.primary.withValues(alpha: 0.22),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 40,
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
          borderRadius: radius,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ---- 1. الهيدر الرسمي الفاخر ----
              _buildHeader(context, isDark),

              // ---- 2. المحتوى والتفاصيل المنظمة ----
              Flexible(
                child: SingleChildScrollView(
                  padding:
                      isPhone ? const EdgeInsets.fromLTRB(14, 14, 14, 16) : const EdgeInsets.fromLTRB(22, 18, 22, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // كروت البيانات الأساسية (شبكية متوازنة 6 عناصر)
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

              // ---- 3. أزرار الإجراءات السفلية المطورة ----
              SafeArea(top: false, child: _buildFooterActions(context, isDark, isPhone)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E3A5F), const Color(0xFF0F172A)]
              : [const Color(0xFF1E4976), const Color(0xFF153456)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 10,
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
              // باج رقم الإجازة والسنة (يتقلص على الشاشات الضيقة بدل أن يُقص)
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.assignment_rounded, color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'إجازة رقم ${permit.permitYear} / ${permit.permitNumber}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'عرض باركود الإجازة',
                        child: InkWell(
                          onTap: _showBarcodeDialog,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 15),
                                SizedBox(width: 4),
                                Text(
                                  'باركود',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'نسخ بيانات الإجازة',
                        child: InkWell(
                          onTap: _copyPermitSummary,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
                            ),
                            child: const Icon(Icons.copy_rounded, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // زر الإغلاق X
              IconButton(
                tooltip: 'إغلاق',
                icon: Container(
                  padding: const EdgeInsets.all(5),
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
          const SizedBox(height: 14),
          // اسم صاحب الإجازة
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                ),
                child: CircleAvatar(
                  radius: 23,
                  backgroundColor: Colors.white.withValues(alpha: 0.22),
                  child: const Icon(Icons.person_rounded, color: Colors.white, size: 27),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      permit.fullName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Cairo',
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.verified_rounded, color: Color(0xFF4ADE80), size: 14),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'مديرية بلدية الهاشمية · وثيقة إجازة رسمية مسجلة',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 11.5,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
        final twoCols = constraints.maxWidth >= 280;
        final tileWidth = twoCols ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _infoTile(
              context,
              icon: Icons.grid_view_rounded,
              label: context.tr('plot_number'),
              value: permit.plotNumber.isNotEmpty ? permit.plotNumber : '-',
              color: AppColors.primary,
              width: tileWidth,
            ),
            _infoTile(
              context,
              icon: Icons.calendar_month_rounded,
              label: context.tr('permit_date'),
              value: AppDateUtils.formatDate(permit.permitDate),
              color: AppColors.secondary,
              width: tileWidth,
            ),
            if (permit.permitType.isNotEmpty)
              _infoTile(
                context,
                icon: Icons.apartment_rounded,
                label: context.tr('permit_type'),
                value: permit.permitType,
                color: AppColors.info,
                width: tileWidth,
              ),
            if (permit.plotArea != null)
              _infoTile(
                context,
                icon: Icons.square_foot_rounded,
                label: context.tr('plot_area'),
                value: '${_area(permit.plotArea!)} م²',
                color: AppColors.accent,
                width: tileWidth,
              ),
            if (permit.buildingArea != null)
              _infoTile(
                context,
                icon: Icons.domain_rounded,
                label: context.tr('building_area'),
                value: '${_area(permit.buildingArea!)} م²',
                color: AppColors.secondary,
                width: tileWidth,
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
    final compact = width < 200;
    return Container(
      width: width,
      padding: EdgeInsets.all(compact ? 10 : 13),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.12) : color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 7 : 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: compact ? 18 : 22),
          ),
          SizedBox(width: compact ? 8 : 12),
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
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                    fontFamily: 'Cairo',
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
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color, fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontFamily: 'Cairo',
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
                  fontFamily: 'Cairo',
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
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Cairo'),
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
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Cairo'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooterActions(BuildContext context, bool isDark, bool isPhone) {
    return Container(
      padding: isPhone
          ? const EdgeInsets.fromLTRB(14, 10, 14, 10)
          : const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: _responsiveActions(
        [
          // زر تعديل الإجازة أو زر حسناً
          Expanded(
            child: widget.canEdit
                ? ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
                          fontSize: 13,
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
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
                          fontSize: 13,
                        ),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
          ),
          const SizedBox(width: 10),

          // زر تصدير / طباعة PDF
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                side: BorderSide(color: AppColors.primary.withValues(alpha: 0.6), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _exportingPdf
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : const Icon(Icons.print_rounded, size: 18, color: AppColors.primary),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  context.tr('export_pdf'),
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    fontSize: 13,
                  ),
                ),
              ),
              onPressed: _exportingPdf ? null : _handleExportPdf,
            ),
          ),
          const SizedBox(width: 10),

          // زر طباعة الباركود وحده (منفصل عن ملف التفاصيل)
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                side: const BorderSide(color: Color(0xFF1FA2C4), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _printingBarcode
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1FA2C4)),
                    )
                  : const Icon(Icons.qr_code_2_rounded, size: 18, color: Color(0xFF1FA2C4)),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'طباعة باركود',
                  maxLines: 1,
                  style: TextStyle(
                    color: Color(0xFF1FA2C4),
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    fontSize: 13,
                  ),
                ),
              ),
              onPressed: _printingBarcode ? null : _handlePrintBarcode,
            ),
          ),
          const SizedBox(width: 10),

          // زر تصدير Excel
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                side: BorderSide(color: AppColors.secondary.withValues(alpha: 0.6), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _exportingExcel
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.secondary),
                    )
                  : const Icon(Icons.table_view_rounded, size: 18, color: AppColors.secondary),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  context.tr('export_excel'),
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    fontSize: 13,
                  ),
                ),
              ),
              onPressed: _exportingExcel ? null : _handleExportExcel,
            ),
          ),
        ],
      ),
    );
  }

  /// أزرار التذييل: صف واحد على الشاشات العريضة، وشبكة 2×2 على الهاتف
  /// (بدل تصغير النصوص حتى تصبح غير مقروءة).
  Widget _responsiveActions(List<Widget> items) {
    final buttons = items.whereType<Expanded>().map((e) => e.child).toList();
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 560 || buttons.length < 4) {
          return Row(
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: buttons[i]),
              ],
            ],
          );
        }
        Widget pair(Widget a, Widget b) => Row(
              children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)],
            );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            pair(buttons[0], buttons[1]),
            const SizedBox(height: 10),
            pair(buttons[2], buttons[3]),
          ],
        );
      },
    );
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
