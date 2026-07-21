import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/professional_back_button.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late final TextEditingController _nameCtrl;
  late final TextEditingController _birthDateCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _oldPasswordCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _confirmPasswordCtrl;

  String? _localAvatarPath;
  bool _saving = false;
  bool _obscureOldPassword = true;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _nameCtrl = TextEditingController(text: user?.fullName ?? '');
    _birthDateCtrl = TextEditingController(text: user?.birthDate ?? '');
    _phoneCtrl = TextEditingController(text: user?.phoneNumber ?? '');
    _oldPasswordCtrl = TextEditingController();
    _passwordCtrl = TextEditingController();
    _confirmPasswordCtrl = TextEditingController();
    _localAvatarPath = user?.avatarPath;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _birthDateCtrl.dispose();
    _phoneCtrl.dispose();
    _oldPasswordCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        if (!mounted) return;
        // نفتح شاشة قص الصورة المخصصة
        final croppedFile = await Navigator.of(context).push<File>(
          MaterialPageRoute(
            builder: (_) => ProfileImageCropper(imageFile: File(picked.path)),
          ),
        );
        
        if (croppedFile != null) {
          setState(() {
            _localAvatarPath = croppedFile.path;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('عذراً، تعذر اختيار أو قص الصورة')),
        );
      }
    }
  }

  Future<void> _selectBirthDate() async {
    DateTime initial = DateTime(1990);
    if (_birthDateCtrl.text.isNotEmpty) {
      initial = DateTime.tryParse(_birthDateCtrl.text) ?? DateTime(1990);
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _birthDateCtrl.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final auth = context.read<AuthProvider>();

    try {
      // 1. تحديث الملف الشخصي
      final profileSuccess = await auth.updateUserProfile(
        fullName: _nameCtrl.text.trim(),
        birthDate: _birthDateCtrl.text.trim().isNotEmpty ? _birthDateCtrl.text.trim() : null,
        phoneNumber: _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
        avatarPath: _localAvatarPath,
      );

      // 2. تحديث كلمة المرور إذا تم إدخالها
      bool pwdSuccess = true;
      if (_passwordCtrl.text.isNotEmpty) {
        pwdSuccess = await auth.changePassword(
          oldPassword: _oldPasswordCtrl.text,
          newPassword: _passwordCtrl.text,
        );
      }

      if (mounted) {
        if (profileSuccess && pwdSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تحديث الملف الشخصي بنجاح', style: TextStyle(fontFamily: 'Cairo')),
              backgroundColor: AppColors.secondary,
            ),
          );
          // تفريغ حقول كلمة المرور بعد النجاح
          _oldPasswordCtrl.clear();
          _passwordCtrl.clear();
          _confirmPasswordCtrl.clear();
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(auth.error ?? 'حدث خطأ أثناء التحديث', style: const TextStyle(fontFamily: 'Cairo')),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''), style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(
        leading: const ProfessionalBackButton(),
        title: const Text('الملف الشخصي للمستخدم'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 550),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // صورة المستخدم الحركية
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark ? const Color(0xFF1E293B) : Colors.grey[200],
                            border: Border.all(color: AppColors.primary, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                            image: _localAvatarPath != null
                                ? DecorationImage(
                                    image: FileImage(File(_localAvatarPath!)),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _localAvatarPath == null
                              ? Center(
                                  child: Text(
                                    user?.fullName.isNotEmpty == true ? user!.fullName[0] : 'م',
                                    style: const TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      user?.email ?? '',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // القسم الأول: البيانات الشخصية
                  _buildSectionCard(
                    title: 'البيانات الشخصية والاتصال',
                    icon: Icons.person_outline_rounded,
                    isDark: isDark,
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'الاسم الكامل ثلاثياً',
                          prefixIcon: const Icon(Icons.badge_rounded, color: AppColors.primary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        validator: (v) => Validators.required(v, message: 'الرجاء إدخال الاسم بالكامل'),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'رقم الهاتف',
                          prefixIcon: const Icon(Icons.phone_rounded, color: AppColors.primary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: _selectBirthDate,
                        borderRadius: BorderRadius.circular(16),
                        child: IgnorePointer(
                          child: TextFormField(
                            controller: _birthDateCtrl,
                            decoration: InputDecoration(
                              labelText: 'تحديث المواليد / تاريخ الميلاد',
                              prefixIcon: const Icon(Icons.calendar_month_rounded, color: AppColors.primary),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // القسم الثاني: تغيير كلمة المرور
                  _buildSectionCard(
                    title: 'تغيير كلمة المرور',
                    icon: Icons.lock_reset_rounded,
                    isDark: isDark,
                    children: [
                      TextFormField(
                        controller: _oldPasswordCtrl,
                        obscureText: _obscureOldPassword,
                        obscuringCharacter: '●',
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور القديمة',
                          prefixIcon: const Icon(Icons.lock_person_rounded, color: AppColors.primary),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureOldPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                            onPressed: () => setState(() => _obscureOldPassword = !_obscureOldPassword),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        validator: (v) {
                          if (_passwordCtrl.text.isNotEmpty && (v == null || v.isEmpty)) {
                            return 'الرجاء إدخال كلمة المرور القديمة لتأكيد الهوية';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscurePassword,
                        obscuringCharacter: '●',
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور الجديدة',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        validator: (v) {
                          if (v != null && v.isNotEmpty && v.length < 8) {
                            return 'يجب أن لا تقل كلمة المرور عن 8 رموز';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPasswordCtrl,
                        obscureText: _obscureConfirm,
                        obscuringCharacter: '●',
                        decoration: InputDecoration(
                          labelText: 'تأكيد كلمة المرور الجديدة',
                          prefixIcon: const Icon(Icons.lock_reset_rounded, color: AppColors.primary),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        validator: (v) {
                          if (_passwordCtrl.text.isNotEmpty && (v == null || v.isEmpty)) {
                            return 'يرجى تأكيد كلمة المرور الجديدة';
                          }
                          if (v != _passwordCtrl.text) {
                            return 'كلمتا المرور غير متطابقتين';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),

                  // زر الحفظ الرئيسي
                  ElevatedButton(
                    onPressed: _saving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 3,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                          )
                        : const Text(
                            'حفظ التعديلات',
                            style: TextStyle(
                              fontSize: 16,
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
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Card(
      elevation: isDark ? 0 : 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// شاشة قص وتحديد صور الملف الشخصي بطريقة احترافية وحركية كاملة (Offline + zero packages)
class ProfileImageCropper extends StatefulWidget {
  final File imageFile;
  const ProfileImageCropper({super.key, required this.imageFile});

  @override
  State<ProfileImageCropper> createState() => _ProfileImageCropperState();
}

class _ProfileImageCropperState extends State<ProfileImageCropper> {
  final GlobalKey _repaintKey = GlobalKey();
  bool _cropping = false;

  Future<void> _cropAndSave() async {
    setState(() => _cropping = true);
    try {
      final boundary = _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.5); // جودة عالية
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final pngBytes = byteData.buffer.asUint8List();
        
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/cropped_avatar_${DateTime.now().millisecondsSinceEpoch}.png');
        await file.writeAsBytes(pngBytes);
        
        if (mounted) {
          Navigator.of(context).pop(file);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء قص الصورة: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cropping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('قص وتحديد الصورة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.check_rounded, size: 28),
            onPressed: _cropping ? null : _cropAndSave,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // جزء العرض والتحريك
                  RepaintBoundary(
                    key: _repaintKey,
                    child: Container(
                      width: 280,
                      height: 280,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InteractiveViewer(
                        minScale: 0.1,
                        maxScale: 5.0,
                        boundaryMargin: const EdgeInsets.all(240),
                        child: Image.file(
                          widget.imageFile,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  
                  // قناع الدائرة الأبيض الشفاف المعتم
                  IgnorePointer(
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      decoration: const ShapeDecoration(
                        shape: _CustomOverlayShape(280),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            color: Colors.black,
            child: const Text(
              'استخدم إصبعين للتكبير/التصغير واسحب الصورة لتوسيط الجزء المناسب داخل الدائرة المحددة',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'Cairo', height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// القناع المعتم للقص
class _CustomOverlayShape extends ShapeBorder {
  final double cropSize;
  const _CustomOverlayShape(this.cropSize);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path();

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final path = Path()..addRect(rect);
    final cropRect = Rect.fromCenter(
      center: rect.center,
      width: cropSize,
      height: cropSize,
    );
    path.addOval(cropRect);
    path.fillType = PathFillType.evenOdd;
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.72)
      ..style = PaintingStyle.fill;
    canvas.drawPath(getOuterPath(rect), paint);

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(rect.center, cropSize / 2, borderPaint);
  }

  @override
  ShapeBorder scale(double t) => _CustomOverlayShape(cropSize * t);
}
