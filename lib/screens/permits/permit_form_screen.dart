import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/validators.dart';
import '../../l10n/app_strings.dart';
import '../../models/permit_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permit_provider.dart';
import '../../widgets/professional_back_button.dart';
import '../../widgets/tab_switch_notification.dart';

/// شاشة إضافة/تعديل إجازة متطورة مع واجهة UI/UX احترافية
/// + إمكانية إرفاق ملفات PDF وصور وربطها بالإجازة
class PermitFormScreen extends StatefulWidget {
  const PermitFormScreen({super.key, this.existing});
  final PermitModel? existing;

  bool get isEdit => existing != null;

  @override
  State<PermitFormScreen> createState() => _PermitFormScreenState();
}

class _PermitFormScreenState extends State<PermitFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _permitNumberCtrl;
  late final TextEditingController _yearCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _plotCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _nameChangeCtrl;
  late final TextEditingController _plotAreaCtrl;
  late final TextEditingController _buildingAreaCtrl;
  late final TextEditingController _newRegistryNameCtrl;

  late DateTime _date;
  String? _permitType;
  bool _saving = false;

  // قائمة مسارات المرفقات المحملة (PDF وصور)
  final List<String> _attachmentPaths = [];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _permitNumberCtrl = TextEditingController(text: e?.permitNumber.toString() ?? '');
    _yearCtrl = TextEditingController(text: (e?.permitYear ?? DateTime.now().year).toString());
    _nameCtrl = TextEditingController(text: e?.fullName ?? '');
    _plotCtrl = TextEditingController(text: e?.plotNumber ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _nameChangeCtrl = TextEditingController(text: e?.nameChangeNotes ?? '');
    _plotAreaCtrl = TextEditingController(text: e?.plotArea?.toString() ?? '');
    _buildingAreaCtrl = TextEditingController(text: e?.buildingArea?.toString() ?? '');
    _newRegistryNameCtrl = TextEditingController(text: e?.namePerNewRegistry ?? '');
    _date = e?.permitDate ?? DateTime.now();
    _permitType = e?.permitType.isNotEmpty == true ? e!.permitType : null;

    if (e?.attachmentUrls != null) {
      _attachmentPaths.addAll(e!.attachmentUrls);
    }

    if (!widget.isEdit) {
      _yearCtrl.addListener(_onYearChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onYearChanged();
      });
    }
  }

  void _onYearChanged() {
    if (!widget.isEdit) {
      final parsedYear = int.tryParse(_yearCtrl.text);
      if (parsedYear != null && parsedYear > 1900 && parsedYear < 2100) {
        final suggested = context.read<PermitProvider>().suggestNextNumber(parsedYear);
        if (_permitNumberCtrl.text != suggested.toString()) {
          setState(() {
            _permitNumberCtrl.text = suggested.toString();
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _yearCtrl.removeListener(_onYearChanged);
    _permitNumberCtrl.dispose();
    _yearCtrl.dispose();
    _nameCtrl.dispose();
    _plotCtrl.dispose();
    _notesCtrl.dispose();
    _nameChangeCtrl.dispose();
    _plotAreaCtrl.dispose();
    _buildingAreaCtrl.dispose();
    _newRegistryNameCtrl.dispose();
    super.dispose();
  }

  /// التقاط اختيار ملف PDF
  Future<void> _pickPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final file = File(path);
        final sizeInBytes = await file.length();
        final sizeInMb = sizeInBytes / (1024 * 1024);
        if (sizeInMb > 5.0) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('حجم المرفق يتجاوز الحد الأقصى المسموح به (5 ميجابايت)')),
          );
          return;
        }
        setState(() {
          _attachmentPaths.add(path);
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح ملف PDF')),
      );
    }
  }

  /// التقاط صورة من الكاميرا أو اختيار من الجهاز
  Future<void> _pickImage() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'إضافة صورة مرفقة',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // التقاط من الكاميرا
                  _buildPickerOption(
                    icon: Icons.camera_alt_rounded,
                    label: 'التقاط من الكاميرا',
                    color: AppColors.primary,
                    onTap: () async {
                      Navigator.pop(ctx);
                      _getImage(ImageSource.camera);
                    },
                  ),
                  // تحميل من الجهاز
                  _buildPickerOption(
                    icon: Icons.photo_library_rounded,
                    label: 'تحميل من الجهاز',
                    color: AppColors.secondary,
                    onTap: () async {
                      Navigator.pop(ctx);
                      _getImage(ImageSource.gallery);
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPickerOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              fontFamily: 'Cairo',
              color: isDark ? Colors.grey[300] : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _getImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1200,
      );
      if (photo != null) {
        final file = File(photo.path);
        final sizeInBytes = await file.length();
        final sizeInMb = sizeInBytes / (1024 * 1024);
        if (sizeInMb > 5.0) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('حجم المرفق يتجاوز الحد الأقصى المسموح به (5 ميجابايت)')),
          );
          return;
        }
        setState(() {
          _attachmentPaths.add(photo.path);
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر الوصول إلى الكاميرا/الصور')),
      );
    }
  }

  void _showSuccessDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        
        // إغلاق تلقائي
        Future.delayed(const Duration(seconds: 2), () {
          if (ctx.mounted) {
            Navigator.of(ctx).pop();
          }
        });

        return ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: isDark 
                      ? const Color(0xFF1E293B).withValues(alpha: 0.9) 
                      : Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.12) : AppColors.primary.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [Color(0xFF4ADE80), Color(0xFF15803D)],
                          center: Alignment(-0.2, -0.2),
                          radius: 0.7,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF22C55E).withValues(alpha: 0.4),
                            blurRadius: 18,
                            spreadRadius: 4,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1970),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (picked != null) setState(() => _date = picked);
  }

  bool _isDuplicateNumber() {
    final provider = context.read<PermitProvider>();
    final year = int.tryParse(_yearCtrl.text) ?? DateTime.now().year;
    final number = int.tryParse(_permitNumberCtrl.text) ?? 0;
    final clashing = provider.byYear(year).where((p) => p.permitNumber == number && p.id != widget.existing?.id);
    return clashing.isNotEmpty;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isDuplicateNumber()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('permit_number_duplicate')), backgroundColor: AppColors.danger),
      );
      return;
    }

    setState(() => _saving = true);
    final auth = context.read<AuthProvider>();
    final provider = context.read<PermitProvider>();

    try {
      if (widget.isEdit) {
        await provider.updatePermit(
          widget.existing!,
          fullName: _nameCtrl.text.trim(),
          plotNumber: _plotCtrl.text.trim(),
          permitYear: int.parse(_yearCtrl.text),
          permitNumber: int.parse(_permitNumberCtrl.text),
          permitDate: _date,
          notes: _notesCtrl.text.trim(),
          permitType: _permitType ?? '',
          nameChangeNotes: _nameChangeCtrl.text.trim(),
          plotArea: double.tryParse(_plotAreaCtrl.text.trim()),
          buildingArea: double.tryParse(_buildingAreaCtrl.text.trim()),
          namePerNewRegistry: _newRegistryNameCtrl.text.trim(),
          attachmentUrls: _attachmentPaths,
          actorId: auth.user!.id,
          actorName: auth.user!.fullName,
        );
      } else {
        await provider.addPermit(
          fullName: _nameCtrl.text.trim(),
          plotNumber: _plotCtrl.text.trim(),
          permitYear: int.parse(_yearCtrl.text),
          permitNumber: int.parse(_permitNumberCtrl.text),
          permitDate: _date,
          notes: _notesCtrl.text.trim(),
          permitType: _permitType ?? '',
          nameChangeNotes: _nameChangeCtrl.text.trim(),
          plotArea: double.tryParse(_plotAreaCtrl.text.trim()),
          buildingArea: double.tryParse(_buildingAreaCtrl.text.trim()),
          namePerNewRegistry: _newRegistryNameCtrl.text.trim(),
          attachmentUrls: _attachmentPaths,
          actorId: auth.user!.id,
          actorName: auth.user!.fullName,
        );
      }

      if (!mounted) return;
      final msg = context.tr('saved_successfully');
      _showSuccessDialog(context, msg);

      // انتظر قليلاً ريثما تختفي النافذة التجميلية
      await Future.delayed(const Duration(milliseconds: 2100));

      if (!mounted) return;

      if (widget.isEdit) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } else {
        // مسح الحقول بالكامل لتكون نظيفة في المرة القادمة
        _nameCtrl.clear();
        _plotCtrl.clear();
        _notesCtrl.clear();
        _nameChangeCtrl.clear();
        _plotAreaCtrl.clear();
        _buildingAreaCtrl.clear();
        _newRegistryNameCtrl.clear();
        _attachmentPaths.clear();
        
        // إعادة تهيئة السنة والتسلسل
        _yearCtrl.text = DateTime.now().year.toString();
        _onYearChanged();

        // توجيه التبويب للرئيسية (Index 0)
        TabSwitchNotification(0).dispatch(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء حفظ البيانات')),
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
    final isEdit = widget.isEdit;

    final hasAdd = auth.user?.canAdd ?? true;
    final hasEdit = auth.user?.canEdit ?? true;

    if ((isEdit && !hasEdit) || (!isEdit && !hasAdd)) {
      return Scaffold(
        appBar: AppBar(
          leading: const ProfessionalBackButton(),
          title: Text(isEdit ? context.tr('edit_permit') : context.tr('add_permit')),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_person_rounded, color: AppColors.danger, size: 64),
                ),
                const SizedBox(height: 24),
                Text(
                  isEdit ? 'الحساب غير مصرح له بالتعديل' : 'الحساب غير مصرح له بالإدخال',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 12),
                Text(
                  isEdit 
                      ? 'تم إيقاف صلاحية تعديل الإجازات لهذا الحساب من قبل مسؤول النظام.'
                      : 'تم إيقاف صلاحية إضافة إجازات جديدة لهذا الحساب من قبل مسؤول النظام.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.grey, height: 1.5, fontFamily: 'Cairo'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const ProfessionalBackButton(),
        title: Text(widget.isEdit ? context.tr('edit_permit') : context.tr('add_permit')),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---- هيدر تجميلي زجاجي ----
                  _buildFormHeader(isDark),
                  const SizedBox(height: 16),

                  // Section 1: بيانات الإجازة والسنة
                  _buildCardSection(
                    title: 'بيانات الإجازة والنوع',
                    icon: Icons.assignment_rounded,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _permitNumberCtrl,
                              readOnly: true,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: widget.isEdit ? context.tr('permit_number') : 'رقم الإجازة (تلقائي 🔒)',
                                prefixIcon: const Icon(Icons.lock_rounded, color: AppColors.primary),
                              ),
                              validator: Validators.permitNumber,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _yearCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: context.tr('permit_year'),
                                prefixIcon: const Icon(Icons.calendar_today_rounded, color: AppColors.primary),
                              ),
                              validator: Validators.permitYear,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _permitType,
                        decoration: InputDecoration(
                          labelText: context.tr('permit_type'),
                          prefixIcon: const Icon(Icons.category_rounded, color: AppColors.primary),
                        ),
                        items: AppConstants.permitTypes
                            .map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() => _permitType = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Section 2: بيانات المواطن والقطعة
                  _buildCardSection(
                    title: 'بيانات المواطن والقطعة والتاريخ',
                    icon: Icons.person_rounded,
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: InputDecoration(
                          labelText: context.tr('full_name'),
                          prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.primary),
                        ),
                        validator: (v) => Validators.required(v, message: context.tr('required_field')),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _plotCtrl,
                        decoration: InputDecoration(
                          labelText: context.tr('plot_number'),
                          prefixIcon: const Icon(Icons.grid_view_rounded, color: AppColors.primary),
                        ),
                        validator: (v) => Validators.required(v, message: context.tr('required_field')),
                      ),
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: context.tr('permit_date'),
                            prefixIcon: const Icon(Icons.event_rounded, color: AppColors.primary),
                          ),
                          child: Text(
                            '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Section 3: المساحات
                  _buildCardSection(
                    title: 'مساحات العرصة والبناء (م²)',
                    icon: Icons.square_foot_rounded,
                    children: [
                      TextFormField(
                        controller: _plotAreaCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: context.tr('plot_area'),
                          prefixIcon: const Icon(Icons.crop_square_rounded, color: AppColors.accent),
                        ),
                        validator: Validators.positiveNumber,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _buildingAreaCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: context.tr('building_area'),
                          prefixIcon: const Icon(Icons.domain_rounded, color: AppColors.secondary),
                        ),
                        validator: Validators.positiveNumber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Section 4: الملاحظات والسجل
                  _buildCardSection(
                    title: 'الملاحظات والتغيرات السابقة',
                    icon: Icons.note_alt_rounded,
                    children: [
                      TextFormField(
                        controller: _notesCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: context.tr('notes'),
                          prefixIcon: const Icon(Icons.notes_rounded, color: AppColors.info),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _nameChangeCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: context.tr('name_change_notes'),
                          prefixIcon: const Icon(Icons.published_with_changes_rounded, color: AppColors.accent),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _newRegistryNameCtrl,
                        decoration: InputDecoration(
                          labelText: context.tr('name_per_new_registry'),
                          prefixIcon: const Icon(Icons.badge_rounded, color: AppColors.secondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Section 5: المرفقات والوثائق الرسمية (PDF وصور)
                  _buildAttachmentsSection(isDark),

                  const SizedBox(height: 28),

                  // زر الحفظ الرئيسي
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.save_rounded, size: 22),
                    label: Text(
                      widget.isEdit ? 'حفظ التعديلات' : 'حفظ وتخزين الإجازة',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
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
            child: Icon(
              widget.isEdit ? Icons.edit_note_rounded : Icons.post_add_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isEdit ? 'تعديل بيانات إجازة بناء' : 'إضافة إجازة بناء جديدة',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                const Text(
                  'أدخل المعطيات واكتمل من إضافة المرفقات (PDF أو الصور)',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162232) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppColors.primary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          ...children,
        ],
      ),
    );
  }

  /// قسم رفع المرفقات والوثائق الرسمية (PDF وصور)
  Widget _buildAttachmentsSection(bool isDark) {
    return _buildCardSection(
      title: 'المرفقات والوثائق الرسمية (PDF وصور)',
      icon: Icons.attach_file_rounded,
      children: [
        Row(
          children: [
            // زر اختيار PDF
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: AppColors.danger),
                ),
                icon: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.danger, size: 16),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('إضافة ملف PDF', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 11.5)),
                ),
                onPressed: _pickPdf,
              ),
            ),
            const SizedBox(width: 6),

            // زر اختيار صورة
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: AppColors.secondary),
                ),
                icon: const Icon(Icons.add_a_photo_rounded, color: AppColors.secondary, size: 16),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('إضافة صورة', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 11.5)),
                ),
                onPressed: _pickImage,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // عرض قائمة الملفات المرفقة
        if (_attachmentPaths.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: Colors.grey),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'لم يتم إرفاق وثائق بعد. اضغط أعلاه لإدراج PDF أو صور.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: _attachmentPaths.asMap().entries.map((entry) {
              final idx = entry.key;
              final path = entry.value;
              final isPdf = path.toLowerCase().endsWith('.pdf');
              final fileName = path.split(Platform.pathSeparator).last;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isPdf ? AppColors.danger.withValues(alpha: 0.08) : AppColors.secondary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isPdf ? AppColors.danger.withValues(alpha: 0.3) : AppColors.secondary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                      color: isPdf ? AppColors.danger : AppColors.secondary,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.red, size: 18),
                      onPressed: () {
                        setState(() {
                          _attachmentPaths.removeAt(idx);
                        });
                      },
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
