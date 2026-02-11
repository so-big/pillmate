// lib/edit_profile.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart'; // ใช้ CupertinoPicker
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';

// นำเข้า DatabaseHelper
import 'database_helper.dart';
import 'services/auth_service.dart';

class EditProfilePage extends StatefulWidget {
  final String username; // Master username (เจ้าของบัญชีหลัก)
  final Map<String, dynamic>
  profile; // ข้อมูลโปรไฟล์ที่จะแก้ (อาจเป็น sub-profile)

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

  // ✅ ตัวแปรเก็บเวลาอาหาร
  String _breakfastTime = '06:00';
  String _lunchTime = '12:00';
  String _dinnerTime = '18:00';
  String _bedtimeTime = '21:00';

  // ✅ เปิด/ปิดการแจ้งเตือนแต่ละมื้อ
  bool _breakfastNotify = true;
  bool _lunchNotify = true;
  bool _dinnerNotify = true;
  bool _bedtimeNotify = true;

  // เช็คว่าเป็นบัญชีหลักหรือไม่ (ถ้าชื่อตรงกับ username ที่ login)
  bool get _isMasterProfile => _originalProfileName == widget.username;

  final dbHelper = DatabaseHelper();

  // รายการรูปภาพต้นฉบับ (Assets)
  final List<String> _avatarAssets = const [
    'assets/simpleProfile/profile_1.png',
    'assets/simpleProfile/profile_2.png',
    'assets/simpleProfile/profile_3.png',
    'assets/simpleProfile/profile_4.png',
    'assets/simpleProfile/profile_5.png',
    'assets/simpleProfile/profile_6.png',
  ];
  int? _selectedAvatarIndex;

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

    // ✅ โหลดเวลาอาหารจากโปรไฟล์นั้นๆ โดยตรง (รองรับทั้ง Master และ Sub-profile)
    _breakfastTime = p['breakfast']?.toString() ?? '06:00';
    _lunchTime = p['lunch']?.toString() ?? '12:00';
    _dinnerTime = p['dinner']?.toString() ?? '18:00';
    _bedtimeTime = p['bedtime']?.toString() ?? '21:00';
    _breakfastNotify = (p['breakfast_notify'] ?? 1) == 1;
    _lunchNotify = (p['lunch_notify'] ?? 1) == 1;
    _dinnerNotify = (p['dinner_notify'] ?? 1) == 1;
    _bedtimeNotify = (p['bedtime_notify'] ?? 1) == 1;
  }

  bool get _usingCustomImage =>
      _customImageBase64 != null && _customImageBase64!.isNotEmpty;

  // ฟังก์ชันแปลง Asset เป็น Base64
  Future<String> _loadAssetAsBase64(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    final buffer = byteData.buffer;
    final Uint8List uint8list = buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    return base64Encode(uint8list);
  }

  // ฟังก์ชันเลือกรูปจากรายการ Assets
  Future<void> _selectAvatarFromAssets(int index) async {
    try {
      final base64 = await _loadAssetAsBase64(_avatarAssets[index]);
      setState(() {
        _selectedAvatarIndex = index;
        _customImageBase64 = base64;
      });
    } catch (e) {
      debugPrint('editProfile: load asset error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('โหลดรูปโปรไฟล์ไม่สำเร็จ')));
    }
  }

  // ฟังก์ชันเลือกรูปจาก Gallery
  Future<void> _pickCustomImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);

      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final base64Str = base64Encode(bytes);

      setState(() {
        _customImageBase64 = base64Str;
        _selectedAvatarIndex = null;
      });
    } catch (e) {
      debugPrint('editProfile: pick image error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เกิดข้อผิดพลาดในการเลือกรูปภาพ')),
      );
    }
  }

  // Widget แสดงรูป Preview
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

  // ตรวจสอบรหัสผ่าน (Master Password)
  Future<bool> _verifyPassword(String inputPassword) async {
    try {
      final user = await dbHelper.getUser(widget.username);
      if (user != null) {
        if (AuthService.verifyPassword(inputPassword, user['password'].toString())) {
          return true;
        }
      }
    } catch (e) {
      debugPrint('editProfile: verifyPassword error: $e');
    }
    return false;
  }

  // Dialog ยืนยันรหัสผ่าน
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
                    'ใส่รหัสผ่านบัญชีหลักเพื่อยืนยันการดำเนินการ',
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

  // ✅ Helper: สร้าง Row เวลาอาหาร + สวิตช์เปิด/ปิด
  Widget _buildMealRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String time,
    required bool enabled,
    required VoidCallback onTimePick,
    required ValueChanged<bool> onToggle,
  }) {
    return Row(
      children: [
        Icon(icon, color: enabled ? iconColor : Colors.grey[400]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: enabled ? Colors.black : Colors.grey,
            ),
          ),
        ),
        TextButton(
          onPressed: enabled ? onTimePick : null,
          style: TextButton.styleFrom(
            backgroundColor: enabled ? Colors.grey[200] : Colors.grey[100],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            time,
            style: TextStyle(
              fontSize: 16,
              color: enabled ? Colors.black : Colors.grey,
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 48,
          child: Switch(
            value: enabled,
            onChanged: onToggle,
            activeColor: Colors.teal,
          ),
        ),
      ],
    );
  }

  // ✅ ฟังก์ชันเลือกเวลา (เหมือน EditAccountPage)
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

  // --- ฟังก์ชันบันทึกโปรไฟล์ ---
  Future<void> _saveProfile() async {
    if (_isSaving) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    // ป้องกันการเปลี่ยนชื่อบัญชีหลัก
    if (_isMasterProfile &&
        _nameController.text.trim() != _originalProfileName) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปลี่ยนชื่อบัญชีหลักได้')),
      );
      _nameController.text = _originalProfileName;
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

      // ✅ อัปเดตข้อมูลรวมถึงเวลาอาหารของโปรไฟล์นั้นๆ (ไม่ว่าจะ Master หรือ Sub)
      final Map<String, dynamic> updatedValues = {
        'userid': newName,
        'info': newInfo,
        'image_base64': _customImageBase64 ?? '',
        'breakfast': _breakfastTime,
        'lunch': _lunchTime,
        'dinner': _dinnerTime,
        'bedtime': _bedtimeTime,
        'breakfast_notify': _breakfastNotify ? 1 : 0,
        'lunch_notify': _lunchNotify ? 1 : 0,
        'dinner_notify': _dinnerNotify ? 1 : 0,
        'bedtime_notify': _bedtimeNotify ? 1 : 0,
      };

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

  // --- ฟังก์ชันลบโปรไฟล์ ---
  Future<void> _deleteProfile() async {
    if (_isSaving) return;

    if (_isMasterProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่สามารถลบบัญชีหลักได้ กรุณาใช้เมนูแก้ไขบัญชีหลัก'),
        ),
      );
      return;
    }

    final confirmed = await _showPasswordConfirmDialog();
    if (confirmed != true) {
      return;
    }

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
      _isSaving = true;
    });

    try {
      final db = await dbHelper.database;

      final count = await db.delete(
        'users',
        where: 'userid = ?',
        whereArgs: [_originalProfileName],
      );

      // ลบข้อมูลที่เกี่ยวข้อง (Cascade Logic)
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

      if (!mounted) return;

      if (count > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'ลบโปรไฟล์ "${_originalProfileName}" และข้อมูลที่เกี่ยวข้องเรียบร้อยแล้ว',
            ),
          ),
        );
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
                  readOnly: _isMasterProfile,
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

                // --- ✅ ส่วนแก้ไขเวลาอาหาร (เปิดให้แก้ไขได้ทุกโปรไฟล์) ---
                const Text(
                  'แก้ไขเวลาอาหาร (สำหรับแจ้งเตือน)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'เปิด/ปิดสวิตช์เพื่อเลือกมื้อที่ต้องการรับการแจ้งเตือน',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),

                // อาหารเช้า
                _buildMealRow(
                  icon: Icons.free_breakfast,
                  iconColor: Colors.brown,
                  label: 'อาหารเช้า',
                  time: _breakfastTime,
                  enabled: _breakfastNotify,
                  onTimePick: () => _pickTime(
                    initialTime: _breakfastTime,
                    label: 'อาหารเช้า',
                    onSelected: (time) =>
                        setState(() => _breakfastTime = time),
                  ),
                  onToggle: (v) => setState(() => _breakfastNotify = v),
                ),
                const Divider(),

                // อาหารกลางวัน
                _buildMealRow(
                  icon: Icons.fastfood,
                  iconColor: Colors.orange,
                  label: 'อาหารกลางวัน',
                  time: _lunchTime,
                  enabled: _lunchNotify,
                  onTimePick: () => _pickTime(
                    initialTime: _lunchTime,
                    label: 'อาหารกลางวัน',
                    onSelected: (time) => setState(() => _lunchTime = time),
                  ),
                  onToggle: (v) => setState(() => _lunchNotify = v),
                ),
                const Divider(),

                // อาหารเย็น
                _buildMealRow(
                  icon: Icons.dinner_dining,
                  iconColor: Colors.blueGrey,
                  label: 'อาหารเย็น',
                  time: _dinnerTime,
                  enabled: _dinnerNotify,
                  onTimePick: () => _pickTime(
                    initialTime: _dinnerTime,
                    label: 'อาหารเย็น',
                    onSelected: (time) => setState(() => _dinnerTime = time),
                  ),
                  onToggle: (v) => setState(() => _dinnerNotify = v),
                ),
                const Divider(),

                // ก่อนนอน
                _buildMealRow(
                  icon: Icons.bedtime,
                  iconColor: Colors.indigo,
                  label: 'ก่อนนอน',
                  time: _bedtimeTime,
                  enabled: _bedtimeNotify,
                  onTimePick: () => _pickTime(
                    initialTime: _bedtimeTime,
                    label: 'ก่อนนอน',
                    onSelected: (time) => setState(() => _bedtimeTime = time),
                  ),
                  onToggle: (v) => setState(() => _bedtimeNotify = v),
                ),
                const SizedBox(height: 24),

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

                if (!_isMasterProfile) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _deleteProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
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
