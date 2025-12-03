// lib/edit_account.dart

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';

// 1. นำเข้า DatabaseHelper
import 'database_helper.dart';

class EditAccountPage extends StatefulWidget {
  final String username;

  const EditAccountPage({super.key, required this.username});

  @override
  State<EditAccountPage> createState() => _EditAccountPageState();
}

class _EditAccountPageState extends State<EditAccountPage> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  // ✅ NEW: Controller สำหรับคำตอบกันลืม
  final TextEditingController _securityAnswerController =
      TextEditingController();

  bool _isSaving = false;
  String? _errorMessage;

  Map<String, dynamic>? _accountUser;
  String? _selectedBase64Image;

  final List<String> _avatarAssets = const [
    'assets/simpleProfile/profile_1.png',
    'assets/simpleProfile/profile_2.png',
    'assets/simpleProfile/profile_3.png',
    'assets/simpleProfile/profile_4.png',
    'assets/simpleProfile/profile_5.png',
    'assets/simpleProfile/profile_6.png',
  ];
  int? _selectedAvatarIndex;

  // ✅ NEW: รายการคำถามกันลืม (ชุดเดียวกับ Create Account)
  final List<String> _securityQuestions = const [
    'ชื่อสัตว์เลี้ยงตัวแรกของคุณ?',
    'จังหวัดที่คุณเกิด?',
    'ชื่อกลางของแม่คุณ?',
    'สีที่คุณชื่นชอบ?',
    'อาหารจานโปรดของคุณ?',
  ];
  String? _selectedSecurityQuestion; // เก็บคำถามที่เลือก

  final ImagePicker _picker = ImagePicker();

  // 2. ประกาศตัวแปร dbHelper
  final dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  // 3. แก้ไขการโหลดข้อมูลจาก SQLite (เพิ่มการโหลด Security info)
  Future<void> _loadAccount() async {
    try {
      final user = await dbHelper.getUser(widget.username);

      if (user != null) {
        setState(() {
          // ต้องสร้าง copy map เพื่อให้แน่ใจว่าแก้ไขได้ (Mutable)
          _accountUser = Map<String, dynamic>.from(user);
          // ใช้ key 'image_base64' ให้ตรงกับ DB
          _selectedBase64Image = user['image_base64']?.toString();
          _selectedAvatarIndex = null;

          // ✅ NEW: โหลดคำถามและคำตอบเดิม
          if (user['security_question'] != null) {
            _selectedSecurityQuestion = user['security_question'].toString();
            // เช็คว่าคำถามเดิมอยู่ในลิสต์ไหม ถ้าไม่อยู่ (เช่น เป็นคำถามเก่า) ให้ reset หรือ handle ตามเหมาะสม
            if (!_securityQuestions.contains(_selectedSecurityQuestion)) {
              _selectedSecurityQuestion = null;
            }
          }
          if (user['security_answer'] != null) {
            _securityAnswerController.text = user['security_answer'].toString();
          }
        });
      } else {
        debugPrint('User not found in DB');
      }
    } catch (e) {
      debugPrint('Error loading account in EditAccountPage: $e');
    }
  }

  Future<String> _loadAssetAsBase64(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    final buffer = byteData.buffer;
    final Uint8List uint8list = buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    return base64Encode(uint8list);
  }

  Future<void> _selectAvatarFromAssets(int index) async {
    try {
      final base64 = await _loadAssetAsBase64(_avatarAssets[index]);
      setState(() {
        _selectedAvatarIndex = index;
        _selectedBase64Image = base64;
      });
    } catch (e) {
      debugPrint('Error loading avatar asset in EditAccount: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('โหลดรูปโปรไฟล์ไม่สำเร็จ')),
        );
      }
    }
  }

  Future<Uint8List> _resizeAndCenterCropToSquare(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image src = frame.image;

    final int w = src.width;
    final int h = src.height;

    if (w == 0 || h == 0) {
      return bytes;
    }

    final int minSide = w < h ? w : h;
    const double targetSize = 512.0;
    final double scale = targetSize / minSide;

    final double scaledW = w * scale;
    final double scaledH = h * scale;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    const Rect outputRect = Rect.fromLTWH(0, 0, targetSize, targetSize);
    canvas.clipRect(outputRect);

    final double dx = (targetSize - scaledW) / 2;
    final double dy = (targetSize - scaledH) / 2;

    final Rect destRect = Rect.fromLTWH(dx, dy, scaledW, scaledH);
    final Rect srcRect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());

    final Paint paint = Paint();
    canvas.drawImageRect(src, srcRect, destRect, paint);

    final ui.Image outImage = await recorder.endRecording().toImage(
      targetSize.toInt(),
      targetSize.toInt(),
    );

    final byteData = await outImage.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();

      Uint8List processed;
      try {
        processed = await _resizeAndCenterCropToSquare(bytes);
      } catch (e) {
        debugPrint('Error resizing/cropping image in EditAccount: $e');
        processed = bytes;
      }

      final base64 = base64Encode(processed);

      setState(() {
        _selectedBase64Image = base64;
        _selectedAvatarIndex = null;
      });
    } catch (e) {
      debugPrint('Error picking image from gallery in EditAccount: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เลือกรูปจากเครื่องไม่สำเร็จ')),
        );
      }
    }
  }

  Widget _buildAvatarPreview() {
    Widget child;

    if (_selectedAvatarIndex != null) {
      child = ClipOval(
        child: Image.asset(
          _avatarAssets[_selectedAvatarIndex!],
          fit: BoxFit.cover,
          width: 96,
          height: 96,
        ),
      );
    } else if (_selectedBase64Image != null &&
        _selectedBase64Image!.isNotEmpty) {
      try {
        final bytes = base64Decode(_selectedBase64Image!);
        child = ClipOval(
          child: Image.memory(bytes, fit: BoxFit.cover, width: 96, height: 96),
        );
      } catch (_) {
        child = const CircleAvatar(
          radius: 48,
          child: Icon(Icons.person, size: 40),
        );
      }
    } else {
      child = const CircleAvatar(
        radius: 48,
        child: Icon(Icons.person, size: 40),
      );
    }

    return child;
  }

  // 4. แก้ไขการตรวจสอบรหัสผ่านเดิมจาก SQLite
  Future<bool> _validateOldPassword(String oldPassword) async {
    try {
      final user = await dbHelper.getUser(widget.username);
      if (user != null && user['password'] == oldPassword) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error validating old password in EditAccount: $e');
      return false;
    }
  }

  Future<void> _saveAccount() async {
    final newPwd = _newPasswordController.text.trim();
    final confirmPwd = _confirmPasswordController.text.trim();

    // Validation รหัสผ่านใหม่ (ถ้ามีการกรอก)
    if (newPwd.isNotEmpty && newPwd.length < 6) {
      setState(() {
        _errorMessage = 'รหัสผ่านใหม่ต้องมีอย่างน้อย 6 ตัวอักษร';
      });
      return;
    }

    if (newPwd.isNotEmpty && newPwd != confirmPwd) {
      setState(() {
        _errorMessage = 'รหัสผ่านใหม่และยืนยันรหัสผ่านไม่ตรงกัน';
      });
      return;
    }

    // Validation คำถามกันลืม (ควรต้องมีข้อมูล)
    if (_selectedSecurityQuestion == null) {
      setState(() {
        _errorMessage = 'กรุณาเลือกคำถามกันลืม';
      });
      return;
    }
    if (_securityAnswerController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'กรุณากรอกคำตอบกันลืม';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
    });

    // --- Dialog ถามรหัสผ่านเดิม ---
    final TextEditingController pwdController = TextEditingController();
    String? errorText;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: const Text(
                'ยืนยันการแก้ไขบัญชี',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'กรุณากรอกรหัสผ่านเดิมของคุณเพื่อยืนยันการแก้ไข',
                    style: TextStyle(fontSize: 14, color: Colors.black),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pwdController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.black),
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.black),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.black, width: 2),
                      ),
                      errorBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.red),
                      ),
                      focusedErrorBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.red, width: 2),
                      ),
                      labelText: 'รหัสผ่านเดิม',
                      labelStyle: const TextStyle(color: Colors.black54),
                      errorText: errorText,
                      errorStyle: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.black87),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final input = pwdController.text.trim();
                    if (input.isEmpty) {
                      setStateDialog(() {
                        errorText = 'กรุณากรอกรหัสผ่านเดิม';
                      });
                      return;
                    }

                    final ok = await _validateOldPassword(input);
                    if (!ok) {
                      setStateDialog(() {
                        errorText = 'รหัสผ่านเดิมไม่ถูกต้อง';
                      });
                      return;
                    }

                    if (mounted) {
                      Navigator.pop(ctx); // ปิด Dialog
                      // ทำการบันทึก
                      await _applyAccountChanges(
                        newPwd.isEmpty ? null : newPwd,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('ยืนยัน'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 5. แก้ไขการบันทึกข้อมูลลง SQLite (เพิ่ม security question/answer)
  Future<void> _applyAccountChanges(String? newPassword) async {
    setState(() {
      _isSaving = true;
    });

    try {
      if (_accountUser == null) {
        throw Exception('User data is null');
      }

      // สร้าง Map ใหม่สำหรับเตรียมอัปเดต
      final Map<String, dynamic> updatedUser = Map<String, dynamic>.from(
        _accountUser!,
      );

      // อัปเดตรหัสผ่านถ้ามีการเปลี่ยน
      if (newPassword != null) {
        updatedUser['password'] = newPassword;
      }

      // อัปเดตรูปภาพโดยใช้ key 'image_base64'
      updatedUser['image_base64'] =
          _selectedBase64Image ?? updatedUser['image_base64'] ?? '';

      // ✅ NEW: อัปเดตคำถามและคำตอบกันลืม
      updatedUser['security_question'] = _selectedSecurityQuestion;
      updatedUser['security_answer'] = _securityAnswerController.text.trim();

      // ลบ key 'image' เก่าออกถ้ามี
      updatedUser.remove('image');

      // เรียกใช้ updateUser ใน DatabaseHelper
      await dbHelper.updateUser(updatedUser);

      if (!mounted) return;
      Navigator.pop(context); // ปิดหน้า EditAccountPage

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('แก้ไขข้อมูลสำเร็จ')));
    } catch (e) {
      debugPrint('Error applying account changes: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'บันทึกการแก้ไขไม่สำเร็จ: $e';
      });
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
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _securityAnswerController.dispose(); // ✅ NEW: dispose answer controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usernameText = widget.username;

    return Scaffold(
      appBar: AppBar(title: const Text('แก้ไขบัญชีผู้ใช้')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'บัญชี: $usernameText',
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 16),

              const Text(
                'รูปโปรไฟล์',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 12),

              Center(child: _buildAvatarPreview()),
              const SizedBox(height: 16),

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

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('เลือกรูปจากโทรศัพท์'),
                ),
              ),

              const SizedBox(height: 24),

              // ✅ NEW: ส่วนแก้ไขคำถามกันลืม
              const Text(
                'ตั้งค่าความปลอดภัย',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _selectedSecurityQuestion,
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(
                  labelText: 'คำถามกันลืม',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.help_outline),
                ),
                items: _securityQuestions.map((String question) {
                  return DropdownMenuItem<String>(
                    value: question,
                    child: Text(question),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedSecurityQuestion = newValue;
                  });
                },
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _securityAnswerController,
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(
                  labelText: 'คำตอบกันลืม',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.security),
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'เปลี่ยนรหัสผ่าน (ไม่บังคับ)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _newPasswordController,
                obscureText: true,
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'รหัสผ่านใหม่',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                style: const TextStyle(color: Colors.black),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'ยืนยันรหัสผ่านใหม่',
                ),
              ),

              const SizedBox(height: 16),

              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveAccount,
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
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'บันทึกการแก้ไขบัญชี',
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
    );
  }
}
