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
      await androidImpl?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('NortificationSetup: requestNotificationsPermission error $e');
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

  // ------------ ENTRY POINT (เรียกจาก Dashboard) ------------

  /// core: ล้าง noti เดิมทั้งหมด แล้วตั้ง noti ใหม่ให้ user นี้ล่วงหน้า 2 วัน
  static Future<void> run({
    required BuildContext context,
    required String username,
  }) async {
    await _initializePluginIfNeeded();

    // 1) ล้าง notification ทั้งหมดของแอป (ทุก user)
    try {
      await _flnp.cancelAll();
    } catch (e) {
      debugPrint('NortificationSetup: cancelAll error $e');
    }

    // 2) อ่าน reminders / eated / settings
    final reminders = await _readRemindersFor(username);
    final takenKeys = await _readTakenKeysFor(username);
    final settings = await _readSettings();

    final now = DateTime.now();
    // ลดจาก 7 วันเหลือ 2 วัน ตามที่นายบ่น
    final until = now.add(const Duration(days: 2));

    final scheduledForUser = <ScheduledNotify>[];

    for (final r in reminders) {
      final String reminderId = r['id']?.toString() ?? '';
      if (reminderId.isEmpty) continue;

      final times = _generateDoseTimes(r, now, until);
      for (final doseTime in times) {
        final doseIso = doseTime.toIso8601String();
        final key = '$reminderId|$doseIso';

        // ถ้าโดสนี้กินไปแล้วจาก eated.json ก็ไม่ต้องตั้ง noti
        if (takenKeys.contains(key)) {
          continue;
        }

        // หน้าต่างการแจ้งเตือน: [dose - advance, dose + after]
        final windowStart = doseTime.subtract(
          Duration(minutes: settings.advance),
        );
        final windowEnd = doseTime.add(Duration(minutes: settings.after));

        // ถ้าหน้าต่างหมดอายุไปแล้วทั้งก้อน ก็ข้าม
        if (windowEnd.isBefore(now)) continue;

        // เริ่มแจ้งจาก max(now, windowStart)
        final firstNotify = windowStart.isAfter(now) ? windowStart : now;

        final gapMinutes = settings.gap <= 0 ? 5 : settings.gap;

        var current = firstNotify;
        while (!current.isAfter(windowEnd)) {
          final notifyIso = current.toIso8601String();

          // id ไม่ซ้ำต่อ "ครั้งที่ยิง" (dose + เวลา)
          final id = _stableId(username, reminderId, '$doseIso|$notifyIso');

          final medName = r['medicineName']?.toString() ?? 'ถึงเวลากินยา';
          final profileName = r['profileName']?.toString() ?? username;

          await _scheduleNotification(
            id: id,
            when: current,
            title: 'เตือนกินยา ($profileName)',
            body: medName,
          );

          scheduledForUser.add(
            ScheduledNotify(
              userid: username,
              reminderId: reminderId,
              doseDateTime: doseIso,
              notifyAt: notifyIso,
              notificationId: id,
            ),
          );

          current = current.add(Duration(minutes: gapMinutes));
        }
      }
    }

    // 3) เขียน pillmate/nortification_setup.json ใหม่ (log เฉพาะของ user ปัจจุบัน)
    try {
      final file = await _setupFile();
      await file.writeAsString(
        jsonEncode(scheduledForUser.map((e) => e.toJson()).toList()),
        flush: true,
      );
    } catch (e) {
      debugPrint('NortificationSetup: write setup file error $e');
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
  }) async {
    // ใช้ channel ใหม่สำหรับเสียง alarm.mp3
    const androidDetails = AndroidNotificationDetails(
      'pillmate_alarm_channel',
      'Pillmate Alarm',
      channelDescription: 'แจ้งเตือนเวลากินยาพร้อมเสียงปลุก',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alarm'),
      fullScreenIntent: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final tzWhen = tz.TZDateTime.from(when, tz.local);

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
  }
}
