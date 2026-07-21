import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants/app_constants.dart';
import '../models/permit_model.dart';
import '../models/pending_operation.dart';
import '../models/user_model.dart';

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

  Future<void> deletePermitLocally(String id) async {
    await _permitsBox.delete(id);
  }

  List<PermitModel> getPermitsByYear(int year) {
    return getAllPermits().where((p) => p.permitYear == year).toList()
      ..sort((a, b) => a.permitNumber.compareTo(b.permitNumber));
  }

  List<int> getAvailableYears() {
    final years = getAllPermits().map((p) => p.permitYear).toSet().toList();
    years.sort((a, b) => b.compareTo(a));
    return years;
  }

  int nextPermitNumberForYear(int year) {
    final permits = getPermitsByYear(year);
    if (permits.isEmpty) return 1;
    return permits.map((p) => p.permitNumber).reduce((a, b) => a > b ? a : b) + 1;
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

  String? getLocale() => _settingsBox.get(AppConstants.keyLocale) as String?;
  Future<void> setLocale(String locale) => _settingsBox.put(AppConstants.keyLocale, locale);

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

  Map? getCachedUser() => _userBox.get('current_user') as Map?;
  Future<void> setCachedUser(Map data) => _userBox.put('current_user', data);
  Future<void> clearCachedUser() => _userBox.delete('current_user');

  // ===================== حفظ بيانات تسجيل الدخول الأخيرة =====================
  Future<void> saveLastCredentials(String email, String password) async {
    await _settingsBox.put('last_login_email', email);
    await _secureStorage.write(key: 'last_login_password', value: password);
  }

  String getLastEmail() => _settingsBox.get('last_login_email', defaultValue: '') as String;
  
  Future<String> getLastPassword() async {
    return await _secureStorage.read(key: 'last_login_password') ?? '';
  }

  // ===================== حسابات الموظفين التجريبية (Demo Users) =====================

  List<UserModel> getDemoProfiles() {
    final raw = _settingsBox.get('demo_profiles') as List?;
    if (raw == null || raw.isEmpty) {
      final cached = getCachedUser();
      if (cached != null) {
        return [UserModel.fromMap(Map<String, dynamic>.from(cached))];
      }
      return [];
    }
    final list = raw.map((e) => UserModel.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    // تصفية وحذف الأسماء الوهمية المخزنة سابقاً في الكاش المحلي
    final filtered = list.where((u) => !u.id.startsWith('demo-emp')).toList();
    if (filtered.length != list.length) {
      saveDemoProfiles(filtered);
    }
    return filtered;
  }

  Future<void> saveDemoProfiles(List<UserModel> profiles) async {
    final list = profiles.map((p) => p.toMap()).toList();
    await _settingsBox.put('demo_profiles', list);
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
