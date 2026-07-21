import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../models/permit_model.dart';
import '../../providers/permit_provider.dart';
import '../../services/pdf_service.dart';

/// شاشة التقارير والإحصائيات - تصميم حديث بـ 6 كارتات
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  int? _selectedYear;
  bool _loading = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _exportPdf(List<PermitModel> permits) async {
    setState(() => _loading = true);
    try {
      final reportTitle = _selectedYear != null
          ? 'كشف إجازات البناء لعام $_selectedYear'
          : 'كشف إجازات البناء الموحد';
      final file = await PdfService.instance
          .buildPermitsListPdf(permits, title: reportTitle);
      await OpenFilex.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('خطأ في تصدير PDF: $e'),
            backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = context.watch<PermitProvider>();
    final years = provider.availableYears;
    final permitsToExport = provider.search(year: _selectedYear);

    return Scaffold(
      appBar: AppBar(
        title: const Text('التقارير والإحصائيات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            onPressed: () => provider.forceSync(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- كارت الإحصائيات السريعة ----
                  _buildStatsCard(isDark, provider),
                  const SizedBox(height: 24),

                  // ---- عنوان قسم التقارير ----
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.dashboard_rounded,
                            color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'أنواع التقارير المتاحة',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ---- شبكة 6 كارتات ----
                  _buildReportsGrid(isDark, provider, years, permitsToExport),
                ],
              ),
            ),
    );
  }

  // ============================================================
  // كارت الإحصائيات العلوي
  // ============================================================
  Widget _buildStatsCard(bool isDark, PermitProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.analytics_rounded, color: Colors.white, size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'إحصائيات النظام الشاملة',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _statBadge('إجمالي الإجازات', '${provider.totalCount}',
                  Icons.folder_rounded),
              const SizedBox(width: 12),
              _statBadge('إجازات السنة', '${provider.thisYearCount}',
                  Icons.calendar_today_rounded),
              const SizedBox(width: 12),
              _statBadge('إجازات الشهر', '${provider.thisMonthCount}',
                  Icons.today_rounded),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // شبكة الـ 6 كارتات
  // ============================================================
  Widget _buildReportsGrid(bool isDark, PermitProvider provider,
      List<int> years, List<PermitModel> permitsToExport) {
    const reportCards = <_ReportCardData>[
      _ReportCardData(
        title: 'التقرير السنوي',
        subtitle: 'طباعة كشف PDF لسنة كاملة',
        icon: Icons.picture_as_pdf_rounded,
        gradientColors: [Color(0xFFD64545), Color(0xFFEB7A7A)],
        isActive: true,
      ),
      _ReportCardData(
        title: 'تصدير Excel',
        subtitle: 'تصدير جدول بيانات Excel',
        icon: Icons.table_view_rounded,
        gradientColors: [Color(0xFF2E9E6D), Color(0xFF6FCF97)],
        isActive: false,
      ),
      _ReportCardData(
        title: 'تقرير حسب النوع',
        subtitle: 'تقارير مفلترة حسب نوع الإجازة',
        icon: Icons.apartment_rounded,
        gradientColors: [Color(0xFF7B5EA7), Color(0xFFB39DDB)],
        isActive: false,
      ),
      _ReportCardData(
        title: 'الإحصائيات الشاملة',
        subtitle: 'رسوم بيانية وإحصائيات متقدمة',
        icon: Icons.bar_chart_rounded,
        gradientColors: [Color(0xFF3C93C2), Color(0xFF81D4FA)],
        isActive: false,
      ),
      _ReportCardData(
        title: 'تقرير المرفقات',
        subtitle: 'كشف بجميع الوثائق المرفقة',
        icon: Icons.attach_file_rounded,
        gradientColors: [Color(0xFFE0A526), Color(0xFFF2C94C)],
        isActive: false,
      ),
      _ReportCardData(
        title: 'تقرير التعديلات',
        subtitle: 'سجل التعديلات والتغييرات',
        icon: Icons.history_rounded,
        gradientColors: [Color(0xFF456882), Color(0xFF8FB8C9)],
        isActive: false,
      ),
    ];

    final isWide = MediaQuery.of(context).size.width > 600;
    final ratio = isWide ? 1.25 : 0.95;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        // أعطِ الكروت مساحة رأسية أكبر لتفادي RenderFlex overflow
        childAspectRatio: ratio,
      ),
      itemCount: reportCards.length,
      itemBuilder: (context, index) {
        final card = reportCards[index];
        if (card.isActive) {
          return _ActiveReportCard(
            card: card,
            years: years,
            selectedYear: _selectedYear,
            permitsCount: permitsToExport.length,
            pulseController: _pulseController,
            onYearChanged: (y) => setState(() => _selectedYear = y),
            onExport: () => _exportPdf(permitsToExport),
          );
        }
        return _InactiveReportCard(card: card);
      },
    );
  }

  Widget _statBadge(String label, String value, IconData icon) {
    return Flexible(
      fit: FlexFit.tight,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 18),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// بيانات كارت التقرير
// ============================================================
class _ReportCardData {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final bool isActive;

  const _ReportCardData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.isActive,
  });
}

// ============================================================
// كارت تقرير مفعّل (التقرير السنوي) - تفاعلي ونابض
// ============================================================
class _ActiveReportCard extends StatefulWidget {
  final _ReportCardData card;
  final List<int> years;
  final int? selectedYear;
  final int permitsCount;
  final AnimationController pulseController;
  final ValueChanged<int?> onYearChanged;
  final VoidCallback onExport;

  const _ActiveReportCard({
    required this.card,
    required this.years,
    required this.selectedYear,
    required this.permitsCount,
    required this.pulseController,
    required this.onYearChanged,
    required this.onExport,
  });

  @override
  State<_ActiveReportCard> createState() => _ActiveReportCardState();
}

class _ActiveReportCardState extends State<_ActiveReportCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedBuilder(
        animation: widget.pulseController,
        builder: (context, child) {
          final pulseValue = widget.pulseController.value;
          final glowOpacity = 0.15 + (pulseValue * 0.15);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            transform: _isHovered
                ? Matrix4.diagonal3Values(1.03, 1.03, 1.0)
                : Matrix4.identity(),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E293B), const Color(0xFF162232)]
                    : [Colors.white, const Color(0xFFF8FAFC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: widget.card.gradientColors[0].withValues(alpha: 0.5),
                width: 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.card.gradientColors[0]
                      .withValues(alpha: glowOpacity),
                  blurRadius: _isHovered ? 20 : 12,
                  spreadRadius: _isHovered ? 2 : 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _showExportDialog(context),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // الأيقونة والشارة
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  colors: widget.card.gradientColors),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: widget.card.gradientColors[0]
                                      .withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Icon(widget.card.icon,
                                color: Colors.white, size: 22),
                          ),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.secondary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: AppColors.secondary
                                          .withValues(alpha: 0.3)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_rounded,
                                        color: AppColors.secondary, size: 12),
                                    SizedBox(width: 3),
                                    Text(
                                      'مفعّل',
                                      style: TextStyle(
                                        color: AppColors.secondary,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // العنوان والوصف
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          widget.card.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.card.subtitle,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        int? tempYear = widget.selectedYear;

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final provider = context.read<PermitProvider>();
            final permitsCount = provider.search(year: tempYear).length;

            return Container(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // مقبض السحب
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // العنوان
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                                colors: widget.card.gradientColors),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.picture_as_pdf_rounded,
                              color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تصدير التقرير السنوي',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 17),
                              ),
                              Text(
                                'اختر السنة ثم اضغط تصدير',
                                style:
                                    TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // اختيار السنة
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.grey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.grey.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Flexible(
                            child: Row(
                              children: [
                                Icon(Icons.calendar_month_rounded,
                                    color: AppColors.primary, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text('اختر السنة:',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                          DropdownButton<int?>(
                            value: tempYear,
                            hint: const Text('جميع السنين'),
                            underline: const SizedBox(),
                            items: [
                              const DropdownMenuItem<int?>(
                                  value: null, child: Text('جميع السنين')),
                              ...widget.years.map((y) => DropdownMenuItem<int?>(
                                  value: y, child: Text('$y'))),
                            ],
                            onChanged: (v) {
                              setModalState(() => tempYear = v);
                              widget.onYearChanged(v);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // عداد الإجازات
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.description_rounded,
                              color: AppColors.primary, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'سيتم تصدير $permitsCount إجازة',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // زر التصدير
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 4,
                        ),
                        icon: const Icon(Icons.download_rounded, size: 22),
                        label: const Text(
                          'تصدير PDF الآن',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          widget.onExport();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================================
// كارت تقرير غير مفعّل (قيد التطوير)
// ============================================================
class _InactiveReportCard extends StatelessWidget {
  final _ReportCardData card;

  const _InactiveReportCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E293B).withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.grey.withValues(alpha: 0.2),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          // المحتوى المعتم
          Opacity(
            opacity: 0.45,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // الأيقونة
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: card.gradientColors),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(card.icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      card.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    card.subtitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark ? Colors.grey[500] : Colors.grey[500],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // شارة قيد التطوير + أيقونة القفل
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_rounded,
                    size: 10,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'قيد التطوير',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
