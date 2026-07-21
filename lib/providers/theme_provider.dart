import 'package:flutter/material.dart';
import '../services/hive_service.dart';

class ThemeProvider extends ChangeNotifier {
  final HiveService _hive = HiveService.instance;

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  void init() {
    final saved = _hive.getThemeMode();
    switch (saved) {
      case 'light':
        _mode = ThemeMode.light;
        break;
      case 'dark':
        _mode = ThemeMode.dark;
        break;
      default:
        _mode = ThemeMode.system;
    }
  }

  bool isDark(BuildContext context) {
    if (_mode == ThemeMode.system) {
      return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
    return _mode == ThemeMode.dark;
  }

  void toggle(BuildContext context) {
    final currentlyDark = isDark(context);
    _mode = currentlyDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    // حفظ في الخلفية بشكل غير معطل للواجهة (Non-blocking background I/O)
    _hive.setThemeMode(_mode == ThemeMode.dark ? 'dark' : 'light');
  }

  void setMode(ThemeMode mode) {
    _mode = mode;
    notifyListeners();
    _hive.setThemeMode(mode == ThemeMode.dark ? 'dark' : (mode == ThemeMode.light ? 'light' : 'system'));
  }
}
