import 'package:intl/intl.dart';

class AppDateUtils {
  AppDateUtils._();

  /// تاريخ ميلادي دائماً (كما هو في البيانات الأصلية)، مثال: 2026-07-18
  static String formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  static String formatDateTime(DateTime date) => DateFormat('yyyy-MM-dd HH:mm').format(date);

  static String formatDateArabicStyle(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  static String timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inSeconds < 60) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
    if (diff.inDays < 30) return 'قبل ${diff.inDays} يوم';
    return formatDate(date);
  }
}
