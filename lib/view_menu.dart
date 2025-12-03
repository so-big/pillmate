// lib/view_menu.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// ใช้ยิง noti ทดสอบ
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Database Helper
import 'database_helper.dart';

// ✅ เรียกใช้หน้า setting ที่สร้างใหม่
import 'nortification_setting.dart';

// ตัวแปรเทสต์แจ้งเตือน
int norti_test = 1; // 1 = ให้ดังตอนกดเทสต์, 0 = ปิด

// ---------- ส่วนสำหรับทดสอบแจ้งเตือน (ปรับปรุงให้รองรับ Windows) ----------

final FlutterLocalNotificationsPlugin _testNotiPlugin =
    FlutterLocalNotificationsPlugin();

bool _testNotiInitialized = false;

Future<void> _initTestNotifications() async {
  if (_testNotiInitialized) return;

  // 1. ตั้งค่าสำหรับ Android
  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  // 2. ตั้งค่าสำหรับ Linux/Windows (ใช้ Linux setting เป็นพื้นฐานสำหรับ Desktop บางตัว)
  const LinuxInitializationSettings linuxInit = LinuxInitializationSettings(
    defaultActionName: 'Open notification',
  );

  // 3. ตั้งค่าสำหรับ iOS (ใส่ไว้กัน error หากรันบน mac/ios)
  const DarwinInitializationSettings darwinInit =
      DarwinInitializationSettings();

  final InitializationSettings initSettings = InitializationSettings(
    android: androidInit,
    linux: linuxInit,
    iOS: darwinInit,
    macOS: darwinInit,
  );

  await _testNotiPlugin.initialize(initSettings);

  // ขอ Permission เฉพาะบน Android (Windows ไม่ต้องขอแบบนี้)
  if (Platform.isAndroid) {
    try {
      final androidImpl = _testNotiPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidImpl?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('LeftMenu: requestNotificationsPermission error: $e');
    }
  }

  _testNotiInitialized = true;
}

Future<void> _showTestAlarm() async {
  try {
    await _initTestNotifications();

    // ตั้งค่า Android Specific
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'pillmate_alarm_test', // channel id
          'Pillmate Alarm Test',
          channelDescription: 'ทดสอบเสียงแจ้งเตือนแบบนาฬิกาปลุก',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('alarm'),
          fullScreenIntent: true,
        );

    // ตั้งค่าทั่วไป (NotificationDetails)
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _testNotiPlugin.show(
      9999,
      'ทดสอบเสียงแจ้งเตือน',
      'เสียงนี้คือทดสอบแจ้งเตือน (Alarm Mode)',
      details,
    );
  } catch (e) {
    debugPrint('Show Test Alarm Error: $e');
    // กันแอปเด้งถ้ารันบน Windows แล้ว Plugin ยังไม่สมบูรณ์
  }
}

// -----------------------------------------------------------

class LeftMenu extends StatefulWidget {
  final String username;

  final VoidCallback onShowDashboard;
  final VoidCallback onManageCalendar;
  final VoidCallback onCreateProfile;
  final VoidCallback onmanage_profile;

  final VoidCallback onAddMedicine;
  final VoidCallback onManageMedicine;

  final VoidCallback onLogout;

  const LeftMenu({
    super.key,
    required this.username,
    required this.onShowDashboard,
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
  bool _isNfcEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadUserImage();
    _loadNfcStatus();
  }

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

  Future<File> get _appStatusFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/pillmate/appstatus.json');
  }

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

  Future<void> _toggleNfc(bool value) async {
    setState(() {
      _isNfcEnabled = value;
    });

    try {
      final file = await _appStatusFile;
      Map<String, dynamic> data = {};
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          try {
            data = jsonDecode(content) as Map<String, dynamic>;
          } catch (_) {}
        }
      }

      data['nfc_enabled'] = value;
      data['updated_at'] = DateTime.now().toIso8601String();

      await file.writeAsString(jsonEncode(data));
      debugPrint('Saved NFC status: $value to appstatus.json');

      widget.onShowDashboard();
    } catch (e) {
      debugPrint('LeftMenu: error saving NFC status: $e');
    }
  }

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
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          content: Text(
            message,
            style: const TextStyle(color: Colors.black, fontSize: 16),
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
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
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
                // ✅ เมนูตั้งค่าการแจ้งเตือน
                ListTile(
                  leading: const Icon(Icons.notifications_active),
                  title: const Text(
                    'ตั้งค่าการแจ้งเตือน',
                    style: TextStyle(color: Colors.black),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    // ถ้าเปิด test mode -> ยิง noti
                    if (norti_test == 1) {
                      await _showTestAlarm();
                    }
                    // ไปหน้า NortificationSettingPage
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NortificationSettingPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.nfc),
                  title: const Text(
                    'ใช้ NFC',
                    style: TextStyle(color: Colors.black),
                  ),
                  value: _isNfcEnabled,
                  onChanged: (bool value) async {
                    await _toggleNfc(value);
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
