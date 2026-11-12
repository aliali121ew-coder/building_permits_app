import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService.instance;
  UserModel? _user;
  bool _loading = false;
  String? _error;

  UserModel? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get loading => _loading;
  String? get error => _error;

  /// «تذكرني»: يعيد المستخدم المحفوظ فوراً، ثم يحدّث ملفه من الخادم في الخلفية
  /// (بطء الشبكة لا يعيد المستخدم إلى شاشة الدخول أبداً).
  void restoreSession() {
    _user = _auth.restoreCachedUser();
    notifyListeners();
    if (_user != null) refreshUser();
  }

  Future<bool> signIn(String email, String password) => _run<bool>(() async {
        _user = await _auth.signIn(email: email, password: password);
        return true;
      }, fallback: false);

  Future<bool> signUp(
          {required String email,
          required String password,
          required String fullName}) =>
      _run<bool>(() async {
        await _auth.signUp(
            email: email, password: password, fullName: fullName);
        return true;
      }, fallback: false);

  Future<bool> activateWithCode(String code) => _run<bool>(() async {
        _user = await _auth.activateWithCode(code);
        return true;
      }, fallback: false);

  Future<bool> changePassword(
          {required String oldPassword, required String newPassword}) =>
      _run<bool>(() async {
        await _auth.changePassword(
            oldPassword: oldPassword, newPassword: newPassword);
        return true;
      }, fallback: false);

  Future<bool> updateUserProfile(
          {required String fullName,
          String? birthDate,
          String? phoneNumber,
          String? avatarPath}) =>
      _run<bool>(() async {
        await _auth.updateUserProfile(
            fullName: fullName,
            birthDate: birthDate,
            phoneNumber: phoneNumber,
            avatarPath: avatarPath);
        _user = _auth.currentUser;
        return true;
      }, fallback: false);

  Future<void> refreshUser() => _run<void>(() async {
        _user = await _auth.refreshCurrentProfile() ?? _user;
      });

  Future<void> signOut() async {
    _user = null;
    notifyListeners();
    await _auth.signOut();
  }

  Future<T> _run<T>(Future<T> Function() action, {T? fallback}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      return await action();
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
      if (fallback != null) return fallback;
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
