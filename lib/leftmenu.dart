// lib/leftmenu.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// ใช้ยิง noti ทดสอบ
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

  final VoidCallback onManageCalendar; // จัดการปฏิทินแจ้งเตือน
  final VoidCallback onCreateProfile; // เพิ่มโปรไฟล์
  final VoidCallback onManageProfile; // จัดการโปรไฟล์

  final VoidCallback onAddMedicine; // เพิ่มยา
  final VoidCallback onManageMedicine; // จัดการยา

  final VoidCallback onLogout; // ออกจากระบบ

  const LeftMenu({
    super.key,
    required this.username,
    required this.onManageCalendar,
    required this.onCreateProfile,
    required this.onManageProfile,
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

  Future<void> _loadUserImage() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/user.json');

      if (!await file.exists()) return;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return;

      final data = jsonDecode(content);
      if (data is! List) return;

      for (final u in data) {
        if (u is Map || u is Map<String, dynamic>) {
          final map = Map<String, dynamic>.from(u);
          if (map['userid'] == widget.username) {
            final img = map['image'];
            if (img != null && img.toString().isNotEmpty) {
              setState(() {
                _imageBase64 = img.toString();
              });
            }
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('LeftMenu: error loading user image: $e');
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
                // เมนู 1: จัดการปฏิทินแจ้งเตือน
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

                const Divider(height: 1),

                // เมนู 2: เพิ่มยา
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

                // เมนู 3: จัดการยา
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

                const Divider(height: 1),

                // เมนู 4: เพิ่มโปรไฟล์
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

                // เมนู 5: จัดการโปรไฟล์
                ListTile(
                  leading: const Icon(Icons.manage_accounts),
                  title: const Text(
                    'จัดการโปรไฟล์',
                    style: TextStyle(color: Colors.black),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onManageProfile();
                  },
                ),

                const Divider(height: 1),

                // เมนูใหม่: ตั้งค่าการแจ้งเตือน
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
