import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/permit_model.dart';
import '../models/pending_operation.dart';
import 'connectivity_service.dart';
import 'hive_service.dart';
import 'supabase_service.dart';

enum SyncStatus { idle, syncing, offline, error }

/// حدث تغيير وارد من مستخدم آخر (لعرض تنبيه "تم التعديل من قبل ...")
class RemoteChangeEvent {
  RemoteChangeEvent({required this.actorName, required this.action, required this.permitLabel});
  final String actorName;
  final String action; // insert / update / delete
  final String permitLabel;
}

/// خدمة المزامنة: Offline-First + Realtime
/// - أي إضافة/تعديل/حذف يُكتب فوراً محلياً في Hive (يعمل التطبيق بدون إنترنت)
/// - إن وُجد اتصال: يُرسل فوراً إلى Supabase ويُبث لباقي الأجهزة عبر Realtime
/// - إن انقطع الاتصال: تُحفظ العملية في طابور (pending_ops_box) وتُرسل فور عودة الشبكة تلقائياً
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final _uuid = const Uuid();
  final HiveService _hive = HiveService.instance;
  final SupabaseService _supa = SupabaseService.instance;

  final StreamController<SyncStatus> _statusController = StreamController<SyncStatus>.broadcast();
  final StreamController<RemoteChangeEvent> _remoteChangeController = StreamController<RemoteChangeEvent>.broadcast();
  final StreamController<void> _dataChangedController = StreamController<void>.broadcast();

  Stream<SyncStatus> get statusStream => _statusController.stream;
  Stream<RemoteChangeEvent> get remoteChangeStream => _remoteChangeController.stream;
  Stream<void> get dataChangedStream => _dataChangedController.stream; // لإعادة بناء الواجهة عند أي تغيير محلي/بعيد

  RealtimeChannel? _channel;
  StreamSubscription<bool>? _connSub;
  bool _isSyncing = false;

  Future<void> start() async {
    if (!SupabaseService.isConfigured) {
      _statusController.add(SyncStatus.offline);
      return;
    }

    _connSub = ConnectivityService.instance.onlineStream.listen((online) {
      if (online) {
        _flushPendingThenPull();
      } else {
        _statusController.add(SyncStatus.offline);
      }
    });

    if (ConnectivityService.instance.isOnline) {
      _subscribeRealtime();
      await _flushPendingThenPull();
    } else {
      _statusController.add(SyncStatus.offline);
    }
  }

  void dispose() {
    _connSub?.cancel();
    _channel?.unsubscribe();
    _statusController.close();
    _remoteChangeController.close();
    _dataChangedController.close();
  }

  // ===================== عمليات القراءة (تُقرأ محلياً دوماً - سريعة وتعمل بدون نت) =====================

  List<PermitModel> getAllPermits() => _hive.getAllPermits();
  List<PermitModel> getPermitsByYear(int year) => _hive.getPermitsByYear(year);
  List<int> getAvailableYears() => _hive.getAvailableYears();
  int suggestNextPermitNumber(int year) => _hive.nextPermitNumberForYear(year);

  // ===================== عمليات الكتابة (Offline-First) =====================

  Future<PermitModel> addPermit(PermitModel permit) async {
    await _hive.upsertPermit(permit.copyWith(isSyncedLocally: false));
    _dataChangedController.add(null);
    await _enqueueOrSend(type: 'insert', permit: permit);
    return permit;
  }

  Future<PermitModel> updatePermitData(PermitModel permit) async {
    await _hive.upsertPermit(permit.copyWith(isSyncedLocally: false));
    _dataChangedController.add(null);
    await _enqueueOrSend(type: 'update', permit: permit);
    return permit;
  }

  Future<void> softDeletePermit(PermitModel permit, {required String actorId, required String actorName}) async {
    final updated = permit.copyWith(
      isDeleted: true,
      updatedBy: actorId,
      updatedByName: actorName,
      isSyncedLocally: false,
    );
    await _hive.upsertPermit(updated);
    _dataChangedController.add(null);
    await _enqueueOrSend(type: 'update', permit: updated);
  }

  Future<void> _enqueueOrSend({required String type, required PermitModel permit}) async {
    final op = PendingOperation(
      opId: _uuid.v4(),
      permitId: permit.id,
      type: type,
      payload: permit.toSupabaseMap(),
      createdAt: DateTime.now().toUtc(),
    );

    if (!ConnectivityService.instance.isOnline) {
      await _hive.addPendingOp(op);
      _statusController.add(SyncStatus.offline);
      return;
    }

    try {
      _statusController.add(SyncStatus.syncing);
      if (type == 'insert') {
        final saved = await _supa.insertPermit(op.payload);
        await _hive.upsertPermit(saved.copyWith(isSyncedLocally: true));
      } else {
        final saved = await _supa.updatePermit(permit.id, op.payload);
        await _hive.upsertPermit(saved.copyWith(isSyncedLocally: true));
      }
      _dataChangedController.add(null);
      _statusController.add(SyncStatus.idle);
    } catch (_) {
      // فشل الإرسال رغم وجود اتصال (مثلاً خطأ خادم مؤقت) -> نضعها في الطابور لإعادة المحاولة
      await _hive.addPendingOp(op);
      _statusController.add(SyncStatus.error);
    }
  }

  // ===================== تفريغ الطابور المعلّق عند عودة الاتصال =====================

  Future<void> _flushPendingThenPull() async {
    if (_isSyncing) return;
    _isSyncing = true;
    _statusController.add(SyncStatus.syncing);
    try {
      final pending = _hive.getPendingOps();
      for (final op in pending) {
        try {
          if (op.type == 'insert') {
            final saved = await _supa.insertPermit(op.payload);
            await _hive.upsertPermit(saved.copyWith(isSyncedLocally: true));
          } else {
            final saved = await _supa.updatePermit(op.permitId, op.payload);
            await _hive.upsertPermit(saved.copyWith(isSyncedLocally: true));
          }
          await _hive.removePendingOp(op.opId);
        } catch (_) {
          await _hive.updatePendingOp(op.incrementRetry());
        }
      }

      final lastSync = _hive.getLastSyncAt();
      final localCount = _hive.getAllPermits().length;
      final List<PermitModel> changed;
      if (lastSync == null || localCount == 0) {
        changed = await _supa.fetchAllPermits();
      } else {
        changed = await _supa.fetchChangedSince(lastSync);
      }
      await _hive.upsertManyPermits(changed);
      await _hive.setLastSyncAt(DateTime.now().toUtc());

      _dataChangedController.add(null);
      _statusController.add(SyncStatus.idle);
      _subscribeRealtime();
    } catch (_) {
      _statusController.add(SyncStatus.error);
    } finally {
      _isSyncing = false;
    }
  }

  // ===================== الاستماع اللحظي (Realtime) =====================

  void _subscribeRealtime() {
    if (_channel != null) return;
    _channel = _supa.subscribeToPermits(
      onInsert: (payload) => _handleRemote('insert', payload.newRecord),
      onUpdate: (payload) => _handleRemote('update', payload.newRecord),
      onDelete: (payload) => _handleRemote('delete', payload.oldRecord),
    );
  }

  void _handleRemote(String action, Map<String, dynamic> record) {
    try {
      final permit = PermitModel.fromMap(record);
      if (action == 'delete') {
        _hive.deletePermitLocally(permit.id);
      } else {
        _hive.upsertPermit(permit.copyWith(isSyncedLocally: true));
      }
      _dataChangedController.add(null);

      final actor = permit.updatedByName ?? permit.createdByName ?? 'مستخدم آخر';
      _remoteChangeController.add(RemoteChangeEvent(
        actorName: actor,
        action: action,
        permitLabel: '${permit.fullName} (${permit.permitYear}/${permit.permitNumber})',
      ));
    } catch (_) {
      // تجاهل حمولة غير متوقعة بأمان
    }
  }

  Future<void> forceFullSync() async {
    _isSyncing = false;
    final changed = await _supa.fetchAllPermits();
    await _hive.upsertManyPermits(changed);
    await _hive.setLastSyncAt(DateTime.now().toUtc());
    _dataChangedController.add(null);
    _statusController.add(SyncStatus.idle);
  }

  /// تحديث كامل: يمسح النسخة المحلية بالكامل ثم يعيد تنزيل كل الإجازات من الخادم.
  /// يُستخدم لإزالة أي بيانات قديمة/مكررة تراكمت محلياً بعد استبدال بيانات الخادم.
  /// تنبيه: يتجاهل أي تعديلات محلية غير مُزامَنة (الخادم هو المصدر الموثوق).
  Future<void> fullRefreshFromServer() async {
    if (!SupabaseService.isConfigured) {
      throw Exception('يلزم الاتصال بالخادم لإجراء التحديث الكامل.');
    }
    _isSyncing = true;
    _statusController.add(SyncStatus.syncing);
    try {
      await _hive.clearAllPermitsData();
      _dataChangedController.add(null);
      final all = await _supa.fetchAllPermits();
      await _hive.upsertManyPermits(all);
      await _hive.setLastSyncAt(DateTime.now().toUtc());
      _dataChangedController.add(null);
      _statusController.add(SyncStatus.idle);
    } catch (e) {
      _statusController.add(SyncStatus.error);
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }
}
