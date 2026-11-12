import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../services/cloudflare_api_service.dart';

/// تغيير كلمة المرور للمستخدم الحالي: الحالية ← الجديدة ← التأكيد
Future<void> showChangePasswordDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PasswordDialog(
      title: 'تغيير كلمة المرور',
      askOld: true,
      onSubmit: (ctx, oldPwd, newPwd) async {
        final auth = ctx.read<AuthProvider>();
        final ok = await auth.changePassword(oldPassword: oldPwd!, newPassword: newPwd);
        if (!ok) throw auth.error ?? 'تعذر تغيير كلمة المرور';
        return 'تم تغيير كلمة المرور بنجاح';
      },
    ),
  );
}

/// إعادة تعيين كلمة مرور مستخدم من قبل المدير
Future<void> showResetPasswordDialog(BuildContext context, UserModel user) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PasswordDialog(
      title: 'كلمة مرور جديدة لـ ${user.fullName}',
      askOld: false,
      onSubmit: (ctx, _, newPwd) async {
        await CloudflareApiService.instance.resetUserPassword(userId: user.id, newPassword: newPwd);
        return 'تم تعيين كلمة المرور الجديدة لـ ${user.fullName}';
      },
    ),
  );
}

typedef _Submit = Future<String> Function(BuildContext context, String? oldPassword, String newPassword);

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.title, required this.askOld, required this.onSubmit});
  final String title;
  final bool askOld;
  final _Submit onSubmit;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _hide = true;
  bool _saving = false;
  String? _error;

  static final _rules = <String, bool Function(String)>{
    '8 أحرف على الأقل': (p) => p.length >= 8,
    'حرف إنجليزي كبير': (p) => RegExp(r'[A-Z]').hasMatch(p),
    'حرف إنجليزي صغير': (p) => RegExp(r'[a-z]').hasMatch(p),
    'رقم': (p) => RegExp(r'[0-9]').hasMatch(p),
    'رمز خاص (!@#...)': (p) => RegExp(r'[!@#\$%^&*()_,\.?":{}|<>\-]').hasMatch(p),
  };

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    String? err;
    if (widget.askOld && _old.text.isEmpty) {
      err = 'أدخل كلمة المرور الحالية';
    } else if (!_rules.values.every((r) => r(_new.text))) {
      err = 'كلمة المرور الجديدة لا تستوفي الشروط';
    } else if (_new.text != _confirm.text) {
      err = 'تأكيد كلمة المرور غير مطابق';
    } else if (widget.askOld && _old.text == _new.text) {
      err = 'كلمة المرور الجديدة مطابقة للحالية';
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final msg = await widget.onSubmit(context, widget.askOld ? _old.text : null, _new.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.secondary,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        isDense: true,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );

  @override
  Widget build(BuildContext context) {
    final p = _new.text;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(widget.title, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16)),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.askOld) ...[
                TextField(
                  controller: _old,
                  obscureText: _hide,
                  decoration: _dec('كلمة المرور الحالية', Icons.lock_clock_rounded),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _new,
                obscureText: _hide,
                onChanged: (_) => setState(() {}),
                decoration: _dec('كلمة المرور الجديدة', Icons.lock_outline_rounded).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: _hide,
                onSubmitted: (_) => _submit(),
                decoration: _dec('تأكيد كلمة المرور الجديدة', Icons.lock_reset_rounded),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in _rules.entries) _RuleChip(label: e.key, met: e.value(p)),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5, color: AppColors.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('حفظ', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.label, required this.met});
  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final c = met ? AppColors.secondary : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(met ? Icons.check_circle_rounded : Icons.radio_button_unchecked, size: 13, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: c, fontFamily: 'Cairo')),
        ],
      ),
    );
  }
}
