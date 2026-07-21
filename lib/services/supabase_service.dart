import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/app_constants.dart';
import '../models/permit_model.dart';
import '../models/user_model.dart';
import 'hive_service.dart';

/// طبقة الاتصال بـ Supabase (Backend الكامل: DB + Auth + Realtime + Storage)
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  static bool get isConfigured =>
      !AppConstants.supabaseUrl.contains('YOUR_PROJECT_REF') &&
      AppConstants.supabaseUrl.isNotEmpty &&
      AppConstants.supabaseAnonKey != 'YOUR_SUPABASE_ANON_KEY';

  SupabaseClient? get client {
    if (!isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static Future<void> initialize() async {
    if (!isConfigured) return;
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      publishableKey: AppConstants.supabaseAnonKey,
      realtimeClientOptions: const RealtimeClientOptions(
        eventsPerSecond: 20,
      ),
    );
  }

  // ===================== المصادقة =====================

  Session? get currentSession {
    if (!isConfigured || client == null) return null;
    try {
      return client!.auth.currentSession;
    } catch (_) {
      return null;
    }
  }

  User? get currentAuthUser {
    if (!isConfigured || client == null) return null;
    try {
      return client!.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  Stream<AuthState>? get authStateChanges => client?.auth.onAuthStateChange;

  Future<AuthResponse> signIn(
      {required String email, required String password}) {
    if (!isConfigured || client == null) {
      throw Exception('Supabase غير مهيأ بعد.');
    }
    return client!.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    if (!isConfigured || client == null) {
      throw Exception('Supabase غير مهيأ بعد.');
    }
    final res = await client!.auth.signUp(email: email, password: password);
    if (res.user != null) {
      final profile = UserModel(
        id: res.user!.id,
        fullName: fullName,
        role: AppConstants.roleEmployee,
        isActive:
            true, // We allow them to log in to see the approval/activation screen
        canAdd: true,
        canEdit: true,
        canDelete: false,
        canView: true,
        email: email,
        approvalStatus: 'pending', // Default status is pending admin approval
      );
      await createProfile(profile);
    }
    return res;
  }

  Future<void> signOut() async {
    if (!isConfigured || client == null) return;
    await client!.auth.signOut();
  }

  Future<void> updatePassword(String newPassword) async {
    if (!isConfigured || client == null) {
      throw Exception('Supabase غير مهيأ بعد.');
    }
    await client!.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<UserModel?> fetchCurrentProfile() async {
    if (!isConfigured || client == null) return null;
    final uid = currentAuthUser?.id;
    if (uid == null) return null;
    final data =
        await client!.from('profiles').select().eq('id', uid).maybeSingle();
    if (data == null) return null;
    return UserModel.fromMap(data, email: currentAuthUser?.email);
  }

  Future<List<UserModel>> fetchAllProfiles() async {
    if (!isConfigured || client == null || client!.auth.currentUser == null) {
      return HiveService.instance.getDemoProfiles();
    }
    try {
      final data = await client!.from('profiles').select().order('full_name');
      return (data as List)
          .map((e) => UserModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return HiveService.instance.getDemoProfiles();
    }
  }

  Future<void> createProfile(UserModel profile) async {
    if (!isConfigured || client == null) return;
    await client!.from('profiles').insert(profile.toSupabaseMap());
  }

  Future<void> updateProfileRole(
      {required String userId,
      required String role,
      required bool isActive}) async {
    if (!isConfigured || client == null) return;
    await client!
        .from('profiles')
        .update({'role': role, 'is_active': isActive}).eq('id', userId);
  }

  Future<void> updateProfileName(
      {required String userId, required String fullName}) async {
    if (!isConfigured || client == null) return;
    await client!
        .from('profiles')
        .update({'full_name': fullName}).eq('id', userId);
  }

  Future<void> updateProfilePermissions(UserModel user) async {
    if (!isConfigured || client == null || client!.auth.currentUser == null) {
      final profiles = await fetchAllProfiles();
      final index = profiles.indexWhere((p) => p.id == user.id);
      if (index != -1) {
        profiles[index] = user;
        await HiveService.instance.saveDemoProfiles(profiles);
      }
      return;
    }
    try {
      await client!
          .from('profiles')
          .update(user.toSupabaseMap())
          .eq('id', user.id);
    } catch (_) {
      final profiles = await fetchAllProfiles();
      final index = profiles.indexWhere((p) => p.id == user.id);
      if (index != -1) {
        profiles[index] = user;
        await HiveService.instance.saveDemoProfiles(profiles);
      }
    }
  }

  // ===================== الإجازات (CRUD) =====================

  Future<List<PermitModel>> fetchAllPermits() async {
    if (!isConfigured || client == null) return [];
    List<PermitModel> allPermits = [];
    int from = 0;
    const step = 1000;

    while (true) {
      final data = await client!
          .from('permits')
          .select()
          .or('is_deleted.eq.false,is_deleted.is.null')
          .order('permit_year', ascending: false)
          .order('permit_number')
          .range(from, from + step - 1);

      final list = (data as List)
          .map((e) => PermitModel.fromMap(e as Map<String, dynamic>))
          .toList();
      allPermits.addAll(list);
      if (list.length < step) break;
      from += step;
    }
    return allPermits;
  }

  /// جلب كل ما تغيّر منذ آخر مزامنة (تفاضلي - أخف بكثير من سحب كل شيء كل مرة)
  Future<List<PermitModel>> fetchChangedSince(DateTime since) async {
    if (!isConfigured || client == null) return [];
    final data = await client!
        .from('permits')
        .select()
        .gt('updated_at', since.toIso8601String());
    return (data as List)
        .map((e) => PermitModel.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<PermitModel> insertPermit(Map<String, dynamic> payload) async {
    if (!isConfigured || client == null) return PermitModel.fromMap(payload);
    final data =
        await client!.from('permits').insert(payload).select().single();
    return PermitModel.fromMap(data);
  }

  Future<PermitModel> updatePermit(
      String id, Map<String, dynamic> payload) async {
    if (!isConfigured || client == null) return PermitModel.fromMap(payload);
    final data = await client!
        .from('permits')
        .update(payload)
        .eq('id', id)
        .select()
        .single();
    return PermitModel.fromMap(data);
  }

  /// حذف منطقي (Soft Delete) - كل الموظفين يقدرون عليه
  Future<void> softDeletePermit(String id,
      {required String updatedBy, required String updatedByName}) async {
    if (!isConfigured || client == null) return;
    await client!.from('permits').update({
      'is_deleted': true,
      'updated_by': updatedBy,
    }).eq('id', id);
  }

  /// حذف فعلي نهائي - الأدمن فقط (مطبّق أيضاً عبر RLS في قاعدة البيانات)
  Future<void> hardDeletePermit(String id) async {
    if (!isConfigured || client == null) return;
    await client!.from('permits').delete().eq('id', id);
  }

  Future<int> nextPermitNumber(int year) async {
    if (!isConfigured || client == null) return 1;
    final result =
        await client!.rpc('next_permit_number', params: {'p_year': year});
    return result as int;
  }

  // ===================== الوقت الحقيقي (Realtime) =====================

  RealtimeChannel? subscribeToPermits({
    required void Function(PostgresChangePayload payload) onInsert,
    required void Function(PostgresChangePayload payload) onUpdate,
    required void Function(PostgresChangePayload payload) onDelete,
  }) {
    if (!isConfigured || client == null) return null;
    final channel = client!.channel('public:permits');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'permits',
          callback: onInsert,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'permits',
          callback: onUpdate,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'permits',
          callback: onDelete,
        )
        .subscribe();
    return channel;
  }

  // ===================== التخزين (مرفقات) =====================

  Future<String> uploadAttachment({
    required String permitId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (!isConfigured || client == null) return '';
    final path = '$permitId/$fileName';
    await client!.storage.from(AppConstants.attachmentsBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return client!.storage
        .from(AppConstants.attachmentsBucket)
        .createSignedUrl(path, 60 * 60 * 24 * 7);
  }

  // ===================== تراخيص النظام والأجهزة والإشعارات =====================

  Future<void> updateProfileLicensing(
      String userId, Map<String, dynamic> data) async {
    if (!isConfigured || client == null) return;
    await client!.from('profiles').update(data).eq('id', userId);
  }

  Future<void> registerDevice({
    required String userId,
    required String deviceId,
    required String deviceName,
    required String osPlatform,
  }) async {
    if (!isConfigured || client == null) return;
    await client!.from('user_devices').upsert({
      'user_id': userId,
      'device_id': deviceId,
      'device_name': deviceName,
      'os_platform': osPlatform,
      'last_active': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> fetchConnectedDevices() async {
    if (!isConfigured || client == null) return [];
    try {
      final res =
          await client!.from('user_devices').select('*, profiles(full_name)');
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchActivationCodes() async {
    if (!isConfigured || client == null) return [];
    try {
      final res = await client!
          .from('activation_codes')
          .select()
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return [];
    }
  }

  Future<void> createActivationCode({
    required String code,
    required int durationDays,
    String? associatedEmail,
  }) async {
    if (!isConfigured || client == null) return;
    await client!.from('activation_codes').insert({
      'code': code,
      'duration_days': durationDays,
      'associated_email': associatedEmail,
    });
  }

  Future<Map<String, dynamic>?> verifyAndUseActivationCode({
    required String code,
    required String userId,
    required String email,
  }) async {
    if (!isConfigured || client == null) return null;

    // 1. التحقق من وجود الكود
    final res = await client!
        .from('activation_codes')
        .select()
        .eq('code', code)
        .maybeSingle();
    if (res == null) {
      throw Exception('رمز التفعيل غير صحيح.');
    }

    final map = Map<String, dynamic>.from(res);
    if (map['is_used'] == true) {
      throw Exception('رمز التفعيل مستخدم مسبقاً.');
    }

    final associatedEmail = map['associated_email'] as String?;
    if (associatedEmail != null &&
        associatedEmail.trim().isNotEmpty &&
        associatedEmail.trim().toLowerCase() != email.trim().toLowerCase()) {
      throw Exception('رمز التفعيل هذا مخصص لبريد إلكتروني آخر.');
    }

    // 2. تحديث الكود كـ مستخدم
    await client!.from('activation_codes').update({
      'is_used': true,
      'used_by_user_id': userId,
      'used_at': DateTime.now().toIso8601String(),
    }).eq('code', code);

    return map;
  }

  /// Server-side, transactional activation. The SQL migration defines this RPC.
  Future<void> consumeActivationCode({required String code}) async {
    if (!isConfigured || client == null) {
      throw Exception('لا يمكن التفعيل دون الاتصال بالخادم.');
    }
    await client!.rpc('consume_activation_code', params: {'p_code': code});
  }

  Future<dynamic> _licensingRpc(
      String name, Map<String, dynamic> params) async {
    if (!isConfigured || client == null) {
      throw Exception('يلزم الاتصال بالخادم لإدارة التراخيص.');
    }
    return client!.rpc(name, params: params);
  }

  Future<void> registerCurrentDevice({
    required String deviceId,
    required String deviceName,
    required String osPlatform,
  }) =>
      _licensingRpc('register_current_device', {
        'p_device_id': deviceId,
        'p_device_name': deviceName,
        'p_os_platform': osPlatform,
      });

  Future<void> approveLicense({required String userId}) =>
      _licensingRpc('admin_approve_account', {'p_user_id': userId});

  Future<void> setLicensePaused(
          {required String userId, required bool paused}) =>
      _licensingRpc('admin_set_license_paused',
          {'p_user_id': userId, 'p_paused': paused});

  Future<void> removeDevice(String deviceRowId) =>
      _licensingRpc('admin_remove_device', {'p_device_row_id': deviceRowId});

  Future<void> createSecureActivationCode({
    required String code,
    required int durationDays,
    String? associatedEmail,
  }) =>
      _licensingRpc('admin_create_activation_code', {
        'p_code': code,
        'p_duration_days': durationDays,
        'p_associated_email': associatedEmail,
      });

  Future<List<Map<String, dynamic>>> fetchNotifications(String userId) async {
    if (!isConfigured || client == null) return [];
    try {
      final res = await client!
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return [];
    }
  }

  Future<void> createNotification({
    required String userId,
    required String title,
    required String message,
  }) async {
    if (!isConfigured || client == null) return;
    await client!.from('notifications').insert({
      'user_id': userId,
      'title': title,
      'message': message,
    });
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    if (!isConfigured || client == null) return;
    await client!
        .from('notifications')
        .update({'is_read': true}).eq('id', notificationId);
  }

  RealtimeChannel? subscribeToProfileChanges(
      String userId, void Function(PostgresChangePayload payload) onUpdate) {
    if (!isConfigured || client == null) return null;
    final channel = client!.channel('public:profiles_user_$userId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: onUpdate,
        )
        .subscribe();
    return channel;
  }

  RealtimeChannel? subscribeToNotifications(
      String userId, void Function(PostgresChangePayload payload) onInsert) {
    if (!isConfigured || client == null) return null;
    final channel = client!.channel('public:notifications_user_$userId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: onInsert,
        )
        .subscribe();
    return channel;
  }
}
