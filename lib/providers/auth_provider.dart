import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService.instance;
  UserModel? _user;
  RealtimeChannel? _profileChannel;
  bool _loading = false;
  String? _error;

  UserModel? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> restoreSession() => _run<void>(() async {
        _user = await _auth.restoreSession();
        _listenToProfile();
      });

  Future<bool> signIn(String email, String password) => _run<bool>(() async {
        _user = await _auth.signIn(email: email, password: password);
        _listenToProfile();
        return true;
      }, fallback: false);

  Future<bool> signInDemo({String role = 'admin'}) => _run<bool>(() async {
        _user = await _auth.signInDemo(role: role);
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

  Future<bool> updatePassword(String password) => _run<bool>(() async {
        await _auth.updatePassword(password);
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
    // إلغاء الاشتراك في الاستماع لقاعدة البيانات في الخلفية
    final pc = _profileChannel;
    _profileChannel = null;
    if (pc != null) {
      pc.unsubscribe().catchError((_) => '');
    }
    
    // تسجيل الخروج محلياً فوراً لتحديث واجهة المستخدم دون انتظار
    _user = null;
    notifyListeners();
    
    // إتمام تسجيل الخروج من السيرفر في الخلفية
    try {
      await _auth.signOut();
    } catch (_) {}
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

  void _listenToProfile() {
    final id = _user?.id;
    if (id == null || id.startsWith('demo-')) return;
    _profileChannel?.unsubscribe();
    _profileChannel =
        SupabaseService.instance.subscribeToProfileChanges(id, (_) async {
      _user = await _auth.refreshCurrentProfile() ?? _user;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _profileChannel?.unsubscribe();
    super.dispose();
  }
}
