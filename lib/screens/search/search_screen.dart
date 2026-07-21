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
  const SearchScreen({super.key, this.initialQuery});

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
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PermitProvider>();
    final isSearching = _queryCtrl.text.trim().isNotEmpty || _year != null || _permitType != null || _fromDate != null || _toDate != null;

    final results = isSearching
        ? provider.search(
            query: _queryCtrl.text,
            year: _year,
            permitType: _permitType,
            fromDate: _fromDate,
            toDate: _toDate,
          )
        : <PermitModel>[];

    final years = provider.availableYears;

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
          // شريط مدخل البحث
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

          // الفلاتر المتقدمة مع حل مشكلة التداخل/الطفح (Overflow Fix)
          if (_showFilters)
            Flexible(
              flex: 0,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildFilters(years),
              ),
            ),

          // محتوى نتائج البحث أو الواجهة التمهيدية الخالية
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
