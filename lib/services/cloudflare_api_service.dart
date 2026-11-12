import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../core/constants/app_constants.dart';
import '../models/permit_model.dart';
import '../models/user_model.dart';
import 'hive_service.dart';

/// خدمة الاتصال المباشر بخادم Cloudflare Edge (Workers + D1 + R2)
class CloudflareApiService {
  CloudflareApiService._() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.backendApiUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = HiveService.instance.getAuthToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ));
  }

  static final CloudflareApiService instance = CloudflareApiService._();
  late final Dio _dio;

  // ===================== المصادقة (Auth) =====================

  Future<UserModel> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final res = await _dio.post('/api/auth/register', data: {
      'email': email.trim().toLowerCase(),
      'password': password,
      'full_name': fullName.trim(),
    });

    final token = res.data['token'] as String;
    await HiveService.instance.setAuthToken(token);
    return UserModel.fromMap(Map<String, dynamic>.from(res.data['user']));
  }

  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final res = await _dio.post('/api/auth/login', data: {
      'email': email.trim().toLowerCase(),
      'password': password,
    });

    final token = res.data['token'] as String;
    await HiveService.instance.setAuthToken(token);
    return UserModel.fromMap(Map<String, dynamic>.from(res.data['user']));
  }

  Future<UserModel?> getMe() async {
    try {
      final res = await _dio.get('/api/auth/me');
      return UserModel.fromMap(Map<String, dynamic>.from(res.data));
    } catch (_) {
      return null;
    }
  }

  Future<void> changePassword({
    String? oldPassword,
    required String newPassword,
  }) async {
    await _dio.post('/api/auth/change-password', data: {
      'old_password': oldPassword ?? '',
      'new_password': newPassword,
    });
  }

  // ===================== الإجازات (Permits) =====================

  Future<List<PermitModel>> fetchPermits({
    int? year,
    String? search,
    DateTime? since,
  }) async {
    final queryParams = <String, dynamic>{};
    if (year != null) queryParams['year'] = year;
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (since != null) queryParams['since'] = since.toIso8601String();

    final res = await _dio.get('/api/permits', queryParameters: queryParams);
    final list = res.data as List;
    return list.map((e) => PermitModel.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  Future<PermitModel?> fetchPermitById(String id) async {
    try {
      final res = await _dio.get('/api/permits/$id');
      return PermitModel.fromMap(Map<String, dynamic>.from(res.data));
    } catch (_) {
      return null;
    }
  }

  Future<int> getNextPermitNumber(int year) async {
    try {
      final res = await _dio.get('/api/permits/next-number/$year');
      return (res.data['next_number'] as num?)?.toInt() ?? 1;
    } catch (_) {
      return 1;
    }
  }

  Future<PermitModel> createPermit(Map<String, dynamic> data) async {
    final res = await _dio.post('/api/permits', data: data);
    return PermitModel.fromMap(Map<String, dynamic>.from(res.data));
  }

  Future<PermitModel> updatePermit(String id, Map<String, dynamic> data) async {
    final res = await _dio.put('/api/permits/$id', data: data);
    return PermitModel.fromMap(Map<String, dynamic>.from(res.data));
  }

  Future<void> softDeletePermit(String id) async {
    await _dio.delete('/api/permits/$id');
  }

  Future<void> hardDeletePermit(String id) async {
    await _dio.delete('/api/permits/$id/hard');
  }

  // ===================== المرفقات (R2 Storage) =====================

  Future<String> uploadAttachment({
    required String permitId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final formData = FormData.fromMap({
      'permit_id': permitId,
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });

    final res = await _dio.post('/api/storage/upload', data: formData);
    final url = res.data['url']?.toString() ?? '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '${AppConstants.backendApiUrl}$url';
  }

  // ===================== التراخيص والأجهزة (Licensing & Admin) =====================

  Future<void> activateCode(String code) async {
    await _dio.post('/api/licensing/activate', data: {'code': code});
  }

  Future<void> registerDevice({
    required String deviceId,
    required String deviceName,
    required String osPlatform,
  }) async {
    await _dio.post('/api/licensing/register-device', data: {
      'device_id': deviceId,
      'device_name': deviceName,
      'os_platform': osPlatform,
    });
  }

  Future<void> updateProfile(String id, Map<String, dynamic> data) async {
    await _dio.put('/api/licensing/profile/$id', data: data);
  }

  Future<List<UserModel>> fetchAllProfiles() async {
    try {
      final res = await _dio.get('/api/licensing/admin/users');
      final list = res.data as List;
      return list.map((e) => UserModel.fromMap(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return HiveService.instance.getDemoProfiles();
    }
  }

  Future<List<Map<String, dynamic>>> fetchDevices() async {
    try {
      final res = await _dio.get('/api/licensing/admin/devices');
      return (res.data as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> removeDevice(String id) async {
    await _dio.delete('/api/licensing/admin/devices/$id');
  }

  Future<List<Map<String, dynamic>>> fetchActivationCodes() async {
    try {
      final res = await _dio.get('/api/licensing/admin/codes');
      return (res.data as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> generateActivationCode({
    required String code,
    required int durationDays,
    String? associatedEmail,
  }) async {
    await _dio.post('/api/licensing/admin/generate-code', data: {
      'code': code,
      'duration_days': durationDays,
      'associated_email': associatedEmail,
    });
  }

  Future<void> approveUser(String userId) async {
    await _dio.post('/api/licensing/admin/approve-user', data: {'user_id': userId});
  }

  Future<void> pauseLicense({required String userId, required bool paused}) async {
    await _dio.post('/api/licensing/admin/pause-license', data: {
      'user_id': userId,
      'paused': paused,
    });
  }

  // ===================== الإشعارات (Notifications) =====================

  Future<List<Map<String, dynamic>>> fetchNotifications() async {
    try {
      final res = await _dio.get('/api/notifications');
      return (res.data as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> markNotificationAsRead(String id) async {
    await _dio.post('/api/notifications/$id/read');
  }

  Future<void> sendNotification({
    required String userId,
    required String title,
    required String message,
  }) async {
    await _dio.post('/api/notifications', data: {
      'user_id': userId,
      'title': title,
      'message': message,
    });
  }

  // ===================== التحديثات (App Updates) =====================

  Future<Map<String, dynamic>?> checkUpdate(String platform) async {
    try {
      final res = await _dio.get('/api/updates/check/$platform');
      return Map<String, dynamic>.from(res.data);
    } catch (_) {
      return null;
    }
  }

  Future<void> setUpdateInfo(Map<String, dynamic> data) async {
    await _dio.post('/api/updates/set', data: data);
  }
}

