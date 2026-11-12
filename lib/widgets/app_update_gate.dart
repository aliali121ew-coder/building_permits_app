import 'dart:async';
import 'dart:io' show exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/app_colors.dart';
import '../core/platform/page_reload.dart';
import '../services/update_service.dart';

/// بوابة التحديث — تلفّ التطبيق بالكامل:
/// - APK/ويندوز: عند رفع إصدار أحدث على Cloudflare تظهر شاشة تمنع الاستخدام
///   ولا تترك إلا خيارين: «تحديث الآن» (تنزيل وتثبيت من داخل التطبيق) أو «خروج».
/// - الويب: عند نشر نسخة جديدة يظهر شريط علوي بعدّ تنازلي 5 ثوانٍ ثم يُحدَّث تلقائياً.
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child});
  final Widget child;

  static _AppUpdateGateState? _instance;

  /// فحص يدوي (من الإعدادات). يعيد false إن كان التطبيق محدّثاً.
  static Future<bool> checkNow() async => await _instance?._check(force: true) ?? false;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> with WidgetsBindingObserver {
  static const _webPollInterval = Duration(minutes: 2);
  static const _appCheckThrottle = Duration(minutes: 10);
  static const _webCountdownSeconds = 5;

  // أندرويد/ويندوز
  AppUpdateInfo? _update;
  bool _downloading = false;
  bool _installerOpened = false;
  double _progress = 0;
  String? _error;
  DateTime? _lastAppCheck;

  // الويب
  String? _webFingerprint;
  Timer? _webPoll;
  Timer? _countdownTimer;
  int? _secondsLeft;

  @override
  void initState() {
    super.initState();
    AppUpdateGate._instance = this;
    WidgetsBinding.instance.addObserver(this);
    // تأخير بسيط كي لا ينافس الفحص إقلاع التطبيق
    Future.delayed(const Duration(seconds: 3), () => _check());
    if (kIsWeb) _webPoll = Timer.periodic(_webPollInterval, (_) => _check());
  }

  @override
  void dispose() {
    if (AppUpdateGate._instance == this) AppUpdateGate._instance = null;
    WidgetsBinding.instance.removeObserver(this);
    _webPoll?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<bool> _check({bool force = false}) async {
    if (kIsWeb) return _checkWeb();
    if (_update != null) return true;
    final now = DateTime.now();
    if (!force && _lastAppCheck != null && now.difference(_lastAppCheck!) < _appCheckThrottle) return false;
    _lastAppCheck = now;
    final update = await UpdateService.instance.checkForUpdate();
    if (update != null && mounted) setState(() => _update = update);
    return update != null;
  }

  // ===================== الويب: عدّ تنازلي ثم تحديث =====================

  Future<bool> _checkWeb() async {
    if (_secondsLeft != null) return true;
    final fp = await UpdateService.instance.currentWebBuildFingerprint();
    if (fp == null) return false;
    if (_webFingerprint == null) {
      _webFingerprint = fp; // أول قراءة = النسخة التي تعمل الآن
      return false;
    }
    if (fp == _webFingerprint) return false;
    _startWebCountdown();
    return true;
  }

  void _startWebCountdown() {
    if (!mounted) return;
    setState(() => _secondsLeft = _webCountdownSeconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = (_secondsLeft ?? 1) - 1;
      if (left <= 0) {
        t.cancel();
        reloadPage();
      } else if (mounted) {
        setState(() => _secondsLeft = left);
      }
    });
  }

  // ===================== أندرويد/ويندوز: تنزيل وتثبيت =====================

  Future<void> _startDownload() async {
    final update = _update;
    if (update == null) return;
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });
    try {
      final file = await UpdateService.instance.downloadUpdate(
        update,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await UpdateService.instance.installUpdate(file);
      if (mounted) setState(() => _installerOpened = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذّر تنزيل التحديث، تحقّق من الإنترنت وأعد المحاولة');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _exitApp() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      SystemNavigator.pop();
    } else {
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_update != null) Positioned.fill(child: _buildForcedUpdate(context, _update!)),
        if (_secondsLeft != null) Positioned(top: 0, left: 0, right: 0, child: _buildWebBanner(context, _secondsLeft!)),
      ],
    );
  }

  Widget _buildWebBanner(BuildContext context, int seconds) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(16),
            color: AppColors.primaryDark,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: seconds / _webCountdownSeconds,
                            strokeWidth: 3,
                            color: Colors.white,
                            backgroundColor: Colors.white24,
                          ),
                          Text('$seconds',
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('يتوفر إصدار جديد',
                              style: TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14)),
                          Text('سيتم تحديث الصفحة تلقائياً…',
                              style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: reloadPage,
                      child: const Text('تحديث الآن',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForcedUpdate(BuildContext context, AppUpdateInfo update) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.black.withValues(alpha: 0.72),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const CircleAvatar(
                        radius: 30,
                        backgroundColor: Color(0x1A1FA2C4),
                        child: Icon(Icons.system_update_rounded, size: 32, color: AppColors.info),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'تحديث إلزامي ${update.version}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'يتوفر إصدار جديد من التطبيق. يجب التحديث للمتابعة.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.grey),
                      ),
                      if (update.releaseNotes.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 160),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: SingleChildScrollView(
                            child: Text(update.releaseNotes,
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, height: 1.6)),
                          ),
                        ),
                      ],
                      if (_downloading) ...[
                        const SizedBox(height: 18),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(minHeight: 8, value: _progress == 0 ? null : _progress),
                        ),
                        const SizedBox(height: 6),
                        Text('جارٍ التنزيل… ${(_progress * 100).toStringAsFixed(0)}%',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey)),
                      ],
                      if (_installerOpened && !_downloading) ...[
                        const SizedBox(height: 12),
                        const Text('أكمل التثبيت من نافذة النظام. إن أُغلقت اضغط «تحديث الآن» مجدداً.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.info)),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.danger)),
                      ],
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.info,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _downloading ? null : _startDownload,
                        icon: const Icon(Icons.download_rounded),
                        label: Text(_downloading ? 'جارٍ التنزيل…' : 'تحديث الآن',
                            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _downloading ? null : _exitApp,
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('خروج من التطبيق',
                            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                      ),
                    ],
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
