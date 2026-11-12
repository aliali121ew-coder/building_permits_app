import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';
import '../models/permit_model.dart';
import '../models/pending_operation.dart';
import 'cloudflare_api_service.dart';
import 'connectivity_service.dart';
import 'hive_service.dart';

enum SyncStatus { idle, syncing, offline, error }

/// حدث تغيير وارد من مستخدم آخر (لعرض تنبيه "تم التعديل من قبل ...")
class RemoteChangeEvent {
  RemoteChangeEvent({required this.actorName, required this.action, required this.permitLabel});
  final String actorName;
  final String action; // insert / update / delete
  final String permitLabel;
}

/// خدمة المزامنة (Offline-First) مع خادم Cloudflare D1:
/// - الحفظ لحظي: أي إضافة/تعديل/حذف يُكتب محلياً ثم يُرسل فوراً للخادم
///   (أو يُوضع في طابور ويُرسل تلقائياً عند عودة الشبكة).
/// - جلب تغييرات الآخرين بسحب تفاضلي خفيف (`since`) كل [_pollInterval]،
///   ويتوقف السحب تماماً والتطبيق في الخلفية لتوفير قراءات D1.
class SyncService with WidgetsBindingObserver {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _pollInterval = Duration(seconds: 30);

  final _uuid = const Uuid();
  final HiveService _hive = HiveService.instance;
  final CloudflareApiService _api = CloudflareApiService.instance;

  final StreamController<SyncStatus> _statusController = StreamController<SyncStatus>.broadcast();
  final StreamController<RemoteChangeEvent> _remoteChangeController = StreamController<RemoteChangeEvent>.broadcast();
  final StreamController<void> _dataChangedController = StreamController<void>.broadcast();

  Stream<SyncStatus> get statusStream => _statusController.stream;
  Stream<RemoteChangeEvent> get remoteChangeStream => _remoteChangeController.stream;
  Stream<void> get dataChangedStream => _dataChangedController.stream;

  Timer? _pollingTimer;
  bool _started = false;
  bool _isSyncing = false;
  bool _inForeground = true;
  SyncStatus _status = SyncStatus.idle;

  void _setStatus(SyncStatus s) {
    if (s == _status) return; // لا إعادة بناء للواجهة إن لم تتغير الحالة
    _status = s;
    _statusController.add(s);
  }

  void _notifyData() => _dataChangedController.add(null);

  /// آمن للاستدعاء أكثر من مرة (يبدأ مرة واحدة فقط).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);

    ConnectivityService.instance.onlineStream.listen((online) {
      if (online) {
        _sync();
        _startPolling();
      } else {
        _stopPolling();
        _setStatus(SyncStatus.offline);
      }
    });

    if (ConnectivityService.instance.isOnline) {
      _startPolling();
      await _sync();
    } else {
      _setStatus(SyncStatus.offline);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _inForeground) return;
    _inForeground = fg;
    if (fg) {
      // عند العودة للتطبيق: سحب فوري لما فاتنا ثم استئناف الدورة
      if (ConnectivityService.instance.isOnline) {
        _sync();
        _startPolling();
      }
    } else {
      _stopPolling();
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    if (!_inForeground) return;
    _pollingTimer = Timer.periodic(_pollInterval, (_) {
      if (ConnectivityService.instance.isOnline) _sync();
    });
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  // ===================== القراءة (محلية دوماً - سريعة وتعمل بدون نت) =====================

  List<PermitModel> getAllPermits() => _hive.getAllPermits();

  // ===================== الكتابة (Offline-First + حفظ لحظي) =====================

  Future<PermitModel> addPermit(PermitModel permit) async {
    await _hive.upsertPermit(permit.copyWith(isSyncedLocally: false));
    _notifyData();
    await _enqueueOrSend(type: 'insert', permit: permit);
    return permit;
  }

  Future<PermitModel> updatePermitData(PermitModel permit) async {
    await _hive.upsertPermit(permit.copyWith(isSyncedLocally: false));
    _notifyData();
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
    _notifyData();
    await _enqueueOrSend(type: 'update', permit: updated);
  }

  Future<void> _enqueueOrSend({required String type, required PermitModel permit}) async {
    final op = PendingOperation(
      opId: _uuid.v4(),
      permitId: permit.id,
      type: type,
      payload: permit.toApiMap(),
      createdAt: DateTime.now().toUtc(),
    );

    if (!ConnectivityService.instance.isOnline) {
      await _hive.addPendingOp(op);
      _setStatus(SyncStatus.offline);
      return;
    }

    try {
      await _send(op);
      _setStatus(SyncStatus.idle);
    } catch (_) {
      // فشل مؤقت رغم وجود اتصال -> الطابور يعيد المحاولة في الدورة القادمة
      await _hive.addPendingOp(op);
      _setStatus(SyncStatus.error);
    }
  }

  /// إرسال عملية واحدة للخادم وحفظ النسخة المؤكدة محلياً
  Future<void> _send(PendingOperation op) async {
    final saved = op.type == 'insert'
        ? await _api.createPermit(op.payload)
        : await _api.updatePermit(op.permitId, op.payload);
    if (saved.isDeleted) {
      await _hive.deletePermitLocally(saved.id);
    } else {
      await _hive.upsertPermit(saved.copyWith(isSyncedLocally: true));
    }
    _notifyData();
  }

  // ===================== دورة المزامنة: تفريغ الطابور ثم سحب التغييرات =====================

  /// مزامنة فورية (السحب للتحديث): تجلب التغييرات فقط وليس كل البيانات.
  Future<void> syncNow() => _sync();

  Future<void> _sync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      for (final op in _hive.getPendingOps()) {
        try {
          await _send(op);
          await _hive.removePendingOp(op.opId);
        } catch (_) {
          await _hive.updatePendingOp(op.incrementRetry());
        }
      }

      final lastSync = _hive.getLastSyncAt();
      final firstSync = lastSync == null || _hive.permitsCount == 0;
      if (firstSync) _setStatus(SyncStatus.syncing);

      final changed = firstSync
          ? await _api.fetchPermits()
          : await _api.fetchPermits(since: lastSync);

      if (changed.isNotEmpty) {
        await _applyServerRows(changed);
        if (!firstSync) _announceRemoteChange(changed);
        _notifyData();
      }
      _setStatus(SyncStatus.idle);
    } catch (_) {
      _setStatus(SyncStatus.error);
    } finally {
      _isSyncing = false;
    }
  }

  /// حفظ صفوف الخادم محلياً، ونقل مؤشر المزامنة إلى أحدث `updated_at` من الخادم
  /// (ساعة الخادم وليس ساعة الجهاز، فلا تضيع تغييرات بسبب فرق التوقيت).
  Future<void> _applyServerRows(List<PermitModel> rows) async {
    final live = <PermitModel>[];
    var latest = _hive.getLastSyncAt();
    for (final p in rows) {
      if (latest == null || p.updatedAt.isAfter(latest)) latest = p.updatedAt;
      if (p.isDeleted) {
        await _hive.deletePermitLocally(p.id);
      } else {
        live.add(p.copyWith(isSyncedLocally: true));
      }
    }
    await _hive.upsertManyPermits(live);
    if (latest != null) await _hive.setLastSyncAt(latest.toUtc());
  }

  void _announceRemoteChange(List<PermitModel> rows) {
    final myId = _hive.getCachedUser()?['id']?.toString();
    final others = rows.where((p) => p.updatedBy != null && p.updatedBy != myId).toList();
    if (others.isEmpty) return;
    final p = others.last;
    _remoteChangeController.add(RemoteChangeEvent(
      actorName: p.updatedByName ?? 'مستخدم آخر',
      action: p.isDeleted ? 'delete' : (p.createdAt == p.updatedAt ? 'insert' : 'update'),
      permitLabel: others.length == 1
          ? '${p.fullName} (${p.permitYear}/${p.permitNumber})'
          : '${others.length} إجازات',
    ));
  }
}
