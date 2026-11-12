import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/app_constants.dart';
import '../models/permit_model.dart';
import '../models/user_model.dart';
import 'cloudflare_api_service.dart';
import 'hive_service.dart';

/// طبقة الاتصال الموحدة - تُوجّه جميع العمليات إلى خادم Cloudflare Edge المباشر
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  static bool get isConfigured => AppConstants.backendApiUrl.isNotEmpty;

  SupabaseClient? get client => null;

  static Future<void> initialize() async {
    // تم تحويل الخادم إلى Cloudflare Workers بنجاح
  }

  // ===================== المصادقة =====================

  Session? get currentSession {
    final token = HiveService.instance.getAuthToken();
    if (token == null || token.isEmpty) return null;
    final cached = HiveService.instance.getCachedUser();
    final id = cached?['id']?.toString() ?? 'user';
    final email = cached?['email']?.toString() ?? '';
    return Session(
      accessToken: token,
      tokenType: 'bearer',
      user: User(
        id: id,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: email,
      ),
    );
  }

  User? get currentAuthUser => currentSession?.user;

  Stream<AuthState>? get authStateChanges => null;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final user = await CloudflareApiService.instance.login(
      email: email,
      password: password,
    );
    await HiveService.instance.setCachedUser(user.toMap());
    final session = currentSession;
    return AuthResponse(session: session, user: session?.user);
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final user = await CloudflareApiService.instance.register(
      email: email,
      password: password,
      fullName: fullName,
    );
    await HiveService.instance.setCachedUser(user.toMap());
    final session = currentSession;
    return AuthResponse(session: session, user: session?.user);
  }

  Future<void> signOut() async {
    await HiveService.instance.clearAuthToken();
  }

  Future<void> updatePassword(String newPassword) async {
    await CloudflareApiService.instance.changePassword(newPassword: newPassword);
  }

  Future<UserModel?> fetchCurrentProfile() async {
    return await CloudflareApiService.instance.getMe();
  }

  Future<List<UserModel>> fetchAllProfiles() async {
    return await CloudflareApiService.instance.fetchAllProfiles();
  }

  Future<void> createProfile(UserModel profile) async {
    await CloudflareApiService.instance.updateProfile(profile.id, profile.toSupabaseMap());
  }

  Future<void> updateProfileRole({
    required String userId,
    required String role,
    required bool isActive,
  }) async {
    await CloudflareApiService.instance.updateProfile(userId, {
      'role': role,
      'is_active': isActive ? 1 : 0,
    });
  }

  Future<void> updateProfileName({
    required String userId,
    required String fullName,
  }) async {
    await CloudflareApiService.instance.updateProfile(userId, {
      'full_name': fullName,
    });
  }

  Future<void> updateProfilePermissions(UserModel user) async {
    await CloudflareApiService.instance.updateProfile(user.id, user.toSupabaseMap());
  }

  // ===================== الإجازات (CRUD) =====================

  Future<List<PermitModel>> fetchAllPermits() async {
    return await CloudflareApiService.instance.fetchPermits();
  }

  Future<List<PermitModel>> fetchChangedSince(DateTime since) async {
    return await CloudflareApiService.instance.fetchPermits(since: since);
  }

  Future<PermitModel> insertPermit(Map<String, dynamic> payload) async {
    return await CloudflareApiService.instance.createPermit(payload);
  }

  Future<PermitModel> updatePermit(String id, Map<String, dynamic> payload) async {
    return await CloudflareApiService.instance.updatePermit(id, payload);
  }

  Future<void> softDeletePermit(
    String id, {
    required String updatedBy,
    required String updatedByName,
  }) async {
    await CloudflareApiService.instance.softDeletePermit(id);
  }

  Future<void> hardDeletePermit(String id) async {
    await CloudflareApiService.instance.hardDeletePermit(id);
  }

  Future<int> nextPermitNumber(int year) async {
    return await CloudflareApiService.instance.getNextPermitNumber(year);
  }

  // ===================== الوقت الحقيقي (Realtime) =====================

  RealtimeChannel? subscribeToPermits({
    required void Function(PostgresChangePayload payload) onInsert,
    required void Function(PostgresChangePayload payload) onUpdate,
    required void Function(PostgresChangePayload payload) onDelete,
  }) {
    return null;
  }

  // ===================== التخزين (مرفقات عبر Cloudflare R2) =====================

  Future<String> uploadAttachment({
    required String permitId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    return await CloudflareApiService.instance.uploadAttachment(
      permitId: permitId,
      fileName: fileName,
      bytes: bytes,
    );
  }

  // ===================== تراخيص النظام والأجهزة والإشعارات =====================

  Future<void> updateProfileLicensing(String userId, Map<String, dynamic> data) async {
    await CloudflareApiService.instance.updateProfile(userId, data);
  }

  Future<void> registerDevice({
    required String userId,
    required String deviceId,
    required String deviceName,
    required String osPlatform,
  }) async {
    await CloudflareApiService.instance.registerDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      osPlatform: osPlatform,
    );
  }

  Future<void> registerCurrentDevice({
    required String deviceId,
    required String deviceName,
    required String osPlatform,
  }) async {
    await CloudflareApiService.instance.registerDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      osPlatform: osPlatform,
    );
  }

  Future<List<Map<String, dynamic>>> fetchConnectedDevices() async {
    return await CloudflareApiService.instance.fetchDevices();
  }

  Future<List<Map<String, dynamic>>> fetchActivationCodes() async {
    return await CloudflareApiService.instance.fetchActivationCodes();
  }

  Future<void> createActivationCode({
    required String code,
    required int durationDays,
    String? associatedEmail,
  }) async {
    await CloudflareApiService.instance.generateActivationCode(
      code: code,
      durationDays: durationDays,
      associatedEmail: associatedEmail,
    );
  }

  Future<void> createSecureActivationCode({
    required String code,
    required int durationDays,
    String? associatedEmail,
  }) async {
    await CloudflareApiService.instance.generateActivationCode(
      code: code,
      durationDays: durationDays,
      associatedEmail: associatedEmail,
    );
  }

  Future<Map<String, dynamic>?> verifyAndUseActivationCode({
    required String code,
    required String userId,
    required String email,
  }) async {
    await CloudflareApiService.instance.activateCode(code);
    return {'code': code};
  }

  Future<void> consumeActivationCode({required String code}) async {
    await CloudflareApiService.instance.activateCode(code);
  }

  Future<void> approveLicense({required String userId}) async {
    await CloudflareApiService.instance.approveUser(userId);
  }

  Future<void> setLicensePaused({required String userId, required bool paused}) async {
    await CloudflareApiService.instance.pauseLicense(userId: userId, paused: paused);
  }

  Future<void> removeDevice(String deviceRowId) async {
    await CloudflareApiService.instance.removeDevice(deviceRowId);
  }

  Future<List<Map<String, dynamic>>> fetchNotifications(String userId) async {
    return await CloudflareApiService.instance.fetchNotifications();
  }

  Future<void> createNotification({
    required String userId,
    required String title,
    required String message,
  }) async {
    await CloudflareApiService.instance.sendNotification(
      userId: userId,
      title: title,
      message: message,
    );
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    await CloudflareApiService.instance.markNotificationAsRead(notificationId);
  }

  RealtimeChannel? subscribeToProfileChanges(
    String userId,
    void Function(PostgresChangePayload payload) onUpdate,
  ) {
    return null;
  }

  RealtimeChannel? subscribeToNotifications(
    String userId,
    void Function(PostgresChangePayload payload) onInsert,
  ) {
    return null;
  }
}
