import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../models/user_model.dart';
import 'cloudflare_api_service.dart';
import 'hive_service.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final CloudflareApiService _api = CloudflareApiService.instance;
  final HiveService _hive = HiveService.instance;
  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  bool get _hasToken => (_hive.getAuthToken() ?? '').isNotEmpty;

  /// يعيد المستخدم المحفوظ محلياً فوراً (بدون انتظار الشبكة) — أساس «تذكرني».
  UserModel? restoreCachedUser() {
    final cached = _hive.getCachedUser();
    if (cached != null && _hasToken) {
      _currentUser = UserModel.fromMap(Map<String, dynamic>.from(cached));
    }
    return _currentUser;
  }

  Future<UserModel> signIn({required String email, required String password}) async {
    final user = await _api.login(email: email, password: password).timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw const ApiException('انتهت مهلة الاتصال بالخادم'),
        );
    _currentUser = _withAdminPrivileges(user, email);
    await _cache(_currentUser!);
    // «تذكرني» تلقائياً: حفظ البريد وكلمة المرور (مشفّرة) لإعادة الدخول الصامت عند انتهاء الجلسة
    await _hive.saveLastCredentials(email.trim(), password);
    _registerCurrentDevice();
    return _currentUser!;
  }

  Future<void> signUp({required String email, required String password, required String fullName}) async {
    final user = await _api.register(email: email, password: password, fullName: fullName);
    await _cache(user);
  }

  Future<UserModel> activateWithCode(String code) async {
    if (_currentUser == null) throw const ApiException('يجب تسجيل الدخول أولاً');
    await _api.activateCode(code.trim().toUpperCase());
    return (await refreshCurrentProfile()) ?? (throw const ApiException('تعذر تحديث حالة الترخيص'));
  }

  /// تحديث الملف الشخصي من الخادم. عند انتهاء الجلسة (401) يُعاد الدخول بصمت
  /// بالبيانات المحفوظة، وإن فشل ذلك يبقى آخر ملف محفوظ (العمل بدون إنترنت).
  Future<UserModel?> refreshCurrentProfile({Duration timeout = const Duration(seconds: 6)}) async {
    if (!_hasToken) return _currentUser;
    try {
      final fresh = await _api.getMe().timeout(timeout);
      _currentUser = _withAdminPrivileges(fresh, fresh.email);
      await _cache(_currentUser!);
    } on ApiException catch (e) {
      if (e.statusCode == 401) await _silentRelogin();
    } catch (_) {
      // بدون اتصال: نُبقي آخر ملف تم التحقق منه.
    }
    return _currentUser;
  }

  Future<void> _silentRelogin() async {
    final email = _hive.getLastEmail();
    final password = await _hive.getLastPassword();
    if (email.isEmpty || password.isEmpty) return;
    try {
      await signIn(email: email, password: password);
    } catch (_) {}
  }

  Future<void> changePassword({required String oldPassword, required String newPassword}) async {
    final email = _currentUser?.email;
    if (email == null) throw const ApiException('المستخدم غير مسجل الدخول');
    await _api.changePassword(oldPassword: oldPassword, newPassword: newPassword);
    await _hive.saveLastCredentials(email, newPassword);
  }

  Future<void> updateUserProfile({
    required String fullName,
    String? birthDate,
    String? phoneNumber,
    String? avatarPath,
  }) async {
    if (_currentUser == null) return;
    // صورة جديدة من الجهاز ← تُرفع إلى R2 كي يراها المدير من أي جهاز
    // (وأيضاً أي صورة قديمة محفوظة محلياً فقط تُرفع مرة واحدة)
    String? avatar = avatarPath;
    if (avatar != null && !avatar.startsWith('http')) {
      final file = File(avatar);
      avatar = (kIsWeb || !file.existsSync()) ? null : await _api.uploadAttachment(
        permitId: 'avatars',
        fileName: 'avatar_${_currentUser!.id}.png',
        bytes: await file.readAsBytes(),
      );
    }
    await _api.updateProfile(_currentUser!.id, {
      'full_name': fullName,
      'avatar_path': avatar,
      'phone_number': phoneNumber,
      'birth_date': birthDate,
    });
    _currentUser = _currentUser!.copyWith(
      fullName: fullName,
      birthDate: birthDate,
      phoneNumber: phoneNumber,
      avatarPath: avatar,
    );
    await _cache(_currentUser!);
  }

  /// تسجيل الخروج: يمسح الجلسة فقط. بيانات «تذكرني» تبقى لتعبئة شاشة الدخول تلقائياً.
  Future<void> signOut() async {
    await _hive.clearCachedUser();
    _currentUser = null;
  }

  UserModel _withAdminPrivileges(UserModel user, String? email) => _isSystemAdmin(email)
      ? user.copyWith(
          role: AppConstants.roleAdmin,
          isActive: true,
          canAdd: true,
          canEdit: true,
          canDelete: true,
          canView: true,
          approvalStatus: 'approved')
      : user;

  bool _isSystemAdmin(String? email) => email?.trim().toLowerCase() == 'see313see@gmail.com';

  Future<void> _cache(UserModel user) => _hive.setCachedUser(user.toMap());

  Future<void> _registerCurrentDevice() async {
    if (_currentUser == null || kIsWeb) return;
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
      } else {
        id = '${Platform.operatingSystem}-${Platform.localHostname}';
        name = Platform.localHostname;
        platform = Platform.operatingSystem;
      }
      await _api.registerDevice(deviceId: id, deviceName: name, osPlatform: platform);
    } catch (_) {
      // تسجيل الجهاز غير حاجب.
    }
  }
}
