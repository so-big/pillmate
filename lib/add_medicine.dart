// lib/add_medicine.dart

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

// ✅ เรียกใช้ DatabaseHelper
import 'database_helper.dart';

class MedicineAddPage extends StatefulWidget {
  final String username;

  const MedicineAddPage({super.key, required this.username});

  @override
  State<MedicineAddPage> createState() => _MedicineAddPageState();
}

class _MedicineAddPageState extends State<MedicineAddPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _detailController = TextEditingController();

  bool _beforeMeal = true;
  bool _afterMeal = false;

  // รูป default จาก assets
  final List<String> _pillImages = const [
    'assets/pill/p_1.png',
    'assets/pill/p_2.png',
    'assets/pill/p_3.png',
    'assets/pill/p_4.png',
    'assets/pill/p_5.png',
  ];

  late String _selectedImage; // เก็บ path ของรูปที่เลือก (ถ้าเป็น asset)

  // base64 ของรูปจากเครื่อง (ถ้าเลือกจาก Gallery)
  String? _customImageBase64;

  bool _isSaving = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _selectedImage = _pillImages[0]; // เริ่มต้นเลือกรูปแรก
  }

  // ฟังก์ชันย่อรูปและ Crop ให้เป็นสี่เหลี่ยมจัตุรัส (เหมือนหน้า Profile)
  Future<Uint8List> _resizeAndCenterCropToSquare(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image src = frame.image;

    final int w = src.width;
    final int h = src.height;

    if (w == 0 || h == 0) return bytes;

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
        debugPrint('Error resizing/cropping image: $e');
        processed = bytes;
      }

      final base64Str = base64Encode(processed);

      setState(() {
        _customImageBase64 = base64Str;
        // ถ้าเลือกรูปเอง ให้ path asset เป็นค่าว่างหรือค่าเดิมก็ได้ (แต่ UI จะเช็ค _customImageBase64 ก่อน)
      });
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('เลือกรูปไม่สำเร็จ')));
      }
    }
  }

  void _selectPillImage(int index) {
    setState(() {
      _selectedImage = _pillImages[index];
      _customImageBase64 = null; // เคลียร์รูป Custom ออกถ้ากลับมาเลือก Asset
    });
  }

  // ✅ ฟังก์ชันบันทึกข้อมูลลง SQLite
  Future<void> _saveMedicine() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;

      // เตรียมข้อมูล
      // ถ้ามี customImage ให้ใช้ base64, ถ้าไม่มีให้ใช้ path asset
      final String imageToSave = _customImageBase64 ?? _selectedImage;

      final String id = DateTime.now().millisecondsSinceEpoch.toString();

      final Map<String, dynamic> row = {
        'id': id,
        'name': _nameController.text.trim(),
        'detail': _detailController.text.trim(),
        'image': imageToSave,
        'before_meal': _beforeMeal ? 1 : 0, // SQLite ไม่มี bool ต้องใช้ int
        'after_meal': _afterMeal ? 1 : 0,
        'createby': widget.username,
        'created_at': DateTime.now().toIso8601String(),
      };

      // บันทึกลงตาราง medicines
      await db.insert('medicines', row);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('บันทึกข้อมูลยาเรียบร้อย')));

      Navigator.pop(context); // ปิดหน้าจอ
    } catch (e) {
      debugPrint('Error saving medicine to DB: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
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
    _detailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เพิ่มยาใหม่')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ส่วนแสดงรูปภาพที่เลือก
                Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal, width: 2),
                    ),
                    child: _customImageBase64 != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              base64Decode(_customImageBase64!),
                              fit: BoxFit.cover,
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Image.asset(
                              _selectedImage,
                              fit: BoxFit.contain,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  'เลือกรูปยา',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                // Grid เลือกรูปจาก Assets
                SizedBox(
                  height: 60,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _pillImages.length,
                    itemBuilder: (context, index) {
                      final isSelected =
                          (_customImageBase64 == null &&
                          _selectedImage == _pillImages[index]);
                      return GestureDetector(
                        onTap: () => _selectPillImage(index),
                        child: Container(
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.teal.withOpacity(0.2)
                                : Colors.transparent,
                            border: Border.all(
                              color: isSelected
                                  ? Colors.teal
                                  : Colors.grey.shade300,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Image.asset(
                            _pillImages[index],
                            width: 40,
                            height: 40,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 12),

                // ปุ่มเลือกจาก Gallery
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('เลือกรูปจากเครื่อง'),
                  ),
                ),

                const SizedBox(height: 24),

                // ชื่อยา
                TextFormField(
                  controller: _nameController,
                  // ✅ กำหนดสีตัวอักษรเป็นสีดำ
                  style: const TextStyle(color: Colors.black),
                  decoration: const InputDecoration(
                    labelText: 'ชื่อยา *',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'กรุณากรอกชื่อยา';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // รายละเอียด / สรรพคุณ
                TextFormField(
                  controller: _detailController,
                  maxLines: 3,
                  // ✅ กำหนดสีตัวอักษรเป็นสีดำ
                  style: const TextStyle(color: Colors.black),
                  decoration: const InputDecoration(
                    labelText: 'สรรพคุณ / รายละเอียด',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),

                // เงื่อนไขการกินยา
                const Text(
                  'ช่วงเวลาการทานยา',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                CheckboxListTile(
                  title: const Text('ก่อนอาหาร'),
                  value: _beforeMeal,
                  onChanged: (val) {
                    setState(() {
                      _beforeMeal = val ?? false;
                    });
                  },
                  activeColor: Colors.teal,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  title: const Text('หลังอาหาร'),
                  value: _afterMeal,
                  onChanged: (val) {
                    setState(() {
                      _afterMeal = val ?? false;
                    });
                  },
                  activeColor: Colors.teal,
                  controlAffinity: ListTileControlAffinity.leading,
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveMedicine,
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
                            'บันทึกข้อมูลตัวยา',
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
