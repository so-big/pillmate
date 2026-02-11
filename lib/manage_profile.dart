// lib/manage_profile.dart

import 'dart:convert';
// import 'dart:io'; // ไม่ได้ใช้แล้ว เพราะเปลี่ยนไปใช้ DB
// import 'package:path_provider/path_provider.dart'; // ไม่ได้ใช้แล้ว

import 'package:flutter/material.dart'; // ต้อง import เพื่อใช้ object Database

import 'create_profile.dart';
import 'edit_account.dart';
import 'edit_profile.dart';
import 'database_helper.dart'; // ✅ เรียกใช้ DatabaseHelper
import 'services/auth_service.dart';

class manage_profilePage extends StatefulWidget {
  final String username;

  const manage_profilePage({super.key, required this.username});

  @override
  State<manage_profilePage> createState() => _manage_profilePageState();
}

class _manage_profilePageState extends State<manage_profilePage> {
  List<Map<String, dynamic>> _profiles = [];
  bool _isLoading = true;

  Map<String, dynamic>? _accountUser; // ข้อมูล account (Master)

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ✅ แก้ไข: โหลดข้อมูลจาก SQLite แทน JSON
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      // 1. โหลดข้อมูล Master Account
      // เทียบเท่ากับ: SELECT * FROM users WHERE userid = 'username'
      final masterUser = await dbHelper.getUser(widget.username);

      // 2. โหลดข้อมูล Sub-profiles
      // เทียบเท่ากับ: SELECT * FROM users WHERE sub_profile = 'username'
      final List<Map<String, dynamic>> subProfiles = await db.query(
        'users',
        where: 'sub_profile = ?',
        whereArgs: [widget.username],
      );

      setState(() {
        _accountUser = masterUser;
        // แปลงเป็น List<Map> เพื่อให้แน่ใจว่าแก้ไขได้และไม่ติดเรื่อง read-only
        _profiles = List<Map<String, dynamic>>.from(subProfiles);
      });
    } catch (e) {
      debugPrint('Error loading profiles from DB: $e');
      setState(() {
        _profiles = [];
        _accountUser = null;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ✅ แก้ไข: เช็ครหัสผ่านจาก DB
  Future<bool> _validatePassword(String passwordInput) async {
    try {
      final dbHelper = DatabaseHelper();
      final user = await dbHelper.getUser(widget.username);

      if (user != null) {
        // เช็คว่ารหัสผ่านตรงกันหรือไม่ (supports hashed + legacy)
        if (AuthService.verifyPassword(passwordInput, user['password'].toString())) {
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Error validating password DB: $e');
      return false;
    }
  }

  // ✅ แก้ไข: ลบข้อมูลจาก DB
  Future<void> _deleteProfile(int index) async {
    final toDelete = _profiles[index];
    // ใน DB เราใช้ userid เป็นชื่อของ sub-profile
    final userIdToDelete = toDelete['userid'];

    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      // สั่งลบแถวที่มี userid ตรงกับโปรไฟล์ที่จะลบ
      await db.delete(
        'users',
        where: 'userid = ?',
        whereArgs: [userIdToDelete],
      );

      setState(() {
        _profiles.removeAt(index);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ลบโปรไฟล์ "$userIdToDelete" เรียบร้อย')),
      );
    } catch (e) {
      debugPrint('Error deleting profile DB: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ลบโปรไฟล์ไม่สำเร็จ: $e')));
    }
  }

  Future<void> _confirmDelete(int index) async {
    final profile = _profiles[index];
    // เปลี่ยน key จาก 'name' เป็น 'userid' ตาม DB schema
    final name = profile['userid']?.toString() ?? 'ไม่ทราบชื่อ';
    final TextEditingController pwdController = TextEditingController();
    String? errorText;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text('ยืนยันการลบโปรไฟล์'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'คุณต้องการลบโปรไฟล์ "$name" ใช่หรือไม่?\n\n'
                    'กรุณากรอกรหัสผ่านของคุณ (Master) เพื่อยืนยัน',
                    // น้องใบเตยเพิ่ม color: Colors.black เข้าไปที่นี่ค่ะ
                    style: const TextStyle(fontSize: 14, color: Colors.black),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pwdController,
                    obscureText: true,
                    // ตรงนี้เป็นสีดำอยู่แล้ว
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'รหัสผ่าน',
                      // ปรับจาก Colors.black87 เป็น Colors.black ให้ดำสนิทตามที่นายท่านต้องการค่ะ
                      labelStyle: const TextStyle(color: Colors.black),
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                  },
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final input = pwdController.text.trim();
                    if (input.isEmpty) {
                      setStateDialog(() {
                        errorText = 'กรุณากรอกรหัสผ่าน';
                      });
                      return;
                    }

                    final ok = await _validatePassword(input);
                    if (!ok) {
                      setStateDialog(() {
                        errorText = 'รหัสผ่านไม่ถูกต้อง';
                      });
                      return;
                    }

                    if (mounted) {
                      Navigator.pop(ctx);
                      await _deleteProfile(index);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('ยืนยันลบ'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildProfileImage(dynamic imageData) {
    const fallback = 'assets/imagenotfound.png';

    if (imageData == null || imageData.toString().isEmpty) {
      return Image.asset(fallback, fit: BoxFit.cover);
    }

    try {
      final bytes = base64Decode(imageData.toString());
      return Image.memory(bytes, fit: BoxFit.cover);
    } catch (e) {
      debugPrint('Error decoding base64 image: $e');
      return Image.asset(fallback, fit: BoxFit.cover);
    }
  }

  Future<void> _goToCreateProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateProfilePage()),
    );
    await _loadData();
  }

  Future<void> _goToEditAccount() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditAccountPage(username: widget.username),
      ),
    );
    await _loadData();
  }

  Future<void> _goToEditProfile(int index) async {
    final profile = _profiles[index];
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            EditProfilePage(username: widget.username, profile: profile),
      ),
    );
    await _loadData();
  }

  Widget _buildProfileActions(int index) {
    const double buttonWidth = 80;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: buttonWidth,
          child: ElevatedButton(
            onPressed: () => _goToEditProfile(index),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade400,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('แก้ไข', style: TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: buttonWidth,
          child: ElevatedButton(
            onPressed: () => _confirmDelete(index),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('ลบ', style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountCard() {
    // เปลี่ยน key ให้ตรงกับ DB: userid, image_base64
    final accName = _accountUser?['userid']?.toString() ?? widget.username;
    final accImage = _accountUser?['image_base64'];

    return InkWell(
      onTap: _goToEditAccount,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // รูปโปรไฟล์ account
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  color: Colors.grey.shade200,
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildProfileImage(accImage),
              ),
              const SizedBox(width: 12),

              // ชื่อ account
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      accName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'บัญชีผู้ใช้หลัก (Master Account)',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // ปุ่มแก้ไข (เฉพาะ account)
              SizedBox(
                width: 80,
                child: ElevatedButton(
                  onPressed: _goToEditAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade400,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('แก้ไข', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasProfiles = _profiles.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('จัดการโปรไฟล์')),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : (!hasProfiles && _accountUser == null)
            ? const Center(
                child: Text(
                  'ยังไม่มีข้อมูลโปรไฟล์',
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: 1 + _profiles.length,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // การ์ด account เป็นใบแรก
                    return _buildAccountCard();
                  }

                  final profileIndex = index - 1;
                  final profile = _profiles[profileIndex];
                  // ใช้ key 'userid' แทน 'name' ตาม DB
                  final name = profile['userid']?.toString() ?? 'ไม่ทราบชื่อ';
                  // ใช้ key 'sub_profile' แทน 'createby' ตาม DB
                  final createBy = profile['sub_profile']?.toString() ?? '-';

                  return InkWell(
                    onTap: () => _goToEditProfile(profileIndex),
                    borderRadius: BorderRadius.circular(12),
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // รูปโปรไฟล์
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(32),
                                color: Colors.grey.shade200,
                              ),
                              clipBehavior: Clip.antiAlias,
                              // ใช้ key 'image_base64' แทน 'image' ตาม DB
                              child: _buildProfileImage(
                                profile['image_base64'],
                              ),
                            ),
                            const SizedBox(width: 12),

                            // ชื่อโปรไฟล์
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'สร้างโดย: $createBy',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 8),

                            // ปุ่ม แก้ไข / ลบ
                            _buildProfileActions(profileIndex),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),

      // ปุ่มเพิ่มโปรไฟล์ใหม่ด้านล่าง
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _goToCreateProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text(
                'เพิ่มโปรไฟล์ใหม่',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
