import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../models/permit_model.dart';
import '../models/pending_operation.dart';

/// طبقة التخزين المحلي - كل قراءة/كتابة في التطبيق تمر أولاً من هنا (Offline-First)
/// لا نستخدم build_runner/Hive TypeAdapters المولّدة تلقائياً؛ نخزّن كخرائط (Map)
/// لتفادي الاعتماد على أدوات توليد الكود وتبسيط الصيانة.
class HiveService {
  HiveService._();
  static final HiveService instance = HiveService._();

  late Box _permitsBox;
  late Box _pendingOpsBox;
  late Box _settingsBox;
  late Box _userBox;
  final _secureStorage = const FlutterSecureStorage();

  Future<void> init() async {
    await Hive.initFlutter();
    _permitsBox = await Hive.openBox(AppConstants.hivePermitsBox);
    _pendingOpsBox = await Hive.openBox(AppConstants.hivePendingOpsBox);
    _settingsBox = await Hive.openBox(AppConstants.hiveSettingsBox);
    _userBox = await Hive.openBox(AppConstants.hiveUserBox);
  }

  // ===================== الإجازات =====================

  List<PermitModel> getAllPermits() {
    return _permitsBox.values
        .map((e) => PermitModel.fromHiveMap(Map.from(e as Map)))
        .where((p) => !p.isDeleted)
        .toList();
  }

  PermitModel? getPermit(String id) {
    final raw = _permitsBox.get(id);
    if (raw == null) return null;
    return PermitModel.fromHiveMap(Map.from(raw as Map));
  }

  Future<void> upsertPermit(PermitModel permit) async {
    await _permitsBox.put(permit.id, permit.toHiveMap());
  }

  Future<void> upsertManyPermits(List<PermitModel> permits) async {
    if (permits.isEmpty) return;
    const chunkSize = 400;
    for (var i = 0; i < permits.length; i += chunkSize) {
      final end = (i + chunkSize < permits.length) ? i + chunkSize : permits.length;
      final chunk = permits.sublist(i, end);
      final map = {for (final p in chunk) p.id: p.toHiveMap()};
      await _permitsBox.putAll(map);
      // منح إطار العمل فرصة لمعالجة رسائل النظام والنوافذ بدون تجميد 60 FPS
      await Future.delayed(Duration.zero);
    }
  }

  int get permitsCount => _permitsBox.length;

  Future<void> deletePermitLocally(String id) async {
    await _permitsBox.delete(id);
  }

  // ===================== طابور المزامنة =====================

  List<PendingOperation> getPendingOps() {
    return _pendingOpsBox.values.map((e) => PendingOperation.fromMap(e as Map)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> addPendingOp(PendingOperation op) async {
    await _pendingOpsBox.put(op.opId, op.toMap());
  }

  Future<void> removePendingOp(String opId) async {
    await _pendingOpsBox.delete(opId);
  }

  Future<void> updatePendingOp(PendingOperation op) async {
    await _pendingOpsBox.put(op.opId, op.toMap());
  }

  int get pendingOpsCount => _pendingOpsBox.length;

  // ===================== الإعدادات =====================

  String? getThemeMode() => _settingsBox.get(AppConstants.keyThemeMode) as String?;
  Future<void> setThemeMode(String mode) => _settingsBox.put(AppConstants.keyThemeMode, mode);


  DateTime? getLastSyncAt() {
    final raw = _settingsBox.get(AppConstants.keyLastSyncAt) as String?;
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  Future<void> setLastSyncAt(DateTime dt) => _settingsBox.put(AppConstants.keyLastSyncAt, dt.toIso8601String());

  // ===================== سجل عمليات البحث =====================

  List<SearchLog> getSearchHistory() {
    final raw = _settingsBox.get('search_history_logs_v2') as List?;
    if (raw == null) {
      // محاولة استرجاع السجلات القديمة وترقيتها
      final oldRaw = _settingsBox.get('search_history_logs') as List?;
      if (oldRaw != null) {
        final list = oldRaw.map((e) => SearchLog(query: e.toString(), timestamp: DateTime.now())).toList();
        saveSearchHistory(list);
        return list;
      }
      return [];
    }
    return raw.map((e) => SearchLog.fromMap(Map.from(e as Map))).toList();
  }

  Future<void> saveSearchHistory(List<SearchLog> logs) async {
    final list = logs.map((e) => e.toMap()).toList();
    await _settingsBox.put('search_history_logs_v2', list);
  }

  Future<void> saveSearchQuery(String query) async {
    final clean = query.trim();
    if (clean.length < 2) return;
    
    final current = getSearchHistory();
    current.removeWhere((element) => element.query.toLowerCase() == clean.toLowerCase());
    current.insert(0, SearchLog(query: clean, timestamp: DateTime.now()));
    
    if (current.length > 50) current.removeLast();
    await saveSearchHistory(current);
  }

  Future<void> clearSearchHistory() async {
    await _settingsBox.delete('search_history_logs_v2');
    await _settingsBox.delete('search_history_logs');
  }

  // ===================== جلسة المستخدم (كاش محلي) =====================

  /// معرّف ثابت لهذا المتصفح (لتسجيل الجهاز ضمن حد الترخيص)
  String webDeviceId() {
    var id = _settingsBox.get('web_device_id') as String?;
    if (id == null) {
      id = 'web-${const Uuid().v4()}';
      _settingsBox.put('web_device_id', id);
    }
    return id;
  }

  String? getAuthToken() => _settingsBox.get('auth_jwt_token') as String?;
  Future<void> setAuthToken(String token) => _settingsBox.put('auth_jwt_token', token);
  Future<void> clearAuthToken() => _settingsBox.delete('auth_jwt_token');

  Map? getCachedUser() => _userBox.get('current_user') as Map?;
  Future<void> setCachedUser(Map data) => _userBox.put('current_user', data);
  Future<void> clearCachedUser() async {
    await clearAuthToken();
    await _userBox.delete('current_user');
  }

  // ===================== حفظ بيانات تسجيل الدخول الأخيرة =====================
  Future<void> saveLastCredentials(String email, String password) async {
    await _settingsBox.put('last_login_email', email);
    await _secureStorage.write(key: 'last_login_password', value: password);
  }

  String getLastEmail() => _settingsBox.get('last_login_email', defaultValue: '') as String;
  
  Future<String> getLastPassword() async {
    try {
      return await _secureStorage.read(key: 'last_login_password') ?? '';
    } catch (_) {
      return '';
    }
  }
}

class SearchLog {
  final String query;
  final DateTime timestamp;

  SearchLog({required this.query, required this.timestamp});

  factory SearchLog.fromMap(Map map) {
    return SearchLog(
      query: map['query'] as String? ?? '',
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'query': query,
        'timestamp': timestamp.toIso8601String(),
      };
}
