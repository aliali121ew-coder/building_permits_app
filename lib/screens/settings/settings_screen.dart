import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../l10n/app_strings.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/cloudflare_api_service.dart';
import '../../widgets/admin_gate.dart';
import '../../widgets/app_update_gate.dart';
import '../../widgets/password_dialogs.dart';
import '../../widgets/user_avatar.dart';
import '../admin/activity_log_screen.dart';
import '../admin/licensing_screen.dart';
import '../admin/pending_accounts_screen.dart';
import '../admin/user_management_screen.dart';
import '../auth/login_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _loadPendingCount();
  }

  /// عدد طلبات الحسابات الجديدة (للمدير فقط، قراءة واحدة عند فتح الإعدادات)
  Future<void> _loadPendingCount() async {
    if (!(context.read<AuthProvider>().isAdmin)) return;
    final n = await CloudflareApiService.instance.fetchPendingCount();
    if (mounted) setState(() => _pending = n);
  }

  Future<void> _openAdmin(Widget screen) async {
    await openAdminScreen(context, screen);
    _loadPendingCount();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: UserAvatar(path: user?.avatarPath, name: user?.fullName ?? ''),
              title: Text(user?.fullName ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(auth.isAdmin ? context.tr('admin') : context.tr('employee')),
              trailing: const Icon(Icons.edit_rounded, size: 18),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_rounded, color: AppColors.primary),
              title: const Text('تغيير كلمة المرور', style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: () => showChangePasswordDialog(context),
            ),
          ),
          if (auth.isAdmin) ...[
            const _SectionTitle('إدارة النظام'),
            _AdminTile(
              icon: Icons.how_to_reg_rounded,
              color: AppColors.info,
              title: 'طلبات الحسابات الجديدة',
              badge: _pending,
              onTap: () => _openAdmin(const PendingAccountsScreen()),
            ),
            _AdminTile(
              icon: Icons.manage_accounts_rounded,
              color: AppColors.accent,
              title: 'المستخدمون والصلاحيات',
              subtitle: 'الصلاحيات، كلمة المرور، الإيقاف والقفل',
              onTap: () => _openAdmin(const UserManagementScreen()),
            ),
            _AdminTile(
              icon: Icons.verified_user_rounded,
              color: AppColors.secondary,
              title: 'التراخيص والأجهزة',
              onTap: () => _openAdmin(const LicensingScreen()),
            ),
            _AdminTile(
              icon: Icons.history_rounded,
              color: Colors.orange,
              title: 'سجل النشاط',
              subtitle: 'كل تسجيل وتعديل من جميع الموظفين',
              onTap: () => _openAdmin(const ActivityLogScreen()),
            ),
          ],
          const _SectionTitle('التطبيق'),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode_rounded),
              title: Text(context.tr('dark_mode')),
              value: themeProvider.isDark(context),
              onChanged: (_) => themeProvider.toggle(context),
            ),
          ),
          if (kIsWeb)
          Card(
            child: ListTile(
              leading: const Icon(Icons.system_update_rounded, color: AppColors.info),
              title: const Text('التحقق من وجود تحديث', style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: () async {
                final found = await AppUpdateGate.checkNow();
                if (!found && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('التطبيق محدّث لآخر إصدار', style: TextStyle(fontFamily: 'Cairo')),
                    backgroundColor: AppColors.secondary,
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              await auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
            label: Text(context.tr('logout'), style: const TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Colors.grey)),
      );
}

class _AdminTile extends StatelessWidget {
  const _AdminTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.badge = 0,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle!, style: const TextStyle(fontSize: 11.5)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(12)),
                child: Text('$badge',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            const SizedBox(width: 6),
            const Icon(Icons.lock_outline_rounded, size: 16, color: Colors.grey),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
