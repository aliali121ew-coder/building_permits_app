/// ثوابت عامة تُستخدم عبر التطبيق
class AppConstants {
  AppConstants._();

  // ---- Cloudflare Backend API ----
  static const String backendApiUrl = 'https://building-permits-backend.aliali121ew.workers.dev';

  // ---- صناديق Hive المحلية ----
  static const String hivePermitsBox = 'permits_box';
  static const String hivePendingOpsBox = 'pending_ops_box';
  static const String hiveSettingsBox = 'settings_box';
  static const String hiveUserBox = 'user_box';

  // ---- مفاتيح الإعدادات ----
  static const String keyThemeMode = 'theme_mode'; // light / dark / system
  static const String keyLastSyncAt = 'last_sync_at';

  // ---- الأدوار ----
  static const String roleAdmin = 'admin';
  static const String roleEmployee = 'employee';

  // ---- أنواع الإجازة الشائعة (تُقترح تلقائياً، وتقبل نص حر أيضاً) ----
  static const List<String> permitTypes = [
    'اجازة جديدة',
    'ملحق اجازة',
    'تغيير مخططات',
    'اضافة بناء طابق',
    'طابقين',
    'ثالث',
    'تغيير اسم من القديم الى الجديد',
    'هيكل مسقف',
    'باتلو',
    'اضافة بناء',
    'بناء اضافي',
    'ترميم',
    'تسوية مخالفة',
    'تجديد اجازة',
  ];
}
