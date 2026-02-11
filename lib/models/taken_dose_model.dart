/// Data model for a taken dose record.
class TakenDoseModel {
  final int? rowId; // SQLite auto-increment (null when inserting)
  final String reminderId;
  final String doseDateTime; // ISO 8601
  final String userid;
  final String takenAt; // ISO 8601
  final String profileName;

  const TakenDoseModel({
    this.rowId,
    required this.reminderId,
    required this.doseDateTime,
    required this.userid,
    required this.takenAt,
    this.profileName = '',
  });

  /// Create from a SQLite row map.
  factory TakenDoseModel.fromMap(Map<String, dynamic> map) {
    return TakenDoseModel(
      rowId: map['id'] as int?,
      reminderId: (map['reminder_id'] ?? '').toString(),
      doseDateTime: (map['dose_date_time'] ?? '').toString(),
      userid: (map['userid'] ?? '').toString(),
      takenAt: (map['taken_at'] ?? '').toString(),
      profileName: (map['profile_name'] ?? '').toString(),
    );
  }

  /// Convert to a SQLite row map.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'reminder_id': reminderId,
      'dose_date_time': doseDateTime,
      'userid': userid,
      'taken_at': takenAt,
      'profile_name': profileName,
    };
    if (rowId != null) {
      map['id'] = rowId;
    }
    return map;
  }
}
