// lib/view_menu.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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
  bool _isNfcEnabled = false; // ค่าเริ่มต้นเป็น false (ปิด)

  @override
  void initState() {
    super.initState();
    _loadUserImage();
    _loadNfcStatus();
  }

  // แก้ไข: ดึงรูปภาพจาก Database (คอลัมน์ image_base64)
  Future<void> _loadUserImage() async {
    try {
      final dbHelper = DatabaseHelper();
      final userMap = await dbHelper.getUser(widget.username);

      if (userMap != null) {
        final img = userMap['image_base64'];

        if (img != null && img.toString().isNotEmpty) {
          setState(() {
            _imageBase64 = img.toString();
          });
        }
      }
    } catch (e) {
      debugPrint('LeftMenu: error loading user image from DB: $e');
    }
  }

  // ✅ ฟังก์ชันหาไฟล์ appstatus.json
  Future<File> get _appStatusFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/appstatus.json');
  }

  // ✅ ฟังก์ชันโหลดสถานะ NFC
  Future<void> _loadNfcStatus() async {
    try {
      final file = await _appStatusFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content);
          if (data is Map) {
            setState(() {
              _isNfcEnabled = data['nfc_enabled'] ?? false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('LeftMenu: error loading NFC status: $e');
    }
  }

  // ✅ ฟังก์ชันบันทึกสถานะ NFC ลง JSON
  Future<void> _toggleNfc(bool value) async {
    // อัปเดต UI ก่อน
    setState(() {
      _isNfcEnabled = value;
    });

    try {
      final file = await _appStatusFile;
      // อ่านข้อมูลเดิมก่อน (ถ้ามี)
      Map<String, dynamic> data = {};
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          try {
            data = jsonDecode(content) as Map<String, dynamic>;
          } catch (_) {}
        }
      }

      // อัปเดตค่า NFC
      data['nfc_enabled'] = value;
      data['updated_at'] = DateTime.now().toIso8601String();

      await file.writeAsString(jsonEncode(data));
      debugPrint('Saved NFC status: $value to appstatus.json');

      // ✅ สั่ง Refresh Dashboard ทันที
      widget.onShowDashboard();
    } catch (e) {
      debugPrint('LeftMenu: error saving NFC status: $e');
    }
  }

  // ✅ ฟังก์ชันแสดง Dialog แจ้งเตือนตามสถานะ NFC
  Future<void> _showNfcInfoDialog(bool isEnabled) async {
    String message;
    if (isEnabled) {
      message =
          'ฟังก์ชั่น NFC บนแอพถูกเปิดแล้ว แต่ผู้ใช้งานจะต้องเปิดฟังก์ชั่น NFC บนโทรศัพท์ด้วย';
    } else {
      message = 'ฟังก์ชั่น NFC ถูกปิดแล้วโหมดใช้งานสำหรับอุปกรณ์ที่ไม่มี NFC';
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(
            'การตั้งค่า NFC',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ), // หัวข้อสีดำ
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 16,
            ), // ✅ เนื้อหาตัวหนังสือสีดำ
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
              },
              child: const Text(
                'ตกลง',
                style: TextStyle(
                  color: Colors.teal,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
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
                // เมนู 1: จัดการกำหนดการรายวัน (ไปหน้า Dashboard)
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

                const Divider(height: 1),

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

                const Divider(height: 1),

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

                const Divider(height: 1),

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

                const Divider(height: 1), // ✅ ขีดแบ่ง Section ก่อน NFC
                // ✅ เมนูใหม่: สวิตช์เปิด/ปิด NFC
                SwitchListTile(
                  secondary: const Icon(Icons.nfc),
                  title: const Text(
                    'ใช้ NFC',
                    style: TextStyle(color: Colors.black),
                  ),
                  value: _isNfcEnabled,
                  onChanged: (bool value) async {
                    // 1. บันทึกค่า และ Refresh Dashboard
                    await _toggleNfc(value);
                    // 2. แสดง Dialog แจ้งเตือน
                    if (context.mounted) {
                      await _showNfcInfoDialog(value);
                    }
                  },
                  activeColor: Colors.teal,
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
