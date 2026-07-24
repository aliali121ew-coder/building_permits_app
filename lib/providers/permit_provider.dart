import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/permit_model.dart';
import '../services/sync_service.dart';

class PermitProvider extends ChangeNotifier {
  final SyncService _sync = SyncService.instance;
  final _uuid = const Uuid();

  StreamSubscription? _dataSub;
  StreamSubscription<SyncStatus>? _statusSub;
  StreamSubscription<RemoteChangeEvent>? _remoteSub;

  List<PermitModel> _permits = [];
  List<PermitModel> get permits => _permits;

  SyncStatus _syncStatus = SyncStatus.idle;
  SyncStatus get syncStatus => _syncStatus;

  RemoteChangeEvent? lastRemoteChange;

  void init() {
    _refresh();
    _sync.start();
    _dataSub = _sync.dataChangedStream.listen((_) => _refresh());
    _statusSub = _sync.statusStream.listen((s) {
      _syncStatus = s;
      notifyListeners();
    });
    _remoteSub = _sync.remoteChangeStream.listen((event) {
      lastRemoteChange = event;
      notifyListeners();
    });
  }

  Map<int, int> _yearCounts = {};
  Map<int, List<PermitModel>> _byYearCache = {};
  List<int> _availableYearsCache = [];
  int _thisYearCount = 0;
  int _thisMonthCount = 0;

  void _refresh() {
    _permits = _sync.getAllPermits()..sort((a, b) {
      final byYear = b.permitYear.compareTo(a.permitYear);
      if (byYear != 0) return byYear;
      return b.permitNumber.compareTo(a.permitNumber);
    });

    final counts = <int, int>{};
    final byYearMap = <int, List<PermitModel>>{};
    final now = DateTime.now();
    int thisYear = 0;
    int thisMonth = 0;

    for (final p in _permits) {
      final yr = p.permitYear != 0 ? p.permitYear : p.permitDate.year;
      counts[yr] = (counts[yr] ?? 0) + 1;
      (byYearMap[yr] ??= []).add(p);

      if (yr == now.year) {
        thisYear++;
        if (p.permitDate.year == now.year && p.permitDate.month == now.month) {
          thisMonth++;
        }
      }
    }

    _yearCounts = counts;
    _byYearCache = byYearMap;
    _availableYearsCache = counts.keys.toList()..sort((a, b) => b.compareTo(a));
    _thisYearCount = thisYear;
    _thisMonthCount = thisMonth;

    notifyListeners();
  }

  List<int> get availableYears {
    if (_availableYearsCache.isNotEmpty) return _availableYearsCache;
    final yearsFromSync = _sync.getAvailableYears();
    if (yearsFromSync.isNotEmpty) return yearsFromSync;
    final now = DateTime.now().year;
    return [now, now - 1, now - 2, now - 3, now - 4, now - 5];
  }

  List<PermitModel> byYear(int year) => _byYearCache[year] ?? const [];

  int getYearCount(int year) => _yearCounts[year] ?? 0;

  int suggestNextNumber(int year) => _sync.suggestNextPermitNumber(year);

  int get totalCount => _permits.length;

  int get thisYearCount => _thisYearCount;

  int get thisMonthCount => _thisMonthCount;

  List<PermitModel> search({
    String? query,
    int? year,
    String? permitType,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    final hasQuery = query != null && query.trim().isNotEmpty;
    final hasType = permitType != null && permitType.isNotEmpty;
    final hasFrom = fromDate != null;
    final hasTo = toDate != null;

    // Fast O(1) lookup if only year filter is active
    if (!hasQuery && !hasType && !hasFrom && !hasTo) {
      if (year != null) return byYear(year);
      return _permits;
    }

    var results = year != null ? byYear(year) : _permits;

    if (hasQuery) {
      final q = query.trim().toLowerCase();
      results = results.where((p) {
        return p.fullName.toLowerCase().contains(q) ||
            p.plotNumber.toLowerCase().contains(q) ||
            p.permitNumber.toString().contains(q) ||
            p.notes.toLowerCase().contains(q) ||
            p.namePerNewRegistry.toLowerCase().contains(q) ||
            p.nameChangeNotes.toLowerCase().contains(q);
      }).toList();
    }

    if (hasType) {
      results = results.where((p) => p.permitType == permitType).toList();
    }
    if (fromDate != null) {
      results = results.where((p) => !p.permitDate.isBefore(fromDate)).toList();
    }
    if (toDate != null) {
      results = results.where((p) => !p.permitDate.isAfter(toDate)).toList();
    }

    return results;
  }

  Future<PermitModel> addPermit({
    required String fullName,
    required String plotNumber,
    required int permitYear,
    int? permitNumber,
    required DateTime permitDate,
    String notes = '',
    String permitType = '',
    String nameChangeNotes = '',
    double? plotArea,
    double? buildingArea,
    String namePerNewRegistry = '',
    List<String> attachmentUrls = const [],
    required String actorId,
    required String actorName,
  }) async {
    final now = DateTime.now().toUtc();
    final permit = PermitModel(
      id: _uuid.v4(),
      permitNumber: permitNumber ?? suggestNextNumber(permitYear),
      permitYear: permitYear,
      fullName: fullName,
      plotNumber: plotNumber,
      permitDate: permitDate,
      notes: notes,
      permitType: permitType,
      nameChangeNotes: nameChangeNotes,
      plotArea: plotArea,
      buildingArea: buildingArea,
      namePerNewRegistry: namePerNewRegistry,
      attachmentUrls: attachmentUrls,
      createdBy: actorId,
      createdByName: actorName,
      createdAt: now,
      updatedBy: actorId,
      updatedByName: actorName,
      updatedAt: now,
    );
    final saved = await _sync.addPermit(permit);
    _refresh();
    return saved;
  }

  Future<void> updatePermit(PermitModel existing, {
    String? fullName,
    String? plotNumber,
    int? permitYear,
    int? permitNumber,
    DateTime? permitDate,
    String? notes,
    String? permitType,
    String? nameChangeNotes,
    double? plotArea,
    double? buildingArea,
    String? namePerNewRegistry,
    List<String>? attachmentUrls,
    required String actorId,
    required String actorName,
  }) async {
    final updated = existing.copyWith(
      fullName: fullName,
      plotNumber: plotNumber,
      permitYear: permitYear,
      permitNumber: permitNumber,
      permitDate: permitDate,
      notes: notes,
      permitType: permitType,
      nameChangeNotes: nameChangeNotes,
      plotArea: plotArea,
      buildingArea: buildingArea,
      namePerNewRegistry: namePerNewRegistry,
      attachmentUrls: attachmentUrls,
      updatedBy: actorId,
      updatedByName: actorName,
      updatedAt: DateTime.now().toUtc(),
    );
    await _sync.updatePermitData(updated);
    _refresh();
  }

  Future<void> deletePermit(PermitModel permit, {required String actorId, required String actorName}) async {
    await _sync.softDeletePermit(permit, actorId: actorId, actorName: actorName);
    _refresh();
  }

  Future<void> forceSync() => _sync.forceFullSync();

  /// تحديث كامل: مسح النسخة المحلية وإعادة السحب من الخادم، ثم إعادة بناء القوائم.
  Future<void> fullRefresh() async {
    await _sync.fullRefreshFromServer();
    _refresh();
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _statusSub?.cancel();
    _remoteSub?.cancel();
    super.dispose();
  }
}
