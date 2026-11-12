import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permit_provider.dart';
import '../permits/permit_detail_screen.dart';

/// شاشة ماسح الباركود ورمز QR الفوري لعرض تفاصيل إجازة البناء مباشرة
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  final TextEditingController _manualCtrl = TextEditingController();
  bool _isShowingDetail = false;

  @override
  void initState() {
    super.initState();
    // في المتصفحات بلا قارئ مدمج (iPhone / ويندوز) تُحمَّل مكتبة القراءة من موقعنا لا من CDN خارجي
    if (kIsWeb) MobileScannerPlatform.instance.setBarcodeLibraryScriptUrl('zxing/reader.js');
  }
  bool _torchEnabled = false;
  String? _lastScannedRaw;

  @override
  void dispose() {
    _scannerController.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleCodeDetected(String rawValue) async {
    if (_isShowingDetail) return;
    final code = rawValue.trim();
    if (code.isEmpty) return;

    final provider = context.read<PermitProvider>();
    final auth = context.read<AuthProvider>();
    final matchedPermit = provider.findByCode(code);

    setState(() {
      _isShowingDetail = true;
      _lastScannedRaw = code;
    });

    if (matchedPermit != null) {
      await PermitDetailScreen.show(
        context,
        matchedPermit,
        canEdit: auth.user?.canEdit ?? true,
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'لم يتم العثور على إجازة مطابقة للباركود: $code',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    if (mounted) {
      setState(() {
        _isShowingDetail = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'قارئ باركود إجازات البناء',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          IconButton(
            tooltip: 'تشغيل / إيقاف الفلاش',
            icon: Icon(_torchEnabled ? Icons.flash_on_rounded : Icons.flash_off_rounded),
            onPressed: () async {
              await _scannerController.toggleTorch();
              setState(() => _torchEnabled = !_torchEnabled);
            },
          ),
          IconButton(
            tooltip: 'تبديل الكاميرا',
            icon: const Icon(Icons.cameraswitch_rounded),
            onPressed: () => _scannerController.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          // منطقة الكاميرا ومسح الباركود
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: (capture) {
                    if (_isShowingDetail) return;
                    for (final barcode in capture.barcodes) {
                      final raw = barcode.rawValue;
                      if (raw != null && raw.trim().isNotEmpty) {
                        _handleCodeDetected(raw);
                        break;
                      }
                    }
                  },
                ),

                // إطار التوجيه البصري في وسط الكاميرا
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: AppColors.secondary,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondary.withValues(alpha: 0.25),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),

                // شريط التوجيه العلوي فوق الكاميرا
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'وجّه الكاميرا نحو باركود الإجازة لعرض بطاقة التفاصيل فوراً',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // شريط سفلي لإدخال رقم/باركود الإجازة يدوياً عند الحاجة
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_lastScannedRaw != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'آخر قراءة: $_lastScannedRaw',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11.5, color: Colors.grey, fontFamily: 'Cairo'),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualCtrl,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (v) {
                          if (v.trim().isNotEmpty) _handleCodeDetected(v);
                        },
                        decoration: InputDecoration(
                          hintText: 'أو أدخل رقم الإجازة (مثال: 2026/77) أو رقم القطعة...',
                          hintStyle: const TextStyle(fontSize: 12, fontFamily: 'Cairo'),
                          isDense: true,
                          prefixIcon: const Icon(Icons.qr_code_rounded, color: AppColors.primary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        if (_manualCtrl.text.trim().isNotEmpty) {
                          _handleCodeDetected(_manualCtrl.text);
                        }
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text(
                        'عرض',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

