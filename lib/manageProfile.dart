// lib/manageProfile.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'createProfile.dart';
import 'editAccount.dart';
import 'editProfile.dart';

class ManageProfilePage extends StatefulWidget {
  final String username;

  const ManageProfilePage({super.key, required this.username});

  @override
  State<ManageProfilePage> createState() => _ManageProfilePageState();
}

class _ManageProfilePageState extends State<ManageProfilePage> {
  List<Map<String, dynamic>> _profiles = [];
  bool _isLoading = true;

  Map<String, dynamic>? _accountUser; // ข้อมูล account จาก user.json

  Future<File> get _profilesFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/profiles.json');
  }

  Future<File> get _usersFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/user.json');
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // โหลด user.json สำหรับ account
      final usersFile = await _usersFile;
      Map<String, dynamic>? account;

      if (await usersFile.exists()) {
        final content = await usersFile.readAsString();
        if (content.trim().isNotEmpty) {
          final list = jsonDecode(content);
          if (list is List) {
            for (final u in list) {
              if (u is Map || u is Map<String, dynamic>) {
                final map = Map<String, dynamic>.from(u);
                if (map['userid'] == widget.username) {
                  account = map;
                  break;
                }
              }
            }
          }
        }
      }

      // โหลด profiles.json สำหรับโปรไฟล์ต่าง ๆ
      final profilesFile = await _profilesFile;

      List<dynamic> listProfiles = [];
      if (await profilesFile.exists()) {
        final content = await profilesFile.readAsString();
        if (content.trim().isNotEmpty) {
          listProfiles = jsonDecode(content);
        }
      }

      final filtered = listProfiles
          .where((p) {
            if (p is Map<String, dynamic>) {
              return p['createby'] == widget.username;
            }
            if (p is Map) {
              return p['createby'] == widget.username;
            }
            return false;
          })
          .map<Map<String, dynamic>>((p) => Map<String, dynamic>.from(p));

      setState(() {
        _accountUser = account;
        _profiles = filtered.toList();
      });
    } catch (e) {
      debugPrint('Error loading profiles/account in manageProfile: $e');
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

  Future<bool> _validatePassword(String passwordInput) async {
    try {
      final file = await _usersFile;
      if (!await file.exists()) return false;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return false;

      final list = jsonDecode(content);
      if (list is! List) return false;

      for (final u in list) {
        if (u is Map || u is Map<String, dynamic>) {
          final map = Map<String, dynamic>.from(u);
          if (map['userid'] == widget.username &&
              map['password'] == passwordInput) {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      debugPrint('Error validating password: $e');
      return false;
    }
  }

  Future<void> _deleteProfile(int index) async {
    final toDelete = _profiles[index];

    try {
      final file = await _profilesFile;

      List<dynamic> list = [];
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          list = jsonDecode(content);
        }
      }

      list.removeWhere((p) {
        if (p is Map || p is Map<String, dynamic>) {
          final map = Map<String, dynamic>.from(p);
          return map['name'] == toDelete['name'] &&
              map['createby'] == toDelete['createby'];
        }
        return false;
      });

      await file.writeAsString(jsonEncode(list));

      setState(() {
        _profiles.removeAt(index);
      });
    } catch (e) {
      debugPrint('Error deleting profile: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ลบโปรไฟล์ไม่สำเร็จ: $e')));
    }
  }

  Future<void> _confirmDelete(int index) async {
    final profile = _profiles[index];
    final name = profile['name']?.toString() ?? 'ไม่ทราบชื่อ';
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
                    'กรุณากรอกรหัสผ่านของคุณเพื่อยืนยัน',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pwdController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'รหัสผ่าน',
                      labelStyle: const TextStyle(color: Colors.black87),
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
    final accName = _accountUser?['userid']?.toString() ?? widget.username;
    final accImage = _accountUser?['image'];

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
                      'บัญชีผู้ใช้ (แก้ไขรูปภาพ / รหัสผ่านได้)',
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
                  final name = profile['name']?.toString() ?? 'ไม่ทราบชื่อ';

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
                              child: _buildProfileImage(profile['image']),
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
                                    'สร้างโดย: ${profile['createby'] ?? '-'}',
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
