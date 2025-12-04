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
Future<Map<String, int>> _loadNotificationSettings() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/pillmate/appstatus.json');

    if (await file.exists()) {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      // ดึงค่าตาม Key ที่เราแก้ไขไปในขั้นตอนก่อนหน้า
      return {
        'snoozeDuration': (data['time_mode_snooze_duration'] as int? ?? 2),
        'repeatCount': (data['time_mode_repeat_count'] as int? ?? 1),
      };
    }
  } catch (e) {
    debugPrint('Error loading appstatus.json settings for notification: $e');
  }
  // Fallback to default (2 mins, 1 repeat)
  return {'snoozeDuration': 2, 'repeatCount': 1};
}

// 3. ฟังก์ชันหลักสำหรับตั้งเวลาแจ้งเตือน
void scheduleNotificationForNewAlert() async {
  debugPrint('\n=============================================================');
  debugPrint('🔔🔔🔔 NOTIFICATION SERVICE TRIGGERED! (ทำงานแล้วนะ) 🔔🔔🔔');

  // 3.1. โหลดค่าตั้งค่า
  final settings = await _loadNotificationSettings();
  final int snoozeDuration = settings['snoozeDuration']!; // 2 นาที
  final int repeatCount =
      settings['repeatCount']!; // 1 ครั้ง (รวมครั้งแรกเป็น 2)

  debugPrint(
    '--- Settings Loaded: Snooze $snoozeDuration mins, Repeat $repeatCount times ---',
  );

  // 3.2. กำหนดเวลาแจ้งเตือนเป้าหมาย: 10:25 AM Today (อัพเดตแล้ว)
  final DateTime now = DateTime.now();

  // สร้าง DateTime ของ 10:25 น. วันนี้
  DateTime targetTime = DateTime(
    now.year,
    now.month,
    now.day,
    10,
    29,
  ); // ✅ แก้เป็น 25 แล้ว

  // หาก 10:25 น. ได้ผ่านไปแล้ว (เพื่อป้องกันการแจ้งเตือนล้มเหลว) ให้เลื่อนไปเป็นพรุ่งนี้
  if (targetTime.isBefore(now)) {
    targetTime = targetTime.add(const Duration(days: 1));
    debugPrint(
      'Target time (10:25) has passed. Scheduling for tomorrow: $targetTime', // ✅ อัพเดตข้อความ
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
    final int notificationId = currentScheduleTime.millisecondsSinceEpoch;

    // รายละเอียดการแจ้งเตือน
    const NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'pillmate_id',
        'Pillmate Reminders',
        channelDescription: 'แจ้งเตือนการทานยา',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker',
        sound: RawResourceAndroidNotificationSound(
          '01_clock_alarm_normal_30_sec',
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

// **สิ่งที่ต้องทำเพิ่มเติม**:
// 1. เพิ่ม dependency ใน pubspec.yaml: flutter_local_notifications, timezone, path_provider
// 2. เรียกใช้ `initializeNotifications()` ใน main.dart ก่อน runApp()
// 3. ตรวจสอบว่า `01_clock_alarm_normal_30_sec.mp3` ถูกตั้งค่าเป็น Android Raw Resource ถูกต้อง
