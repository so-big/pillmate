// lib/nortification_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:async'; // เพิ่มสำหรับการใช้ Stream

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart'; // ✅ สำคัญ: มาจากตัวอย่าง
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// 1. ประกาศ Plugin
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Stream สำหรับจัดการการกด Notification (ตามตัวอย่าง)
final StreamController<NotificationResponse> selectNotificationStream =
    StreamController<NotificationResponse>.broadcast();

// 2. ฟังก์ชัน Initialize หลัก (เรียกใน main.dart)
Future<void> initializeNotifications() async {
  // 2.1 ตั้งค่า Timezone ให้ถูกต้องตามตัวอย่างเป๊ะๆ
  await _configureLocalTimeZone();

  // 2.2 ตั้งค่า Android
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  // 2.3 ตั้งค่า iOS/macOS (ตามตัวอย่างแต่ตัดให้สั้นลงเท่าที่จำเป็น)
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

  // 2.4 Initialize Plugin
  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse:
        (NotificationResponse notificationResponse) {
          selectNotificationStream.add(notificationResponse);
        },
  );

  debugPrint('Notification Plugin Initialized & Timezone Configured');
}

// ✅ ฟังก์ชันตั้งค่า Timezone (คัดลอก Logic มาจากตัวอย่างที่ท่านให้)
Future<void> _configureLocalTimeZone() async {
  if (kIsWeb || Platform.isLinux) {
    return;
  }
  tzdata.initializeTimeZones();

  // ใช้ flutter_timezone ดึงค่า Timezone ของเครื่องจริงๆ
  final String timeZoneName = await FlutterTimezone.getLocalTimezone();

  // Set ค่า local location ให้ระบบรู้ว่าตอนนี้อยู่ Timezone ไหน
  tz.setLocalLocation(tz.getLocation(timeZoneName));
  debugPrint('Local Timezone set to: $timeZoneName');
}

// Helper อ่านค่า settings (เหมือนเดิม)
Future<Map<String, dynamic>> _loadNotificationSettings() async {
  const String defaultRawSoundName = '01_clock_alarm_normal_30_sec';
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

// 3. ฟังก์ชันหลักสำหรับตั้งแจ้งเตือน
void scheduleNotificationForNewAlert() async {
  debugPrint('\n=============================================================');
  debugPrint('🔔🔔🔔 NOTIFICATION SERVICE TRIGGERED! (FIXED VERSION) 🔔🔔🔔');

  // โหลด Settings
  final settings = await _loadNotificationSettings();
  final int snoozeDuration = settings['snoozeDuration'] as int;
  final int repeatCount = settings['repeatCount'] as int;
  // ใช้เสียง default ก่อนเพื่อทดสอบความชัวร์ (ถ้าอยากใช้ custom ให้แก้ตรงนี้)
  // final String rawResourceName = settings['rawResourceName'] as String;

  // ✅ ใช้ tz.TZDateTime.now(tz.local) ตามตัวอย่าง เพื่อให้ได้เวลาปัจจุบันที่ถูกต้องแน่นอน
  final tz.TZDateTime now = tz.TZDateTime.now(tz.local);

  // ตั้งเป้าหมาย 11:03 ของวันนี้
  tz.TZDateTime targetTime = tz.TZDateTime(
    tz.local,
    now.year,
    now.month,
    now.day,
    11,
    3,
  );

  debugPrint('Current Time (Local): $now');
  debugPrint('Initial Target Time: $targetTime');

  // ⭐️ LOGIC ทดสอบ: ถ้าเลยเวลาแล้ว ให้ตั้งเตือนในอีก 5 วินาที ⭐️
  if (targetTime.isBefore(now)) {
    targetTime = now.add(const Duration(seconds: 5));
    debugPrint(
      '>>> Time passed! Rescheduling for 5 seconds from now: $targetTime',
    );
  } else {
    debugPrint('>>> Scheduling for today at: $targetTime');
  }

  for (int i = 0; i <= repeatCount; i++) {
    final tz.TZDateTime currentScheduleTime = targetTime.add(
      Duration(minutes: i * snoozeDuration),
    );

    // เช็คว่าเวลายังไม่ผ่านไป (เผื่อ Loop)
    if (currentScheduleTime.isBefore(now)) {
      continue;
    }

    // ✅ แก้ ID overflow ตามหลักการ Bitwise
    final int notificationId =
        (currentScheduleTime.millisecondsSinceEpoch ~/ 1000) & 0x7FFFFFFF;

    final NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'pillmate_id',
        'Pillmate Reminders',
        channelDescription: 'แจ้งเตือนการทานยา',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
        // sound: RawResourceAndroidNotificationSound(rawResourceName), // เปิดบรรทัดนี้ถ้าจะใช้เสียง Custom
      ),
    );

    try {
      // ✅ ใช้ zonedSchedule ตามตัวอย่าง
      await flutterLocalNotificationsPlugin.zonedSchedule(
        notificationId,
        'ถึงเวลานัดทานยา! (ครั้งที่ ${i + 1})',
        'ทดสอบแจ้งเตือนเวลา ${currentScheduleTime.hour}:${currentScheduleTime.minute.toString().padLeft(2, '0')}:${currentScheduleTime.second}',
        currentScheduleTime,
        notificationDetails,
        // ✅ ตั้งค่าตามตัวอย่าง: absoluteTime และ exactAllowWhileIdle
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

      debugPrint('✅ Scheduled ID:$notificationId at $currentScheduleTime');
    } catch (e) {
      debugPrint('❌ Error scheduling notification: $e');
    }
  }
  debugPrint('=============================================================\n');
}
