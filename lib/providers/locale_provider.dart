import 'package:flutter/material.dart';
import '../services/hive_service.dart';

class LocaleProvider extends ChangeNotifier {
  final HiveService _hive = HiveService.instance;

  Locale _locale = const Locale('ar');
  Locale get locale => _locale;

  void init() {
    final saved = _hive.getLocale();
    _locale = Locale(saved ?? 'ar');
  }

  Future<void> setLocale(String code) async {
    _locale = Locale(code);
    await _hive.setLocale(code);
    notifyListeners();
  }

  Future<void> toggle() => setLocale(_locale.languageCode == 'ar' ? 'en' : 'ar');
}
