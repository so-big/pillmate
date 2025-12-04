import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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

Future<Map<String, dynamic>> _loadNotificationSettings() async {
  const String defaultRawSoundName = 'a01_clock_alarm_normal_30_sec';
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/pillmate/appstatus.json');

    if (await file.exists()) {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      String loadedSoundName =
          data['time_mode_sound']?.toString().toLowerCase() ??
          defaultRawSoundName;

      if (loadedSoundName.contains('.') || loadedSoundName.contains('/')) {
        loadedSoundName = defaultRawSoundName;
      }
      return {
        'snoozeDuration': (data['time_mode_snooze_duration'] as int? ?? 2),
        'repeatCount': (data['time_mode_repeat_count'] as int? ?? 1),
        'rawResourceName': loadedSoundName,
      };
    }
  } catch (e) {
    debugPrint('Error loading settings: $e');
  }
  return {
    'snoozeDuration': 2,
    'repeatCount': 1,
    'rawResourceName': defaultRawSoundName,
  };
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

  UpcomingDose? nextDose = null;

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

    final intervalMinutes =
        (reminder['interval_minutes'] as int? ?? 0) +
        ((reminder['interval_hours'] as int? ?? 0) * 60);

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
  // ✅ ประกาศตัวแปร now ภายในฟังก์ชัน
  final now = tz.TZDateTime.now(tz.local);

  debugPrint('\n=============================================================');
  debugPrint('🔔🔔🔔 NOTIFICATION SERVICE: START SCHEDULING 🔔🔔🔔');
  debugPrint('Master User: $username');

  // ⚠️ ยกเลิกการแจ้งเตือนเก่าทั้งหมดก่อน (Reset)
  await flutterLocalNotificationsPlugin.cancelAll();
  debugPrint('✅ Cancelled all previous notifications.');

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
  final settings = await _loadNotificationSettings();
  final int snoozeDuration = settings['snoozeDuration'] as int;
  final int repeatCount = settings['repeatCount'] as int;
  final String rawResourceName = settings['rawResourceName'] as String;

  debugPrint('Upcoming Dose found at: $targetTime');
  debugPrint('Medicine: ${reminder['medicine_name']}');

  // ------------------------------------------------
  // สร้าง Notification Content
  // ------------------------------------------------

  final medicineName = reminder['medicine_name']?.toString() ?? 'ยา';
  final profileName = reminder['profile_name']?.toString() ?? 'คุณ';

  String mealInstruction;
  final beforeMeal = reminder['medicine_before_meal'] == 1;
  final afterMeal = reminder['medicine_after_meal'] == 1;

  if (beforeMeal && !afterMeal) {
    mealInstruction = 'ก่อนอาหาร';
  } else if (afterMeal && !beforeMeal) {
    mealInstruction = 'หลังอาหาร';
  } else if (beforeMeal && afterMeal) {
    mealInstruction = 'ก่อนหรือหลังอาหารก็ได้';
  } else {
    mealInstruction = 'โดยไม่ระบุเวลาที่สัมพันธ์กับมื้ออาหาร';
  }

  // Title: ชื่อยา (medicine_name)
  final String title = medicineName;

  // Body: ได้เวลากินยา [medicine_name] ของ [profile_name] แล้วค่ะ กรุณาทานยา [ก่อนอาหาร/หลังอาหาร]
  final String body =
      'ได้เวลากินยา $medicineName ของ $profileName แล้วค่ะ กรุณาทานยา $mealInstruction';

  // ------------------------------------------------
  // ตั้งเวลาแจ้งเตือน (รวม Snooze)
  // ------------------------------------------------

  for (int i = 0; i <= repeatCount; i++) {
    final tz.TZDateTime currentScheduleTime = targetTime.add(
      Duration(minutes: i * snoozeDuration),
    );

    // ตรวจสอบอีกครั้งว่าเวลาที่จะ schedule ไม่เลยเวลาปัจจุบันไปแล้ว (เผื่อ Loop)
    if (currentScheduleTime.isBefore(now)) {
      continue;
    }

    final int notificationId =
        (currentScheduleTime.millisecondsSinceEpoch ~/ 1000) & 0x7FFFFFFF;

    final NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'pillmate_custom_sound_v2',
        'Pillmate Reminders',
        channelDescription: 'แจ้งเตือนการทานยา',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
        sound: RawResourceAndroidNotificationSound(rawResourceName),
      ),
    );

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        notificationId,
        title, // ชื่อยา
        body, // รายละเอียด
        currentScheduleTime,
        notificationDetails,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: nextDose.doseKey, // เก็บ Dose Key ไว้ใน Payload
      );

      debugPrint(
        '✅ Scheduled ID:$notificationId at $currentScheduleTime (Snooze $i)',
      );
    } catch (e) {
      debugPrint('❌ Error scheduling notification: $e');
    }
  }
  debugPrint('=============================================================\n');

  // 🔔 ส่งข้อความสถานะกลับไปที่ UI: ตั้งค่าสำเร็จ
  final timeFormat =
      '${targetTime.hour.toString().padLeft(2, '0')}:${targetTime.minute.toString().padLeft(2, '0')}';

  uiMessageStream.add(
    "✅ ตั้งค่าแจ้งเตือนยา '$medicineName' เวลา $timeFormat สำเร็จแล้ว",
  );
}
