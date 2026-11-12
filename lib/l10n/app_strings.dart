import 'package:flutter/material.dart';

/// نصوص الواجهة (التطبيق عربي بالكامل).
/// الاستخدام: context.tr('home_title')
class AppStrings {
  AppStrings._();

  static const Map<String, Map<String, String>> _values = {
    'ar': {
      'app_name': 'إجازات البناء',
      'welcome_title': 'مرحباً بك',
      'welcome_subtitle': 'نظام إدارة إجازات البناء المؤسسي',
      'welcome_get_started': 'ابدأ الآن',
      'login_title': 'تسجيل الدخول',
      'email': 'البريد الإلكتروني',
      'password': 'كلمة المرور',
      'login_button': 'دخول',
      'home_title': 'الرئيسية',
      'total_permits': 'إجمالي الإجازات',
      'this_year': 'إجازات هذه السنة',
      'this_month': 'إجازات هذا الشهر',
      'search': 'بحث',
      'add_permit': 'إضافة إجازة',
      'edit_permit': 'تعديل إجازة',
      'all_permits': 'كل الإجازات',
      'settings': 'الإعدادات',
      'sync_status': 'حالة المزامنة',
      'synced': 'تمت المزامنة',
      'syncing': 'جارٍ المزامنة...',
      'offline': 'غير متصل',
      'sync_error': 'خطأ بالمزامنة',
      'permit_number': 'رقم الإجازة',
      'full_name': 'الاسم الثلاثي',
      'plot_number': 'رقم القطعة',
      'permit_date': 'التاريخ',
      'notes': 'الملاحظات',
      'permit_type': 'نوع الإجازة',
      'permit_year': 'السنة',
      'plot_area': 'مساحة العرصة',
      'building_area': 'مساحة البناء',
      'name_change_notes': 'التغيرات (تغيير الاسم)',
      'name_per_new_registry': 'الاسم حسب صورة القيد الجديدة',
      'save': 'حفظ',
      'cancel': 'إلغاء',
      'delete': 'حذف',
      'edit': 'تعديل',
      'required_field': 'هذا الحقل مطلوب',
      'confirm_delete': 'تأكيد الحذف',
      'confirm_delete_msg': 'هل أنت متأكد من حذف هذه الإجازة؟',
      'saved_successfully': 'تم الحفظ بنجاح',
      'deleted_successfully': 'تم الحذف بنجاح',
      'logout': 'تسجيل الخروج',
      'dark_mode': 'الوضع الليلي',
      'language': 'اللغة',
      'export_pdf': 'تصدير PDF',
      'export_excel': 'تصدير Excel',
      'print': 'طباعة',
      'no_results': 'لا توجد نتائج',
      'advanced_filters': 'فلاتر متقدمة',
      'from_date': 'من تاريخ',
      'to_date': 'إلى تاريخ',
      'apply': 'تطبيق',
      'clear_filters': 'مسح الفلاتر',
      'attachments': 'المرفقات',
      'add_attachment': 'إضافة مرفق',
      'user_management': 'إدارة المستخدمين',
      'admin': 'مدير',
      'employee': 'موظف',
      'active': 'مُفعّل',
      'inactive': 'موقوف',
      'permit_number_duplicate': 'رقم الإجازة مستخدم بالفعل لهذه السنة',
      'changed_by': 'تم التعديل بواسطة',
      'view_details': 'عرض التفاصيل',
      'audit_log': 'سجل التدقيق',
    },
  };

  static String of(BuildContext context, String key) => _values['ar']![key] ?? key;
}

extension AppStringsX on BuildContext {
  String tr(String key) => AppStrings.of(this, key);
}
