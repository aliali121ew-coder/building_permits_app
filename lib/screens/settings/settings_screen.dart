import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../l10n/app_strings.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/permit_provider.dart';
import '../../providers/theme_provider.dart';
import '../admin/user_management_screen.dart';
import '../auth/login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final localeProvider = context.watch<LocaleProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: const Icon(Icons.person_rounded, color: AppColors.primary),
              ),
              title: Text(auth.user?.fullName ?? ''),
              subtitle: Text(auth.isAdmin ? context.tr('admin') : context.tr('employee')),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_rounded, color: AppColors.primary),
              title: const Text('تغيير كلمة المرور', style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: () => _showChangePasswordDialog(context),
            ),
          ),
          if (auth.isAdmin) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.security_rounded, color: AppColors.accent),
                title: const Text('إدارة صلاحيات المستخدمين والموظفين', style: TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const UserManagementScreen()),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode_rounded),
              title: Text(context.tr('dark_mode')),
              value: themeProvider.isDark(context),
              onChanged: (_) => themeProvider.toggle(context),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.language_rounded),
              title: Text(context.tr('language')),
              trailing: Text(localeProvider.locale.languageCode == 'ar' ? 'العربية' : 'English'),
              onTap: () => localeProvider.toggle(),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_sync_rounded, color: AppColors.info),
              title: const Text('تحديث كامل من الخادم', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text(
                'يمسح النسخة المحلية ويعيد تنزيل كل الإجازات من الخادم (يحل مشكلة البيانات القديمة أو المكررة)',
                style: TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: () => _showFullRefreshDialog(context),
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

  void _showChangePasswordDialog(BuildContext context) {
    final auth = context.read<AuthProvider>();
    
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    
    bool obscurePassword = true;
    bool obscureConfirm = true;
    
    bool hasLength = false;
    bool hasUpper = false;
    bool hasLower = false;
    bool hasDigit = false;
    bool hasSpecial = false;
    String passwordStrength = '';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            
            void updatePasswordStrength(String password) {
              if (password.isEmpty) {
                setDialogState(() {
                  hasLength = false;
                  hasUpper = false;
                  hasLower = false;
                  hasDigit = false;
                  hasSpecial = false;
                  passwordStrength = '';
                });
                return;
              }
              setDialogState(() {
                hasLength = password.length >= 8;
                hasUpper = RegExp(r'[A-Z]').hasMatch(password);
                hasLower = RegExp(r'[a-z]').hasMatch(password);
                hasDigit = RegExp(r'[0-9]').hasMatch(password);
                hasSpecial = RegExp(r'[!@#\$%^&*()_,\.?":{}|<>\-]').hasMatch(password);
                
                int score = 0;
                if (hasLength) score++;
                if (hasUpper) score++;
                if (hasLower) score++;
                if (hasDigit) score++;
                if (hasSpecial) score++;
                
                if (score <= 2) {
                  passwordStrength = 'weak';
                } else if (score <= 4) {
                  passwordStrength = 'medium';
                } else {
                  passwordStrength = 'strong';
                }
              });
            }
            
            Color strengthColor = Colors.grey;
            String strengthLabel = '';
            int dotsCount = 0;
            if (passwordStrength.isNotEmpty) {
              switch (passwordStrength) {
                case 'weak':
                  strengthColor = AppColors.danger;
                  strengthLabel = 'ضعيفة';
                  dotsCount = 1;
                  break;
                case 'medium':
                  strengthColor = Colors.orange;
                  strengthLabel = 'متوسطة';
                  dotsCount = 2;
                  break;
                case 'strong':
                  strengthColor = AppColors.secondary;
                  strengthLabel = 'قوية جداً';
                  dotsCount = 3;
                  break;
              }
            }

            Widget requirementItem(String text, bool met) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      met ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: met ? AppColors.secondary : AppColors.danger,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Cairo',
                        color: met ? AppColors.secondary : Colors.grey,
                        fontWeight: met ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Row(
                children: [
                  Icon(Icons.lock_reset_rounded, color: AppColors.primary, size: 28),
                  SizedBox(width: 10),
                  Text(
                    'تغيير كلمة المرور',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'يرجى إدخال كلمة مرور جديدة مستوفية لشروط الأمان الموضحة أدناه.',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey, height: 1.5),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: passwordCtrl,
                        obscureText: obscurePassword,
                        obscuringCharacter: '●',
                        onChanged: updatePasswordStrength,
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور الجديدة',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
                          suffixIcon: IconButton(
                            icon: Icon(obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                            onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                      
                      // مؤشر القوة وقائمة الشروط
                      if (passwordStrength.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: strengthColor.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: strengthColor.withValues(alpha: 0.15), width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text('قوة كلمة المرور: ', style: TextStyle(fontSize: 11, fontFamily: 'Cairo')),
                                  Text(
                                    strengthLabel,
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: strengthColor, fontFamily: 'Cairo'),
                                  ),
                                  const Spacer(),
                                  Row(
                                    children: List.generate(3, (index) {
                                      final isActive = index < dotsCount;
                                      return Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 2),
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isActive ? strengthColor : Colors.grey.withValues(alpha: 0.3),
                                        ),
                                      );
                                    }),
                                  ),
                                ],
                              ),
                              const Divider(height: 12),
                              requirementItem('طول كلمة المرور 8 رموز فما فوق', hasLength),
                              requirementItem('أحرف كبيرة (A-Z) على الأقل', hasUpper),
                              requirementItem('أحرف صغيرة (a-z) على الأقل', hasLower),
                              requirementItem('أرقام (0-9) على الأقل', hasDigit),
                              requirementItem('رموز خاصة (مثل !@#\$%^&*()_) على الأقل', hasSpecial),
                            ],
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: confirmCtrl,
                        obscureText: obscureConfirm,
                        obscuringCharacter: '●',
                        decoration: InputDecoration(
                          labelText: 'تأكيد كلمة المرور الجديدة',
                          prefixIcon: const Icon(Icons.lock_reset_rounded, color: AppColors.primary),
                          suffixIcon: IconButton(
                            icon: Icon(obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                            onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: auth.loading ? null : () => Navigator.pop(ctx),
                  child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: auth.loading ? null : () async {
                    if (passwordCtrl.text.isEmpty) {
                      _showSnackBar(context, 'يرجى إدخال كلمة المرور الجديدة.', AppColors.danger);
                      return;
                    }
                    if (passwordCtrl.text != confirmCtrl.text) {
                      _showSnackBar(context, 'كلمتا المرور غير متطابقتين.', AppColors.danger);
                      return;
                    }
                    if (!hasLength || !hasUpper || !hasLower || !hasDigit || !hasSpecial) {
                      _showSnackBar(context, 'يرجى استيفاء جميع شروط الأمان لكلمة المرور.', AppColors.danger);
                      return;
                    }
                    
                    final ok = await auth.updatePassword(passwordCtrl.text);
                    if (ok) {
                      if (context.mounted) {
                        Navigator.pop(ctx);
                        _showSnackBar(context, 'تم تحديث كلمة المرور بنجاح.', AppColors.secondary);
                      }
                    } else {
                      if (context.mounted) {
                        _showSnackBar(context, auth.error ?? 'حدث خطأ أثناء التحديث.', AppColors.danger);
                      }
                    }
                  },
                  child: auth.loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('حفظ التحديث', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showFullRefreshDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool loading = false;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Row(
                children: [
                  Icon(Icons.cloud_sync_rounded, color: AppColors.info, size: 26),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'تحديث كامل من الخادم',
                      style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: const Text(
                'سيتم مسح النسخة المحلية على هذا الجهاز وإعادة تنزيل كل الإجازات من الخادم.\n\n'
                'ملاحظة: أي تعديلات محلية لم تُزامَن بعد ستُفقد، والخادم هو المصدر الموثوق. تأكّد من اتصالك بالإنترنت.',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 13, height: 1.6),
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.pop(ctx),
                  child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.info,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: loading
                      ? null
                      : () async {
                          setDialogState(() => loading = true);
                          try {
                            await context.read<PermitProvider>().fullRefresh();
                            if (dialogCtx.mounted) Navigator.pop(ctx);
                            if (context.mounted) {
                              _showSnackBar(context, 'تم التحديث الكامل بنجاح من الخادم.', AppColors.secondary);
                            }
                          } catch (_) {
                            setDialogState(() => loading = false);
                            if (context.mounted) {
                              _showSnackBar(context, 'تعذّر التحديث الكامل. تحقّق من اتصالك بالإنترنت وأعد المحاولة.', AppColors.danger);
                            }
                          }
                        },
                  child: loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('تأكيد التحديث', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSnackBar(BuildContext context, String msg, Color bg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
