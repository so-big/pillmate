// lib/edit_medicine.dart

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

// ✅ เรียกใช้ DatabaseHelper
import 'database_helper.dart';
import 'services/auth_service.dart';

class EditMedicinePage extends StatefulWidget {
  final String username;
  final Map<String, dynamic> medicine;

  const EditMedicinePage({
    super.key,
    required this.username,
    required this.medicine,
  });

  @override
  State<EditMedicinePage> createState() => _EditMedicinePageState();
}

class _EditMedicinePageState extends State<EditMedicinePage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _detailController;

  bool _beforeMeal = true;
  bool _afterMeal = false;

  final List<String> _pillImages = const [
    'assets/pill/p_1.png',
    'assets/pill/p_2.png',
    'assets/pill/p_3.png',
    'assets/pill/p_4.png',
    'assets/pill/p_5.png',
  ];

  late String _selectedImage;
  String? _customImageBase64;

  bool _isSaving = false;
  final ImagePicker _picker = ImagePicker();

  // ประกาศตัวแปร dbHelper
  final dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();

    final m = widget.medicine;

    _nameController = TextEditingController(text: (m['name'] ?? '').toString());
    _detailController = TextEditingController(
      text: (m['detail'] ?? '').toString(),
    );

    // ✅ ปรับ Key ให้ตรงกับ SQLite (before_meal, after_meal เก็บเป็น 0/1)
    // แต่เพื่อความชัวร์ เผื่อ data เก่า เช็คทั้งสองแบบ
    if (m.containsKey('before_meal')) {
      _beforeMeal = (m['before_meal'] == 1);
    } else {
      _beforeMeal = (m['beforeMeal'] == true);
    }

    if (m.containsKey('after_meal')) {
      _afterMeal = (m['after_meal'] == 1);
    } else {
      _afterMeal = (m['afterMeal'] == true);
    }

    final img = m['image'];
    if (img is String && img.isNotEmpty) {
      // ถ้าเป็น path asset ที่มีอยู่ในลิสต์
      if (_pillImages.contains(img)) {
        _selectedImage = img;
        _customImageBase64 = null;
      }
      // ถ้าเป็น asset path แต่ไม่อยู่ในลิสต์ (เผื่อไว้)
      else if (img.startsWith('assets/')) {
        _selectedImage = img;
        _customImageBase64 = null;
      }
      // ถ้าไม่ใช่ asset ถือว่าเป็น Base64
      else {
        _selectedImage = _pillImages.first;
        _customImageBase64 = img;
      }
    } else {
      _selectedImage = _pillImages.first;
      _customImageBase64 = null;
    }
  }

  bool get _usingCustomImage => _customImageBase64 != null;

  // ✅ ฟังก์ชันย่อรูป (เหมือนเดิม)
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

  Future<void> _pickCustomImage() async {
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
        debugPrint('editMedicine: resize error: $e');
        processed = bytes;
      }

      final base64Str = base64Encode(processed);

      setState(() {
        _customImageBase64 = base64Str;
      });
    } catch (e) {
      debugPrint('editMedicine: pick image error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เกิดข้อผิดพลาดในการเลือกรูปภาพ')),
      );
    }
  }

  // ✅ แก้ไข: ตรวจสอบรหัสผ่านจาก SQLite
  Future<bool> _verifyPassword(String inputPassword) async {
    try {
      final user = await dbHelper.getUser(widget.username);
      if (user != null) {
        if (AuthService.verifyPassword(inputPassword, user['password'].toString())) {
          return true;
        }
      }
    } catch (e) {
      debugPrint('editMedicine: verifyPassword error: $e');
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
              title: const Text(
                'ยืนยันรหัสผ่าน',
                style: TextStyle(color: Colors.black),
              ),
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

  // ✅ แก้ไข: บันทึกข้อมูลลง SQLite (UPDATE)
  Future<void> _saveMedicine() async {
    if (_isSaving) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_beforeMeal && !_afterMeal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาเลือกว่าต้องกินก่อนหรือหลังอาหารอย่างน้อย 1 แบบ'),
        ),
      );
      return;
    }

    if (_beforeMeal && _afterMeal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('เลือกได้อย่างใดอย่างหนึ่ง: ก่อนอาหาร หรือ หลังอาหาร'),
        ),
      );
      return;
    }

    // ยืนยันรหัสผ่านก่อนเซฟ
    final confirmed = await _showPasswordConfirmDialog();
    if (confirmed != true) {
      return;
    }

    // จัดรูปแบบข้อมูลสำหรับบันทึก
    var name = _nameController.text.trim();
    var detail = _detailController.text.trim();

    // ตัดคำถ้าเกิน (ป้องกัน database error แม้ TEXT จะรับได้เยอะ)
    if (name.length > 50) name = name.substring(0, 50);
    if (detail.length > 100) detail = detail.substring(0, 100);

    setState(() {
      _isSaving = true;
    });

    try {
      final db = await dbHelper.database;

      final String imageValue = _usingCustomImage
          ? _customImageBase64!
          : _selectedImage;

      // เตรียมข้อมูลอัปเดต (ใช้ key snake_case ตาม DB)
      final Map<String, dynamic> updatedValues = {
        'name': name,
        'detail': detail,
        'image': imageValue,
        'before_meal': _beforeMeal ? 1 : 0,
        'after_meal': _afterMeal ? 1 : 0,
        // 'createby' ไม่ต้องแก้ เพราะเป็นคนเดิม
      };

      final String id = widget.medicine['id'].toString();

      // สั่ง Update
      await db.update(
        'medicines',
        updatedValues,
        where: 'id = ?',
        whereArgs: [id],
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกการแก้ไขตัวยาเรียบร้อย')),
      );

      Navigator.pop(context, updatedValues);
    } catch (e) {
      debugPrint('editMedicine: save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ไม่สามารถบันทึกข้อมูลได้: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildPreviewImage() {
    if (_usingCustomImage) {
      try {
        final bytes = base64Decode(_customImageBase64!);
        return ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: SizedBox(
            width: 80,
            height: 80,
            child: Image.memory(bytes, fit: BoxFit.cover),
          ),
        );
      } catch (_) {
        return const CircleAvatar(
          radius: 40,
          child: Icon(Icons.medication, size: 30),
        );
      }
    } else {
      return CircleAvatar(
        radius: 40,
        backgroundColor: Colors.white,
        child: ClipOval(
          child: Image.asset(
            _selectedImage,
            width: 64,
            height: 64,
            fit: BoxFit.contain,
          ),
        ),
      );
    }
  }

  Widget _buildPillImageSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: _buildPreviewImage()),
        const SizedBox(height: 12),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _pillImages.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index < _pillImages.length) {
                final path = _pillImages[index];
                final isSelected = !_usingCustomImage && path == _selectedImage;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _customImageBase64 = null;
                      _selectedImage = path;
                    });
                  },
                  child: Container(
                    width: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.teal : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(path, fit: BoxFit.contain),
                  ),
                );
              }

              final isCustomSelected = _usingCustomImage;

              return GestureDetector(
                onTap: _pickCustomImage,
                child: Container(
                  width: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCustomSelected
                          ? Colors.teal
                          : Colors.grey.shade300,
                      width: isCustomSelected ? 2 : 1,
                    ),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.add_a_photo, color: Colors.black54),
                      SizedBox(height: 4),
                      Text(
                        'เลือกรูป\nจากเครื่อง',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMealCheckboxes() {
    return Row(
      children: [
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _beforeMeal,
                onChanged: (v) {
                  setState(() {
                    _beforeMeal = v ?? false;
                    if (_beforeMeal) _afterMeal = false;
                  });
                },
              ),
              const Flexible(
                child: Text(
                  'ก่อนอาหาร',
                  style: TextStyle(fontSize: 14, color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _afterMeal,
                onChanged: (v) {
                  setState(() {
                    _afterMeal = v ?? false;
                    if (_afterMeal) _beforeMeal = false;
                  });
                },
              ),
              const Flexible(
                child: Text(
                  'หลังอาหาร',
                  style: TextStyle(fontSize: 14, color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
      appBar: AppBar(title: const Text('แก้ไขตัวยา')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ชื่อยา *',
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
                    hintText: 'ระบุชื่อยา (ไม่เกิน 50 ตัวอักษร)',
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
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) {
                      return 'กรุณาระบุชื่อยา';
                    }
                    if (v.length > 50) {
                      return 'ชื่อยาต้องไม่เกิน 50 ตัวอักษร';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                const Text(
                  'เลือกรูปตัวยา',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                _buildPillImageSelector(),

                const SizedBox(height: 16),

                const Text(
                  'เวลารับประทาน',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                _buildMealCheckboxes(),

                const SizedBox(height: 16),

                const Text(
                  'สรรพคุณ (ไม่จำเป็นต้องระบุ)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _detailController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.black87),
                  decoration: InputDecoration(
                    hintText:
                        'สรรพคุณหรือรายละเอียดเพิ่มเติมของยา (ไม่เกิน 100 ตัวอักษร)',
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
                    final v = value?.trim() ?? '';
                    if (v.length > 100) {
                      return 'สรรพคุณต้องไม่เกิน 100 ตัวอักษร';
                    }
                    return null;
                  },
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
                            'บันทึกการแก้ไขตัวยา',
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
