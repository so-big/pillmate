/// Data model for app notification settings.
class NotificationSettingsModel {
  final String soundName;
  final int snoozeDurationMinutes;
  final int repeatCount;
  final String updatedAt;

  const NotificationSettingsModel({
    this.soundName = 'a01_clock_alarm_normal_30_sec',
    this.snoozeDurationMinutes = 2,
    this.repeatCount = 1,
    this.updatedAt = '',
  });

  /// Create from a JSON map (from appstatus.json or SharedPreferences).
  factory NotificationSettingsModel.fromMap(Map<String, dynamic> map) {
    return NotificationSettingsModel(
      soundName: (map['time_mode_sound'] ?? 'a01_clock_alarm_normal_30_sec')
          .toString(),
      snoozeDurationMinutes:
          (map['time_mode_snooze_duration'] as int?) ?? 2,
      repeatCount: (map['time_mode_repeat_count'] as int?) ?? 1,
      updatedAt: (map['updated_at'] ?? '').toString(),
    );
  }

  /// Convert to a JSON map for persistence.
  Map<String, dynamic> toMap() {
    return {
      'time_mode_sound': soundName,
      'time_mode_snooze_duration': snoozeDurationMinutes,
      'time_mode_repeat_count': repeatCount,
      'updated_at': updatedAt.isNotEmpty
          ? updatedAt
          : DateTime.now().toIso8601String(),
    };
  }

  NotificationSettingsModel copyWith({
    String? soundName,
    int? snoozeDurationMinutes,
    int? repeatCount,
    String? updatedAt,
  }) {
    return NotificationSettingsModel(
      soundName: soundName ?? this.soundName,
      snoozeDurationMinutes:
          snoozeDurationMinutes ?? this.snoozeDurationMinutes,
      repeatCount: repeatCount ?? this.repeatCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
