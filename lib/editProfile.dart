// lib/editProfile.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

class EditProfilePage extends StatefulWidget {
  final String username;
  final Map<String, dynamic> profile;

  const EditProfilePage({
    super.key,
    required this.username,
    required this.profile,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _noteController;

  String? _customImageBase64;
  String? _assetImagePath;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    final p = widget.profile;

    _nameController = TextEditingController(text: (p['name'] ?? '').toString());
    _noteController = TextEditingController(text: (p['note'] ?? '').toString());

    final img = p['image'];
    if (img is String && img.isNotEmpty) {
      if (img.startsWith('assets/')) {
        _assetImagePath = img;
        _customImageBase64 = null;
      } else {
        _assetImagePath = null;
        _customImageBase64 = img;
      }
    }
  }

  bool get _usingCustomImage => _customImageBase64 != null;

  Future<File> get _profilesFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/profiles.json');
  }

  Future<File> get _usersFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/user.json');
  }

  Future<void> _pickCustomImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);

      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final base64Str = base64Encode(bytes);

      setState(() {
        _customImageBase64 = base64Str;
        _assetImagePath = null;
      });
    } catch (e) {
      debugPrint('editProfile: pick image error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เกิดข้อผิดพลาดในการเลือกรูปภาพ')),
      );
    }
  }

  Widget _buildAvatarPreview() {
    if (_usingCustomImage) {
      try {
        final bytes = base64Decode(_customImageBase64!);
        return CircleAvatar(
          radius: 40,
          backgroundColor: Colors.white,
          child: ClipOval(
            child: Image.memory(
              bytes,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),
        );
      } catch (_) {
        return const CircleAvatar(
          radius: 40,
          child: Icon(Icons.person, size: 32),
        );
      }
    } else if (_assetImagePath != null) {
      return CircleAvatar(
        radius: 40,
        backgroundColor: Colors.white,
        child: ClipOval(
          child: Image.asset(
            _assetImagePath!,
            width: 80,
            height: 80,
            fit: BoxFit.cover,
          ),
        ),
      );
    } else {
      return const CircleAvatar(
        radius: 40,
        child: Icon(Icons.person, size: 32),
      );
    }
  }

  Future<bool> _verifyPassword(String inputPassword) async {
    try {
      final file = await _usersFile;
      if (!await file.exists()) return false;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return false;

      final decoded = jsonDecode(content);
      if (decoded is! List) return false;

      for (final u in decoded) {
        if (u is Map || u is Map<String, dynamic>) {
          final map = Map<String, dynamic>.from(u);
          final userid = map['userid']?.toString();
          final password = map['password']?.toString();
          if (userid == widget.username && password == inputPassword) {
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('editProfile: verifyPassword error: $e');
    }
    return false;
  }

  Future<bool?> _showPasswordConfirmDialog() async {
    final controller = TextEditingController();
    bool isChecking = false;
    String? errorText;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            Future<void> onConfirm() async {
              final pwd = controller.text.trim();
              if (pwd.isEmpty) {
                setStateDialog(() {
                  errorText = 'กรุณากรอกรหัสผ่าน';
                });
                return;
              }

              setStateDialog(() {
                isChecking = true;
                errorText = null;
              });

              final ok = await _verifyPassword(pwd);

              setStateDialog(() {
                isChecking = false;
              });

              if (ok) {
                Navigator.of(ctx).pop(true);
              } else {
                setStateDialog(() {
                  errorText = 'รหัสผ่านไม่ถูกต้อง';
                });
              }
            }

            return AlertDialog(
              // แก้ให้เหลือคำนี้คำเดียวตามคำสั่ง
              title: const Text('กรุณายืนยันรหัสผ่าน'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    obscureText: true,
                    style: const TextStyle(color: Colors.black87),
                    decoration: InputDecoration(
                      labelText: 'รหัสผ่าน',
                      labelStyle: const TextStyle(color: Colors.black87),
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isChecking
                      ? null
                      : () => Navigator.of(ctx).pop(false),
                  child: const Text('ยกเลิก'),
                ),
                TextButton(
                  onPressed: isChecking ? null : onConfirm,
                  child: isChecking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('ยืนยัน'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveProfile() async {
    if (_isSaving) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    // ยืนยันรหัสผ่านก่อนบันทึก
    final confirmed = await _showPasswordConfirmDialog();
    if (confirmed != true) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final file = await _profilesFile;

      List<dynamic> list = [];
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(content);
            if (decoded is List) {
              list = decoded;
            }
          } catch (e) {
            debugPrint('editProfile: JSON decode error: $e');
          }
        }
      }

      final original = widget.profile;
      final id =
          original['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();

      final now = DateTime.now();

      final updated = {
        'id': id,
        'name': _nameController.text.trim(),
        'note': _noteController.text.trim(),
        'image': _usingCustomImage
            ? _customImageBase64
            : (_assetImagePath ?? original['image']),
        'createby': original['createby'] ?? widget.username,
        'createdAt': original['createdAt'] ?? now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };

      bool replaced = false;
      for (int i = 0; i < list.length; i++) {
        final item = list[i];
        try {
          if (item is Map && item['id'] == id) {
            list[i] = updated;
            replaced = true;
            break;
          }
        } catch (_) {}
      }

      if (!replaced) {
        list.add(updated);
      }

      await file.writeAsString(jsonEncode(list), flush: true);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกการแก้ไขโปรไฟล์เรียบร้อย')),
      );

      Navigator.pop(context, updated);
    } catch (e) {
      debugPrint('editProfile: error saving profile: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่สามารถบันทึกข้อมูลได้ กรุณาลองใหม่อีกครั้ง'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('แก้ไขโปรไฟล์')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      _buildAvatarPreview(),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: InkWell(
                          onTap: _pickCustomImage,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.teal,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.edit,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                const Text(
                  'ชื่อโปรไฟล์ *',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'ระบุชื่อโปรไฟล์',
                    hintStyle: const TextStyle(color: Colors.black45),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'กรุณาระบุชื่อโปรไฟล์';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                const Text(
                  'รายละเอียดเพิ่มเติม (ไม่จำเป็นต้องระบุ)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _noteController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'รายละเอียดเพิ่มเติมเกี่ยวกับโปรไฟล์',
                    hintStyle: const TextStyle(color: Colors.black45),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'บันทึกการแก้ไขโปรไฟล์',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
