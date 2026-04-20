import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ✅ Import Database Helper ของนายท่าน
import 'database_helper.dart';

// -----------------------------------------------------------------------------
// GLOBAL SETUP
// -----------------------------------------------------------------------------

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final StreamController<NotificationResponse> selectNotificationStream =
    StreamController<NotificationResponse>.broadcast();

// 🚨 NEW: Stream สำหรับส่งข้อความสถานะกลับไปที่ UI (เพื่อแสดง SnackBar)
final StreamController<String> uiMessageStream =
    StreamController<String>.broadcast();

final dbHelper = DatabaseHelper(); // ✅ เรียกใช้ Database Helper

const Set<String> _availableRawSounds = {
  'a01_clock_alarm_normal_30_sec',
  'a02_clock_alarm_normal_1_min',
  'a03_clock_alarm_normal_1_30_min',
  'a04_clock_alarm_continue_30_sec',
  'a05_clock_alarm_continue_1_min',
  'a06_clock_alarm_continue_1_30_min',
};

String _normalizeRawSoundName(String value) {
  final fileName = value.split('/').last.split('.').first.toLowerCase();
  return _availableRawSounds.contains(fileName)
      ? fileName
      : 'a01_clock_alarm_normal_30_sec';
}

final List<Timer> _foregroundSoundTimers = [];
final List<AudioPlayer> _foregroundAudioPlayers = [];

void cancelForegroundAlertSounds() {
  for (final timer in _foregroundSoundTimers) {
    timer.cancel();
  }
  _foregroundSoundTimers.clear();

  for (final player in _foregroundAudioPlayers) {
    unawaited(player.stop());
    unawaited(player.dispose());
  }
  _foregroundAudioPlayers.clear();
}

Future<bool> _isDoseAlreadyTaken(String doseKey) async {
  final parts = doseKey.split('|');
  if (parts.length < 2) return false;

  final rows = await dbHelper.database.then(
    (db) => db.query(
      'taken_doses',
      columns: ['reminder_id'],
      where: 'reminder_id = ? AND dose_date_time = ?',
      whereArgs: [parts.first, parts.sublist(1).join('|')],
      limit: 1,
    ),
  );

  return rows.isNotEmpty;
}

void _scheduleForegroundAlertSounds({
  required UpcomingDose nextDose,
  required String rawResourceName,
  required int snoozeDuration,
  required int repeatCount,
}) {
  cancelForegroundAlertSounds();

  final totalAlerts = repeatCount > 0 ? repeatCount : 1;
  final gapMinutes = snoozeDuration > 0 ? snoozeDuration : 5;

  for (int i = 0; i < totalAlerts; i++) {
    final scheduleTime = nextDose.doseTime.add(
      Duration(minutes: i * gapMinutes),
    );
    final delay = scheduleTime.difference(tz.TZDateTime.now(tz.local));
    if (delay.isNegative) continue;

    _foregroundSoundTimers.add(
      Timer(delay, () async {
        final lifecycleState = WidgetsBinding.instance.lifecycleState;
        if (lifecycleState != AppLifecycleState.resumed) return;
        if (await _isDoseAlreadyTaken(nextDose.doseKey)) return;

        final player = AudioPlayer();
        _foregroundAudioPlayers.add(player);

        try {
          await player.setVolume(1.0);
          await player.play(AssetSource('sound_norti/$rawResourceName.mp3'));
          debugPrint(
            '🔊 Foreground alert sound played: $rawResourceName for ${nextDose.doseKey}',
          );

          player.onPlayerComplete.listen((_) {
            _foregroundAudioPlayers.remove(player);
            unawaited(player.dispose());
          });
        } catch (e) {
          debugPrint('❌ Foreground alert sound failed: $e');
          _foregroundAudioPlayers.remove(player);
          unawaited(player.dispose());
        }
      }),
    );
  }
}

// -----------------------------------------------------------------------------
// INIT & TIMEZONE (จากโค้ดเดิม)
// -----------------------------------------------------------------------------

Future<void> initializeNotifications() async {
  await _configureLocalTimeZone();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
    macOS: initializationSettingsDarwin,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse:
        (NotificationResponse notificationResponse) {
          selectNotificationStream.add(notificationResponse);
        },
  );

  debugPrint('Notification Plugin Initialized & Timezone Configured');
}

Future<void> _configureLocalTimeZone() async {
  if (kIsWeb || Platform.isLinux) {
    return;
  }
  tzdata.initializeTimeZones();
  final String timeZoneName = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(timeZoneName));
  debugPrint('Local Timezone set to: $timeZoneName');
}

// -----------------------------------------------------------------------------
// HELPER: โหลด Settings จาก appstatus.json (สำหรับ Sound & Snooze)
// -----------------------------------------------------------------------------

Future<Map<String, dynamic>> _loadNotificationSettings(String username) async {
  const String defaultRawSoundName = 'a01_clock_alarm_normal_30_sec';
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/pillmate/appstatus.json');

    if (await file.exists()) {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final userSettings = _readUserTimeModeSettings(data, username);
      final loadedSoundName = _normalizeRawSoundName(
        userSettings['time_mode_sound']?.toString() ?? defaultRawSoundName,
      );
      return {
        'snoozeDuration':
            int.tryParse(
              userSettings['time_mode_snooze_duration']?.toString() ?? '',
            ) ??
            5,
        'repeatCount':
            int.tryParse(
              userSettings['time_mode_repeat_count']?.toString() ?? '',
            ) ??
            1,
        'rawResourceName': loadedSoundName,
      };
    }
  } catch (e) {
    debugPrint('Error loading settings: $e');
  }
  return {
    'snoozeDuration': 5,
    'repeatCount': 1,
    'rawResourceName': defaultRawSoundName,
  };
}

Map<String, dynamic> _readUserTimeModeSettings(
  Map<String, dynamic> data,
  String username,
) {
  final settingsByUser = data['time_mode_settings_by_user'];
  if (settingsByUser is Map) {
    final settings = settingsByUser[username];
    if (settings is Map) {
      return Map<String, dynamic>.from(settings);
    }
  }
  return {};
}

// -----------------------------------------------------------------------------
// CORE LOGIC: ค้นหาโดสถัดไปที่ยังไม่ได้กิน
// -----------------------------------------------------------------------------

// Class สำหรับเก็บข้อมูลโดสถัดไปที่พบ
class UpcomingDose {
  final Map<String, dynamic> reminder;
  final tz.TZDateTime doseTime;
  final String doseKey; // reminderId|doseTimeIso

  UpcomingDose({
    required this.reminder,
    required this.doseTime,
    required this.doseKey,
  });
}

// ฟังก์ชันหลักในการหาโดสถัดไปที่ต้องกิน
Future<UpcomingDose?> _getUpcomingDose(String username) async {
  final db = await dbHelper.database;
  // กำหนดเวลาปัจจุบันที่ใช้งาน
  final now = tz.TZDateTime.now(tz.local);

  // 1. ดึงข้อมูลการแจ้งเตือนที่สร้างโดยผู้ใช้นี้
  final List<Map<String, dynamic>> reminders = await db.query(
    'calendar_alerts',
    where: 'createby = ?',
    whereArgs: [username],
  );

  // 2. ดึงข้อมูลโดสที่กินไปแล้ว
  final List<Map<String, dynamic>> takenDoses = await db.query(
    'taken_doses',
    columns: ['reminder_id', 'dose_date_time'],
    where: 'userid = ?',
    whereArgs: [username],
  );
  final Set<String> takenKeys = takenDoses.map((row) {
    return '${row['reminder_id']?.toString()}|${row['dose_date_time']?.toString()}';
  }).toSet();

  UpcomingDose? nextDose;

  for (final reminder in reminders) {
    final reminderId = reminder['id']?.toString();
    if (reminderId == null) continue;

    final startStr = reminder['start_date_time']?.toString();
    final endStr = reminder['end_date_time']?.toString();
    final notifyByTime = reminder['notify_by_time'] == 1;

    final DateTime? startDT = startStr != null
        ? DateTime.tryParse(startStr)
        : null;
    final tz.TZDateTime? start = startDT != null
        ? tz.TZDateTime.from(startDT, tz.local)
        : null;

    DateTime? endDT;
    if (endStr != null && endStr.isNotEmpty) {
      endDT = DateTime.tryParse(endStr);
    }
    final tz.TZDateTime? tzEnd = endDT != null
        ? tz.TZDateTime.from(endDT, tz.local)
        : null;

    if (start == null) continue;

    int intervalMinutes =
        int.tryParse(reminder['interval_minutes']?.toString() ?? '') ?? 0;
    if (intervalMinutes <= 0) {
      final intervalHours =
          int.tryParse(reminder['interval_hours']?.toString() ?? '') ?? 0;
      intervalMinutes = intervalHours * 60;
    }

    // ------------------------------------------------
    // Logic ค้นหาเวลากินยาถัดไปสำหรับ Reminder นี้
    // ------------------------------------------------

    tz.TZDateTime? doseCandidate;

    if (!notifyByTime || intervalMinutes <= 0) {
      // โหมดตั้งเวลาเดียว (หรือไม่มี Interval)
      doseCandidate = start;
    } else {
      // โหมดตั้งเวลาแบบ Interval

      // a. คำนวณจำนวน Intervals ที่ผ่านไปจนถึงปัจจุบัน
      final diffMinutes = now.difference(start).inMinutes;
      // จำนวนรอบที่ผ่านไปแล้ว (ตั้งแต่ start)
      int steps = (diffMinutes / intervalMinutes).floor();
      // หาก start อยู่ในอนาคต steps จะเป็นค่าลบ ให้เริ่มที่ 0
      steps = steps < 0 ? 0 : steps;

      // b. หาเวลาที่ถูกกำหนดไว้ในรอบปัจจุบันหรือรอบถัดไป
      while (true) {
        final currentCandidate = start.add(
          Duration(minutes: (steps) * intervalMinutes),
        );

        // c. ตรวจสอบว่าเกินเวลาสิ้นสุดแล้วหรือไม่
        if (tzEnd != null && currentCandidate.isAfter(tzEnd)) {
          break; // เกินวันสิ้นสุดแล้ว
        }

        // d. ตรวจสอบว่าเวลานี้เป็น "เวลาถัดไปที่ยังไม่ถึง" หรือไม่
        // ถ้าน้อยกว่าหรือเท่ากับ now ให้ข้ามไปรอบถัดไปทันที (ไม่แจ้งเตือนของอดีต)
        if (currentCandidate.isBefore(now)) {
          steps++;
          continue;
        }

        // e. ถ้านอกเหนือจากเงื่อนไขด้านบน คือเวลาที่กำลังจะมาถึง
        doseCandidate = currentCandidate;
        break;
      }
    }

    // ------------------------------------------------
    // ตรวจสอบ Candidate
    // ------------------------------------------------
    if (doseCandidate != null) {
      // Dose ที่จะแจ้งเตือน ต้องไม่เกิน End Date
      if (tzEnd != null && doseCandidate.isAfter(tzEnd)) continue;

      final doseKey = '$reminderId|${doseCandidate.toIso8601String()}';

      // 1. ต้องไม่เคยถูกกินแล้ว
      if (takenKeys.contains(doseKey)) {
        continue;
      }

      // 2. ต้องเป็นเวลาที่ใกล้กว่าโดสที่เคยเจอ
      if (nextDose == null || doseCandidate.isBefore(nextDose.doseTime)) {
        nextDose = UpcomingDose(
          reminder: reminder,
          doseTime: doseCandidate,
          doseKey: doseKey,
        );
      }
    }
  }

  return nextDose;
}

// -----------------------------------------------------------------------------
// SCHEDULING ENTRY POINT (ปรับปรุงโค้ดเดิม)
// -----------------------------------------------------------------------------

// 3. ฟังก์ชันหลักสำหรับตั้งแจ้งเตือน (รับ username เข้ามา)
void scheduleNotificationForNewAlert(String username) async {
  debugPrint('\n=============================================================');
  debugPrint('🔔🔔🔔 FOREGROUND ALERT SERVICE: START 🔔🔔🔔');
  debugPrint('Master User: $username');

  cancelForegroundAlertSounds();
  debugPrint('✅ Cancelled previous foreground alert timers.');

  // ค้นหาโดสถัดไปที่ต้องกินจริง ๆ
  final nextDose = await _getUpcomingDose(username);

  if (nextDose == null) {
    debugPrint('ℹ️ No upcoming doses found for master user: $username.');
    debugPrint(
      '=============================================================\n',
    );
    // 🔔 ส่งข้อความสถานะกลับไปที่ UI
    uiMessageStream.add("ไม่พบการแจ้งเตือนยาที่ต้องตั้งค่าในขณะนี้");
    return;
  }

  final reminder = nextDose.reminder;
  final targetTime = nextDose.doseTime;

  // โหลด Settings สำหรับ Custom Sound, Snooze
  final settings = await _loadNotificationSettings(username);
  final int snoozeDuration = settings['snoozeDuration'] as int;
  final int repeatCount = settings['repeatCount'] as int;
  final String rawResourceName = settings['rawResourceName'] as String;

  _scheduleForegroundAlertSounds(
    nextDose: nextDose,
    rawResourceName: rawResourceName,
    snoozeDuration: snoozeDuration,
    repeatCount: repeatCount,
  );

  debugPrint('Upcoming Dose found at: $targetTime');
  debugPrint('Medicine: ${reminder['medicine_name']}');

  final medicineName = reminder['medicine_name']?.toString() ?? 'ยา';
  debugPrint('✅ Foreground sound timers set with sound=$rawResourceName');
  debugPrint('=============================================================\n');

  // 🔔 ส่งข้อความสถานะกลับไปที่ UI: ตั้งค่าสำเร็จ
  final timeFormat =
      '${targetTime.hour.toString().padLeft(2, '0')}:${targetTime.minute.toString().padLeft(2, '0')}';

  uiMessageStream.add(
    "✅ ตั้งค่าแจ้งเตือนยา '$medicineName' เวลา $timeFormat สำเร็จแล้ว",
  );
}
