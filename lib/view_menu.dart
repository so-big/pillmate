// lib/view_menu.dart

import 'dart:convert';
import 'package:flutter/material.dart';

// ใช้ยิง noti ทดสอบ
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Database Helper
import 'database_helper.dart';

// หน้า setting การแจ้งเตือน
import 'nortification_setting.dart';

// ตัวแปรเทสต์แจ้งเตือน
int norti_test = 1; // 1 = ให้ดังตอนกดเทสต์, 0 = ปิด

// ---------- ส่วนสำหรับทดสอบแจ้งเตือน (เฉพาะเมนูนี้) ----------

final FlutterLocalNotificationsPlugin _testNotiPlugin =
    FlutterLocalNotificationsPlugin();

bool _testNotiInitialized = false;

Future<void> _initTestNotifications() async {
  if (_testNotiInitialized) return;

  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings = InitializationSettings(
    android: androidInit,
  );

  await _testNotiPlugin.initialize(initSettings);

  try {
    final androidImpl = _testNotiPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();
  } catch (e) {
    debugPrint('LeftMenu: requestNotificationsPermission error: $e');
  }

  _testNotiInitialized = true;
}

Future<void> _showTestAlarm() async {
  await _initTestNotifications();

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'pillmate_alarm_test', // channel สำหรับ test
    'Pillmate Alarm Test',
    channelDescription: 'ทดสอบเสียงแจ้งเตือนแบบนาฬิกาปลุก',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('alarm'),
    fullScreenIntent: true,
  );

  const NotificationDetails details = NotificationDetails(
    android: androidDetails,
  );

  await _testNotiPlugin.show(
    9999,
    'ทดสอบเสียงแจ้งเตือน',
    'เสียงนี้คือทดสอบแจ้งเตือนแบบนาฬิกาปลุก',
    details,
  );
}

// -----------------------------------------------------------

class LeftMenu extends StatefulWidget {
  final String username;

  final VoidCallback
  onShowDashboard; // เมนูใหม่: จัดการกำหนดการรายวัน (Dashboard)
  final VoidCallback onManageCalendar; // จัดการปฏิทินแจ้งเตือน (Calendar)
  final VoidCallback onCreateProfile; // เพิ่มโปรไฟล์
  final VoidCallback onmanage_profile; // จัดการโปรไฟล์

  final VoidCallback onAddMedicine; // เพิ่มยา
  final VoidCallback onManageMedicine; // จัดการยา

  final VoidCallback onLogout; // ออกจากระบบ

  const LeftMenu({
    super.key,
    required this.username,
    required this.onShowDashboard, // รับค่า callback สำหรับ dashboard
    required this.onManageCalendar,
    required this.onCreateProfile,
    required this.onmanage_profile,
    required this.onAddMedicine,
    required this.onManageMedicine,
    required this.onLogout,
  });

  @override
  State<LeftMenu> createState() => _LeftMenuState();
}

class _LeftMenuState extends State<LeftMenu> {
  String? _imageBase64;

  @override
  void initState() {
    super.initState();
    _loadUserImage();
  }

  // แก้ไข: ดึงรูปภาพจาก Database (คอลัมน์ image_base64)
  Future<void> _loadUserImage() async {
    try {
      final dbHelper = DatabaseHelper();
      final userMap = await dbHelper.getUser(widget.username);

      if (userMap != null) {
        // ✅ แก้ไข: ใช้ชื่อคอลัมน์ 'image_base64' ให้ถูกต้อง
        final img = userMap['image_base64'];

        if (img != null && img.toString().isNotEmpty) {
          setState(() {
            _imageBase64 = img.toString();
          });
        }
      }
    } catch (e) {
      debugPrint('LeftMenu: error loading user image from DB: $e');
      // ถ้า error ก็ปล่อยไป ใช้ default avatar แทน
    }
  }

  Widget _buildAvatar() {
    if (_imageBase64 == null || _imageBase64!.isEmpty) {
      return const CircleAvatar(
        backgroundColor: Colors.white,
        child: Icon(Icons.person, color: Colors.teal, size: 32),
      );
    }

    try {
      final bytes = base64Decode(_imageBase64!);
      return CircleAvatar(
        backgroundColor: Colors.white,
        backgroundImage: MemoryImage(bytes),
      );
    } catch (e) {
      debugPrint('LeftMenu: error decoding base64 image: $e');
      return const CircleAvatar(
        backgroundColor: Colors.white,
        child: Icon(Icons.person, color: Colors.teal, size: 32),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Colors.teal),
            accountName: Text(
              widget.username,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            accountEmail: const Text('Pillmate User'),
            currentAccountPicture: _buildAvatar(),
          ),

          // ทำเลื่อนเผื่อเมนูยาว
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // เมนูใหม่ 1: จัดการกำหนดการรายวัน (ไปหน้า Dashboard)
                ListTile(
                  leading: const Icon(Icons.dashboard),
                  title: const Text(
                    'จัดการกำหนดการรายวัน',
                    style: TextStyle(color: Colors.black),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onShowDashboard();
                  },
                ),

                // ลบ Divider ออกเพื่อให้เป็นกลุ่มเดียวกับปฏิทิน

                // เมนู 2: จัดการปฏิทินแจ้งเตือน (ไปหน้า Calendar)
                ListTile(
                  leading: const Icon(Icons.calendar_month),
                  title: const Text(
                    'จัดการปฏิทินแจ้งเตือน',
                    style: TextStyle(color: Colors.black),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onManageCalendar();
                  },
                ),

                const Divider(height: 1), // จบหมวดการจัดการเวลา
                // เมนู 3: เพิ่มยา
                ListTile(
                  leading: const Icon(Icons.medication),
                  title: const Text(
                    'เพิ่มยา',
                    style: TextStyle(color: Colors.black),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onAddMedicine();
                  },
                ),

                // เมนู 4: จัดการยา
                ListTile(
                  leading: const Icon(Icons.medication_liquid),
                  title: const Text(
                    'จัดการยา',
                    style: TextStyle(color: Colors.black),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onManageMedicine();
                  },
                ),

                const Divider(height: 1), // จบหมวดยา
                // เมนู 5: เพิ่มโปรไฟล์
                ListTile(
                  leading: const Icon(Icons.person_add),
                  title: const Text(
                    'เพิ่มโปรไฟล์',
                    style: TextStyle(color: Colors.black),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onCreateProfile();
                  },
                ),

                // เมนู 6: จัดการโปรไฟล์
                ListTile(
                  leading: const Icon(Icons.manage_accounts),
                  title: const Text(
                    'จัดการโปรไฟล์',
                    style: TextStyle(color: Colors.black),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onmanage_profile();
                  },
                ),

                const Divider(height: 1), // จบหมวดโปรไฟล์
                // เมนู: ตั้งค่าการแจ้งเตือน
                ListTile(
                  leading: const Icon(Icons.notifications_active),
                  title: const Text(
                    'ตั้งค่าการแจ้งเตือน',
                    style: TextStyle(color: Colors.black),
                  ),
                  onTap: () async {
                    Navigator.pop(context);

                    // ถ้าเปิด test mode -> ยิง noti เสียงดังเหมือนนาฬิกาปลุก
                    if (norti_test == 1) {
                      await _showTestAlarm();
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NortificationSettingPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // เมนูล่างสุด: ออกจากระบบ
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              'ออกจากระบบ',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            onTap: () {
              Navigator.pop(context);
              widget.onLogout();
            },
          ),
        ],
      ),
    );
  }
}
