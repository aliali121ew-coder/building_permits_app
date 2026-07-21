import '../core/constants/app_constants.dart';

class UserModel {
  const UserModel({
    required this.id,
    required this.fullName,
    required this.role,
    required this.isActive,
    this.canAdd = true,
    this.canEdit = true,
    this.canDelete = false,
    this.canView = true,
    this.email,
    this.birthDate,
    this.phoneNumber,
    this.avatarPath,
    this.approvalStatus = 'pending',
    this.licenseStartAt,
    this.licenseEndAt,
    this.licensePaused = false,
    this.licensePausedSecondsLeft,
    this.lastPausedAt,
    this.activatedCode,
  });

  final String id;
  final String fullName;
  final String role; // admin / employee
  final bool isActive;
  final bool canAdd;
  final bool canEdit;
  final bool canDelete;
  final bool canView;
  final String? email;
  final String? birthDate;
  final String? phoneNumber;
  final String? avatarPath;
  
  // حقول التراخيص الجديدة
  final String approvalStatus; // pending / approved / suspended
  final DateTime? licenseStartAt;
  final DateTime? licenseEndAt;
  final bool licensePaused;
  final int? licensePausedSecondsLeft;
  final DateTime? lastPausedAt;
  final String? activatedCode;

  bool get isAdmin => role == AppConstants.roleAdmin;
  
  // التحقق من تفعيل الترخيص وصلاحيته
  bool get isLicenseActive {
    if (isAdmin) return true;
    if (approvalStatus != 'approved') return false;
    if (licensePaused) return false;
    if (licenseEndAt == null) return false;
    return DateTime.now().isBefore(licenseEndAt!);
  }

  // حساب الوقت المتبقي بالثواني
  int get remainingSeconds {
    if (isAdmin) return 99999999;
    if (licensePaused) return licensePausedSecondsLeft ?? 0;
    if (licenseEndAt == null) return 0;
    final diff = licenseEndAt!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  factory UserModel.fromMap(Map<String, dynamic> map, {String? email}) {
    final roleStr = map['role'] as String? ?? AppConstants.roleEmployee;
    final isAdminUser = roleStr == AppConstants.roleAdmin;

    DateTime? parseDateTime(dynamic value) {
      if (value == null) return null;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return UserModel(
      id: map['id']?.toString() ?? '',
      fullName: map['full_name'] as String? ?? '',
      role: roleStr,
      isActive: map['is_active'] as bool? ?? true,
      canAdd: map['can_add'] as bool? ?? true,
      canEdit: map['can_edit'] as bool? ?? true,
      canDelete: map['can_delete'] as bool? ?? isAdminUser,
      canView: map['can_view'] as bool? ?? true,
      email: email ?? map['email'] as String?,
      birthDate: map['birth_date'] as String?,
      phoneNumber: map['phone_number'] as String?,
      avatarPath: map['avatar_path'] as String?,
      approvalStatus: map['approval_status'] as String? ?? 'pending',
      licenseStartAt: parseDateTime(map['license_start_at']),
      licenseEndAt: parseDateTime(map['license_end_at']),
      licensePaused: map['license_paused'] as bool? ?? false,
      licensePausedSecondsLeft: map['license_paused_seconds_left'] as int?,
      lastPausedAt: parseDateTime(map['last_paused_at']),
      activatedCode: map['activated_code']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'full_name': fullName,
        'role': role,
        'is_active': isActive,
        'can_add': canAdd,
        'can_edit': canEdit,
        'can_delete': canDelete,
        'can_view': canView,
        'email': email,
        'birth_date': birthDate,
        'phone_number': phoneNumber,
        'avatar_path': avatarPath,
        'approval_status': approvalStatus,
        'license_start_at': licenseStartAt?.toIso8601String(),
        'license_end_at': licenseEndAt?.toIso8601String(),
        'license_paused': licensePaused,
        'license_paused_seconds_left': licensePausedSecondsLeft,
        'last_paused_at': lastPausedAt?.toIso8601String(),
        'activated_code': activatedCode,
      };

  Map<String, dynamic> toSupabaseMap() => {
        'id': id,
        'full_name': fullName,
        'role': role,
        'is_active': isActive,
        'approval_status': approvalStatus,
        'license_start_at': licenseStartAt?.toIso8601String(),
        'license_end_at': licenseEndAt?.toIso8601String(),
        'license_paused': licensePaused,
        'license_paused_seconds_left': licensePausedSecondsLeft,
        'last_paused_at': lastPausedAt?.toIso8601String(),
        'activated_code': activatedCode,
        'email': email,
      };

  UserModel copyWith({
    String? fullName,
    String? role,
    bool? isActive,
    bool? canAdd,
    bool? canEdit,
    bool? canDelete,
    bool? canView,
    String? email,
    String? birthDate,
    String? phoneNumber,
    String? avatarPath,
    String? approvalStatus,
    DateTime? licenseStartAt,
    DateTime? licenseEndAt,
    bool? licensePaused,
    int? licensePausedSecondsLeft,
    DateTime? lastPausedAt,
    String? activatedCode,
  }) {
    return UserModel(
      id: id,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      canAdd: canAdd ?? this.canAdd,
      canEdit: canEdit ?? this.canEdit,
      canDelete: canDelete ?? this.canDelete,
      canView: canView ?? this.canView,
      email: email ?? this.email,
      birthDate: birthDate ?? this.birthDate,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      avatarPath: avatarPath ?? this.avatarPath,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      licenseStartAt: licenseStartAt ?? this.licenseStartAt,
      licenseEndAt: licenseEndAt ?? this.licenseEndAt,
      licensePaused: licensePaused ?? this.licensePaused,
      licensePausedSecondsLeft: licensePausedSecondsLeft ?? this.licensePausedSecondsLeft,
      lastPausedAt: lastPausedAt ?? this.lastPausedAt,
      activatedCode: activatedCode ?? this.activatedCode,
    );
  }
}
