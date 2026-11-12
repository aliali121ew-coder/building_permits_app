import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/platform/page_reload.dart';
import '../services/update_service.dart';

/// بوابة التحديث (الويب): عند نشر نسخة جديدة على Cloudflare يظهر شريط علوي
/// بعدّ تنازلي 5 ثوانٍ ثم تُحدَّث الصفحة تلقائياً.
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child});
  final Widget child;

  static _AppUpdateGateState? _instance;

  /// فحص يدوي (من الإعدادات). يعيد false إن كان التطبيق محدّثاً.
  static Future<bool> checkNow() async => await _instance?._check() ?? false;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> with WidgetsBindingObserver {
  static const _pollInterval = Duration(minutes: 2);
  static const _countdownSeconds = 5;

  String? _fingerprint;
  Timer? _poll;
  Timer? _countdown;
  int? _secondsLeft;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    AppUpdateGate._instance = this;
    WidgetsBinding.instance.addObserver(this);
    _check(); // أول قراءة = بصمة النسخة التي تعمل الآن
    _poll = Timer.periodic(_pollInterval, (_) => _check());
  }

  @override
  void dispose() {
    if (AppUpdateGate._instance == this) AppUpdateGate._instance = null;
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _countdown?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<bool> _check() async {
    if (_secondsLeft != null) return true;
    final fp = await UpdateService.instance.currentWebBuildFingerprint();
    if (fp == null) return false;
    if (_fingerprint == null) {
      _fingerprint = fp;
      return false;
    }
    if (fp == _fingerprint) return false;
    _startCountdown();
    return true;
  }

  void _startCountdown() {
    if (!mounted) return;
    setState(() => _secondsLeft = _countdownSeconds);
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = (_secondsLeft ?? 1) - 1;
      if (left <= 0) {
        t.cancel();
        reloadPage();
      } else if (mounted) {
        setState(() => _secondsLeft = left);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_secondsLeft != null) Positioned(top: 0, left: 0, right: 0, child: _banner(_secondsLeft!)),
      ],
    );
  }

  Widget _banner(int seconds) {
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
                            value: seconds / _countdownSeconds,
                            strokeWidth: 3,
                            color: Colors.white,
                            backgroundColor: Colors.white24,
                          ),
                          Text('$seconds',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
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
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14)),
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
}
