import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../services/cloudflare_api_service.dart';

DateTime? _unlockedAt;
const _unlockWindow = Duration(minutes: 5);

/// يطلب من المدير تأكيد هويته بكلمة مروره قبل فتح شاشات الإدارة.
/// التحقق يتم على الخادم، وبعد النجاح لا يُسأل مجدداً لمدة 5 دقائق.
Future<bool> confirmAdminAccess(BuildContext context) async {
  if (_unlockedAt != null && DateTime.now().difference(_unlockedAt!) < _unlockWindow) return true;
  final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _AdminGateDialog(),
      ) ??
      false;
  if (ok) _unlockedAt = DateTime.now();
  return ok;
}

/// يفتح شاشة إدارية بعد تأكيد المدير
Future<void> openAdminScreen(BuildContext context, Widget screen) async {
  if (!await confirmAdminAccess(context) || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

class _AdminGateDialog extends StatefulWidget {
  const _AdminGateDialog();

  @override
  State<_AdminGateDialog> createState() => _AdminGateDialogState();
}

class _AdminGateDialogState extends State<_AdminGateDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_ctrl.text.isEmpty) {
      setState(() => _error = 'أدخل رمز التأكيد');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await CloudflareApiService.instance.verifyPassword(_ctrl.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _checking = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Row(
        children: [
          Icon(Icons.admin_panel_settings_rounded, color: AppColors.accent),
          SizedBox(width: 10),
          Expanded(
            child: Text('تأكيد هوية المدير',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('أدخل كلمة مرور المدير للدخول إلى الإدارة.',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5, color: Colors.grey)),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            obscureText: _obscure,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'رمز التأكيد',
              errorText: _error,
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.pop(context, false),
          child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _checking ? null : _submit,
          child: _checking
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('دخول', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
