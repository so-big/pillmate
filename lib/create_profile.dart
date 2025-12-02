// lib/create_profile.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui; // ใช้สำหรับจัดการรูป / วาดลง canvas

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

// Import DatabaseHelper
import 'database_helper.dart';

class CreateProfilePage extends StatefulWidget {
  const CreateProfilePage({super.key});

  @override
  State<CreateProfilePage> createState() => _CreateProfilePageState();
}

class _CreateProfilePageState extends State<CreateProfilePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _infoController =
      TextEditingController(); // ✅ เพิ่ม Controller สำหรับ Info

  bool _isSaving = false;
  String? _errorMessage;

  String? _currentUsername; // Master User (ผู้สร้าง)

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
  String? _selectedBase64Image; // base64 ที่จะเขียนลง DB

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<Directory> _appDir() async {
    return getApplicationDocumentsDirectory();
  }

  // ยังคงอ่านจาก user-stat.json เพื่อดูว่าใคร Login อยู่ (Master User)
  Future<void> _loadCurrentUser() async {
    try {
      final dir = await _appDir();
      final file = File('${dir.path}/user-stat.json');

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content);
          if (data is Map && data['username'] != null) {
            setState(() {
              _currentUsername = data['username'].toString();
            });
            return;
          }
        }
      }
      setState(() {
        _currentUsername ??= 'unknown';
      });
    } catch (e) {
      debugPrint('Error reading user-stat.json: $e');
      setState(() {
        _currentUsername ??= 'unknown';
      });
    }
  }

  // แปลง asset image -> base64
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
    // decode รูป
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image src = frame.image;

    final int w = src.width;
    final int h = src.height;

    if (w == 0 || h == 0) {
      return bytes; // กันรูปพังแปลก ๆ
    }

    final int minSide = w < h ? w : h;

    const double targetSize = 512.0;
    final double scale = targetSize / minSide;

    final double scaledW = w * scale;
    final double scaledH = h * scale;

    // เตรียม canvas ขนาด 512x512
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    final Paint paint = Paint();

    // ให้พื้นที่ทำงานคือ 512x512
    const Rect outputRect = Rect.fromLTWH(0, 0, targetSize, targetSize);
    canvas.clipRect(outputRect);

    // วาดรูปที่ถูก scale แล้วให้อยู่กลาง 512x512
    final double dx = (targetSize - scaledW) / 2;
    final double dy = (targetSize - scaledH) / 2;

    final Rect destRect = Rect.fromLTWH(dx, dy, scaledW, scaledH);
    final Rect srcRect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());

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
        processed = bytes; // ถ้าพลาดก็ใช้รูปเดิมไปก่อน
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

  // ✅ ฟังก์ชันบันทึกข้อมูลลง SQLite
  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final info = _infoController.text.trim(); // ✅ รับค่า info

    if (name.isEmpty) {
      setState(() {
        _errorMessage = 'กรุณากรอกชื่อโปรไฟล์';
      });
      return;
    }

    if (_currentUsername == null || _currentUsername == 'unknown') {
      setState(() {
        _errorMessage = 'ไม่พบข้อมูลผู้ใช้หลัก (Master User)';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final dbHelper = DatabaseHelper();

      // เตรียมข้อมูลลง DB
      Map<String, dynamic> row = {
        'userid': name, // ใช้ชื่อโปรไฟล์เป็น userid ของ sub-profile
        'password': '-', // ใส่ - ตามที่กำหนด
        'image_base64': _selectedBase64Image ?? '',
        'sub_profile':
            _currentUsername, // ✅ ระบุว่าใครเป็นเจ้าของ (Master User)
        'info': info, // ✅ บันทึกข้อมูลเพิ่มเติมลงคอลัมน์ info
        'created_at': DateTime.now().toIso8601String(),
      };

      // บันทึกลงตาราง users
      await dbHelper.insertUser(row);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('บันทึกโปรไฟล์เรียบร้อย')));

      Navigator.pop(context); // กลับไปหน้าก่อน
    } catch (e) {
      debugPrint('Error saving profile to DB: $e');

      // กรณี Error ส่วนใหญ่จะเป็นเรื่องชื่อซ้ำ (Unique Constraint)
      String msg = 'บันทึกไม่สำเร็จ: $e';
      if (e.toString().contains('UNIQUE constraint failed')) {
        msg = 'ชื่อโปรไฟล์ "$name" มีอยู่แล้ว กรุณาใช้ชื่ออื่น';
      }

      if (!mounted) return;
      setState(() {
        _errorMessage = msg;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
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

  Widget _buildAvatarSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'รูปโปรไฟล์',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 12),

        // รูปใหญ่ preview
        Center(child: _buildAvatarPreview()),

        const SizedBox(height: 16),

        // แถวรูปให้เลือกจาก assets
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

        // ปุ่มเลือกจากโทรศัพท์
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

  @override
  void dispose() {
    _nameController.dispose();
    _infoController.dispose(); // ✅ อย่าลืม dispose controller ตัวใหม่
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usernameText = _currentUsername ?? 'กำลังโหลด...';

    return Scaffold(
      appBar: AppBar(title: const Text('สร้างโปรไฟล์')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ผู้ใช้ปัจจุบัน
              Text(
                'ผู้ใช้ปัจจุบัน (Master): $usernameText',
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 16),

              // รูปโปรไฟล์
              _buildAvatarSelector(),
              const SizedBox(height: 24),

              // ชื่อโปรไฟล์
              const Text(
                'ชื่อโปรไฟล์',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: 'เช่น คุณพ่อ, คุณแม่, ตัวฉันเอง',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                ),
              ),

              const SizedBox(height: 16),

              // ✅ เพิ่มช่องกรอกข้อมูลเพิ่มเติม (info)
              const Text(
                'ข้อมูลเพิ่มเติม (ไม่จำเป็นต้องใส่)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _infoController,
                maxLines: 4, // กำหนดให้สูง 4 บรรทัด
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText:
                      'เช่น โรคประจำตัว, ยาที่แพ้, เบอร์ติดต่อฉุกเฉิน ฯลฯ',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  alignLabelWithHint: true,
                ),
              ),

              const SizedBox(height: 24),

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
                          'บันทึกโปรไฟล์',
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
