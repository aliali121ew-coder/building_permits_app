import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/hive_service.dart';
import 'search_screen.dart';
import '../../widgets/professional_back_button.dart';

class SearchHistoryScreen extends StatefulWidget {
  const SearchHistoryScreen({super.key});

  @override
  State<SearchHistoryScreen> createState() => _SearchHistoryScreenState();
}

class _SearchHistoryScreenState extends State<SearchHistoryScreen> {
  final _searchCtrl = TextEditingController();
  String _dateFilter = 'all'; // 'all', 'today', 'week', 'month'
  List<SearchLog> _allLogs = [];
  List<SearchLog> _filteredLogs = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _searchCtrl.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _loadLogs() {
    setState(() {
      _allLogs = HiveService.instance.getSearchHistory();
      _applyFilters();
    });
  }

  void _applyFilters() {
    final query = _searchCtrl.text.trim().toLowerCase();
    final now = DateTime.now();
    
    setState(() {
      _filteredLogs = _allLogs.where((log) {
        // 1. فحص النص
        if (query.isNotEmpty && !log.query.toLowerCase().contains(query)) {
          return false;
        }

        // 2. فحص التاريخ والفلتر المختار
        final difference = now.difference(log.timestamp).inDays;
        if (_dateFilter == 'today') {
          return difference == 0 && log.timestamp.day == now.day;
        } else if (_dateFilter == 'week') {
          return difference <= 7;
        } else if (_dateFilter == 'month') {
          return difference <= 30;
        }

        return true;
      }).toList();
    });
  }

  Future<void> _deleteLogItem(SearchLog log) async {
    setState(() {
      _allLogs.remove(log);
      HiveService.instance.saveSearchHistory(_allLogs);
      _applyFilters();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم حذف عملية البحث من السجل', style: TextStyle(fontFamily: 'Cairo')),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح سجل البحث', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: const Text('هل أنت متأكد من مسح جميع عمليات البحث السابقة؟', style: TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('مسح الكل', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await HiveService.instance.clearSearchHistory();
      _loadLogs();
    }
  }

  // دالة تصنيف عمليات البحث حسب الأيام (اليوم، أمس، التواريخ الأقدم)
  Map<String, List<SearchLog>> _groupLogsByDay(List<SearchLog> logs) {
    final Map<String, List<SearchLog>> grouped = {};
    final now = DateTime.now();

    for (var log in logs) {
      String key;
      if (log.timestamp.year == now.year &&
          log.timestamp.month == now.month &&
          log.timestamp.day == now.day) {
        key = 'اليوم';
      } else if (log.timestamp.year == now.year &&
          log.timestamp.month == now.month &&
          log.timestamp.day == now.subtract(const Duration(days: 1)).day) {
        key = 'أمس';
      } else {
        key = "${log.timestamp.year}/${log.timestamp.month.toString().padLeft(2, '0')}/${log.timestamp.day.toString().padLeft(2, '0')}";
      }

      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(log);
    }
    return grouped;
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'م' : 'ص';
    return "${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period";
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groupedLogs = _groupLogsByDay(_filteredLogs);

    return Scaffold(
      appBar: AppBar(
        leading: const ProfessionalBackButton(),
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text('سجل البحث المنسق'),
        ),
        actions: [
          if (_allLogs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, size: 26),
              tooltip: 'مسح السجل بالكامل',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: Column(
        children: [
          // شريط البحث المدمج ونظام الفلترة
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'البحث في العمليات السابقة...',
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 12),
                
                // فلتر الفترات الزمنية بشكل أزرار أنيقة ومسطحة
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip(label: 'الكل', value: 'all'),
                      const SizedBox(width: 8),
                      _buildFilterChip(label: 'اليوم', value: 'today'),
                      const SizedBox(width: 8),
                      _buildFilterChip(label: 'آخر 7 أيام', value: 'week'),
                      const SizedBox(width: 8),
                      _buildFilterChip(label: 'آخر 30 يوم', value: 'month'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // قائمة عرض السجلات المنسقة واليومية
          Expanded(
            child: _filteredLogs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history_toggle_off_rounded,
                          size: 64,
                          color: isDark ? Colors.grey[700] : Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _allLogs.isEmpty
                              ? 'سجل البحث فارغ حالياً'
                              : 'لا توجد نتائج تطابق الفلتر الحالي',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: groupedLogs.keys.length,
                    itemBuilder: (ctx, index) {
                      final dayKey = groupedLogs.keys.elementAt(index);
                      final logs = groupedLogs[dayKey]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // عنوان اليوم/التاريخ
                          Padding(
                            padding: const EdgeInsets.only(top: 16, bottom: 8, right: 8),
                            child: Text(
                              dayKey,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                                fontFamily: 'Cairo',
                                letterSpacing: 0.5,
                                shadows: [
                                  Shadow(
                                    color: AppColors.primary.withValues(alpha: 0.08),
                                    offset: const Offset(0, 1),
                                    blurRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          
                          // قائمة الكروت الفرعية
                          Card(
                            elevation: isDark ? 0 : 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            color: isDark ? const Color(0xFF1E293B) : Colors.white,
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: logs.length,
                              separatorBuilder: (ctx, idx) => const Divider(height: 1, indent: 16, endIndent: 16),
                              itemBuilder: (ctx, idx) {
                                final log = logs[idx];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                                    radius: 18,
                                    child: const Icon(Icons.history_rounded, size: 18, color: AppColors.primary),
                                  ),
                                  title: Text(
                                    log.query,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                  subtitle: Text(
                                    _formatTime(log.timestamp),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 20, color: Colors.grey),
                                    onPressed: () => _deleteLogItem(log),
                                  ),
                                  onTap: () {
                                    // الانتقال لشاشة البحث مع الكلمة المفتاحية المحددة مباشرة
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => SearchScreen(initialQuery: log.query),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({required String label, required String value}) {
    final isSelected = _dateFilter == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? Colors.white
              : (isDark ? Colors.white70 : Colors.black87),
          fontWeight: FontWeight.bold,
          fontFamily: 'Cairo',
          fontSize: 12,
        ),
      ),
      selected: isSelected,
      selectedColor: AppColors.primary,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.grey[200],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _dateFilter = value;
            _applyFilters();
          });
        }
      },
    );
  }
}
