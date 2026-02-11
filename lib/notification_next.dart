// lib/notification_next.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'database_helper.dart';

/// โครงสร้างบันทึกใน pillmate/nortification_setup.json (log ว่าตั้ง noti อะไรไว้แล้วบ้าง)
class ScheduledNotify {
  final String userid;
  final String reminderId;
  final String doseDateTime; // ISO เวลากินยา
  final String notifyAt; // ISO เวลาเด้งจริง
  final int notificationId; // id ของ noti ใน plugin

  ScheduledNotify({
    required this.userid,
    required this.reminderId,
    required this.doseDateTime,
    required this.notifyAt,
    required this.notificationId,
  });

  Map<String, dynamic> toJson() => {
    'userid': userid,
    'reminderId': reminderId,
    'doseDateTime': doseDateTime,
    'notifyAt': notifyAt,
    'notificationId': notificationId,
  };
}

class NortificationSetup {
  NortificationSetup._();

  static final FlutterLocalNotificationsPlugin _flnp =
      FlutterLocalNotificationsPlugin();

  // ------------ FILE HELPERS ------------

  static Future<Directory> _appDir() async =>
      await getApplicationDocumentsDirectory();

  static Future<File> _settingsFile() async =>
      File('${(await _appDir()).path}/nortification_setting.json');

  static Future<File> _setupFile() async =>
      File('${(await _appDir()).path}/pillmate/nortification_setup.json');

  // ------------ INIT PLUGIN ------------

  static bool _initialized = false;

  /// init plugin + timezone + ขอ permission แจ้งเตือนบน Android
  static Future<void> _initializePluginIfNeeded() async {
    if (_initialized) return;

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const LinuxInitializationSettings linuxInit = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );

    final initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
      linux: linuxInit,
    );

    await _flnp.initialize(initSettings);

    // Android 13+ ต้องขอ permission แจ้งเตือน
    try {
      final androidImpl = _flnp
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await androidImpl?.requestNotificationsPermission();
      debugPrint('NortificationSetup: Notification permission granted: $granted');
      
      // ขอ permission สำหรับ exact alarm (Android 12+)
      final exactAlarmPermission = await androidImpl?.requestExactAlarmsPermission();
      debugPrint('NortificationSetup: Exact alarm permission granted: $exactAlarmPermission');
    } catch (e) {
      debugPrint('NortificationSetup: requestPermissions error $e');
    }

    // timezone fix เป็น Asia/Bangkok
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(await _localTimeZoneName()));

    _initialized = true;
  }

  static Future<String> _localTimeZoneName() async {
    // Use device's actual timezone instead of hardcoded value
    try {
      return await FlutterTimezone.getLocalTimezone();
    } catch (e) {
      debugPrint('NortificationSetup: Failed to get timezone, falling back to Asia/Bangkok: $e');
      return 'Asia/Bangkok';
    }
  }

  // ------------ READ SETTINGS (from DB with JSON fallback) ------------

  /// อ่านตั้งค่าการแจ้งเตือน
  /// advanceMinutes: แจ้งล่วงหน้านานแค่ไหน
  /// afterMinutes: แจ้งต่อหลังถึงเวลาจริงกี่นาที
  /// repeatGapMinutes: เว้นห่างแต่ละลูกซ้ำกี่นาที
  static Future<({int advance, int after, int playDuration, int gap})>
  _readSettings() async {
    try {
      // Try reading from DB app_settings first
      final dbHelper = DatabaseHelper();
      final advanceStr = await dbHelper.getSetting('advanceMinutes');
      final afterStr = await dbHelper.getSetting('afterMinutes');
      final playDurStr = await dbHelper.getSetting('playDurationMinutes');
      final gapStr = await dbHelper.getSetting('repeatGapMinutes');

      if (advanceStr != null || afterStr != null || gapStr != null) {
        return (
          advance: int.tryParse(advanceStr ?? '30') ?? 30,
          after: int.tryParse(afterStr ?? '30') ?? 30,
          playDuration: int.tryParse(playDurStr ?? '1') ?? 1,
          gap: int.tryParse(gapStr ?? '5') ?? 5,
        );
      }

      // Fallback: try legacy JSON files
      final file = await _settingsFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final map = jsonDecode(content);
          if (map is Map<String, dynamic>) {
            final advance =
                int.tryParse('${map['advanceMinutes'] ?? 30}') ?? 30;
            final after = int.tryParse('${map['afterMinutes'] ?? 30}') ?? 30;
            final playDur =
                int.tryParse('${map['playDurationMinutes'] ?? 1}') ?? 1;
            final gap = int.tryParse('${map['repeatGapMinutes'] ?? 5}') ?? 5;
            return (
              advance: advance,
              after: after,
              playDuration: playDur,
              gap: gap,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('NortificationSetup: read settings error $e');
    }
    // default: ล่วงหน้า 30 นาที หลังถึงเวลา 30 นาที เล่น 1 นาที, เว้น 5 นาที
    return (advance: 30, after: 30, playDuration: 1, gap: 5);
  }

  /// อ่านตั้งค่าเสียง + repeat count จาก appstatus.json
  static Future<Map<String, dynamic>> _readSoundSettings() async {
    try {
      final dir = await _appDir();
      final file = File('${dir.path}/pillmate/appstatus.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content);
          if (data is Map<String, dynamic>) {
            // ดึงชื่อไฟล์เสียงจาก time_mode_sound (ไม่มี extension)
            String? soundPath = data['time_mode_sound']?.toString();
            String soundName = 'alarm'; // default
            if (soundPath != null && soundPath.isNotEmpty) {
              // Extract filename without extension
              // e.g. "assets/sound_norti/a01_clock_alarm_normal_30_sec.mp3" -> "a01_clock_alarm_normal_30_sec"
              final parts = soundPath.split('/').last.split('.');
              if (parts.isNotEmpty) {
                soundName = parts.first.toLowerCase(); // ensure lowercase
              }
            }

            final repeatCount = data['time_mode_repeat_count'] as int? ?? 3;
            final snoozeDuration = data['time_mode_snooze_duration'] as int? ?? 5;

            return {
              'soundName': soundName,
              'repeatCount': repeatCount,
              'snoozeDuration': snoozeDuration,
            };
          }
        }
      }
    } catch (e) {
      debugPrint('NortificationSetup: read sound settings error $e');
    }
    return {
      'soundName': 'alarm',
      'repeatCount': 3,
      'snoozeDuration': 5,
    };
  }

  // ------------ ENTRY POINT (เรียกจาก Dashboard) ------------

  /// core: ล้าง noti เดิมทั้งหมด แล้วตั้ง noti ใหม่ให้ user นี้ล่วงหน้า (คำนวณ 5 ครั้งถัดไป)
  static Future<void> run({
    required BuildContext context,
    required String username,
  }) async {
    await _initializePluginIfNeeded();

    // 1) ล้าง notification ทั้งหมดของแอป
    try {
      await _flnp.cancelAll();
    } catch (e) {
      debugPrint('NortificationSetup: cancelAll error $e');
    }

    // 2) ล้างข้อมูล scheduled_notifications เดิมใน DB
    final dbHelper = DatabaseHelper();
    await dbHelper.clearScheduledNotifications(username);

    // 3) อ่าน reminders / takenDoses / settings
    final reminders = await _readRemindersFor(username);
    final takenKeys = await _readTakenKeysFor(username);
    final settings = await _readSettings();

    // 4) อ่านเสียง + repeat settings จาก appstatus.json หรือ DB
    final soundSettings = await _readSoundSettings();
    final soundName = (soundSettings['soundName'] as String?) ?? 'alarm';
    final int repeatCount = (soundSettings['repeatCount'] as int?) ?? 3;
    final int snoozeDuration = (soundSettings['snoozeDuration'] as int?) ?? 5;

    final now = DateTime.now();
    final scheduledForUser = <Map<String, dynamic>>[];

    for (final r in reminders) {
      final String reminderId = r['id']?.toString() ?? '';
      if (reminderId.isEmpty) continue;

      // คำนวณเวลากินยาทั้งหมด เริ่มจาก now และขยายไปจนกว่าจะครบเงื่อนไขหรือถึง limit (30 วัน)
      final until = now.add(const Duration(days: 30));
      final allDoseTimes = _generateDoseTimes(r, now, until);

      // เก็บ notify timestamps ที่ตั้งไว้สำหรับ reminder นี้
      final List<String> timestampsForReminder = [];

      // เงื่อนไขขั้นต่ำ: ต้องมีจำนวน alerts >= (5 * repeatCount) และช่วงเวลาตั้งแต่แรกถึงล่าสุด >= 24 ชั่วโมง
      final int thresholdCount = 5 * repeatCount;
      final Duration thresholdDuration = const Duration(hours: 24);

      DateTime? firstScheduledForThisReminder;
      DateTime? lastScheduledForThisReminder;
      int totalAlertsForThisReminder = 0;

      // สำหรับแต่ละ dose (ตามเวลาที่เกิดขึ้นในอนาคต)
      for (final doseTime in allDoseTimes) {
        final doseIso = doseTime.toIso8601String();
        final key = '$reminderId|$doseIso';
        if (takenKeys.contains(key)) continue; // ข้ามถ้ากินแล้ว

        // หน้าต่างการแจ้งเตือน: [dose - advance, dose + after]
        final windowStart = doseTime.subtract(Duration(minutes: settings.advance));
        final windowEnd = doseTime.add(Duration(minutes: settings.after));

        // เริ่มแจ้งจาก max(now, windowStart)
        var candidate = windowStart.isAfter(now) ? windowStart : now;

        // ในแต่ละหน้าต่าง จะอนุญาตการแจ้งซ้ำสูงสุด repeatCount ครั้ง (หรือจนกว่า windowEnd จะหมด)
        int perDoseCounter = 0;
        while (perDoseCounter < repeatCount && !candidate.isAfter(windowEnd)) {
          final notifyTime = candidate;

          // สร้าง id และอย่าให้ซ้ำ
          final id = _stableId(username, reminderId, '$doseIso|${notifyTime.toIso8601String()}|$perDoseCounter');

          // สร้างข้อความตามฟอร์แมตที่กำหนด
          final medName = r['medicineName']?.toString() ?? 'ถึงเวลากินยา';
          final profileName = r['profileName']?.toString() ?? username;
          final mealTiming = ((r['medicineBeforeMeal'] == true) || (r['medicineBeforeMeal']?.toString() == '1'))
              ? 'Before Meal'
              : (((r['medicineAfterMeal'] == true) || (r['medicineAfterMeal']?.toString() == '1')) ? 'After Meal' : '');
          final scheduledTimeStr = DateTime.parse(doseIso).toLocal();
          final scheduledTimeFormatted = '${scheduledTimeStr.hour.toString().padLeft(2, '0')}:${scheduledTimeStr.minute.toString().padLeft(2, '0')}';
          final currentCount = perDoseCounter + 1;

          final body = '"$profileName", it is time to take "$medName" (${mealTiming}). Alert $currentCount/$repeatCount for scheduled time $scheduledTimeFormatted.';
          final title = '$profileName — Reminder';

          await _scheduleNotification(
            id: id,
            when: notifyTime,
            title: title,
            body: body,
            soundName: soundName,
          );

          // บันทึกลง DB
          scheduledForUser.add({
            'notification_id': id,
            'username': username,
            'reminder_id': reminderId,
            'dose_time': doseIso,
            'notify_at': notifyTime.toIso8601String(),
            'created_at': DateTime.now().toIso8601String(),
            'canceled': 0,
          });

          timestampsForReminder.add(notifyTime.toIso8601String());

          // อัปเดต counters และช่วงเวลา
          totalAlertsForThisReminder += 1;
          firstScheduledForThisReminder ??= notifyTime;
          lastScheduledForThisReminder = notifyTime;

          perDoseCounter += 1;
          candidate = candidate.add(Duration(minutes: snoozeDuration));

          // เช็คเงื่อนไขทั้งสอง — ถ้าทั้งสองเป็นจริงแล้ว ให้หยุดการสร้าง alert เพิ่มเติมสำหรับ reminder นี้
          final durationSpan = lastScheduledForThisReminder!.difference(firstScheduledForThisReminder!);
          if (totalAlertsForThisReminder >= thresholdCount && durationSpan >= thresholdDuration) {
            break;
          }
        }

        // ถ้าบรรลุเงื่อนไขแล้ว ก็หยุดลูป doses ของ reminder นี้
        if (totalAlertsForThisReminder >= thresholdCount && lastScheduledForThisReminder != null && lastScheduledForThisReminder.difference(firstScheduledForThisReminder ?? lastScheduledForThisReminder) >= thresholdDuration) {
          break;
        }
      }

      // Log รายการ timestamps ที่คำนวณได้สำหรับ reminder นี้
      if (timestampsForReminder.isNotEmpty) {
        debugPrint('NortificationSetup: Reminder $reminderId scheduled timestamps:');
        for (final t in timestampsForReminder) {
          debugPrint('  - $t');
        }
      }
    }

    // 5) บันทึก scheduled_notifications ลง DB
    for (final record in scheduledForUser) {
      await dbHelper.insertScheduledNotification(record);
    }

    // --- Debug log: รายการ timestamps ทั้งหมด (group by reminder)
    if (scheduledForUser.isNotEmpty) {
      final Map<String, List<String>> grouped = {};
      for (final rec in scheduledForUser) {
        final rid = rec['reminder_id']?.toString() ?? 'unknown';
        grouped.putIfAbsent(rid, () => []).add(rec['notify_at']?.toString() ?? '');
      }

      debugPrint('NortificationSetup: Scheduled ${scheduledForUser.length} notifications for $username');
      debugPrint('NortificationSetup: Detailed schedule:');
      for (final entry in grouped.entries) {
        debugPrint('Reminder ${entry.key}:');
        for (final ts in entry.value) {
          debugPrint('  - $ts');
        }
      }
    } else {
      debugPrint('NortificationSetup: No notifications scheduled for $username');
    }
  }

  // ------------ READ DATA (from SQLite) ------------

  /// อ่าน calendar_alerts จาก SQLite (กรองตาม createby = username)
  static Future<List<Map<String, dynamic>>> _readRemindersFor(
    String username,
  ) async {
    try {
      final dbHelper = DatabaseHelper();
      final rows = await dbHelper.getCalendarAlerts(username);
      // Map snake_case columns to camelCase keys used by _generateDoseTimes
      return rows.map<Map<String, dynamic>>((row) {
        return {
          'id': row['id'],
          'medicineName': row['medicine_name'] ?? '',
          'profileName': row['profile_name'] ?? '',
          'startDateTime': row['start_date_time'] ?? '',
          'endDateTime': row['end_date_time'] ?? '',
          'notifyByTime': (row['notify_by_time'] == 1) ? true : false,
          'intervalMinutes': row['interval_minutes'],
          'intervalHours': row['interval_hours'],
          'medicineBeforeMeal': row['medicine_before_meal'],
          'medicineAfterMeal': row['medicine_after_meal'],
          'createby': row['createby'],
        };
      }).toList();
    } catch (e) {
      debugPrint('NortificationSetup: read reminders from DB error $e');
      return [];
    }
  }

  /// อ่าน taken_doses จาก SQLite -> key = '$reminderId|$doseDateTimeIso'
  static Future<Set<String>> _readTakenKeysFor(String username) async {
    final keys = <String>{};
    try {
      final dbHelper = DatabaseHelper();
      final rows = await dbHelper.getTakenDoses(username);
      for (final row in rows) {
        final rid = row['reminder_id']?.toString();
        final doseStr = row['dose_date_time']?.toString();
        if (rid != null && doseStr != null && doseStr.isNotEmpty) {
          keys.add('$rid|$doseStr');
        }
      }
    } catch (e) {
      debugPrint('NortificationSetup: read taken doses from DB error $e');
    }
    return keys;
  }

  // ------------ GENERATE DOSE TIMES (ใช้ intervalMinutes) ------------

  /// สร้างเวลาทั้งหมดในช่วง [startFrom, until] จาก reminder
  /// ใช้ field: intervalMinutes (หน่วยนาที)
  /// ถ้าไม่มีให้ fallback จาก intervalHours * 60 เผื่อของเก่ายังหลงเหลือ
  static List<DateTime> _generateDoseTimes(
    Map<String, dynamic> r,
    DateTime startFrom,
    DateTime until,
  ) {
    final result = <DateTime>[];

    final startStr = r['startDateTime']?.toString();
    if (startStr == null || startStr.isEmpty) return result;
    final start = DateTime.tryParse(startStr);
    if (start == null) return result;

    final endStr = r['endDateTime']?.toString();
    final end = (endStr != null && endStr.isNotEmpty)
        ? DateTime.tryParse(endStr)
        : null;

    final notifyByTime = r['notifyByTime'] == true;

    // intervalMinutes ใหม่
    final intervalMinutesRaw = int.tryParse(
      r['intervalMinutes']?.toString() ?? '',
    );

    // fallback จาก intervalHours ถ้ายังมีใน JSON
    final intervalHoursRaw = int.tryParse(r['intervalHours']?.toString() ?? '');

    final intervalMinutes =
        intervalMinutesRaw ??
        ((intervalHoursRaw != null && intervalHoursRaw > 0)
            ? intervalHoursRaw * 60
            : 0);

    // ขอบเขตช่วงเวลาที่ใช้หาโดส
    final rangeStart = startFrom.isAfter(start) ? startFrom : start;
    final rangeEnd = end == null ? until : (until.isBefore(end) ? until : end);

    if (!notifyByTime || intervalMinutes <= 0) {
      // เคส "ครั้งเดียว" ตาม startDateTime
      if (!start.isBefore(rangeStart) && start.isBefore(rangeEnd)) {
        result.add(start);
      }
      return result;
    }

    // มี interval (นาที)
    final stepMinutes = intervalMinutes;
    if (stepMinutes <= 0) return result;

    // หาเวลาแรก >= rangeStart
    DateTime first;
    if (!rangeStart.isAfter(start)) {
      first = start;
    } else {
      final diffMinutes = rangeStart.difference(start).inMinutes;
      final steps = (diffMinutes / stepMinutes).ceil();
      first = start.add(Duration(minutes: steps * stepMinutes));
    }

    var t = first;
    while (!t.isAfter(rangeEnd)) {
      result.add(t);
      t = t.add(Duration(minutes: stepMinutes));
    }

    return result;
  }

  // ------------ NOTI HELPER ------------

  /// ทำ id ให้คงที่ต่อ "ครั้งที่แจ้ง" (user + reminder + key)
  static int _stableId(String user, String rid, String key) {
    final s = '$user|$rid|$key';
    return s.hashCode & 0x7fffffff;
  }

  static Future<void> _scheduleNotification({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required String soundName,
  }) async {
    // ใช้ channel ใหม่สำหรับเสียงที่เลือก
    final androidDetails = AndroidNotificationDetails(
      'pillmate_alarm_channel',
      'Pillmate Alarm',
      channelDescription: 'แจ้งเตือนเวลากินยาพร้อมเสียงปลุก',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound(soundName),
      fullScreenIntent: true,
      enableVibration: true,
      enableLights: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      sound: 'alarm.mp3', // iOS ใช้ไฟล์เดียว (ถ้าต้องการหลายไฟล์ต้อง copy ไปที่ bundle)
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final tzWhen = tz.TZDateTime.from(when, tz.local);

    try {
      await _flnp.zonedSchedule(
        id,
        title,
        body,
        tzWhen,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: null,
      );
      debugPrint('NortificationSetup: Scheduled notification $id at $when with sound $soundName');
    } catch (e) {
      debugPrint('NortificationSetup: Failed to schedule notification $id: $e');
    }
  }
}
