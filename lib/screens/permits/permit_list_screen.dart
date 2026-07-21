import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../l10n/app_strings.dart';
import '../../models/permit_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permit_provider.dart';
import '../../widgets/professional_back_button.dart';
import 'permit_detail_screen.dart';
import 'permit_form_screen.dart';

/// شاشة الإجازات بحسب السنين (مقسمة لصفحتين: شبكة اختيار السنة <- ثم -> قائمة إجازات السنة المختارة)
class PermitListScreen extends StatefulWidget {
  const PermitListScreen({super.key, this.initialYear, this.sortByRecentEdits = false});

  final int? initialYear;
  final bool sortByRecentEdits;

  @override
  State<PermitListScreen> createState() => _PermitListScreenState();
}

class _PermitListScreenState extends State<PermitListScreen> {
  int? _selectedYear;
  bool _viewingList = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  int _displayLimit = 60;

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialYear;
    if (_selectedYear != null) {
      _viewingList = true;
    }

    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 400) {
        if (_displayLimit < 7000) {
          setState(() {
            _displayLimit += 60;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSearchOrYearChanged() {
    setState(() {
      _displayLimit = 60;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PermitProvider>();
    final years = provider.availableYears;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isSearching = _searchCtrl.text.trim().isNotEmpty;
    // هل نحن في صفحة قائمة إجازات سنة معينة أو في وضع البحث؟
    final isShowingPermitsList = _selectedYear != null || isSearching || _viewingList;

    List<PermitModel> items = provider.search(
      query: _searchCtrl.text,
      year: _selectedYear,
    );

    if (widget.sortByRecentEdits) {
      items = [...items]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }

    final visibleCount = min(items.length, _displayLimit);

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            widget.sortByRecentEdits
                ? (isShowingPermitsList
                    ? (_selectedYear == null ? 'آخر التعديلات' : 'تعديلات سنة $_selectedYear')
                    : 'تعديل الإجازات حسب السنين')
                : (isShowingPermitsList
                    ? (_selectedYear == null ? 'جميع الإجازات' : 'إجازات سنة $_selectedYear')
                    : 'مجموعات الإجازات حسب السنين'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
        leading: isShowingPermitsList
            ? Padding(
                padding: const EdgeInsets.all(8.0),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _viewingList = false;
                        _selectedYear = null;
                        _searchCtrl.clear();
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                          width: 1.2,
                        ),
                      ),
                      child: Icon(
                        Directionality.of(context) == TextDirection.rtl
                            ? Icons.arrow_forward_ios_rounded
                            : Icons.arrow_back_ios_new_rounded,
                        size: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
              )
            : const ProfessionalBackButton(),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'مزامنة البيانات',
            onPressed: () => provider.forceSync(),
          ),
        ],
      ),
      body: isShowingPermitsList
          ? _buildPermitsListPage(provider, items, visibleCount)
          : _buildYearsGridPage(provider, years),
    );
  }

  // ==========================================
  // 1. Stage 1: صفحة شبكة السنين (3 أعمدة كاملة)
  // ==========================================
  Widget _buildYearsGridPage(PermitProvider provider, List<int> years) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allYearsList = [null, ...years]; // null = جميع الإجازات

    return Column(
      children: [
        // شريط البحث المباشر العام
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => _onSearchOrYearChanged(),
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم، رقم القطعة، أو الإجازة...',
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        _onSearchOrYearChanged();
                      },
                    )
                  : null,
            ),
          ),
        ),

        // ترويسة التوجيه
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Row(
            children: [
              Icon(
                widget.sortByRecentEdits ? Icons.edit_note_rounded : Icons.calendar_month_rounded,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.sortByRecentEdits
                      ? 'اختر السنة لتعديل إجازاتها (${years.length} سنة)'
                      : 'اختر السنة لعرض إجازاتها (${years.length} سنة)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Cairo'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // شبكة السنين الـ 3 أعمدة الملائمة للشاشة بالكامل
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
            physics: const BouncingScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.25,
            ),
            itemCount: allYearsList.length,
            itemBuilder: (context, index) {
              final y = allYearsList[index];
              final count = y == null ? provider.totalCount : provider.getYearCount(y);
              final label = y == null ? 'الكل' : '$y';
              final isAllCard = y == null;

              return _YearCardWidget(
                key: ValueKey(y ?? 0),
                label: label,
                count: count,
                isAllCard: isAllCard,
                isEditMode: widget.sortByRecentEdits,
                isDark: isDark,
                onTap: () {
                  setState(() {
                    _selectedYear = y;
                    _viewingList = true;
                    _onSearchOrYearChanged();
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 2. Stage 2: صفحة إجازات السنة المختارة بالكامل
  // ==========================================
  Widget _buildPermitsListPage(PermitProvider provider, List<PermitModel> items, int visibleCount) {
    return Column(
      children: [
        // شريط تفاصيل السنة وزر العودة
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E293B)
                : AppColors.primary.withValues(alpha: 0.06),
            border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
          ),
          child: Row(
            children: [
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                ),
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary, size: 20),
                tooltip: 'العودة إلى السنين',
                onPressed: () {
                  setState(() {
                    _selectedYear = null;
                    _searchCtrl.clear();
                  });
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedYear == null ? 'جميع الإجازات المخزنة' : 'سجلات إجازات سنة $_selectedYear',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      'إجمالي العدد المطابق: ${items.length} إجازة',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // شريط البحث الخاص بداخل السنة
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => _onSearchOrYearChanged(),
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم، رقم القطعة، أو الإجازة...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        _onSearchOrYearChanged();
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ),

        const Divider(height: 1),

        // قائمة الكروت بالسلسلة الكاملة
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(context.tr('no_results')))
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: visibleCount + (visibleCount < items.length ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index < visibleCount) {
                      final item = items[index];
                      return Padding(
                        key: ValueKey(item.id),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _PermitTile(
                          permit: item,
                          showEditButton: widget.sortByRecentEdits,
                        ),
                      );
                    }
                    return Padding(
                      key: const ValueKey('show_more'),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.expand_more_rounded, size: 18),
                          label: Text('عرض المزيد (${items.length - visibleCount} متبقية)'),
                          onPressed: () {
                            setState(() {
                              _displayLimit += 100;
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PermitTile extends StatelessWidget {
  const _PermitTile({
    required this.permit,
    this.showEditButton = false,
  });

  final PermitModel permit;
  final bool showEditButton;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dismissible(
      key: ValueKey(permit.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) {
        context.read<PermitProvider>().deletePermit(
              permit,
              actorId: auth.user!.id,
              actorName: auth.user!.fullName,
            );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : AppColors.primary.withValues(alpha: 0.12),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.35)
                  : AppColors.primary.withValues(alpha: 0.07),
              blurRadius: 12,
              spreadRadius: 0,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.02)
                  : Colors.white,
              blurRadius: 1,
              spreadRadius: 0,
              offset: const Offset(-1, -1),
            ),
          ],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF2A5C8A), const Color(0xFF1B3D5E)]
                    : [AppColors.primary.withValues(alpha: 0.15), AppColors.primary.withValues(alpha: 0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
                width: 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '${permit.permitNumber}',
              style: TextStyle(
                color: isDark ? Colors.white : AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          title: Text(
            permit.fullName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          trailing: (showEditButton && (auth.user?.canEdit ?? true))
              ? IconButton(
                  icon: const Icon(Icons.edit_rounded),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => PermitFormScreen(existing: permit)),
                  ),
                )
              : null,
          onTap: () => PermitDetailScreen.show(
            context,
            permit,
            canEdit: auth.user?.canEdit ?? true,
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final auth = context.read<AuthProvider>();

    // ---- 1. التحقق من صلاحية الحذف للمستخدم ----
    if (auth.user?.canDelete != true) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.block_rounded, color: AppColors.danger, size: 48),
              ),
              const SizedBox(height: 16),
              const Text(
                'غير مسموح بالحذف',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.danger),
              ),
              const SizedBox(height: 8),
              const Text(
                'عملية حذف الإجازات مقتصرة حصرياً على مدير النظام (Admin).\nلا تملك صلاحيات حذف السجلات.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('حسناً، فهمت'),
              ),
            ],
          ),
        ),
      );
      return false;
    }

    // ---- 2. إذا كان أدمن: طلب كلمة المرور للتأكيد ----
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteConfirmDialog(permit: permit),
    );

    return result ?? false;
  }
}

class _DeleteConfirmDialog extends StatefulWidget {
  final PermitModel permit;

  const _DeleteConfirmDialog({required this.permit});

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  late final TextEditingController _pwdCtrl;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _pwdCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _pwdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_person_rounded, color: AppColors.accent, size: 22),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'تأكيد الحذف بكلمة المرور',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'أنت بصدد حذف إجازة: ${widget.permit.fullName} (رقم ${widget.permit.permitNumber}).',
              style: const TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _pwdCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة مرور مدير النظام',
                prefixIcon: Icon(Icons.key_rounded, color: AppColors.primary),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'يرجى إدخال كلمة المرور لتأكيد الحذف';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.tr('cancel')),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.delete_forever_rounded, size: 18),
          label: const Text('تأكيد الحذف النهائي'),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, true);
            }
          },
        ),
      ],
    );
  }
}

class _YearCardWidget extends StatefulWidget {
  const _YearCardWidget({
    super.key,
    required this.label,
    required this.count,
    required this.isAllCard,
    required this.isEditMode,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isAllCard;
  final bool isEditMode;
  final bool isDark;
  final VoidCallback onTap;

  @override
  State<_YearCardWidget> createState() => _YearCardWidgetState();
}

class _YearCardWidgetState extends State<_YearCardWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final isAllCard = widget.isAllCard;
    final isEditMode = widget.isEditMode;
    final count = widget.count;
    final label = widget.label;

    final useHoverStyle = _isHovered;

    Color cardBg;
    Gradient? cardGradient;
    Color txtColor;
    Color badgeBg;
    Color badgeTxt;
    Color borderColor;

    if (useHoverStyle) {
      if (isDark) {
        // في الوضع المظلم عند التحويم: الكارت أبيض (نهاري) والنصوص داكنة/أزرق
        cardBg = Colors.white;
        cardGradient = null;
        txtColor = AppColors.primary;
        badgeBg = AppColors.primary.withValues(alpha: 0.15);
        badgeTxt = AppColors.primary;
        borderColor = Colors.white;
      } else {
        // في الوضع الفاتح عند التحويم: الكارت داكن والنصوص بيضاء
        cardBg = const Color(0xFF1E293B);
        cardGradient = null;
        txtColor = Colors.white;
        badgeBg = Colors.white.withValues(alpha: 0.2);
        badgeTxt = Colors.white;
        borderColor = AppColors.primary;
      }
    } else {
      // الحالة الطبيعية بدون تحويم
      if (isAllCard) {
        cardBg = Colors.transparent;
        cardGradient = const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
        txtColor = Colors.white;
        badgeBg = Colors.white.withValues(alpha: 0.25);
        badgeTxt = Colors.white;
        borderColor = isDark ? Colors.white.withValues(alpha: 0.3) : Colors.white;
      } else {
        cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
        cardGradient = null;
        txtColor = isDark ? Colors.white : Colors.black87;
        
        // الأرقام وكلمة إجازة باللون الأبيض المريح عالي التباين
        badgeBg = isDark ? Colors.white.withValues(alpha: 0.15) : AppColors.primary.withValues(alpha: 0.85);
        badgeTxt = Colors.white;
        borderColor = isDark ? Colors.white.withValues(alpha: 0.18) : Colors.white;
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (h) {
          if (_isHovered != h) {
            setState(() => _isHovered = h);
          }
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: cardGradient == null ? cardBg : null,
              gradient: cardGradient,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: borderColor,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isAllCard
                      ? AppColors.primary.withValues(alpha: 0.35)
                      : (isDark ? Colors.black.withValues(alpha: 0.3) : AppColors.primary.withValues(alpha: 0.08)),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isEditMode && !isAllCard)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Icon(
                      Icons.edit_document,
                      size: 24,
                      color: AppColors.primary.withValues(alpha: 0.15),
                    ),
                  ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: txtColor,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isEditMode 
                            ? (isAllCard ? '$count تعديل' : '$count إجازة')
                            : '$count إجازة',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: badgeTxt,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
  }
}
