// lib/editMedicine.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';

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

  @override
  void initState() {
    super.initState();

    final m = widget.medicine;

    _nameController = TextEditingController(text: (m['name'] ?? '').toString());
    _detailController = TextEditingController(
      text: (m['detail'] ?? '').toString(),
    );

    _beforeMeal = (m['beforeMeal'] == true);
    _afterMeal = (m['afterMeal'] == true);

    final img = m['image'];
    if (img is String && img.isNotEmpty) {
      if (_pillImages.contains(img)) {
        _selectedImage = img;
        _customImageBase64 = null;
      } else {
        _selectedImage = _pillImages.first;
        _customImageBase64 = img;
      }
    } else {
      _selectedImage = _pillImages.first;
      _customImageBase64 = null;
    }
  }

  bool get _usingCustomImage => _customImageBase64 != null;

  Future<File> get _pillProfileFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/pillprofile.json');
  }

  Future<File> get _usersFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/user.json');
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
          debugPrint('editMedicine: JSON decode error: $e');
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
      debugPrint('editMedicine: pick image error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เกิดข้อผิดพลาดในการเลือกรูปภาพ')),
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
      final original = widget.medicine;
      final oldId =
          original['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString();
      final now = DateTime.now();
      final imageValue = _usingCustomImage
          ? _customImageBase64
          : _selectedImage;

      final createdAt =
          original['createdAt']?.toString() ?? now.toIso8601String();
      final createBy = original['createby']?.toString() ?? widget.username;

      final updated = {
        'id': oldId,
        'name': name,
        'detail': detail,
        'image': imageValue,
        'beforeMeal': _beforeMeal,
        'afterMeal': _afterMeal,
        'createby': createBy,
        'createdAt': createdAt,
        'updatedAt': now.toIso8601String(),
      };

      bool replaced = false;

      // หา record ในไฟล์ด้วย id เดิม
      for (int i = 0; i < list.length; i++) {
        final item = list[i];
        if (item is Map || item is Map<String, dynamic>) {
          final map = Map<String, dynamic>.from(item);
          if ((map['id'] ?? '').toString() == oldId) {
            list[i] = updated;
            replaced = true;
            break;
          }
        }
      }

      // ถ้ายังไม่เจอเลย ก็เพิ่มใหม่
      if (!replaced) {
        list.add(updated);
      }

      await _savePillList(list);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกการแก้ไขตัวยาเรียบร้อย')),
      );

      setState(() {
        _isSaving = false;
      });

      Navigator.pop(context, updated);
    } catch (e) {
      debugPrint('editMedicine: save error: $e');
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
