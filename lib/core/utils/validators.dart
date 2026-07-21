class Validators {
  Validators._();

  static String? required(String? value, {String message = 'هذا الحقل مطلوب'}) {
    if (value == null || value.trim().isEmpty) return message;
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'الرجاء إدخال البريد الإلكتروني';
    final regex = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,}$');
    if (!regex.hasMatch(value.trim())) return 'صيغة البريد الإلكتروني غير صحيحة';
    return null;
  }

  static String? positiveNumber(String? value) {
    if (value == null || value.trim().isEmpty) return null; // اختياري
    final n = double.tryParse(value.trim());
    if (n == null) return 'الرجاء إدخال رقم صحيح';
    if (n < 0) return 'يجب أن يكون الرقم موجباً';
    return null;
  }

  static String? permitYear(String? value) {
    if (value == null || value.trim().isEmpty) return 'الرجاء إدخال السنة';
    final n = int.tryParse(value.trim());
    if (n == null || n < 1970 || n > DateTime.now().year + 1) return 'سنة غير صحيحة';
    return null;
  }

  static String? permitNumber(String? value) {
    if (value == null || value.trim().isEmpty) return 'الرجاء إدخال رقم الإجازة';
    final n = int.tryParse(value.trim());
    if (n == null || n <= 0) return 'رقم الإجازة يجب أن يكون رقماً موجباً';
    return null;
  }
}
