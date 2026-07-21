import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../home/home_screen.dart';
import 'login_screen.dart';

class WaitingApprovalScreen extends StatefulWidget {
  const WaitingApprovalScreen({super.key});

  @override
  State<WaitingApprovalScreen> createState() => _WaitingApprovalScreenState();
}

class _WaitingApprovalScreenState extends State<WaitingApprovalScreen> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    final auth = context.read<AuthProvider>();
    final success = await auth.activateWithCode(code);
    if (!mounted) return;
    if (success && auth.user?.isLicenseActive == true) {
      // عرض ديالوج النجاح الفخم أولاً
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          backgroundColor: Colors.white,
          title: const Column(
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.secondary, size: 68),
              SizedBox(height: 14),
              Text('تم تفعيل الحساب', 
                   style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.black)),
            ],
          ),
          content: const Text(
            'تم تنشيط اشتراك حسابك بنجاح ودخول المنظومة! سيتم تحويلك إلى الصفحة الرئيسية الآن.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo', color: Colors.black87),
          ),
          actions: [
            Center(
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10)
                ),
                child: const Text('دخول التطبيق', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      );
      
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()), 
        (_) => false
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(auth.error ?? 'تعذر تفعيل الحساب.'), backgroundColor: AppColors.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final paused = user?.licensePaused ?? false;
    final pendingApproval = user?.approvalStatus == 'pending';
    final suspended = user?.approvalStatus == 'suspended' || paused;
    final expired = user?.approvalStatus == 'approved' && !paused && !(user?.isLicenseActive ?? false);
    
    final icon = suspended 
        ? Icons.pause_circle_filled_rounded 
        : expired 
            ? Icons.timer_off_rounded 
            : pendingApproval 
                ? Icons.hourglass_top_rounded 
                : Icons.hourglass_top_rounded;
                
    final color = suspended 
        ? AppColors.danger 
        : expired 
            ? AppColors.secondary 
            : AppColors.info;
            
    final title = suspended 
        ? 'تم إيقاف الترخيص مؤقتاً' 
        : expired 
            ? 'تمت الموافقة على الحساب' 
            : 'بانتظار موافقة الإدارة';
            
    final description = suspended 
        ? 'تم تجميد ترخيص الحساب من قبل الإدارة. يرجى التواصل مع مدير النظام.' 
        : expired 
            ? 'تمت الموافقة على حسابك من قبل الإدارة بنجاح! يرجى إدخال رمز التفعيل لتنشيط اشتراكك والدخول للمنظومة.' 
            : 'تم تسجيل حسابك بنجاح وهو الآن بانتظار مراجعة وموافقة مدير النظام أولاً. بمجرد موافقة المدير، ستتمكن من إدخال رمز التفعيل وتفعيل اشتراكك.';

    final canActivate = expired; // لا يسمح بالتفعيل إلا بعد موافقة المدير (أي عندما تكون الحالة approved والترخيص منتهٍ/غير نشط)

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppColors.primaryDark, Color(0xFF153E65), AppColors.primary], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: SafeArea(child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460), padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .13), borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white.withValues(alpha: .28)), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 30, offset: Offset(0, 15))]),
            child: Column(children: [
              CircleAvatar(radius: 43, backgroundColor: color.withValues(alpha: .2), child: Icon(icon, size: 54, color: Colors.white)),
              const SizedBox(height: 20),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10), Text(description, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: .86), fontFamily: 'Cairo', height: 1.7)),
              const SizedBox(height: 24),
              TextField(
                controller: _codeController, 
                enabled: !auth.loading && canActivate, 
                textCapitalization: TextCapitalization.characters, 
                textAlign: TextAlign.center, 
                style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold, color: Colors.black, fontFamily: 'Cairo'), 
                decoration: InputDecoration(
                  hintText: canActivate ? 'XXXX-XXXX-XXXX' : 'مغلق حتى موافقة الإدارة 🔒', 
                  filled: true, 
                  fillColor: canActivate ? Colors.white : Colors.white.withValues(alpha: 0.6), 
                  prefixIcon: const Icon(Icons.vpn_key_rounded), 
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)
                ), 
                onSubmitted: (_) => _activate()
              ),
              const SizedBox(height: 12), 
              SizedBox(
                width: double.infinity, 
                child: FilledButton.icon(
                  onPressed: (auth.loading || !canActivate) ? null : _activate, 
                  icon: auth.loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.verified_rounded), 
                  label: const Text('تفعيل الحساب', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)), 
                  style: FilledButton.styleFrom(backgroundColor: AppColors.secondary, padding: const EdgeInsets.symmetric(vertical: 14))
                )
              ),
              const SizedBox(height: 10), 
              TextButton.icon(
                onPressed: () async { 
                  await context.read<AuthProvider>().signOut(); 
                  if (context.mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false); 
                }, 
                icon: const Icon(Icons.logout_rounded, color: Colors.white), 
                label: const Text('تسجيل الخروج', style: TextStyle(color: Colors.white, fontFamily: 'Cairo'))
              ),
            ]),
          ),
        ))),
      ),
    );
  }
}
