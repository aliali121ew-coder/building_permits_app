import 'package:flutter/material.dart';
import 'app.dart';
import 'services/connectivity_service.dart';
import 'services/hive_service.dart';
import 'services/supabase_service.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) التخزين المحلي أولاً (تشغيل فوري وسريع للغاية للتطبيق)
  await HiveService.instance.init();

  // 2) تشغيل التطبيق فوراً وبأعلى أداء (60 FPS)
  runApp(const BuildingPermitsApp());

  // 3) تهيئة الشبكة والمزامنة في الخلفية عبر Event Tick بدون حجب المؤقتات إطلاقاً
  Future.delayed(const Duration(milliseconds: 600), () async {
    try {
      await ConnectivityService.instance.init();
      await SupabaseService.initialize().timeout(const Duration(seconds: 3));
      await SyncService.instance.start().timeout(const Duration(seconds: 3));
    } catch (_) {}
  });
}