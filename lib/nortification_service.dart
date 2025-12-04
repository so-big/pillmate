// lib/nortification_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
// ต้องเพิ่ม 2 package นี้ใน pubspec.yaml
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// 1. Initialize Plugin and Timezone
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Timezone location for scheduling (local)
late tz.Location local;

// ฟังก์ชันนี้ต้องถูกเรียกครั้งเดียวในตอนเริ่มต้นแอปฯ (เช่น ใน main.dart)
Future<void> initializeNotifications() async {
  // 1. Initialize Timezone
  tzdata.initializeTimeZones();
  try {
    local = tz.local;
  } catch (e) {
    debugPrint(
      'Error setting local timezone. Falling back to Asia/Bangkok: $e',
    );
    local = tz.getLocation('Asia/Bangkok');
  }

  // 2. Initialize platform specific settings
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  debugPrint('Notification Plugin Initialized: Timezone is ${local.name}');
}

// 2. Helper เพื่ออ่านค่าการตั้งค่าจาก appstatus.json
Future<Map<String, dynamic>> _loadNotificationSettings() async {
  // Default Raw Resource Name สำหรับเสียง Fallback
  const String defaultRawSoundName = '01_clock_alarm_normal_30_sec';

  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/pillmate/appstatus.json');

    if (await file.exists()) {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      // ⚠️ Note: ตอนนี้เราคาดหวังว่า time_mode_sound เป็นชื่อ Raw Resource ล้วนๆ
      String loadedSoundName =
          data['time_mode_sound']?.toString().toLowerCase() ??
          defaultRawSoundName;

      // ตรวจสอบความถูกต้องของชื่อ Raw Resource Name (ควรไม่มีนามสกุลและ Path)
      if (loadedSoundName.contains('.') || loadedSoundName.contains('/')) {
        debugPrint(
          'Warning: Loaded sound name contains invalid characters/path. Falling back to default.',
        );
        loadedSoundName = defaultRawSoundName;
      }

      return {
        'snoozeDuration': (data['time_mode_snooze_duration'] as int? ?? 2),
        'repeatCount': (data['time_mode_repeat_count'] as int? ?? 1),
        // ✅ ดึงชื่อ Raw Resource Name มาเลย
        'rawResourceName': loadedSoundName,
      };
    }
  } catch (e) {
    debugPrint('Error loading appstatus.json settings for notification: $e');
  }
  // Fallback to default (2 mins, 1 repeat) และ Raw Sound Name Default
  return {
    'snoozeDuration': 2,
    'repeatCount': 1,
    'rawResourceName': defaultRawSoundName,
  };
}

// 3. ฟังก์ชันหลักสำหรับตั้งเวลาแจ้งเตือน
void scheduleNotificationForNewAlert() async {
  debugPrint('\n=============================================================');
  debugPrint('🔔🔔🔔 NOTIFICATION SERVICE TRIGGERED! (ทำงานแล้วนะ) 🔔🔔🔔');

  // 3.1. โหลดค่าตั้งค่า (รองรับ dynamic)
  final settings = await _loadNotificationSettings();
  final int snoozeDuration = settings['snoozeDuration'] as int; // 2 นาที
  final int repeatCount =
      settings['repeatCount'] as int; // 1 ครั้ง (รวมครั้งแรกเป็น 2)
  final String rawResourceName =
      settings['rawResourceName'] as String; // ชื่อไฟล์เสียง Raw Resource

  debugPrint(
    '--- Settings Loaded: Snooze $snoozeDuration mins, Repeat $repeatCount times, Raw Sound: $rawResourceName ---',
  );

  // 3.2. กำหนดเวลาแจ้งเตือนเป้าหมาย: 10:43 AM Today
  final DateTime now = DateTime.now();

  // สร้าง DateTime ของ 10:43 น. วันนี้
  DateTime targetTime = DateTime(
    now.year,
    now.month,
    now.day,
    10,
    43, // ✅ แก้เป็น 43 แล้ว
  );

  // หาก 10:43 น. ได้ผ่านไปแล้ว (เพื่อป้องกันการแจ้งเตือนล้มเหลว) ให้เลื่อนไปเป็นพรุ่งนี้
  if (targetTime.isBefore(now)) {
    targetTime = targetTime.add(const Duration(days: 1));
    debugPrint(
      'Target time (10:43) has passed. Scheduling for tomorrow: $targetTime',
    );
  }

  // แปลงเป็น TimeZone object
  tz.TZDateTime scheduledTZTime = tz.TZDateTime.from(targetTime, local);

  // 3.3. ตั้งเวลาแจ้งเตือนตามลำดับ (i=0 คือครั้งแรก, i>0 คือการย้ำ)
  for (int i = 0; i <= repeatCount; i++) {
    // คำนวณเวลาแจ้งเตือนครั้งที่ i
    final tz.TZDateTime currentScheduleTime = scheduledTZTime.add(
      Duration(minutes: i * snoozeDuration),
    );

    // Safety check: ข้ามการตั้งเวลาถ้าเวลาผ่านไปแล้ว (ป้องกันการแจ้งเตือนทันทีในอดีต)
    if (currentScheduleTime.isBefore(tz.TZDateTime.now(local))) {
      debugPrint('Skipping past schedule: $currentScheduleTime');
      continue;
    }

    // ID ต้องไม่ซ้ำกัน
    // ใช้เวลาปัจจุบันของ currentScheduleTime เพื่อให้ ID ไม่ซ้ำกันในการวนลูป
    final int notificationId = currentScheduleTime.millisecondsSinceEpoch;

    // รายละเอียดการแจ้งเตือน
    final NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'pillmate_id',
        'Pillmate Reminders',
        channelDescription: 'แจ้งเตือนการทานยา',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
        sound: RawResourceAndroidNotificationSound(
          rawResourceName, // ✅ ใช้ตัวแปร Raw Resource Name ที่ดึงจาก JSON
        ),
      ),
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      notificationId,
      'ถึงเวลานัดทานยา! (ครั้งที่ ${i + 1})', // i=0 จะเป็นครั้งที่ 1
      'โปรดตรวจสอบยาที่ต้องทาน ณ เวลา ${currentScheduleTime.hour.toString().padLeft(2, '0')}:${currentScheduleTime.minute.toString().padLeft(2, '0')} (ย้ำทุก ${snoozeDuration} นาที)',
      currentScheduleTime,
      notificationDetails,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    debugPrint(
      'ตั้งแจ้งเตือน #$notificationId (ครั้งที่ ${i + 1}) ที่เวลา: $currentScheduleTime',
    );
  }

  debugPrint('=============================================================\n');
}

// **สิ่งที่ต้องทำเพิ่มเติมที่สำคัญ:**
// 1. เพิ่ม dependency ใน pubspec.yaml: flutter_local_notifications, timezone, path_provider
// 2. ⭐️ แก้ไข main.dart เพื่อแก้ไขข้อผิดพลาด LateInitializationError: ⭐️
//    ให้ไปที่ไฟล์ main.dart และเปลี่ยน main() เป็นแบบนี้:
/*
void main() async {
  WidgetsFlutterBinding.ensureInitialized(); 
  await initializeNotifications(); // ต้องรอให้เสร็จก่อน
  runApp(const MyApp());
}
*/
// 3. ตรวจสอบว่าไฟล์เสียงถูกวางใน android/app/src/main/res/raw/ และใช้ชื่อ Raw Resource Name ที่ถูกต้อง
