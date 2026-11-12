import 'package:flutter/material.dart';
import 'app.dart';
import 'services/connectivity_service.dart';
import 'services/hive_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) التخزين المحلي أولاً (تشغيل فوري وسريع للغاية للتطبيق)
  await HiveService.instance.init();

  // 2) تشغيل التطبيق فوراً وبأعلى أداء (60 FPS)
  runApp(const BuildingPermitsApp());

  // 3) تهيئة الشبكة والمزامنة في الخلفية عبر Event Tick بدون حجب المؤقتات إطلاقاً
  Future.delayed(const Duration(milliseconds: 600), () async {
    try {
      // المزامنة تبدأ من PermitProvider.init بعد تهيئة الاتصال
      await ConnectivityService.instance.init();
    } catch (_) {}
  });
}