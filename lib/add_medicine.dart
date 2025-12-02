// lib/add_medicine.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

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

  late String _selectedImage;

  // base64 ของรูปจากเครื่อง
  String? _customImageBase64;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedImage = _pillImages.first;
  }

  bool get _usingCustomImage => _customImageBase64 != null;

  Future<File> get _pillProfileFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/pillprofile.json');
  }

  /// อ่าน / สร้าง list จากไฟล์ pillprofile.json
  Future<List<dynamic>> _loadPillList() async {
    final file = await _pillProfileFile;
    List<dynamic> list = [];
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(content);
          if (decoded is List) list = decoded;
        } catch (e) {
          debugPrint('medicine_add: JSON decode error: $e');
        }
      }
    }
    return list;
  }

  /// บันทึก list กลับลงไฟล์
  Future<void> _savePillList(List<dynamic> list) async {
    final file = await _pillProfileFile;
    await file.writeAsString(jsonEncode(list), flush: true);
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
      });
    } catch (e) {
      debugPrint('medicine_add: pick image error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เกิดข้อผิดพลาดในการเลือกรูปภาพ')),
      );
    }
  }

  /// บันทึกข้อมูลตัวยาลง JSON
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

    var name = _nameController.text.trim();
    var detail = _detailController.text.trim();

    if (name.length > 50) {
      name = name.substring(0, 50);
    }
    if (detail.length > 100) {
      detail = detail.substring(0, 100);
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final list = await _loadPillList();
      final now = DateTime.now();
      final imageValue = _usingCustomImage
          ? _customImageBase64
          : _selectedImage;

      final data = {
        'id': now.millisecondsSinceEpoch.toString(),
        'name': name,
        'detail': detail,
        'image': imageValue,
        'beforeMeal': _beforeMeal,
        'afterMeal': _afterMeal,
        'createby': widget.username,
        'createdAt': now.toIso8601String(),
      };

      list.add(data);
      await _savePillList(list);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกข้อมูลตัวยาเรียบร้อย')),
      );

      setState(() {
        _isSaving = false;
      });

      Navigator.pop(context, data);
    } catch (e) {
      debugPrint('medicine_add: save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ไม่สามารถบันทึกข้อมูลได้: $e')));
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
      appBar: AppBar(title: const Text('เพิ่มตัวยา')),
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
