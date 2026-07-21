import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../l10n/app_strings.dart';
import '../../models/user_model.dart';
import '../../services/supabase_service.dart';
import '../../widgets/professional_back_button.dart';

/// صفحة إدارة الصلاحيات والأدوار للمستخدمين والموظفين
/// (التحكم الكامل بـ صلاحية الإضافة، صلاحية التعديل، صلاحية الحذف، وتغيير الدور)
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  late Future<List<UserModel>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = SupabaseService.instance.fetchAllProfiles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: const ProfessionalBackButton(),
        title: const Text('إدارة الصلاحيات والمستخدمين'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث القائمة',
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<UserModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('حدث خطأ في جلب حسابات المستخدمين: ${snapshot.error}'),
              ),
            );
          }
          final users = snapshot.data ?? [];
          if (users.isEmpty) return Center(child: Text(context.tr('no_results')));

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- كارت الترويسة التوضيحي ----
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                            : [AppColors.primary, AppColors.primaryDark],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          child: const Icon(Icons.security_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'لوحة التحكم بصلاحيات الموظفين',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'يمكنك تفعيل/تعطيل صلاحيات (الإضافة، التعديل، والحذف) لكل حساب تفصيلياً.',
                                style: TextStyle(color: Colors.white70, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // قائمة كروت المستخدمين والصلاحيات
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _UserPermissionCard(
                      user: users[i],
                      onChanged: _reload,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// كارت صلاحيات المستخدم المتطور
class _UserPermissionCard extends StatefulWidget {
  const _UserPermissionCard({required this.user, required this.onChanged});

  final UserModel user;
  final VoidCallback onChanged;

  @override
  State<_UserPermissionCard> createState() => _UserPermissionCardState();
}

class _UserPermissionCardState extends State<_UserPermissionCard> {
  late bool _isActive;
  late String _role;
  late bool _canAdd;
  late bool _canEdit;
  late bool _canDelete;
  late bool _canView;

  @override
  void initState() {
    super.initState();
    _isActive = widget.user.isActive;
    _role = widget.user.role;
    _canAdd = widget.user.canAdd;
    _canEdit = widget.user.canEdit;
    _canDelete = widget.user.canDelete;
    _canView = widget.user.canView;
  }

  bool _saving = false;

  Future<void> _saveUserPermissions() async {
    setState(() => _saving = true);
    try {
      final updatedUser = widget.user.copyWith(
        role: _role,
        isActive: _isActive,
        canAdd: _role == AppConstants.roleAdmin ? true : _canAdd,
        canEdit: _role == AppConstants.roleAdmin ? true : _canEdit,
        canDelete: _role == AppConstants.roleAdmin ? true : _canDelete,
        canView: _role == AppConstants.roleAdmin ? true : _canView,
      );

      await SupabaseService.instance.updateProfilePermissions(updatedUser);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تحديث صلاحيات الحساب (${widget.user.fullName}) بنجاح'),
          backgroundColor: AppColors.secondary,
        ),
      );
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء حفظ الصلاحيات: $e'), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdmin = _role == AppConstants.roleAdmin;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- الهيدر: اسم ورتبة المستخدم ----
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: (isAdmin ? AppColors.accent : AppColors.primary).withValues(alpha: 0.15),
                  child: Icon(
                    isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                    color: isAdmin ? AppColors.accent : AppColors.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.user.fullName.isNotEmpty ? widget.user.fullName : 'مستخدم بدون اسم',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isAdmin
                                  ? AppColors.accent.withValues(alpha: 0.15)
                                  : AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              isAdmin ? 'مدير النظام (Admin)' : 'موظف (Employee)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isAdmin ? AppColors.accent : AppColors.primary,
                              ),
                            ),
                          ),
                          if (_saving)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Text(
                              _isActive ? '· نشط' : '· معطل',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: _isActive ? AppColors.secondary : AppColors.danger,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // مفتاح تفعيل/تأشير الحساب
                Switch(
                  value: _isActive,
                  activeThumbColor: AppColors.secondary,
                  onChanged: (v) {
                    setState(() => _isActive = v);
                    _saveUserPermissions();
                  },
                ),
              ],
            ),
            const Divider(height: 22),

            // ---- اختيار الدور الإداري ----
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  const Text('نوع الحساب والدور:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  DropdownButton<String>(
                    value: _role,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: AppConstants.roleAdmin, child: Text('مدير النظام (Admin)')),
                      DropdownMenuItem(value: AppConstants.roleEmployee, child: Text('موظف إدخال (Employee)')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _role = v;
                          if (v == AppConstants.roleAdmin) {
                            _canAdd = true;
                            _canEdit = true;
                            _canDelete = true;
                            _canView = true;
                          }
                        });
                        _saveUserPermissions();
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ---- كروت مفاتيح الصلاحيات (صلاحيات كاملة، الإضافة، التعديل، المشاهدة، الحذف) ----
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  // 0. صلاحيات كاملة
                  _permissionSwitchTile(
                    title: 'صلاحيات كاملة (تفعيل/تعطيل الكل)',
                    icon: Icons.gpp_good_rounded,
                    color: AppColors.primary,
                    value: isAdmin ? true : (_canAdd && _canEdit && _canView && _canDelete),
                    enabled: !isAdmin,
                    onChanged: (v) {
                      setState(() {
                        _canAdd = v;
                        _canEdit = v;
                        _canView = v;
                        _canDelete = v;
                      });
                      _saveUserPermissions();
                    },
                  ),
                  const Divider(height: 12),

                  // 1. صلاحية الإضافة
                  _permissionSwitchTile(
                    title: 'صلاحية إضافة إجازة جديدة (إضافة)',
                    icon: Icons.add_circle_outline_rounded,
                    color: AppColors.secondary,
                    value: isAdmin ? true : _canAdd,
                    enabled: !isAdmin,
                    onChanged: (v) {
                      setState(() => _canAdd = v);
                      _saveUserPermissions();
                    },
                  ),
                  const Divider(height: 12),

                  // 2. صلاحية التعديل
                  _permissionSwitchTile(
                    title: 'صلاحية تعديل البيانات (تعديل)',
                    icon: Icons.edit_outlined,
                    color: AppColors.info,
                    value: isAdmin ? true : _canEdit,
                    enabled: !isAdmin,
                    onChanged: (v) {
                      setState(() => _canEdit = v);
                      _saveUserPermissions();
                    },
                  ),
                  const Divider(height: 12),

                  // 3. صلاحية المشاهدة
                  _permissionSwitchTile(
                    title: 'صلاحية مشاهدة وتصفح البيانات (مشاهدة)',
                    icon: Icons.visibility_outlined,
                    color: AppColors.primary,
                    value: isAdmin ? true : _canView,
                    enabled: !isAdmin,
                    onChanged: (v) {
                      setState(() => _canView = v);
                      _saveUserPermissions();
                    },
                  ),
                  const Divider(height: 12),

                  // 4. صلاحية الحذف
                  _permissionSwitchTile(
                    title: 'صلاحية حذف الإجازات (حذف)',
                    icon: Icons.delete_outline_rounded,
                    color: AppColors.danger,
                    value: isAdmin ? true : _canDelete,
                    enabled: !isAdmin,
                    onChanged: (v) {
                      setState(() => _canDelete = v);
                      _saveUserPermissions();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permissionSwitchTile({
    required String title,
    required IconData icon,
    required Color color,
    required bool value,
    bool enabled = true,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: enabled ? null : Colors.grey,
            ),
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: color,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}
