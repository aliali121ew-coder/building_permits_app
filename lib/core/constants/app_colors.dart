import 'package:flutter/material.dart';

/// نظام ألوان احترافي موحّد للوضعين الليلي والنهاري
class AppColors {
  AppColors._();

  // ---- الألوان الأساسية (Brand) ----
  static const Color primary = Color(0xFF2A5C8A); // أزرق مؤسسي هادئ
  static const Color primaryDark = Color(0xFF1B3D5E);
  static const Color secondary = Color(0xFF2E9E6D); // أخضر (نجاح / إجازة سارية)
  static const Color accent = Color(0xFFE0A526); // ذهبي (تنبيهات / تمييز)
  static const Color danger = Color(0xFFD64545);
  static const Color info = Color(0xFF3C93C2);

  // ---- تدرجات الكروت الزجاجية (8 كروت بألوان مختلفة) ----
  static const List<List<Color>> cardGradients = [
    [Color(0xFF2A5C8A), Color(0xFF5B9BD5)],
    [Color(0xFF2E9E6D), Color(0xFF6FCF97)],
    [Color(0xFFE0A526), Color(0xFFF2C94C)],
    [Color(0xFFD64545), Color(0xFFEB7A7A)],
    [Color(0xFF7B5EA7), Color(0xFFB39DDB)],
    [Color(0xFF3C93C2), Color(0xFF81D4FA)],
    [Color(0xFF456882), Color(0xFF8FB8C9)],
    [Color(0xFFB8722F), Color(0xFFE0A96D)],
  ];

  // ---- الوضع النهاري (مريح للعين وغير فاقع) ----
  static const Color lightBackground = Color(0xFFEBF0F5);
  static const Color lightSurface = Color(0xFFF7FAFD);
  static const Color lightTextPrimary = Color(0xFF1E293B);
  static const Color lightTextSecondary = Color(0xFF64748B);
  static const Color lightGlassBorder = Color(0x1F000000);

  // ---- الوضع الليلي ----
  static const Color darkBackground = Color(0xFF0E1620);
  static const Color darkSurface = Color(0xFF162232);
  static const Color darkTextPrimary = Color(0xFFEAF0F6);
  static const Color darkTextSecondary = Color(0xFF9AAAB8);
  static const Color darkGlassBorder = Color(0x22FFFFFF);

  // ---- حالة المزامنة ----
  static const Color synced = Color(0xFF2E9E6D);
  static const Color syncing = Color(0xFFE0A526);
  static const Color offline = Color(0xFF9AAAB8);
  static const Color syncError = Color(0xFFD64545);
}
