// lib/createAccount.dart

import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
// import 'package:path_provider/path_provider.dart'; // ไม่ต้องใช้แล้วเพราะย้ายไป Helper
import 'database_helper.dart'; // เรียกใช้ไฟล์ Database ที่สร้างใหม่

class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  // GlobalKey สำหรับฟอร์มและ Controller สำหรับ TextFields
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  String _message = ''; // ข้อความสถานะ

  // รูปโปรไฟล์เบื้องต้นจาก assets
  final List<String> _avatarAssets = const [
    'assets/simpleProfile/profile_1.png',
    'assets/simpleProfile/profile_2.png',
    'assets/simpleProfile/profile_3.png',
    'assets/simpleProfile/profile_4.png',
    'assets/simpleProfile/profile_5.png',
    'assets/simpleProfile/profile_6.png',
  ];

  int? _selectedAvatarIndex;
  String? _selectedBase64Image; // เก็บรูปโปรไฟล์ base64

  final ImagePicker _picker = ImagePicker();

  // เรียกใช้ Helper Database
  final dbHelper = DatabaseHelper();

  // (ลบ Future<File> get _localFile ทิ้ง เพราะไม่ใช้ JSON แล้ว)

  // โหลด asset image → base64
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
      debugPrint('Error loading avatar asset: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('โหลดรูปโปรไฟล์ไม่สำเร็จ')));
    }
  }

  /// รับ bytes รูป -> ย่อให้ด้านที่สั้นที่สุด = 512 -> crop กลางให้ได้ 512x512
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

  /// เลือกรูปจากโทรศัพท์ -> resize+center crop เป็น 512x512 -> base64
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
        debugPrint('Error resizing/cropping image: $e');
        processed = bytes;
      }

      final base64 = base64Encode(processed);

      setState(() {
        _selectedBase64Image = base64;
        _selectedAvatarIndex = null; // ไม่ใช้ avatar สำเร็จรูปแล้ว
      });
    } catch (e) {
      debugPrint('Error picking image from gallery: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เลือกรูปจากเครื่องไม่สำเร็จ')),
      );
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

  Widget _buildAvatarSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'รูปโปรไฟล์',
          textAlign: TextAlign.left,
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
                      color: isSelected ? Colors.blue : Colors.transparent,
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
      ],
    );
  }

  // 2. ฟังก์ชันบันทึกข้อมูลผู้ใช้ (เปลี่ยนจาก JSON File -> SQLite)
  Future<void> _saveUser(String username, String password) async {
    try {
      // ตรวจสอบว่ามี User นี้อยู่แล้วหรือไม่
      final existingUser = await dbHelper.getUser(username);

      if (existingUser != null) {
        setState(() {
          _message = 'Error: Username already exists!';
        });
        return;
      }

      // เตรียมข้อมูลลง SQLite (ตามคอลัมน์ที่คุณระบุ: userid, create_at, image_base64)
      // **หมายเหตุ:** ผมใส่ password ลงไปด้วยเพื่อให้ Login ได้ ถ้าตารางไม่มีให้ลบบรรทัด password ออกครับ
      Map<String, dynamic> newUser = {
        'userid': username,
        'password': password,
        'created_at': DateTime.now().toIso8601String(),
        'image_base64': _selectedBase64Image ?? '',
      };

      // บันทึกลง SQLite
      await dbHelper.insertUser(newUser);

      setState(() {
        _message = 'Success! Account created for $username';
      });

      // นำทางกลับไปยังหน้า Login หลังจากสร้างบัญชีสำเร็จ
      Future.delayed(const Duration(seconds: 2), () {
        Navigator.pop(context);
      });
    } catch (e) {
      setState(() {
        _message = 'Error saving data: $e';
      });
    }
  }

  // 3. ฟังก์ชันจัดการการกดปุ่มสมัครสมาชิก
  void _handleCreateAccount() {
    if (_formKey.currentState!.validate()) {
      if (_passwordController.text != _confirmPasswordController.text) {
        setState(() {
          _message = 'Error: Passwords do not match!';
        });
        return;
      }
      // บันทึกข้อมูล
      _saveUser(_usernameController.text, _passwordController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Account'),
        backgroundColor: Colors.teal,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF86E3CE), Color(0xFFD0F0C0)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Create Your Pillmate Account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 🔹 ส่วนเลือกรูปโปรไฟล์
                  _buildAvatarSelector(),
                  const SizedBox(height: 20),

                  // 1. Username Field
                  TextFormField(
                    style: const TextStyle(
                      color: Colors.black,
                    ), // Style เดิมของคุณ
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username (User ID)',
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a username';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // 2. Password Field
                  TextFormField(
                    style: const TextStyle(
                      color: Colors.black,
                    ), // Style เดิมของคุณ
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty || value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // 3. Confirm Password Field
                  TextFormField(
                    style: const TextStyle(
                      color: Colors.black,
                    ), // Style เดิมของคุณ
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm Password',
                      prefixIcon: Icon(Icons.lock_clock),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 40),

                  // Create Account Button
                  ElevatedButton(
                    onPressed: _handleCreateAccount,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: Colors.teal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'CREATE ACCOUNT',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Status Message
                  Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _message.startsWith('Error')
                          ? Colors.red
                          : Colors.green[800],
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 20),

                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Back to Login',
                      style: TextStyle(
                        color: Colors.blue[700],
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
