import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../models/user_model.dart';
import 'hive_service.dart';
import 'supabase_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final SupabaseService _supa = SupabaseService.instance;
  final HiveService _hive = HiveService.instance;
  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  Future<UserModel?> restoreSession() async {
    final cached = _hive.getCachedUser();
    if (cached != null)
      _currentUser = UserModel.fromMap(Map<String, dynamic>.from(cached));
    if (!SupabaseService.isConfigured || _supa.currentSession == null)
      return _currentUser;
    return refreshCurrentProfile(timeout: const Duration(seconds: 3));
  }

  Future<UserModel> signIn(
      {required String email, required String password}) async {
    if (!SupabaseService.isConfigured)
      throw Exception('لم يتم ربط مشروع Supabase بعد.');
    
    // إضافة مهلة زمنية لتجنب التعليق اللانهائي في الشبكات غير المستقرة
    await _supa.signIn(email: email, password: password).timeout(
      const Duration(seconds: 12),
      onTimeout: () => throw Exception('انتهت مهلة الاتصال بالخادم. يرجى التحقق من تغطية الإنترنت وإعادة المحاولة.'),
    );

    var profile = await _supa.fetchCurrentProfile().timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw Exception('انتهت مهلة جلب بيانات الحساب. يرجى إعادة المحاولة.'),
    );

    if (profile == null && _supa.currentAuthUser != null) {
      final isAdmin = _isSystemAdmin(email);
      profile = UserModel(
        id: _supa.currentAuthUser!.id,
        fullName: isAdmin ? 'مدير النظام' : (email.split('@').first),
        role: isAdmin ? AppConstants.roleAdmin : AppConstants.roleEmployee,
        isActive: true,
        canAdd: true,
        canEdit: true,
        canDelete: isAdmin,
        canView: true,
        email: email,
        approvalStatus: isAdmin ? 'approved' : 'pending',
      );
      await _supa.createProfile(profile).timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw Exception('انتهت مهلة إنشاء ملف التعريف في السيرفر.'),
      );
    }
    if (profile == null) throw Exception('لا يوجد ملف تعريف لهذا المستخدم.');
    
    // تحديث البريد الإلكتروني تلقائياً في قاعدة البيانات إن كان فارغاً
    if (profile.email == null || profile.email != email) {
      profile = profile.copyWith(email: email);
      await _supa.updateProfileLicensing(profile.id, {'email': email}).catchError((_) => null);
    }
    
    _currentUser = _withAdminPrivileges(profile, email);
    await _cache(_currentUser!);
    _registerCurrentDevice();
    return _currentUser!;
  }

  Future<void> signUp(
          {required String email,
          required String password,
          required String fullName}) =>
      _supa.signUp(email: email, password: password, fullName: fullName);

  Future<UserModel> activateWithCode(String code) async {
    if (_currentUser == null) throw Exception('يجب تسجيل الدخول أولاً.');
    await _supa.consumeActivationCode(code: code.trim().toUpperCase());
    return (await refreshCurrentProfile()) ??
        (throw Exception('تعذر تحديث حالة الترخيص.'));
  }

  Future<UserModel?> refreshCurrentProfile(
      {Duration timeout = const Duration(seconds: 5)}) async {
    if (!SupabaseService.isConfigured || _supa.currentSession == null)
      return _currentUser;
    try {
      final fresh = await _supa.fetchCurrentProfile().timeout(timeout);
      if (fresh != null) {
        var updated = fresh;
        final authEmail = _supa.currentAuthUser?.email;
        if (authEmail != null && (fresh.email == null || fresh.email != authEmail)) {
          updated = fresh.copyWith(email: authEmail);
          await _supa.updateProfileLicensing(fresh.id, {'email': authEmail}).catchError((_) => null);
        }
        _currentUser =
            _withAdminPrivileges(updated, authEmail);
        await _cache(_currentUser!);
      }
    } catch (_) {
      // Keep the last server-verified profile while offline.
    }
    return _currentUser;
  }

  Future<void> updatePassword(String password) =>
      _supa.updatePassword(password);

  Future<void> changePassword(
      {required String oldPassword, required String newPassword}) async {
    final email = _currentUser?.email;
    if (email == null) throw Exception('المستخدم غير مسجل الدخول.');
    if (SupabaseService.isConfigured)
      await _supa.signIn(email: email, password: oldPassword);
    await _supa.updatePassword(newPassword);
    await _hive.saveLastCredentials(email, newPassword);
  }

  Future<void> updateUserProfile(
      {required String fullName,
      String? birthDate,
      String? phoneNumber,
      String? avatarPath}) async {
    if (_currentUser == null) return;
    if (SupabaseService.isConfigured)
      await _supa.updateProfileName(
          userId: _currentUser!.id, fullName: fullName);
    _currentUser = _currentUser!.copyWith(
        fullName: fullName,
        birthDate: birthDate,
        phoneNumber: phoneNumber,
        avatarPath: avatarPath);
    await _cache(_currentUser!);
  }

  Future<UserModel> signInDemo({String role = AppConstants.roleAdmin}) async {
    _currentUser = UserModel(
        id: 'demo-$role-001',
        fullName: role == AppConstants.roleAdmin ? 'مدير النظام' : 'موظف إدخال',
        role: role,
        isActive: true,
        email: 'demo@building.app',
        approvalStatus: 'approved',
        licenseEndAt: DateTime.now().add(const Duration(days: 3650)));
    await _cache(_currentUser!);
    return _currentUser!;
  }

  Future<void> signOut() async {
    await _hive.clearCachedUser();
    _currentUser = null;
    if (SupabaseService.isConfigured)
      await _supa
          .signOut()
          .timeout(const Duration(seconds: 2), onTimeout: () {});
  }

  UserModel _withAdminPrivileges(UserModel user, String? email) =>
      _isSystemAdmin(email)
          ? user.copyWith(
              role: AppConstants.roleAdmin,
              isActive: true,
              canAdd: true,
              canEdit: true,
              canDelete: true,
              canView: true,
              approvalStatus: 'approved')
          : user;
  bool _isSystemAdmin(String? email) =>
      email?.trim().toLowerCase() == 'see313see@gmail.com' ||
      email?.trim().toLowerCase() == 'see313see@gmail.cor';
  Future<void> _cache(UserModel user) => _hive.setCachedUser(user.toMap());

  Future<void> _registerCurrentDevice() async {
    if (!SupabaseService.isConfigured || _currentUser == null || kIsWeb) return;
    try {
      final info = DeviceInfoPlugin();
      String id, name, platform;
      if (Platform.isAndroid) {
        final d = await info.androidInfo;
        id = d.id;
        name = '${d.manufacturer} ${d.model}';
        platform = 'Android';
      } else if (Platform.isWindows) {
        final d = await info.windowsInfo;
        id = d.deviceId;
        name = d.computerName;
        platform = 'Windows';
      } else if (Platform.isIOS) {
        final d = await info.iosInfo;
        id = d.identifierForVendor ?? d.name;
        name = d.name;
        platform = 'iOS';
      } else {
        id = '${Platform.operatingSystem}-${Platform.localHostname}';
        name = Platform.localHostname;
        platform = Platform.operatingSystem;
      }
      await _supa.registerCurrentDevice(
          deviceId: id, deviceName: name, osPlatform: platform);
    } catch (_) {
      // Device registration is non-blocking; a server rejection is surfaced on the next online check.
    }
  }
}
