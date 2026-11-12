import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/navigation.dart';
import '../core/platform/pwa_install.dart';
import '../services/hive_service.dart';

/// شريط علوي «ثبّت التطبيق» عند فتحه من المتصفح:
/// - Chrome / Edge / Samsung: زر «تثبيت» يعرض نافذة التثبيت مباشرة.
/// - iPhone (Safari لا يسمح بزر تثبيت): الزر يشرح خطوتي «مشاركة ← إضافة إلى الشاشة الرئيسية».
/// لا يظهر إن كان التطبيق مثبّتاً، وإن أُغلق لا يعود قبل 3 أيام.
class InstallBanner extends StatefulWidget {
  const InstallBanner({super.key, required this.child});
  final Widget child;

  @override
  State<InstallBanner> createState() => _InstallBannerState();
}

class _InstallBannerState extends State<InstallBanner> {
  static const _snooze = Duration(days: 3);

  bool _visible = false;
  bool _ios = false;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb || pwaIsStandalone()) return;
    final dismissed = HiveService.instance.getInstallBannerDismissedAt();
    if (dismissed != null && DateTime.now().difference(dismissed) < _snooze) return;

    _ios = pwaIsIOS();
    _visible = _ios || pwaCanInstall();
    // المتصفح قد يجهّز التثبيت بعد ثوانٍ من الفتح
    onPwaEvent('pwa-installable', () {
      if (mounted && !pwaIsStandalone()) setState(() => _visible = true);
    });
    onPwaEvent('pwa-installed', () {
      if (mounted) setState(() => _visible = false);
    });
  }

  Future<void> _install() async {
    if (_ios) {
      _showIosSteps();
      return;
    }
    setState(() => _installing = true);
    final outcome = await pwaInstall();
    if (!mounted) return;
    setState(() {
      _installing = false;
      if (outcome == 'accepted') _visible = false;
    });
  }

  void _dismiss() {
    HiveService.instance.setInstallBannerDismissedAt(DateTime.now());
    setState(() => _visible = false);
  }

  void _showIosSteps() {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    showDialog<void>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('تثبيت التطبيق على iPhone',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IosStep(n: 1, icon: Icons.ios_share_rounded, text: 'اضغط زر «مشاركة» أسفل شاشة Safari'),
            SizedBox(height: 12),
            _IosStep(n: 2, icon: Icons.add_box_outlined, text: 'اختر «إضافة إلى الشاشة الرئيسية» ثم «إضافة»'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_visible) Positioned(top: 0, left: 0, right: 0, child: _banner()),
      ],
    );
  }

  Widget _banner() {
    return SafeArea(
      bottom: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: Material(
            elevation: 8,
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 2),
                        image: const DecorationImage(image: AssetImage('assets/images/logo.jpg'), fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ثبّت التطبيق على جهازك',
                              style: TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14)),
                          Text('يفتح أسرع ويعمل بدون إنترنت',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11.5)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primaryDark,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        // ثيم التطبيق يجعل الأزرار بعرض لا نهائي (Size.fromHeight)؛ داخل Row يلزم عرض محدد
                        minimumSize: const Size(0, 40),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _installing ? null : _install,
                      icon: const Icon(Icons.install_mobile_rounded, size: 18),
                      label: const Text('تثبيت', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    ),
                    // بدون tooltip: الشريط فوق Navigator فلا يوجد Overlay يعرضه
                    IconButton(
                      onPressed: _dismiss,
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
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

class _IosStep extends StatelessWidget {
  const _IosStep({required this.n, required this.icon, required this.text});
  final int n;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: AppColors.primary,
          child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        const SizedBox(width: 10),
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontFamily: 'Cairo', fontSize: 13.5))),
      ],
    );
  }
}
