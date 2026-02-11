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

/// Notification strategy type.
enum NotifyStrategy { typeA, typeB }

class NortificationSetup {
  NortificationSetup._();

  static final FlutterLocalNotificationsPlugin _flnp =
      FlutterLocalNotificationsPlugin();

  // ------------ FILE HELPERS ------------

  static Future<Directory> _appDir() async =>
      await getApplicationDocumentsDirectory();

  static Future<File> _settingsFile() async =>
      File('${(await _appDir()).path}/nortification_setting.json');

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
    try {
      return await FlutterTimezone.getLocalTimezone();
    } catch (e) {
      debugPrint('NortificationSetup: Failed to get timezone, falling back to Asia/Bangkok: $e');
      return 'Asia/Bangkok';
    }
  }

  // ------------ READ SETTINGS (from DB with JSON fallback) ------------

  static Future<({int advance, int after, int playDuration, int gap})>
  _readSettings() async {
    try {
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
            String? soundPath = data['time_mode_sound']?.toString();
            String soundName = 'alarm';
            if (soundPath != null && soundPath.isNotEmpty) {
              final parts = soundPath.split('/').last.split('.');
              if (parts.isNotEmpty) {
                soundName = parts.first.toLowerCase();
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

  // ------------ STRATEGY SELECTOR ------------

  /// Determine which strategy is active. Reads from app_settings DB.
  /// Defaults to TYPE_B (meal-based) if not set.
  static Future<NotifyStrategy> _getActiveStrategy() async {
    try {
      final dbHelper = DatabaseHelper();
      final strategyStr = await dbHelper.getSetting('notification_strategy');
      if (strategyStr == 'TYPE_A') return NotifyStrategy.typeA;
      if (strategyStr == 'TYPE_B') return NotifyStrategy.typeB;
    } catch (e) {
      debugPrint('NortificationSetup: read strategy error $e');
    }
    return NotifyStrategy.typeB; // default: meal-based
  }

  // ==========================================================================
  // ENTRY POINT — ใช้ Strategy Pattern เลือก Type A หรือ Type B
  // ==========================================================================

  /// Main entry point — เรียกจาก Dashboard.
  /// Auto-selects strategy based on app_settings.notification_strategy
  static Future<void> run({
    required BuildContext context,
    required String username,
  }) async {
    final strategy = await _getActiveStrategy();
    debugPrint('NortificationSetup: Active strategy = ${strategy.name}');

    switch (strategy) {
      case NotifyStrategy.typeA:
        await _runTypeA(username: username);
        break;
      case NotifyStrategy.typeB:
        await _runTypeB(username: username);
        break;
    }
  }

  // ==========================================================================
  // TYPE A — Legacy / Stress-Test Mode
  // (5× repeat multiplier, min 24h duration, interval-based)
  // ==========================================================================

  static Future<void> _runTypeA({required String username}) async {
    await _initializePluginIfNeeded();

    try {
      await _flnp.cancelAll();
    } catch (e) {
      debugPrint('NortificationSetup: cancelAll error $e');
    }

    final dbHelper = DatabaseHelper();
    await dbHelper.clearScheduledNotifications(username);

    final reminders = await _readRemindersFor(username);
    final takenKeys = await _readTakenKeysFor(username);
    final settings = await _readSettings();

    final soundSettings = await _readSoundSettings();
    final soundName = (soundSettings['soundName'] as String?) ?? 'alarm';
    final int repeatCount = (soundSettings['repeatCount'] as int?) ?? 3;
    final int snoozeDuration = (soundSettings['snoozeDuration'] as int?) ?? 5;

    final now = DateTime.now();
    final scheduledForUser = <Map<String, dynamic>>[];

    for (final r in reminders) {
      final String reminderId = r['id']?.toString() ?? '';
      if (reminderId.isEmpty) continue;

      final until = now.add(const Duration(days: 30));
      final allDoseTimes = _generateDoseTimes(r, now, until);

      final List<String> timestampsForReminder = [];

      final int thresholdCount = 5 * repeatCount;
      final Duration thresholdDuration = const Duration(hours: 24);

      DateTime? firstScheduledForThisReminder;
      DateTime? lastScheduledForThisReminder;
      int totalAlertsForThisReminder = 0;

      for (final doseTime in allDoseTimes) {
        final doseIso = doseTime.toIso8601String();
        final key = '$reminderId|$doseIso';
        if (takenKeys.contains(key)) continue;

        final windowStart = doseTime.subtract(Duration(minutes: settings.advance));
        final windowEnd = doseTime.add(Duration(minutes: settings.after));

        var candidate = windowStart.isAfter(now) ? windowStart : now;

        int perDoseCounter = 0;
        while (perDoseCounter < repeatCount && !candidate.isAfter(windowEnd)) {
          final notifyTime = candidate;

          final id = _stableId(username, reminderId, '$doseIso|${notifyTime.toIso8601String()}|$perDoseCounter');

          final medName = r['medicineName']?.toString() ?? 'ถึงเวลากินยา';
          final profileName = r['profileName']?.toString() ?? username;
          final mealTiming = ((r['medicineBeforeMeal'] == true) || (r['medicineBeforeMeal']?.toString() == '1'))
              ? 'Before Meal'
              : (((r['medicineAfterMeal'] == true) || (r['medicineAfterMeal']?.toString() == '1')) ? 'After Meal' : '');
          final scheduledTimeStr = DateTime.parse(doseIso).toLocal();
          final scheduledTimeFormatted = '${scheduledTimeStr.hour.toString().padLeft(2, '0')}:${scheduledTimeStr.minute.toString().padLeft(2, '0')}';
          final currentCount = perDoseCounter + 1;

          final body = '"$profileName", it is time to take "$medName" ($mealTiming). Alert $currentCount/$repeatCount for scheduled time $scheduledTimeFormatted.';
          final title = '$profileName — Reminder [TYPE_A]';

          await _scheduleNotification(
            id: id,
            when: notifyTime,
            title: title,
            body: body,
            soundName: soundName,
          );

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

          totalAlertsForThisReminder += 1;
          firstScheduledForThisReminder ??= notifyTime;
          lastScheduledForThisReminder = notifyTime;

          perDoseCounter += 1;
          candidate = candidate.add(Duration(minutes: snoozeDuration));

          final durationSpan = lastScheduledForThisReminder.difference(firstScheduledForThisReminder!);
          if (totalAlertsForThisReminder >= thresholdCount && durationSpan >= thresholdDuration) {
            break;
          }
        }

        if (totalAlertsForThisReminder >= thresholdCount && lastScheduledForThisReminder != null && lastScheduledForThisReminder.difference(firstScheduledForThisReminder ?? lastScheduledForThisReminder) >= thresholdDuration) {
          break;
        }
      }

      if (timestampsForReminder.isNotEmpty) {
        debugPrint('NortificationSetup [TYPE_A]: Reminder $reminderId scheduled ${timestampsForReminder.length} alerts');
        for (final t in timestampsForReminder) {
          debugPrint('  - $t');
        }
      }
    }

    for (final record in scheduledForUser) {
      await dbHelper.insertScheduledNotification(record);
    }

    debugPrint('NortificationSetup [TYPE_A]: Total ${scheduledForUser.length} notifications for $username');
  }

  // ==========================================================================
  // TYPE B — Meal-Based / 48h Forecast Mode
  // (Breakfast/Lunch/Dinner/Bedtime slots, 15min before/after, max 2 repeats)
  // ==========================================================================

  /// Read the user's meal times from the DB.
  /// Returns a map with keys: breakfast, lunch, dinner, bedtime, isBedtimeEnabled.
  static Future<Map<String, dynamic>> _readUserMealTimes(String username) async {
    try {
      final dbHelper = DatabaseHelper();
      final user = await dbHelper.getUser(username);
      if (user != null) {
        return {
          'breakfast': (user['breakfast'] ?? '06:00').toString(),
          'lunch': (user['lunch'] ?? '12:00').toString(),
          'dinner': (user['dinner'] ?? '18:00').toString(),
          'bedtime': (user['bedtime'] ?? '22:00').toString(),
          'isBedtimeEnabled': (user['is_bedtime_enabled'] == 1 || user['is_bedtime_enabled'] == true),
        };
      }
    } catch (e) {
      debugPrint('NortificationSetup: read meal times error $e');
    }
    return {
      'breakfast': '06:00',
      'lunch': '12:00',
      'dinner': '18:00',
      'bedtime': '22:00',
      'isBedtimeEnabled': false,
    };
  }

  /// Parse "HH:mm" string into DateTime on the given day.
  static DateTime _timeOnDay(DateTime day, String hhMm) {
    final parts = hhMm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(day.year, day.month, day.day, h, m);
  }

  static Future<void> _runTypeB({required String username}) async {
    await _initializePluginIfNeeded();

    try {
      await _flnp.cancelAll();
    } catch (e) {
      debugPrint('NortificationSetup: cancelAll error $e');
    }

    final dbHelper = DatabaseHelper();
    await dbHelper.clearScheduledNotifications(username);

    // Read user's meal times from DB
    final mealTimes = await _readUserMealTimes(username);
    final String breakfastTime = mealTimes['breakfast'] as String;
    final String lunchTime = mealTimes['lunch'] as String;
    final String dinnerTime = mealTimes['dinner'] as String;
    final String bedtimeTime = mealTimes['bedtime'] as String;
    final bool isBedtimeEnabled = mealTimes['isBedtimeEnabled'] as bool;

    // Read reminders, taken doses, sound settings
    final reminders = await _readRemindersFor(username);
    final takenKeys = await _readTakenKeysFor(username);
    final soundSettings = await _readSoundSettings();
    final soundName = (soundSettings['soundName'] as String?) ?? 'alarm';

    // TYPE_B constants
    const int maxRepeats = 2; // max 2 repeat alerts per slot
    const int repeatIntervalMin = 3; // 3-minute interval between repeats
    const int beforeMealMinutes = 15; // 15 min before meal
    const int afterMealMinutes = 15; // 15 min after meal
    const int forecastHours = 48; // 48h forecast window

    final now = DateTime.now();
    final forecastEnd = now.add(const Duration(hours: forecastHours));
    final scheduledForUser = <Map<String, dynamic>>[];

    debugPrint('NortificationSetup [TYPE_B]: Scheduling for $username');
    debugPrint('NortificationSetup [TYPE_B]: Meal times — Breakfast: $breakfastTime, Lunch: $lunchTime, Dinner: $dinnerTime, Bedtime: $bedtimeTime (enabled: $isBedtimeEnabled)');
    debugPrint('NortificationSetup [TYPE_B]: Forecast window: $now → $forecastEnd');

    for (final r in reminders) {
      final String reminderId = r['id']?.toString() ?? '';
      if (reminderId.isEmpty) continue;

      final medName = r['medicineName']?.toString() ?? 'ถึงเวลากินยา';
      final profileName = r['profileName']?.toString() ?? username;
      final bool isBeforeMeal = ((r['medicineBeforeMeal'] == true) || (r['medicineBeforeMeal']?.toString() == '1'));
      final bool isAfterMeal = ((r['medicineAfterMeal'] == true) || (r['medicineAfterMeal']?.toString() == '1'));
      final String mealTiming = isBeforeMeal ? 'Before Meal' : (isAfterMeal ? 'After Meal' : '');

      // Medicine properties/detail for the notification body
      final String medicineDetail = r['medicineDetail']?.toString() ?? '';

      final List<String> timestampsForReminder = [];

      // Generate meal-slot dose times for 48h (today and tomorrow)
      DateTime day = DateTime(now.year, now.month, now.day);
      while (day.isBefore(forecastEnd)) {
        // Build list of meal slots for this day
        final List<({String slot, DateTime mealTime})> slots = [
          (slot: 'Breakfast', mealTime: _timeOnDay(day, breakfastTime)),
          (slot: 'Lunch', mealTime: _timeOnDay(day, lunchTime)),
          (slot: 'Dinner', mealTime: _timeOnDay(day, dinnerTime)),
        ];
        if (isBedtimeEnabled) {
          slots.add((slot: 'Bedtime', mealTime: _timeOnDay(day, bedtimeTime)));
        }

        for (final (:slot, :mealTime) in slots) {
          // Determine the actual notification anchor time
          // Before Meal: notify at (mealTime - beforeMealMinutes)
          // After Meal: notify at (mealTime + afterMealMinutes)
          // Bedtime: always AT mealTime or BEFORE (never after)
          DateTime anchorTime;
          if (slot == 'Bedtime') {
            // Bedtime: only AT or BEFORE
            anchorTime = isBeforeMeal
                ? mealTime.subtract(Duration(minutes: beforeMealMinutes))
                : mealTime; // AT bedtime if not "before meal"
          } else {
            if (isBeforeMeal) {
              anchorTime = mealTime.subtract(Duration(minutes: beforeMealMinutes));
            } else if (isAfterMeal) {
              anchorTime = mealTime.add(Duration(minutes: afterMealMinutes));
            } else {
              anchorTime = mealTime; // default: AT meal time
            }
          }

          // Skip if anchor is in the past or beyond forecast
          if (anchorTime.isBefore(now) || anchorTime.isAfter(forecastEnd)) continue;

          // Check if this dose was already taken
          final doseIso = mealTime.toIso8601String();
          final key = '$reminderId|$doseIso';
          if (takenKeys.contains(key)) continue;

          final slotTimeFormatted = '${mealTime.hour.toString().padLeft(2, '0')}:${mealTime.minute.toString().padLeft(2, '0')}';

          // Schedule up to maxRepeats alerts
          for (int rep = 0; rep < maxRepeats; rep++) {
            final notifyTime = anchorTime.add(Duration(minutes: rep * repeatIntervalMin));
            if (notifyTime.isAfter(forecastEnd)) break;

            final id = _stableId(username, reminderId, '${slot}_${doseIso}_$rep');
            final currentCount = rep + 1;

            String body = '"$profileName", it is time to take "$medName" ($mealTiming). '
                'Alert $currentCount/$maxRepeats for $slot at $slotTimeFormatted.';
            if (medicineDetail.isNotEmpty) {
              body += '\n📋 $medicineDetail';
            }

            final title = '$profileName — $slot Reminder';

            await _scheduleNotification(
              id: id,
              when: notifyTime,
              title: title,
              body: body,
              soundName: soundName,
            );

            scheduledForUser.add({
              'notification_id': id,
              'username': username,
              'reminder_id': reminderId,
              'dose_time': doseIso,
              'notify_at': notifyTime.toIso8601String(),
              'created_at': DateTime.now().toIso8601String(),
              'canceled': 0,
            });

            timestampsForReminder.add('[$slot] ${notifyTime.toIso8601String()}');
          }
        }

        day = day.add(const Duration(days: 1));
      }

      if (timestampsForReminder.isNotEmpty) {
        debugPrint('NortificationSetup [TYPE_B]: Reminder $reminderId ($medName) — ${timestampsForReminder.length} alerts:');
        for (final t in timestampsForReminder) {
          debugPrint('  - $t');
        }
      }
    }

    // Save all to DB
    for (final record in scheduledForUser) {
      await dbHelper.insertScheduledNotification(record);
    }

    debugPrint('NortificationSetup [TYPE_B]: Total ${scheduledForUser.length} notifications for $username');
  }

  // ------------ READ DATA (from SQLite) ------------

  static Future<List<Map<String, dynamic>>> _readRemindersFor(
    String username,
  ) async {
    try {
      final dbHelper = DatabaseHelper();
      final rows = await dbHelper.getCalendarAlerts(username);
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
          'medicineDetail': row['medicine_detail'] ?? '',
          'createby': row['createby'],
        };
      }).toList();
    } catch (e) {
      debugPrint('NortificationSetup: read reminders from DB error $e');
      return [];
    }
  }

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

  // ------------ GENERATE DOSE TIMES (ใช้ intervalMinutes — for TYPE_A) ------------

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

    final intervalMinutesRaw = int.tryParse(
      r['intervalMinutes']?.toString() ?? '',
    );
    final intervalHoursRaw = int.tryParse(r['intervalHours']?.toString() ?? '');

    final intervalMinutes =
        intervalMinutesRaw ??
        ((intervalHoursRaw != null && intervalHoursRaw > 0)
            ? intervalHoursRaw * 60
            : 0);

    final rangeStart = startFrom.isAfter(start) ? startFrom : start;
    final rangeEnd = end == null ? until : (until.isBefore(end) ? until : end);

    if (!notifyByTime || intervalMinutes <= 0) {
      if (!start.isBefore(rangeStart) && start.isBefore(rangeEnd)) {
        result.add(start);
      }
      return result;
    }

    final stepMinutes = intervalMinutes;
    if (stepMinutes <= 0) return result;

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
      styleInformation: BigTextStyleInformation(body),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      sound: 'alarm.mp3',
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
      debugPrint('NortificationSetup: Scheduled #$id at $when [$soundName]');
    } catch (e) {
      debugPrint('NortificationSetup: Failed to schedule #$id: $e');
    }
  }

  // ==========================================================================
  // SIMULATION — JSON output of TYPE_B for testing / debugging
  // ==========================================================================

  /// Generate a JSON simulation of TYPE_B notifications for a user over 48h.
  /// This does NOT actually schedule anything — just returns the plan as JSON.
  static Future<String> simulateTypeB({
    required String username,
    DateTime? simulationStart,
  }) async {
    final mealTimes = await _readUserMealTimes(username);
    final String breakfastTime = mealTimes['breakfast'] as String;
    final String lunchTime = mealTimes['lunch'] as String;
    final String dinnerTime = mealTimes['dinner'] as String;
    final String bedtimeTime = mealTimes['bedtime'] as String;
    final bool isBedtimeEnabled = mealTimes['isBedtimeEnabled'] as bool;

    final reminders = await _readRemindersFor(username);
    final takenKeys = await _readTakenKeysFor(username);

    const int maxRepeats = 2;
    const int repeatIntervalMin = 3;
    const int beforeMealMinutes = 15;
    const int afterMealMinutes = 15;
    const int forecastHours = 48;

    final now = simulationStart ?? DateTime.now();
    final forecastEnd = now.add(const Duration(hours: forecastHours));

    final simulation = <Map<String, dynamic>>[];

    for (final r in reminders) {
      final String reminderId = r['id']?.toString() ?? '';
      if (reminderId.isEmpty) continue;

      final medName = r['medicineName']?.toString() ?? '';
      final profileName = r['profileName']?.toString() ?? username;
      final bool isBeforeMeal = ((r['medicineBeforeMeal'] == true) || (r['medicineBeforeMeal']?.toString() == '1'));
      final bool isAfterMeal = ((r['medicineAfterMeal'] == true) || (r['medicineAfterMeal']?.toString() == '1'));
      final String mealTiming = isBeforeMeal ? 'Before Meal' : (isAfterMeal ? 'After Meal' : '');

      DateTime day = DateTime(now.year, now.month, now.day);
      while (day.isBefore(forecastEnd)) {
        final List<({String slot, DateTime mealTime})> slots = [
          (slot: 'Breakfast', mealTime: _timeOnDay(day, breakfastTime)),
          (slot: 'Lunch', mealTime: _timeOnDay(day, lunchTime)),
          (slot: 'Dinner', mealTime: _timeOnDay(day, dinnerTime)),
        ];
        if (isBedtimeEnabled) {
          slots.add((slot: 'Bedtime', mealTime: _timeOnDay(day, bedtimeTime)));
        }

        for (final (:slot, :mealTime) in slots) {
          DateTime anchorTime;
          if (slot == 'Bedtime') {
            anchorTime = isBeforeMeal
                ? mealTime.subtract(Duration(minutes: beforeMealMinutes))
                : mealTime;
          } else {
            if (isBeforeMeal) {
              anchorTime = mealTime.subtract(Duration(minutes: beforeMealMinutes));
            } else if (isAfterMeal) {
              anchorTime = mealTime.add(Duration(minutes: afterMealMinutes));
            } else {
              anchorTime = mealTime;
            }
          }

          if (anchorTime.isBefore(now) || anchorTime.isAfter(forecastEnd)) continue;

          final doseIso = mealTime.toIso8601String();
          final key = '$reminderId|$doseIso';
          if (takenKeys.contains(key)) continue;

          final slotTimeFormatted = '${mealTime.hour.toString().padLeft(2, '0')}:${mealTime.minute.toString().padLeft(2, '0')}';

          for (int rep = 0; rep < maxRepeats; rep++) {
            final notifyTime = anchorTime.add(Duration(minutes: rep * repeatIntervalMin));
            if (notifyTime.isAfter(forecastEnd)) break;

            simulation.add({
              'profile': profileName,
              'medicine': medName,
              'meal_slot': slot,
              'meal_time': slotTimeFormatted,
              'meal_timing': mealTiming,
              'notify_at': notifyTime.toIso8601String(),
              'alert': '${rep + 1}/$maxRepeats',
              'day': '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
            });
          }
        }

        day = day.add(const Duration(days: 1));
      }
    }

    final output = {
      'strategy': 'TYPE_B',
      'username': username,
      'simulation_start': now.toIso8601String(),
      'forecast_end': forecastEnd.toIso8601String(),
      'meal_times': mealTimes,
      'total_notifications': simulation.length,
      'notifications': simulation,
    };

    return const JsonEncoder.withIndent('  ').convert(output);
  }
}
