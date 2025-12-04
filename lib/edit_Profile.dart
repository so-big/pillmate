// lib/edit_Profile.dart

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui; // เพิ่ม import เพื่อใช้ ui.instantiateImageCodec
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/cupertino.dart'; // เพิ่ม import เพื่อใช้ CupertinoPicker

// นำเข้า DatabaseHelper
import 'database_helper.dart';

class EditProfilePage extends StatefulWidget {
  final String username; // Master username
  final Map<String, dynamic> profile; // ข้อมูลโปรไฟล์ที่จะแก้

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

  late String _originalProfileName;

  bool _isSaving = false;

  // ✅ NEW: ตัวแปรเก็บเวลาอาหาร (ใช้เมื่อกำลังแก้ Master Profile เท่านั้น)
  String _breakfastTime = '06:00';
  String _lunchTime = '12:00';
  String _dinnerTime = '18:00';

  bool get _isMasterProfile => _originalProfileName == widget.username;

  // เรียกใช้ Database Helper
  final dbHelper = DatabaseHelper();

  // 1. เพิ่มรายการรูปภาพต้นฉบับ (เหมือนหน้า Create Profile)
  final List<String> _avatarAssets = const [
    'assets/simpleProfile/profile_1.png',
    'assets/simpleProfile/profile_2.png',
    'assets/simpleProfile/profile_3.png',
    'assets/simpleProfile/profile_4.png',
    'assets/simpleProfile/profile_5.png',
    'assets/simpleProfile/profile_6.png',
  ];
  int? _selectedAvatarIndex; // เก็บสถานะว่าเลือกรูปไหนอยู่ (ถ้าเลือกจาก asset)

  @override
  void initState() {
    super.initState();

    final p = widget.profile;

    _originalProfileName = (p['userid'] ?? '').toString();
    _nameController = TextEditingController(text: _originalProfileName);
    _noteController = TextEditingController(text: (p['info'] ?? '').toString());

    final img = p['image_base64'];
    if (img is String && img.isNotEmpty) {
      _customImageBase64 = img;
    }

    // ✅ NEW: ถ้าเป็น Master Profile ให้โหลดเวลาอาหารล่าสุดมาด้วย
    if (_isMasterProfile) {
      _loadMasterMealTimes();
    }
  }

  // ✅ NEW: ฟังก์ชันโหลดเวลาอาหารของ Master Account
  Future<void> _loadMasterMealTimes() async {
    try {
      final user = await dbHelper.getUser(widget.username);
      if (user != null) {
        if (mounted) {
          setState(() {
            _breakfastTime = user['breakfast']?.toString() ?? '06:00';
            _lunchTime = user['lunch']?.toString() ?? '12:00';
            _dinnerTime = user['dinner']?.toString() ?? '18:00';
          });
        }
      }
    } catch (e) {
      debugPrint('EditProfile: Error loading master meal times: $e');
    }
  }

  bool get _usingCustomImage =>
      _customImageBase64 != null && _customImageBase64!.isNotEmpty;

  // 2. เพิ่มฟังก์ชันแปลง Asset เป็น Base64
  Future<String> _loadAssetAsBase64(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    final buffer = byteData.buffer;
    final Uint8List uint8list = buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    return base64Encode(uint8list);
  }

  // 3. เพิ่มฟังก์ชันเมื่อเลือกรูปจากรายการ Assets
  Future<void> _selectAvatarFromAssets(int index) async {
    try {
      final base64 = await _loadAssetAsBase64(_avatarAssets[index]);
      setState(() {
        _selectedAvatarIndex = index;
        _customImageBase64 = base64; // อัปเดตรูปที่จะบันทึกทันที
      });
    } catch (e) {
      debugPrint('editProfile: load asset error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('โหลดรูปโปรไฟล์ไม่สำเร็จ')));
    }
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
        _selectedAvatarIndex =
            null; // ถ้าเลือกจาก gallery ให้ยกเลิกการเลือก asset
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
    } else {
      return const CircleAvatar(
        radius: 40,
        child: Icon(Icons.person, size: 32),
      );
    }
  }

  Future<bool> _verifyPassword(String inputPassword) async {
    try {
      final user = await dbHelper.getUser(widget.username);
      if (user != null) {
        // ดึงรหัสผ่านของ master user (widget.username)
        if (user['password'] == inputPassword) {
          return true;
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
              title: const Text('กรุณายืนยันรหัสผ่าน'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ใส่รหัสผ่านบัญชีหลักเพื่อยืนยันการดำเนินการ', // แก้ข้อความให้เป็นกลาง
                    style: TextStyle(fontSize: 14, color: Colors.black),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    style: const TextStyle(color: Colors.black87),
                    decoration: InputDecoration(
                      labelText: 'รหัสผ่าน',
                      labelStyle: const TextStyle(color: Colors.black87),
                      errorText: errorText,
                      border: const OutlineInputBorder(),
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

  // ✅ NEW: ฟังก์ชันเลือกเวลา (คัดลอกมาจาก EditAccountPage)
  Future<void> _pickTime({
    required String initialTime,
    required String label,
    required void Function(String time) onSelected,
  }) async {
    final parts = initialTime.split(':');
    int initialHour = int.tryParse(parts[0]) ?? 0;
    int initialMinute = int.tryParse(parts[1]) ?? 0;

    int selectedHour = initialHour;
    int selectedMinute = initialMinute;

    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: 260,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'เลือกเวลาสำหรับ $label (24 ชั่วโมง)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: initialHour.clamp(0, 23),
                        ),
                        itemExtent: 32,
                        magnification: 1.1,
                        useMagnifier: true,
                        onSelectedItemChanged: (index) {
                          selectedHour = index;
                        },
                        children: List.generate(
                          24,
                          (i) => Center(
                            child: Text(
                              i.toString().padLeft(2, '0'),
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Text(
                      ':',
                      style: TextStyle(fontSize: 18, color: Colors.black87),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: initialMinute.clamp(0, 59),
                        ),
                        itemExtent: 32,
                        magnification: 1.1,
                        useMagnifier: true,
                        onSelectedItemChanged: (index) {
                          selectedMinute = index;
                        },
                        children: List.generate(
                          60,
                          (i) => Center(
                            child: Text(
                              i.toString().padLeft(2, '0'),
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('ยกเลิก'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final time =
                          '${selectedHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')}';
                      onSelected(time);
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('ตกลง'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // --- ฟังก์ชันสำหรับการบันทึกโปรไฟล์ (อัปเดตเพื่อรองรับเวลาอาหาร Master) ---
  Future<void> _saveProfile() async {
    if (_isSaving) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    // ✅ เพิ่มการยืนยันว่า Master User ไม่สามารถเปลี่ยนชื่อโปรไฟล์ได้
    if (_isMasterProfile &&
        _nameController.text.trim() != _originalProfileName) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปลี่ยนชื่อบัญชีหลักได้')),
      );
      _nameController.text = _originalProfileName; // รีเซ็ตชื่อกลับ
      return;
    }

    final confirmed = await _showPasswordConfirmDialog();
    if (confirmed != true) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final db = await dbHelper.database;

      final newName = _nameController.text.trim();
      final newInfo = _noteController.text.trim();

      // 1. ข้อมูลที่จะอัปเดตในตาราง users (สำหรับ sub-profile และ master)
      final Map<String, dynamic> updatedValues = {
        // ใช้ newName เฉพาะในกรณีที่เป็น Sub-profile
        'userid': newName,
        'info': newInfo,
        'image_base64': _customImageBase64 ?? '',
      };

      // 2. ถ้าเป็น Master Profile ต้องอัปเดตเวลาอาหารด้วย
      if (_isMasterProfile) {
        updatedValues['breakfast'] = _breakfastTime;
        updatedValues['lunch'] = _lunchTime;
        updatedValues['dinner'] = _dinnerTime;
      }

      // อัปเดตโดยใช้ชื่อโปรไฟล์เดิมเป็นเงื่อนไข
      final count = await db.update(
        'users',
        updatedValues,
        where: 'userid = ?',
        whereArgs: [_originalProfileName],
      );

      if (!mounted) return;

      if (count > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกการแก้ไขโปรไฟล์เรียบร้อย')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบโปรไฟล์ที่ต้องการแก้ไข')),
        );
      }

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('editProfile: error saving profile: $e');

      String msg = 'ไม่สามารถบันทึกข้อมูลได้';
      if (e.toString().contains('UNIQUE constraint failed')) {
        msg = 'ชื่อโปรไฟล์นี้มีอยู่แล้ว กรุณาใช้ชื่ออื่น';
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // --- ฟังก์ชันสำหรับลบโปรไฟล์ (ปรับปรุงการแจ้งเตือน) ---
  Future<void> _deleteProfile() async {
    if (_isSaving) return;

    // ✅ Master Profile ไม่สามารถถูกลบได้
    if (_isMasterProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่สามารถลบบัญชีหลักได้ กรุณาใช้เมนูแก้ไขบัญชีหลัก'),
        ),
      );
      return;
    }

    // ยืนยันรหัสผ่านบัญชีหลักก่อน
    final confirmed = await _showPasswordConfirmDialog();
    if (confirmed != true) {
      return;
    }

    // ยืนยันการลบซ้ำ
    final deleteConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบโปรไฟล์ย่อย?'),
        content: Text(
          'คุณแน่ใจหรือไม่ที่ต้องการลบโปรไฟล์ "${_originalProfileName}"? ข้อมูลนี้จะถูกลบถาวร',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (deleteConfirm != true) return;

    setState(() {
      _isSaving = true; // ใช้สถานะเดียวกันเพื่อแสดง Loading
    });

    try {
      final db = await dbHelper.database;

      // ลบแถวในตาราง users โดยใช้ชื่อโปรไฟล์เดิมเป็นเงื่อนไข
      final count = await db.delete(
        'users',
        where: 'userid = ?',
        whereArgs: [_originalProfileName],
      );

      // ✅ NEW: ลบการแจ้งเตือนและประวัติการกินยาที่ผูกกับโปรไฟล์นี้ด้วย (Cascade Logic)
      await db.delete(
        'calendar_alerts',
        where: 'profile_name = ?',
        whereArgs: [_originalProfileName],
      );
      await db.delete(
        'taken_doses',
        where: 'profile_name = ?',
        whereArgs: [_originalProfileName],
      );
      // หมายเหตุ: Master User ถูกป้องกันการลบไปแล้ว

      if (!mounted) return;

      if (count > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'ลบโปรไฟล์ "${_originalProfileName}" และข้อมูลที่เกี่ยวข้องเรียบร้อยแล้ว',
            ),
          ),
        );
        // Pop หน้าจอและส่งค่า true เพื่อบอกว่ามีการเปลี่ยนแปลง
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบโปรไฟล์ที่ต้องการลบ')),
        );
      }
    } catch (e) {
      debugPrint('editProfile: error deleting profile: $e');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เกิดข้อผิดพลาดในการลบโปรไฟล์')),
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
      appBar: AppBar(
        title: Text(_isMasterProfile ? 'แก้ไขบัญชีหลัก' : 'แก้ไขโปรไฟล์'),
      ),
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

                // 4. ส่วนเลือกรูปจาก Assets
                const SizedBox(height: 16),
                const Text(
                  'เลือกรูปภาพมาตรฐาน',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 72,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _avatarAssets.length,
                    itemBuilder: (context, index) {
                      final isSelected = _selectedAvatarIndex == index;
                      return GestureDetector(
                        onTap: () => _selectAvatarFromAssets(index),
                        child: Container(
                          margin: EdgeInsets.only(
                            right: index == _avatarAssets.length - 1 ? 0 : 8,
                          ),
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? Colors.blue
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              _avatarAssets[index],
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ------------------------------------
                const SizedBox(height: 24),

                Text(
                  _isMasterProfile
                      ? 'บัญชีหลัก (แก้ไขชื่อไม่ได้)'
                      : 'ชื่อโปรไฟล์ *',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  readOnly: _isMasterProfile, // ✅ ห้ามแก้ไขชื่อบัญชีหลัก
                  style: TextStyle(
                    color: _isMasterProfile ? Colors.grey : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: 'ระบุชื่อโปรไฟล์',
                    hintStyle: const TextStyle(color: Colors.black45),
                    filled: true,
                    fillColor: _isMasterProfile
                        ? Colors.grey[200]
                        : Colors.grey[100],
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

                // --- ส่วนแก้ไขเวลาอาหาร (แสดงเฉพาะ Master Profile) ---
                if (_isMasterProfile) ...[
                  const Text(
                    'แก้ไขเวลาอาหาร (สำหรับแจ้งเตือน)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // เวลาอาหารเช้า
                  Row(
                    children: [
                      const Icon(Icons.free_breakfast, color: Colors.brown),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'อาหารเช้า',
                          style: TextStyle(fontSize: 16, color: Colors.black),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _pickTime(
                          initialTime: _breakfastTime,
                          label: 'อาหารเช้า',
                          onSelected: (time) =>
                              setState(() => _breakfastTime = time),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          _breakfastTime,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),

                  // เวลาอาหารกลางวัน
                  Row(
                    children: [
                      const Icon(Icons.fastfood, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'อาหารกลางวัน',
                          style: TextStyle(fontSize: 16, color: Colors.black),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _pickTime(
                          initialTime: _lunchTime,
                          label: 'อาหารกลางวัน',
                          onSelected: (time) =>
                              setState(() => _lunchTime = time),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          _lunchTime,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),

                  // เวลาอาหารเย็น
                  Row(
                    children: [
                      const Icon(Icons.dinner_dining, color: Colors.blueGrey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'อาหารเย็น',
                          style: TextStyle(fontSize: 16, color: Colors.black),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _pickTime(
                          initialTime: _dinnerTime,
                          label: 'อาหารเย็น',
                          onSelected: (time) =>
                              setState(() => _dinnerTime = time),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          _dinnerTime,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],

                // --- END: ส่วนแก้ไขเวลาอาหาร ---
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

                // ปุ่มบันทึกการแก้ไข (เดิม)
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

                // ✅ ปุ่มลบโปรไฟล์ (ใหม่ - ซ่อนเมื่อเป็น Master Profile)
                if (!_isMasterProfile) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _deleteProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red, // พื้นแดง
                        foregroundColor: Colors.white, // ตัวอักษรขาว
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
                              'ลบโปรไฟล์',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
