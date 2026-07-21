import 'package:equatable/equatable.dart';

/// نموذج إجازة البناء - يطابق أعمدة جدول public.permits في Supabase
/// + حقول مزامنة محلية إضافية (لا تُرسل إلى الخادم)
class PermitModel extends Equatable {
  const PermitModel({
    required this.id,
    required this.permitNumber,
    required this.permitYear,
    required this.fullName,
    required this.plotNumber,
    required this.permitDate,
    this.notes = '',
    this.permitType = '',
    this.nameChangeNotes = '',
    this.plotArea,
    this.buildingArea,
    this.namePerNewRegistry = '',
    this.attachmentUrls = const [],
    this.isDeleted = false,
    this.createdBy,
    this.createdByName,
    required this.createdAt,
    this.updatedBy,
    this.updatedByName,
    required this.updatedAt,
    // ---- حقول محلية فقط (لا تُخزّن في Supabase) ----
    this.isSyncedLocally = true,
    this.isPendingDelete = false,
  });

  final String id; // uuid
  final int permitNumber;
  final int permitYear;
  final String fullName;
  final String plotNumber;
  final DateTime permitDate;
  final String notes;
  final String permitType;
  final String nameChangeNotes;
  final double? plotArea;
  final double? buildingArea;
  final String namePerNewRegistry;
  final List<String> attachmentUrls;
  final bool isDeleted;
  final String? createdBy;
  final String? createdByName;
  final DateTime createdAt;
  final String? updatedBy;
  final String? updatedByName;
  final DateTime updatedAt;

  final bool isSyncedLocally;
  final bool isPendingDelete;

  factory PermitModel.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is DateTime) return val;
      final str = val.toString().trim();
      if (str.isEmpty) return DateTime.now();
      return DateTime.tryParse(str) ?? DateTime.now();
    }

    final pDate = parseDate(map['permit_date']);
    final pYear = (map['permit_year'] as num?)?.toInt() ?? pDate.year;

    return PermitModel(
      id: map['id']?.toString() ?? '',
      permitNumber: (map['permit_number'] as num?)?.toInt() ?? 0,
      permitYear: pYear != 0 ? pYear : pDate.year,
      fullName: map['full_name'] as String? ?? '',
      plotNumber: map['plot_number'] as String? ?? '',
      permitDate: pDate,
      notes: map['notes'] as String? ?? '',
      permitType: map['permit_type'] as String? ?? '',
      nameChangeNotes: map['name_change_notes'] as String? ?? '',
      plotArea: (map['plot_area'] as num?)?.toDouble(),
      buildingArea: (map['building_area'] as num?)?.toDouble(),
      namePerNewRegistry: map['name_per_new_registry'] as String? ?? '',
      attachmentUrls: (map['attachment_urls'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      isDeleted: map['is_deleted'] as bool? ?? false,
      createdBy: map['created_by']?.toString(),
      createdByName: map['created_by_name']?.toString(),
      createdAt: parseDate(map['created_at']),
      updatedBy: map['updated_by']?.toString(),
      updatedByName: map['updated_by_name']?.toString(),
      updatedAt: parseDate(map['updated_at']),
    );
  }

  /// خريطة للإرسال إلى Supabase (بدون الحقول المحلية)
  Map<String, dynamic> toSupabaseMap({bool includeId = true}) {
    return {
      if (includeId) 'id': id,
      'permit_number': permitNumber,
      'permit_year': permitYear,
      'full_name': fullName,
      'plot_number': plotNumber,
      'permit_date': permitDate.toIso8601String().split('T').first,
      'notes': notes,
      'permit_type': permitType,
      'name_change_notes': nameChangeNotes,
      'plot_area': plotArea,
      'building_area': buildingArea,
      'name_per_new_registry': namePerNewRegistry,
      'attachment_urls': attachmentUrls,
      'is_deleted': isDeleted,
    };
  }

  /// خريطة للتخزين في Hive (JSON بسيط)
  Map<String, dynamic> toHiveMap() {
    return {
      'id': id,
      'permit_number': permitNumber,
      'permit_year': permitYear,
      'full_name': fullName,
      'plot_number': plotNumber,
      'permit_date': permitDate.toIso8601String(),
      'notes': notes,
      'permit_type': permitType,
      'name_change_notes': nameChangeNotes,
      'plot_area': plotArea,
      'building_area': buildingArea,
      'name_per_new_registry': namePerNewRegistry,
      'attachment_urls': attachmentUrls,
      'is_deleted': isDeleted,
      'created_by': createdBy,
      'created_by_name': createdByName,
      'created_at': createdAt.toIso8601String(),
      'updated_by': updatedBy,
      'updated_by_name': updatedByName,
      'updated_at': updatedAt.toIso8601String(),
      'is_synced_locally': isSyncedLocally,
      'is_pending_delete': isPendingDelete,
    };
  }

  factory PermitModel.fromHiveMap(Map map) {
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is DateTime) return val;
      final str = val.toString().trim();
      if (str.isEmpty) return DateTime.now();
      return DateTime.tryParse(str) ?? DateTime.now();
    }

    final pDate = parseDate(map['permit_date']);
    final pYear = (map['permit_year'] as num?)?.toInt() ?? pDate.year;

    return PermitModel(
      id: map['id']?.toString() ?? '',
      permitNumber: (map['permit_number'] as num?)?.toInt() ?? 0,
      permitYear: pYear != 0 ? pYear : pDate.year,
      fullName: map['full_name'] as String? ?? '',
      plotNumber: map['plot_number'] as String? ?? '',
      permitDate: pDate,
      notes: map['notes'] as String? ?? '',
      permitType: map['permit_type'] as String? ?? '',
      nameChangeNotes: map['name_change_notes'] as String? ?? '',
      plotArea: (map['plot_area'] as num?)?.toDouble(),
      buildingArea: (map['building_area'] as num?)?.toDouble(),
      namePerNewRegistry: map['name_per_new_registry'] as String? ?? '',
      attachmentUrls: (map['attachment_urls'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      isDeleted: map['is_deleted'] as bool? ?? false,
      createdBy: map['created_by']?.toString(),
      createdByName: map['created_by_name']?.toString(),
      createdAt: parseDate(map['created_at']),
      updatedBy: map['updated_by']?.toString(),
      updatedByName: map['updated_by_name']?.toString(),
      updatedAt: parseDate(map['updated_at']),
      isSyncedLocally: map['is_synced_locally'] as bool? ?? true,
      isPendingDelete: map['is_pending_delete'] as bool? ?? false,
    );
  }

  PermitModel copyWith({
    int? permitNumber,
    int? permitYear,
    String? fullName,
    String? plotNumber,
    DateTime? permitDate,
    String? notes,
    String? permitType,
    String? nameChangeNotes,
    double? plotArea,
    double? buildingArea,
    String? namePerNewRegistry,
    List<String>? attachmentUrls,
    bool? isDeleted,
    String? updatedBy,
    String? updatedByName,
    DateTime? updatedAt,
    bool? isSyncedLocally,
    bool? isPendingDelete,
  }) {
    return PermitModel(
      id: id,
      permitNumber: permitNumber ?? this.permitNumber,
      permitYear: permitYear ?? this.permitYear,
      fullName: fullName ?? this.fullName,
      plotNumber: plotNumber ?? this.plotNumber,
      permitDate: permitDate ?? this.permitDate,
      notes: notes ?? this.notes,
      permitType: permitType ?? this.permitType,
      nameChangeNotes: nameChangeNotes ?? this.nameChangeNotes,
      plotArea: plotArea ?? this.plotArea,
      buildingArea: buildingArea ?? this.buildingArea,
      namePerNewRegistry: namePerNewRegistry ?? this.namePerNewRegistry,
      attachmentUrls: attachmentUrls ?? this.attachmentUrls,
      isDeleted: isDeleted ?? this.isDeleted,
      createdBy: createdBy,
      createdByName: createdByName,
      createdAt: createdAt,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedByName: updatedByName ?? this.updatedByName,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
      isSyncedLocally: isSyncedLocally ?? this.isSyncedLocally,
      isPendingDelete: isPendingDelete ?? this.isPendingDelete,
    );
  }

  @override
  List<Object?> get props => [id, permitNumber, permitYear, fullName, plotNumber, permitDate, updatedAt, isDeleted];
}
