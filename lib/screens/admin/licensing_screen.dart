import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../models/user_model.dart';
import '../../services/supabase_service.dart';
import '../../widgets/professional_back_button.dart';

class LicensingScreen extends StatefulWidget {
  const LicensingScreen({super.key});

  @override
  State<LicensingScreen> createState() => _LicensingScreenState();
}

class _LicensingScreenState extends State<LicensingScreen>
    with SingleTickerProviderStateMixin {
  final _service = SupabaseService.instance;
  late final TabController _tabs;
  late Future<List<Map<String, dynamic>>> _codes;
  late Future<List<Map<String, dynamic>>> _devices;
  late Future<List<UserModel>> _users;
  Timer? _countdownTimer;

  static const _durations = [30, 90, 180, 365];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)
      ..addListener(() => setState(() {}));
    _reload();
    
    // تحديث الشاشة كل ثانية لبقاء العداد التنازلي التفاعلي حياً
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _tabs.index == 2) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
        _codes = _service.fetchActivationCodes();
        _devices = _service.fetchConnectedDevices();
        _users = _service.fetchAllProfiles();
      });

  String _generateCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(
        3,
        (_) =>
            List.generate(4, (_) => alphabet[random.nextInt(alphabet.length)])
                .join()).join('-');
  }

  Future<void> _createCode() async {
    final email = TextEditingController();
    var duration = 30;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إنشاء رمز تفعيل',
              style: TextStyle(fontFamily: 'Cairo')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              value: duration,
              decoration: const InputDecoration(labelText: 'مدة الترخيص'),
              items: _durations
                  .map((days) => DropdownMenuItem(
                      value: days, child: Text(_durationLabel(days))))
                  .toList(),
              onChanged: (value) => setDialogState(() => duration = value!),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'البريد المرتبط (اختياري)')),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('إنشاء'))
          ],
        ),
      ),
    );
    if (accepted != true) return;
    final code = _generateCode();
    try {
      await _service.createSecureActivationCode(
          code: code,
          durationDays: duration,
          associatedEmail:
              email.text.trim().isEmpty ? null : email.text.trim());
      _reload();
      _message('تم إنشاء الرمز: $code', success: true);
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _approve(UserModel user) async {
    try {
      await _service.approveLicense(userId: user.id);
      _reload();
      _message('تمت الموافقة على حساب ${user.fullName} بنجاح. هو الآن بانتظار إدخال رمز التفعيل.', success: true);
    } catch (error) {
      _message(error.toString());
    }
  }

  String _formatCountdown(UserModel user) {
    if (user.approvalStatus == 'pending') return 'بانتظار موافقة الإدارة ⏳';
    if (user.licensePaused) return 'الترخيص متوقف مؤقتاً ⏸️';
    if (user.licenseEndAt == null) return 'بانتظار التفعيل بكود 🔑';
    
    final totalSeconds = user.remainingSeconds;
    if (totalSeconds <= 0) return 'منتهي الصلاحية ⚠️';
    
    final days = totalSeconds ~/ 86400;
    final hours = (totalSeconds % 86400) ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    
    final parts = <String>[];
    if (days > 0) parts.add('$days يوم');
    if (hours > 0) parts.add('$hours ساعة');
    if (minutes > 0) parts.add('$minutes دقيقة');
    if (days == 0 && hours == 0) parts.add('$seconds ثانية');
    
    return 'ينتهي خلال: ' + parts.join(' و ');
  }

  Future<void> _togglePause(UserModel user) async {
    try {
      await _service.setLicensePaused(
          userId: user.id, paused: !user.licensePaused);
      _reload();
      _message(
          user.licensePaused
              ? 'تم استئناف الترخيص.'
              : 'تم إيقاف الترخيص مؤقتاً.',
          success: true);
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _removeDevice(Map<String, dynamic> device) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('إزالة الجهاز',
                  style: TextStyle(fontFamily: 'Cairo')),
              content: Text(
                  'سيتم السماح لصاحب الحساب بربط جهاز آخر.\n${device['device_name'] ?? ''}',
                  style: const TextStyle(fontFamily: 'Cairo')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger),
                    child: const Text('إزالة'))
              ],
            ));
    if (confirmed != true) return;
    try {
      await _service.removeDevice(device['id'].toString());
      _reload();
      _message('تمت إزالة الجهاز.', success: true);
    } catch (error) {
      _message(error.toString());
    }
  }

  void _message(String text, {bool success = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(text, style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: success ? AppColors.secondary : AppColors.danger));
  static String _durationLabel(int days) => days == 30
      ? 'شهر واحد'
      : days == 90
          ? '3 أشهر'
          : days == 180
              ? '6 أشهر'
              : 'سنة واحدة';
  String _date(dynamic value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    return parsed == null
        ? '—'
        : DateFormat('yyyy/MM/dd HH:mm').format(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: const ProfessionalBackButton(),
          title: const Text('إدارة التراخيص والأجهزة',
              style: TextStyle(fontFamily: 'Cairo')),
          actions: [
            IconButton(
                onPressed: _reload, icon: const Icon(Icons.refresh_rounded))
          ],
          bottom: TabBar(
              controller: _tabs,
              labelStyle: const TextStyle(fontFamily: 'Cairo'),
              tabs: const [
                Tab(icon: Icon(Icons.key_rounded), text: 'رموز التفعيل'),
                Tab(icon: Icon(Icons.devices_rounded), text: 'الأجهزة'),
                Tab(icon: Icon(Icons.verified_user_rounded), text: 'الحسابات')
              ]),
        ),
        floatingActionButton: _tabs.index == 0
            ? FloatingActionButton.extended(
                onPressed: _createCode,
                icon: const Icon(Icons.add),
                label: const Text('إنشاء رمز',
                    style: TextStyle(fontFamily: 'Cairo')))
            : null,
        body: TabBarView(
            controller: _tabs,
            children: [_codesTab(), _devicesTab(), _usersTab()]),
      );

  Widget _codesTab() => FutureBuilder<List<Map<String, dynamic>>>(
      future: _codes,
      builder: (_, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return _error(snapshot.error);
        final rows = snapshot.data ?? [];
        if (rows.isEmpty)
          return const Center(
              child: Text('لا توجد رموز تفعيل بعد.',
                  style: TextStyle(fontFamily: 'Cairo')));
        return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final row = rows[i];
              final used = row['is_used'] == true;
              final assocEmail = row['associated_email']?.toString();
              
              return Card(
                color: used ? Colors.grey.shade50 : AppColors.secondary.withValues(alpha: 0.02),
                elevation: 0.8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: (used ? Colors.grey.shade300 : AppColors.secondary.withValues(alpha: 0.2)),
                    width: 1,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: (used ? Colors.grey.shade100 : AppColors.secondary.withValues(alpha: 0.12)),
                    child: Icon(
                      used ? Icons.verified_user_rounded : Icons.vpn_key_rounded,
                      color: used ? Colors.grey : AppColors.secondary,
                      size: 22,
                    ),
                  ),
                  title: SelectableText(
                    row['code']?.toString() ?? '',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: used ? Colors.grey.shade700 : AppColors.primaryDark,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مدة الصلاحية: ${_durationLabel((row['duration_days'] as num?)?.toInt() ?? 30)}',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 4,
                          children: [
                            Icon(
                              used ? Icons.link_rounded : Icons.link_off_rounded,
                              size: 14,
                              color: used ? Colors.green : Colors.orange,
                            ),
                            Text(
                              used 
                                  ? (assocEmail != null ? 'مرتبط بـ: $assocEmail' : 'مرتبط ومفعّل')
                                  : (assocEmail != null ? 'مخصص لـ: $assocEmail' : 'غير مرتبط (متاح للجميع)'),
                              style: TextStyle(
                                fontFamily: 'Cairo', 
                                fontSize: 12,
                                fontWeight: used ? FontWeight.w600 : FontWeight.normal,
                                color: used ? Colors.green.shade700 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: used ? Colors.grey.shade200 : AppColors.secondary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            used ? 'مستعمل مسبقاً' : 'جاهز للتفعيل',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: used ? Colors.grey.shade600 : AppColors.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_rounded, color: AppColors.primary),
                    tooltip: 'نسخ الرمز',
                    onPressed: () {
                      final code = row['code']?.toString() ?? '';
                      Clipboard.setData(ClipboardData(text: code));
                      _message('تم نسخ الرمز $code إلى الحافظة.', success: true);
                    },
                  ),
                ),
              );
            });
      });

  Widget _devicesTab() => FutureBuilder<List<Map<String, dynamic>>>(
      future: _devices,
      builder: (_, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return _error(snapshot.error);
        final rows = snapshot.data ?? [];
        if (rows.isEmpty)
          return const Center(
              child: Text('لا توجد أجهزة مسجلة.',
                  style: TextStyle(fontFamily: 'Cairo')));
        return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (_, i) {
              final row = rows[i];
              final profile = row['profiles'];
              final owner = profile is Map ? profile['full_name'] : '—';
              return ListTile(
                  leading: const Icon(Icons.computer_rounded,
                      color: AppColors.primary),
                  title:
                      Text(row['device_name']?.toString() ?? 'جهاز غير مسمى'),
                  subtitle: Text(
                      '$owner • ${row['os_platform'] ?? '—'}\nآخر نشاط: ${_date(row['last_active'])}'),
                  isThreeLine: true,
                  trailing: IconButton(
                      tooltip: 'إزالة الجهاز',
                      onPressed: () => _removeDevice(row),
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: AppColors.danger)));
            });
      });

  Widget _usersTab() => FutureBuilder<List<UserModel>>(
      future: _users,
      builder: (_, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return _error(snapshot.error);
        final users =
            (snapshot.data ?? []).where((user) => !user.isAdmin).toList();
        if (users.isEmpty)
          return const Center(
              child: Text('لا توجد حسابات موظفين.',
                  style: TextStyle(fontFamily: 'Cairo')));
        return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final user = users[i];
              final pending = user.approvalStatus == 'pending';
              final paused = user.licensePaused;
              final status = _formatCountdown(user);
              
              final cardColor = pending
                  ? AppColors.accent.withValues(alpha: 0.02)
                  : paused
                      ? AppColors.danger.withValues(alpha: 0.02)
                      : user.licenseEndAt == null
                          ? Colors.grey.shade50
                          : AppColors.secondary.withValues(alpha: 0.02);

              return Card(
                color: cardColor,
                elevation: 0.8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: pending
                        ? AppColors.accent.withValues(alpha: 0.2)
                        : paused
                            ? AppColors.danger.withValues(alpha: 0.2)
                            : user.licenseEndAt == null
                                ? Colors.grey.shade300
                                : AppColors.secondary.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: (pending
                            ? AppColors.accent
                            : paused
                                ? AppColors.danger
                                : user.licenseEndAt == null
                                    ? Colors.grey
                                    : AppColors.secondary)
                        .withValues(alpha: .15),
                    child: Icon(
                      pending
                          ? Icons.hourglass_empty_rounded
                          : paused
                              ? Icons.pause_rounded
                              : user.licenseEndAt == null
                                  ? Icons.lock_outline_rounded
                                  : Icons.verified_user_rounded,
                      color: pending
                          ? AppColors.accent
                          : paused
                              ? AppColors.danger
                              : user.licenseEndAt == null
                                  ? Colors.grey
                                  : AppColors.secondary,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    user.fullName,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.email ?? 'بدون بريد',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (user.activatedCode != null && user.activatedCode!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 4,
                            children: [
                              const Text(
                                'رمز التفعيل: ',
                                style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.black54),
                              ),
                              SelectableText(
                                user.activatedCode!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.black87,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: user.activatedCode!));
                                  _message('تم نسخ رمز التفعيل ${user.activatedCode!} إلى الحافظة.', success: true);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  child: Icon(Icons.copy_rounded, size: 14, color: AppColors.primary),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        // العدّ التنازلي (يبقى كما هو) + عرض واضح لتاريخ التفعيل ووقت الانتهاء
                        Text(
                          status,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: pending
                                ? AppColors.accent
                                : paused
                                    ? AppColors.danger
                                    : user.licenseEndAt == null
                                        ? Colors.grey.shade700
                                        : AppColors.secondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'تاريخ التفعيل: ${user.licenseStartAt == null ? '—' : DateFormat('yyyy/MM/dd HH:mm').format(user.licenseStartAt!.toLocal())}',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'وقت الانتهاء: ${user.licenseEndAt == null ? '—' : DateFormat('yyyy/MM/dd HH:mm').format(user.licenseEndAt!.toLocal())}',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  isThreeLine: true,
                  trailing: pending
                      ? FilledButton(
                          onPressed: () => _approve(user),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: const Text('موافقة',
                              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)))
                      : (user.licenseEndAt == null
                          ? const SizedBox.shrink()
                          : IconButton(
                              tooltip: paused ? 'استئناف' : 'إيقاف مؤقت',
                              onPressed: () => _togglePause(user),
                              icon: Icon(
                                  paused
                                      ? Icons.play_circle_fill_rounded
                                      : Icons.pause_circle_filled_rounded,
                                  color: paused
                                      ? AppColors.secondary
                                      : AppColors.danger,
                                  size: 28))),
                ),
              );
            });
      });

  Widget _error(Object? error) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('تعذر تحميل البيانات: $error',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Cairo'))));
}
