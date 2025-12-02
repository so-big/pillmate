// lib/manage_medicine.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'add_medicine.dart';
import 'edit_medicine.dart';

class MedicineManagePage extends StatefulWidget {
  final String username;

  const MedicineManagePage({super.key, required this.username});

  @override
  State<MedicineManagePage> createState() => _MedicineManagePageState();
}

class _MedicineManagePageState extends State<MedicineManagePage> {
  List<Map<String, dynamic>> _medicines = [];
  bool _isLoading = true;

  /// 'az' = A → Z, 'za' = Z → A
  String _sortOrder = 'az';

  Future<File> get _pillProfileFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/pillprofile.json');
  }

  @override
  void initState() {
    super.initState();
    _loadMedicines();
  }

  Future<void> _loadMedicines() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final file = await _pillProfileFile;
      List<dynamic> raw = [];

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is List) {
            raw = decoded;
          }
        }
      }

      final List<Map<String, dynamic>> list = [];

      for (final item in raw) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          if (m['createby'] == widget.username) {
            list.add(m);
          }
        }
      }

      _applySort(list);

      setState(() {
        _medicines = list;
      });
    } catch (e) {
      debugPrint('medicine_manage: error loading medicines: $e');
      setState(() {
        _medicines = [];
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _applySort(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final nameA = (a['name'] ?? '').toString().toLowerCase();
      final nameB = (b['name'] ?? '').toString().toLowerCase();
      final cmp = nameA.compareTo(nameB);
      return _sortOrder == 'az' ? cmp : -cmp;
    });
  }

  void _changeSortOrder(String newOrder) {
    if (newOrder == _sortOrder) return;
    setState(() {
      _sortOrder = newOrder;
      _applySort(_medicines);
    });
  }

  Future<void> _addMedicine() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MedicineAddPage(username: widget.username),
      ),
    );

    if (result != null) {
      await _loadMedicines();
    }
  }

  Future<void> _editMedicine(Map<String, dynamic> medicine) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            EditMedicinePage(username: widget.username, medicine: medicine),
      ),
    );

    if (result != null) {
      await _loadMedicines();
    }
  }

  Future<void> _deleteMedicine(Map<String, dynamic> medicine) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('ลบตัวยา'),
          content: Text('ต้องการลบ "${medicine['name'] ?? ''}" ใช่หรือไม่?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('ลบ'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      final file = await _pillProfileFile;
      if (!await file.exists()) return;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return;

      final decoded = jsonDecode(content);
      if (decoded is! List) return;

      final List<dynamic> list = List<dynamic>.from(decoded);
      final String targetId = (medicine['id'] ?? '').toString();

      list.removeWhere((item) {
        if (item is Map) {
          final id = (item['id'] ?? '').toString();
          final createBy = item['createby']?.toString();
          return id == targetId && createBy == widget.username;
        }
        return false;
      });

      await file.writeAsString(jsonEncode(list), flush: true);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ลบตัวยาเรียบร้อย')));

      await _loadMedicines();
    } catch (e) {
      debugPrint('medicine_manage: error deleting medicine: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถลบข้อมูลได้ กรุณาลองใหม่')),
      );
    }
  }

  Widget _buildMedicineImage(dynamic imageData) {
    if (imageData == null) {
      return const CircleAvatar(
        radius: 22,
        child: Icon(Icons.medication, color: Colors.white),
      );
    }

    if (imageData is String && imageData.isNotEmpty) {
      // ถ้าเป็น path asset
      if (imageData.startsWith('assets/')) {
        return CircleAvatar(
          radius: 22,
          backgroundColor: Colors.white,
          child: ClipOval(
            child: Image.asset(
              imageData,
              width: 40,
              height: 40,
              fit: BoxFit.contain,
            ),
          ),
        );
      }

      // ถ้าไม่ใช่ assets/ ถือว่าเป็น base64 (รูปที่อัปโหลดเอง)
      try {
        final bytes = base64Decode(imageData);
        return CircleAvatar(
          radius: 22,
          backgroundColor: Colors.white,
          child: ClipOval(
            child: Image.memory(
              bytes,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
            ),
          ),
        );
      } catch (e) {
        debugPrint('medicine_manage: decode image fail: $e');
        return const CircleAvatar(
          radius: 22,
          child: Icon(Icons.medication, color: Colors.white),
        );
      }
    }

    return const CircleAvatar(
      radius: 22,
      child: Icon(Icons.medication, color: Colors.white),
    );
  }

  Widget _buildSortBar() {
    return Row(
      children: [
        const Text(
          'เรียงตามชื่อ:',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: _sortOrder,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: 'az', child: Text('A → Z')),
            DropdownMenuItem(value: 'za', child: Text('Z → A')),
          ],
          onChanged: (value) {
            if (value == null) return;
            _changeSortOrder(value);
          },
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_medicines.isEmpty) {
      return Center(
        child: Text(
          'ยังไม่มีข้อมูลตัวยา\nกดปุ่ม + เพื่อเพิ่มตัวยาใหม่',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: _buildSortBar(),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            itemCount: _medicines.length,
            itemBuilder: (context, index) {
              final m = _medicines[index];
              final name = (m['name'] ?? '').toString();
              final detail = (m['detail'] ?? '').toString();
              final beforeMeal = m['beforeMeal'] == true;
              final afterMeal = m['afterMeal'] == true;

              String mealText = '';
              if (beforeMeal) {
                mealText = 'ก่อนอาหาร';
              } else if (afterMeal) {
                mealText = 'หลังอาหาร';
              }

              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _editMedicine(m),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        _buildMedicineImage(m['image']),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.isEmpty ? '(ไม่มีชื่อยา)' : name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              if (mealText.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  mealText,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.teal,
                                  ),
                                ),
                              ],
                              if (detail.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  detail,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          color: Colors.redAccent,
                          onPressed: () => _deleteMedicine(m),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('จัดการตัวยา')),
      body: SafeArea(child: _buildBody()),
      floatingActionButton: FloatingActionButton(
        onPressed: _addMedicine,
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add),
      ),
    );
  }
}
