/// عملية بانتظار المزامنة مع Supabase عند عودة الإنترنت
/// (تُخزَّن في صندوق Hive منفصل: pending_ops_box)
class PendingOperation {
  const PendingOperation({
    required this.opId,
    required this.permitId,
    required this.type, // insert / update / delete
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
  });

  final String opId;
  final String permitId;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;

  Map<String, dynamic> toMap() => {
        'op_id': opId,
        'permit_id': permitId,
        'type': type,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
        'retry_count': retryCount,
      };

  factory PendingOperation.fromMap(Map map) => PendingOperation(
        opId: map['op_id'] as String,
        permitId: map['permit_id'] as String,
        type: map['type'] as String,
        payload: Map<String, dynamic>.from(map['payload'] as Map),
        createdAt: DateTime.parse(map['created_at'] as String),
        retryCount: map['retry_count'] as int? ?? 0,
      );

  PendingOperation incrementRetry() => PendingOperation(
        opId: opId,
        permitId: permitId,
        type: type,
        payload: payload,
        createdAt: createdAt,
        retryCount: retryCount + 1,
      );
}
