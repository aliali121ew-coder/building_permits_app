import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../home/home_screen.dart';
import 'waiting_approval_screen.dart';
import '../../services/hive_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // وحدات التحكم بالمدخلات
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLogin = true; // للتحويل بين تسجيل الدخول وإنشاء حساب

  // شروط ومعايير قوة كلمة المرور
  bool _hasLength = false;
  bool _hasUpper = false;
  bool _hasLower = false;
  bool _hasDigit = false;
  bool _hasSpecial = false;
  String _passwordStrength = ''; // '', 'weak', 'medium', 'strong'

  @override
  void initState() {
    super.initState();
    final hive = HiveService.instance;
    _emailCtrl.text = hive.getLastEmail();
    hive.getLastPassword().then((pwd) {
      if (mounted) {
        setState(() {
          _passwordCtrl.text = pwd;
          if (pwd.isNotEmpty) {
            _hasLength = pwd.length >= 8;
            _hasUpper = RegExp(r'[A-Z]').hasMatch(pwd);
            _hasLower = RegExp(r'[a-z]').hasMatch(pwd);
            _hasDigit = RegExp(r'[0-9]').hasMatch(pwd);
            _hasSpecial = RegExp(r'[!@#\$%^&*()_,\.?":{}|<>\-]').hasMatch(pwd);
            
            int score = 0;
            if (_hasLength) score++;
            if (_hasUpper) score++;
            if (_hasLower) score++;
            if (_hasDigit) score++;
            if (_hasSpecial) score++;
            
            if (score <= 2) {
              _passwordStrength = 'weak';
            } else if (score <= 4) {
              _passwordStrength = 'medium';
            } else {
              _passwordStrength = 'strong';
            }
          }
        });
      }
    });
  }

  void _updatePasswordStrength(String password) {
    if (password.isEmpty) {
      setState(() {
        _hasLength = false;
        _hasUpper = false;
        _hasLower = false;
        _hasDigit = false;
        _hasSpecial = false;
        _passwordStrength = '';
      });
      return;
    }
    
    setState(() {
      _hasLength = password.length >= 8;
      _hasUpper = RegExp(r'[A-Z]').hasMatch(password);
      _hasLower = RegExp(r'[a-z]').hasMatch(password);
      _hasDigit = RegExp(r'[0-9]').hasMatch(password);
      _hasSpecial = RegExp(r'[!@#\$%^&*()_,\.?":{}|<>\-]').hasMatch(password);
      
      int score = 0;
      if (_hasLength) score++;
      if (_hasUpper) score++;
      if (_hasLower) score++;
      if (_hasDigit) score++;
      if (_hasSpecial) score++;
      
      if (score <= 2) {
        _passwordStrength = 'weak';
      } else if (score <= 4) {
        _passwordStrength = 'medium';
      } else {
        _passwordStrength = 'strong';
      }
    });
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // معالجة تسجيل الدخول
  Future<void> _submitLogin() async {
    if (!_formKey.currentState!.validate()) return;
    
    final auth = context.read<AuthProvider>();
    final ok = await auth.signIn(_emailCtrl.text.trim(), _passwordCtrl.text);
    
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => auth.user?.isLicenseActive == true
              ? const HomeScreen()
              : const WaitingApprovalScreen(),
        ),
      );
    } else {
      String errorMessage = auth.error ?? 'حدث خطأ أثناء تسجيل الدخول';
      
      if (errorMessage.contains('invalid_credentials') || 
          errorMessage.contains('Invalid login credentials') ||
          errorMessage.contains('Invalid claims') ||
          errorMessage.contains('400')) {
        errorMessage = 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
      } else if (errorMessage.contains('user_not_found') || 
                 errorMessage.contains('User not found')) {
        errorMessage = 'الحساب غير موجود.';
      } else if (errorMessage.contains('إيقاف') || 
                 errorMessage.contains('غير نشط') || 
                 errorMessage.contains('معطل') ||
                 errorMessage.contains('مراجعة مسؤول النظام')) {
        errorMessage = 'عذراً، هذا الحساب في انتظار موافقة وتفعيل مدير النظام. يرجى مراجعة الإدارة.';
      }
      
      _showErrorSnackBar(errorMessage);
    }
  }

  // معالجة إنشاء الحساب الجديد
  Future<void> _submitSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
      _showErrorSnackBar('كلمتا المرور غير متطابقتين.');
      return;
    }

    // التحقق من استيفاء جميع شروط ومعايير كلمة المرور المطلوبة
    if (!_hasLength || !_hasUpper || !_hasLower || !_hasDigit || !_hasSpecial) {
      _showErrorSnackBar('يرجى استيفاء جميع شروط ومعايير كلمة المرور المطلوبة للتسجيل.');
      return;
    }

    final auth = context.read<AuthProvider>();
    final ok = await auth.signUp(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      fullName: _fullNameCtrl.text.trim(),
    );

    if (!mounted) return;
    if (ok) {
      // تفريغ الحقول عند النجاح
      _fullNameCtrl.clear();
      _emailCtrl.clear();
      _passwordCtrl.clear();
      _confirmPasswordCtrl.clear();
      
      // عرض رسالة نجاح مخصصة توضح انتظار موافقة الإدارة
      _showSuccessDialog();
    } else {
      _showErrorSnackBar(auth.error ?? 'حدث خطأ أثناء إنشاء الحساب.');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: AppColors.secondary, size: 28),
            ),
            const SizedBox(width: 12),
            const Text(
              'تم تسجيل طلبك بنجاح',
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: const Text(
          'تم إنشاء حسابك الجديد بنجاح!\n\nحسابك الآن في وضع (بانتظار المراجعة). لن تتمكن من الدخول للمنظومة إلا بعد قيام مدير النظام (Admin) بالموافقة على حسابك وتفعيله.',
          style: TextStyle(fontFamily: 'Cairo', fontSize: 13, height: 1.6),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _isLogin = true); // التحويل تلقائياً لصفحة الدخول
            },
            child: const Text('حسناً، تسجيل الدخول', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordRequirements() {
    if (_passwordStrength.isEmpty) return const SizedBox.shrink();
    
    Color strengthColor;
    String strengthLabel;
    int dotsCount;
    
    switch (_passwordStrength) {
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
      default:
        return const SizedBox.shrink();
    }
    
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: strengthColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: strengthColor.withValues(alpha: 0.15), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // مؤشر القوة بالنقاط الدائرية الكبيرة الحركية
          Row(
            children: [
              const Text(
                'قوة كلمة المرور: ',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
              ),
              const SizedBox(width: 4),
              Text(
                strengthLabel,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: strengthColor, fontFamily: 'Cairo'),
              ),
              const Spacer(),
              Row(
                children: List.generate(3, (index) {
                  final isActive = index < dotsCount;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? strengthColor : Colors.grey.withValues(alpha: 0.3),
                      boxShadow: isActive
                          ? [BoxShadow(color: strengthColor.withValues(alpha: 0.3), blurRadius: 4, spreadRadius: 1)]
                          : null,
                    ),
                  );
                }),
              ),
            ],
          ),
          const Divider(height: 16),
          // متطلبات كلمة المرور
          _requirementItem('طول كلمة المرور 8 رموز فما فوق', _hasLength),
          _requirementItem('أحرف كبيرة (A-Z) على الأقل', _hasUpper),
          _requirementItem('أحرف صغيرة (a-z) على الأقل', _hasLower),
          _requirementItem('أرقام (0-9) على الأقل', _hasDigit),
          _requirementItem('رموز خاصة (مثل !@#\$%^&*()_) على الأقل', _hasSpecial),
        ],
      ),
    );
  }

  Widget _requirementItem(String text, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: met ? AppColors.secondary : AppColors.danger,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                fontFamily: 'Cairo',
                color: met ? AppColors.secondary : Colors.grey,
                fontWeight: met ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                : [const Color(0xFF1A365D), const Color(0xFF2A5C8A), const Color(0xFF3B82F6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: isDark 
                            ? Colors.black.withValues(alpha: 0.45) 
                            : Colors.white.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: isDark 
                              ? Colors.white.withValues(alpha: 0.08) 
                              : AppColors.primary.withValues(alpha: 0.15),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // شعار البلدية الدائري الفاخر في الأعلى
                            Center(
                              child: Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.1),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                  image: const DecorationImage(
                                    image: AssetImage('assets/images/logo.jpg'),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'بلدية الهاشمية',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueAccent,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            Text(
                              _isLogin ? 'بوابة إجازات البناء الرقمية' : 'طلب حساب موظف جديد',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : Colors.black54,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            const SizedBox(height: 24),

                            // ---- التبويبات الفاخرة للتبديل بين دخول/إنشاء ----
                            Container(
                              height: 46,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => setState(() {
                                        _isLogin = true;
                                        _formKey.currentState?.reset();
                                      }),
                                      borderRadius: BorderRadius.circular(14),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 250),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: _isLogin
                                              ? AppColors.primary
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Text(
                                          'تسجيل الدخول',
                                          style: TextStyle(
                                            color: _isLogin ? Colors.white : (isDark ? Colors.white70 : Colors.black54),
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => setState(() {
                                        _isLogin = false;
                                        _formKey.currentState?.reset();
                                      }),
                                      borderRadius: BorderRadius.circular(14),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 250),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: !_isLogin
                                              ? AppColors.primary
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Text(
                                          'إنشاء حساب',
                                          style: TextStyle(
                                            color: !_isLogin ? Colors.white : (isDark ? Colors.white70 : Colors.black54),
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // ---- حقول الإدخال الفلكس الحركية ----
                            
                            // 1. حقل الاسم الكامل (إنشاء حساب فقط)
                            if (!_isLogin) ...[
                              TextFormField(
                                controller: _fullNameCtrl,
                                decoration: InputDecoration(
                                  labelText: 'الاسم الكامل ثلاثياً',
                                  prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.primary),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                validator: (v) => Validators.required(v, message: 'يرجى إدخال الاسم بالكامل'),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // 2. حقل البريد الإلكتروني (مشترك)
                            TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: 'البريد الإلكتروني للعمل',
                                prefixIcon: const Icon(Icons.email_outlined, color: AppColors.primary),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              validator: Validators.email,
                            ),
                            const SizedBox(height: 16),

                            // 3. حقل كلمة المرور (مشترك)
                            TextFormField(
                              controller: _passwordCtrl,
                              obscureText: _obscurePassword,
                              obscuringCharacter: '●',
                              onChanged: _updatePasswordStrength,
                              decoration: InputDecoration(
                                labelText: 'كلمة المرور',
                                prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'يرجى إدخال كلمة المرور';
                                }
                                if (!_isLogin && v.length < 8) {
                                  return 'يجب أن لا تقل كلمة المرور عن 8 رموز لتلبية شروط الأمان';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            if (!_isLogin) _buildPasswordRequirements(),

                            // 4. حقل تأكيد كلمة المرور (إنشاء حساب فقط)
                            if (!_isLogin) ...[
                              TextFormField(
                                controller: _confirmPasswordCtrl,
                                obscureText: _obscureConfirm,
                                obscuringCharacter: '●',
                                decoration: InputDecoration(
                                  labelText: 'تأكيد كلمة المرور',
                                  prefixIcon: const Icon(Icons.lock_reset_rounded, color: AppColors.primary),
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                                  ),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return 'يرجى تأكيد كلمة المرور';
                                  if (v != _passwordCtrl.text) return 'كلمتا المرور غير متطابقتين';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                            ],

                            const SizedBox(height: 12),

                            // زر الإجراء الرئيسي (دخول / تسجيل)
                            ElevatedButton(
                              onPressed: auth.loading
                                  ? null
                                  : (_isLogin ? _submitLogin : _submitSignUp),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 3,
                              ),
                              child: auth.loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                                    )
                                  : Text(
                                      _isLogin ? 'تسجيل الدخول' : 'تسجيل حساب جديد',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
