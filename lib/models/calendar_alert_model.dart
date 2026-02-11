/// Data model for a calendar reminder / alert.
class CalendarAlertModel {
  final String id;
  final String profileName;
  final String medicineName;
  final String medicineImage;
  final int medicineBeforeMeal; // 1 = true, 0 = false
  final int medicineAfterMeal;
  final String startDateTime; // ISO 8601
  final String endDateTime;
  final int notifyByTime; // 1 = interval mode, 0 = single shot
  final int intervalMinutes;
  final int intervalHours;
  final String createby; // username
  final String createdAt;

  const CalendarAlertModel({
    required this.id,
    required this.profileName,
    required this.medicineName,
    this.medicineImage = '',
    this.medicineBeforeMeal = 0,
    this.medicineAfterMeal = 0,
    required this.startDateTime,
    this.endDateTime = '',
    this.notifyByTime = 0,
    this.intervalMinutes = 0,
    this.intervalHours = 0,
    required this.createby,
    this.createdAt = '',
  });

  /// Total interval in minutes, combining hours + minutes fields.
  int get totalIntervalMinutes => intervalMinutes + (intervalHours * 60);

  /// Create from a SQLite row map.
  factory CalendarAlertModel.fromMap(Map<String, dynamic> map) {
    return CalendarAlertModel(
      id: (map['id'] ?? '').toString(),
      profileName: (map['profile_name'] ?? '').toString(),
      medicineName: (map['medicine_name'] ?? '').toString(),
      medicineImage: (map['medicine_image'] ?? '').toString(),
      medicineBeforeMeal: (map['medicine_before_meal'] as int?) ?? 0,
      medicineAfterMeal: (map['medicine_after_meal'] as int?) ?? 0,
      startDateTime: (map['start_date_time'] ?? '').toString(),
      endDateTime: (map['end_date_time'] ?? '').toString(),
      notifyByTime: (map['notify_by_time'] as int?) ?? 0,
      intervalMinutes: (map['interval_minutes'] as int?) ?? 0,
      intervalHours: (map['interval_hours'] as int?) ?? 0,
      createby: (map['createby'] ?? '').toString(),
      createdAt: (map['created_at'] ?? '').toString(),
    );
  }

  /// Convert to a SQLite row map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'profile_name': profileName,
      'medicine_name': medicineName,
      'medicine_image': medicineImage,
      'medicine_before_meal': medicineBeforeMeal,
      'medicine_after_meal': medicineAfterMeal,
      'start_date_time': startDateTime,
      'end_date_time': endDateTime,
      'notify_by_time': notifyByTime,
      'interval_minutes': intervalMinutes,
      'interval_hours': intervalHours,
      'createby': createby,
      'created_at': createdAt,
    };
  }

  CalendarAlertModel copyWith({
    String? id,
    String? profileName,
    String? medicineName,
    String? medicineImage,
    int? medicineBeforeMeal,
    int? medicineAfterMeal,
    String? startDateTime,
    String? endDateTime,
    int? notifyByTime,
    int? intervalMinutes,
    int? intervalHours,
    String? createby,
    String? createdAt,
  }) {
    return CalendarAlertModel(
      id: id ?? this.id,
      profileName: profileName ?? this.profileName,
      medicineName: medicineName ?? this.medicineName,
      medicineImage: medicineImage ?? this.medicineImage,
      medicineBeforeMeal: medicineBeforeMeal ?? this.medicineBeforeMeal,
      medicineAfterMeal: medicineAfterMeal ?? this.medicineAfterMeal,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      notifyByTime: notifyByTime ?? this.notifyByTime,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      intervalHours: intervalHours ?? this.intervalHours,
      createby: createby ?? this.createby,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
