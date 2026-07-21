/// ثوابت عامة تُستخدم عبر التطبيق
class AppConstants {
  AppConstants._();

  // ---- Supabase (تم الربط بمشروعك الحقيقي) ----
  static const String supabaseUrl = 'https://diorwiyawahunnozeoqc.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_pPj5yUCAAIYnubgxty7X0Q_wywAV5K2';
  static const String attachmentsBucket = 'permit-attachments';

  // ---- صناديق Hive المحلية ----
  static const String hivePermitsBox = 'permits_box';
  static const String hivePendingOpsBox = 'pending_ops_box';
  static const String hiveSettingsBox = 'settings_box';
  static const String hiveUserBox = 'user_box';

  // ---- مفاتيح الإعدادات ----
  static const String keyThemeMode = 'theme_mode'; // light / dark / system
  static const String keyLocale = 'locale'; // ar / en
  static const String keyLastSyncAt = 'last_sync_at';

  // ---- الأدوار ----
  static const String roleAdmin = 'admin';
  static const String roleEmployee = 'employee';

  // ---- أنواع الإجازة الشائعة (تُقترح تلقائياً، وتقبل نص حر أيضاً) ----
  static const List<String> permitTypes = [
    'اجازة جديدة',
    'اضافة بناء',
    'بناء اضافي',
    'ترميم',
    'تسوية مخالفة',
    'تجديد اجازة',
  ];

  static const int minSearchChars = 1;
  static const Duration syncDebounce = Duration(milliseconds: 400);
  static const Duration toastDuration = Duration(seconds: 4);
}
