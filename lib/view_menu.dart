// lib/view_menu.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// ❌ ลบ Import Flutter Local Notifications ทิ้ง
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Database Helper
import 'database_helper.dart';

// ✅ เรียกใช้หน้า setting ที่สร้างใหม่
import 'nortification_setting.dart';

// ❌ ลบตัวแปรเทสต์แจ้งเตือน (norti_test) ทิ้ง
// ❌ ลบโค้ดฟังก์ชันทั้งหมดที่เกี่ยวข้องกับการทดสอบแจ้งเตือน (_initTestNotifications, _showTestAlarm) ทิ้ง

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
                // ✅ เมนูตั้งค่าการแจ้งเตือน (ลบโค้ดทดสอบออกแล้ว)
                ListTile(
                  leading: const Icon(Icons.notifications_active),
                  title: const Text(
                    'ตั้งค่าการแจ้งเตือน',
                    style: TextStyle(color: Colors.black),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    // ไปหน้า NortificationSettingPage ทันที
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
