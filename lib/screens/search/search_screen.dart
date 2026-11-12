import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/date_utils.dart';
import '../../l10n/app_strings.dart';
import '../../models/permit_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permit_provider.dart';
import '../../services/hive_service.dart';
import '../../widgets/professional_back_button.dart';
import '../permits/permit_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  final String? initialQuery;
  final bool isEmbeddedDesktop;

  const SearchScreen({
    super.key,
    this.initialQuery,
    this.isEmbeddedDesktop = false,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _queryCtrl;
  int? _year;
  String? _permitType;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _showFilters = false;
  // فلتر نوع الحقل على الكمبيوتر: all, number, name, plot
  String _searchFieldScope = 'all';

  @override
  void initState() {
    super.initState();
    _queryCtrl = TextEditingController(text: widget.initialQuery ?? '');
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      _year = null;
      _permitType = null;
      _fromDate = null;
      _toDate = null;
      _searchFieldScope = 'all';
    });
  }

  List<PermitModel> _filterByScope(List<PermitModel> baseResults, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty || _searchFieldScope == 'all') return baseResults;
    final qNoSpaces = q.replaceAll(' ', '');

    return baseResults.where((p) {
      switch (_searchFieldScope) {
        case 'number':
          final yearNum = '${p.permitYear}/${p.permitNumber}';
          final numYear = '${p.permitNumber}/${p.permitYear}';
          return p.permitNumber.toString().contains(q) ||
              yearNum.contains(qNoSpaces) ||
              numYear.contains(qNoSpaces);
        case 'name':
          return p.fullName.toLowerCase().contains(q) ||
              p.namePerNewRegistry.toLowerCase().contains(q) ||
              p.nameChangeNotes.toLowerCase().contains(q);
        case 'plot':
          return p.plotNumber.toLowerCase().contains(q);
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PermitProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final isSearching = _queryCtrl.text.trim().isNotEmpty ||
        _year != null ||
        _permitType != null ||
        _fromDate != null ||
        _toDate != null;

    final rawResults = isSearching
        ? provider.search(
            query: _queryCtrl.text,
            year: _year,
            permitType: _permitType,
            fromDate: _fromDate,
            toDate: _toDate,
          )
        : <PermitModel>[];

    final results = _filterByScope(rawResults, _queryCtrl.text);
    final years = provider.availableYears;

    // ---- واجهة الكمبيوتر الاحترافية للبحث والاستعلام ----
    if (isDesktop) {
      final desktopContent = Column(
        children: [
          // صندوق البحث العلوي الفاخر للكمبيوتر
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [const Color(0xFF1A382E), const Color(0xFF0F172A)]
                          : [const Color(0xFF1E563E), const Color(0xFF143D2B)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF34D399).withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1E563E).withValues(alpha: 0.25),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.manage_search_rounded, color: Colors.white, size: 30),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'محرك البحث والاستعلام الفوري عن إجازات البناء',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'اكتب رقم الإجازة، أو رقم العقار، أو الاسم الثلاثي، أو رقم القطعة ثم اضغط على الإجازة لعرض التفاصيل وتصدير PDF',
                                  style: TextStyle(color: Colors.white70, fontSize: 12.5, fontFamily: 'Cairo'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      // حقل الإدخال الرئيسي الكبير
                      Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: Container(
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _queryCtrl,
                                autofocus: true,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                onChanged: (v) {
                                  setState(() {});
                                  if (v.trim().length >= 2) {
                                    HiveService.instance.saveSearchQuery(v);
                                  }
                                },
                                decoration: InputDecoration(
                                  hintText: 'أدخل رقم الإجازة، أو العقار، أو الاسم الثلاثي، أو رقم القطعة...',
                                  hintStyle: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13.5,
                                    color: isDark ? Colors.white54 : Colors.black45,
                                  ),
                                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF10B981), size: 26),
                                  suffixIcon: _queryCtrl.text.isNotEmpty
                                      ? IconButton(
                                          tooltip: 'مسح النص',
                                          icon: const Icon(Icons.clear_rounded),
                                          onPressed: () {
                                            _queryCtrl.clear();
                                            setState(() {});
                                          },
                                        )
                                      : null,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // فلتر السنة المباشر
                          Expanded(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int?>(
                                  isExpanded: true,
                                  value: _year,
                                  hint: const Text('كل السنوات', style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                                  items: [
                                    const DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text('كل السنوات', style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                                    ),
                                    ...years.map(
                                      (y) => DropdownMenuItem<int?>(
                                        value: y,
                                        child: Text('سنة $y', style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                                      ),
                                    ),
                                  ],
                                  onChanged: (v) => setState(() => _year = v),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // أزرار تحديد نطاق البحث السريع
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'نطاق البحث:',
                            style: TextStyle(color: Colors.white70, fontSize: 12.5, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                          ),
                          _buildScopeChip('all', 'بحث شامل (الكل)', Icons.travel_explore_rounded),
                          _buildScopeChip('number', 'رقم الإجازة', Icons.tag_rounded),
                          _buildScopeChip('name', 'الاسم الثلاثي', Icons.person_search_rounded),
                          _buildScopeChip('plot', 'رقم القطعة / العقار', Icons.grid_view_rounded),
                          if (_year != null || _permitType != null || _searchFieldScope != 'all')
                            TextButton.icon(
                              onPressed: _clearFilters,
                              icon: const Icon(Icons.restart_alt_rounded, color: Colors.amberAccent, size: 16),
                              label: const Text(
                                'إعادة ضبط الفلاتر',
                                style: TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // منطقة النتائج
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: !isSearching
                    ? _buildDesktopEmptyPrompt(isDark)
                    : results.isEmpty
                        ? _buildDesktopNoResults(isDark)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: AppColors.secondary.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
                                      ),
                                      child: Text(
                                        'عدد الإجازات المطابقة: ${results.length} إجازة',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: AppColors.secondary,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        const Icon(Icons.touch_app_rounded, size: 16, color: Colors.grey),
                                        const SizedBox(width: 6),
                                        Text(
                                          'اضغط على أي بطاقة لعرض نافذة التفاصيل الكاملة وسط الصفحة وتصدير PDF',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? Colors.white60 : Colors.black54,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: GridView.builder(
                                  padding: const EdgeInsets.fromLTRB(32, 6, 32, 28),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 14,
                                    crossAxisSpacing: 16,
                                    mainAxisExtent: 138,
                                  ),
                                  itemCount: results.length,
                                  itemBuilder: (context, i) => _buildDesktopResultCard(results[i], isDark),
                                ),
                              ),
                            ],
                          ),
              ),
            ),
          ),
        ],
      );

      if (widget.isEmbeddedDesktop) {
        return desktopContent;
      }

      return Scaffold(
        appBar: AppBar(
          leading: const ProfessionalBackButton(),
          title: Text(context.tr('search')),
        ),
        body: desktopContent,
      );
    }

    // ---- واجهة الهاتف الأصلية كما هي تماماً ----
    return Scaffold(
      appBar: AppBar(
        leading: const ProfessionalBackButton(),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(context.tr('search')),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _queryCtrl,
              onChanged: (v) {
                setState(() {});
                if (v.trim().length >= 2) {
                  HiveService.instance.saveSearchQuery(v);
                }
              },
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم، رقم القطعة، أو الإجازة...',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_queryCtrl.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _queryCtrl.clear();
                          setState(() {});
                        },
                      ),
                    IconButton(
                      icon: Icon(_showFilters ? Icons.filter_alt : Icons.filter_alt_outlined, color: AppColors.primary),
                      onPressed: () => setState(() => _showFilters = !_showFilters),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_showFilters)
            Flexible(
              flex: 0,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildFilters(years),
              ),
            ),
          Expanded(
            child: !isSearching
                ? _buildEmptySearchPlaceholder(context)
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            'عدد النتائج المطابقة: ${results.length}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: results.isEmpty
                            ? Center(child: Text(context.tr('no_results')))
                            : ListView.separated(
                                padding: const EdgeInsets.all(12),
                                itemCount: results.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, i) => _resultTile(results[i]),
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeChip(String scope, String label, IconData icon) {
    final selected = _searchFieldScope == scope;
    return InkWell(
      onTap: () => setState(() => _searchFieldScope = scope),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? const Color(0xFF143D2B) : Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: selected ? const Color(0xFF143D2B) : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopEmptyPrompt(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3), width: 1.5),
              ),
              child: const Icon(Icons.search_rounded, size: 58, color: Color(0xFF10B981)),
            ),
            const SizedBox(height: 18),
            Text(
              'ابدأ بكتابة معلومة البحث في الشريط أعلاه',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'يمكنك البحث بأي من البيانات التالية، وعند وجود الإجازة اضغط عليها لتظهر بطاقة التفاصيل وسط الصفحة مع خيار تصدير PDF:',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: isDark ? Colors.white60 : Colors.black54,
                fontFamily: 'Cairo',
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: [
                _buildHintBadge(Icons.tag_rounded, 'رقم الإجازة', 'مثال: 77 أو 2026/77', AppColors.primary, isDark),
                _buildHintBadge(Icons.home_work_rounded, 'رقم العقار / القطعة', 'مثال: 128/1060', AppColors.secondary, isDark),
                _buildHintBadge(Icons.person_rounded, 'الاسم الثلاثي', 'مثال: أسراء كريم هندول', AppColors.accent, isDark),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHintBadge(IconData icon, String title, String subtitle, Color color, bool isDark) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
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
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey, fontFamily: 'Cairo'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopNoResults(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.withValues(alpha: 0.6)),
          const SizedBox(height: 14),
          Text(
            'لا توجد إجازة مطابقة لـ "${_queryCtrl.text}"',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'تأكد من كتابة رقم الإجازة أو رقم القطعة/العقار أو الاسم الثلاثي بشكل صحيح',
            style: TextStyle(fontSize: 13, color: Colors.grey, fontFamily: 'Cairo'),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopResultCard(PermitModel permit, bool isDark) {
    final auth = context.read<AuthProvider>();
    return InkWell(
      onTap: () => PermitDetailScreen.show(
        context,
        permit,
        canEdit: auth.user?.canEdit ?? true,
      ),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : AppColors.primary.withValues(alpha: 0.18),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'إجازة ${permit.permitYear} / ${permit.permitNumber}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    permit.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      fontFamily: 'Cairo',
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.picture_as_pdf_rounded, size: 14, color: AppColors.secondary),
                      SizedBox(width: 4),
                      Text(
                        'عرض / PDF',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                const Icon(Icons.grid_view_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'القطعة / العقار: ${permit.plotNumber}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.calendar_today_rounded, size: 15, color: Colors.grey),
                const SizedBox(width: 5),
                Text(
                  AppDateUtils.formatDate(permit.permitDate),
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Cairo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// واجهة الانتظار التمهيدية (إخفاء الأسماء حتى بدء البحث)
  Widget _buildEmptySearchPlaceholder(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.search_rounded, size: 64, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            const Text(
              'البحث في سحابة إجازات البناء',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'اكتب اسم المواطن، رقم القطعة، أو رقم الإجازة في مربع البحث أعلاه لعرض النتائج مباشرة.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(List<int> years) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('advanced_filters'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: _year,
                      decoration: InputDecoration(labelText: context.tr('permit_year'), isDense: true),
                      items: years.map((y) => DropdownMenuItem(value: y, child: Text('$y', overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) => setState(() => _year = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _permitType,
                      decoration: InputDecoration(labelText: context.tr('permit_type'), isDense: true),
                      items: AppConstants.permitTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) => setState(() => _permitType = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _datePickerField(context.tr('from_date'), _fromDate, (d) => setState(() => _fromDate = d))),
                  const SizedBox(width: 10),
                  Expanded(child: _datePickerField(context.tr('to_date'), _toDate, (d) => setState(() => _toDate = d))),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  label: Text(context.tr('clear_filters')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _datePickerField(String label, DateTime? value, ValueChanged<DateTime?> onChanged) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(1970),
          lastDate: DateTime(DateTime.now().year + 1),
        );
        onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, isDense: true),
        child: Text(
          value != null ? AppDateUtils.formatDate(value) : '--',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _resultTile(PermitModel permit) {
    final auth = context.read<AuthProvider>();
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
          child: Text(
            '${permit.permitNumber}',
            style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        title: Text(permit.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Text(
          'سنة: ${permit.permitYear} | قطعة: ${permit.plotNumber}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
        onTap: () => PermitDetailScreen.show(context, permit, canEdit: auth.user?.canEdit ?? true),
      ),
    );
  }
}
