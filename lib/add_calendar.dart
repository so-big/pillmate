// lib/add_calendar.dart

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';

import 'create_profile.dart';
import 'add_medicine.dart';

import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;

// ✅ เรียกใช้ DatabaseHelper
import 'database_helper.dart';

// ❌ ลบ Import นี้ออกได้เลยค่ะ เพราะไม่ได้ใช้แล้ว
// import 'nortification_service.dart';

class CarlendarAddSheet extends StatefulWidget {
  final String username;
  final ScrollController? scrollController;

  const CarlendarAddSheet({
    super.key,
    required this.username,
    this.scrollController,
  });

  @override
  State<CarlendarAddSheet> createState() => _CarlendarAddSheetState();
}

class _CarlendarAddSheetState extends State<CarlendarAddSheet> {
  // ... (ส่วนประกาศตัวแปรเหมือนเดิม ไม่เปลี่ยนแปลง) ...
  List<Map<String, dynamic>> _profiles = [];
  String? _selectedProfileName;
  bool _isLoading = true;
  DateTime _startDateTime = DateTime.now();
  DateTime _endDateTime = DateTime.now();
  // notify_mode: 'interval' (ตามเวลา) หรือ 'meal' (ตามมื้ออาหาร)
  String _notifyMode = 'interval';
  int _intervalMinutes = 4 * 60;
  List<Map<String, dynamic>> _medicines = [];
  String? _selectedMedicineId;
  bool _isLoadingMedicines = false;
  bool _isSaving = false;
  bool _isNfcEnabled = false;
  final dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _endDateTime = _startDateTime;
    _loadProfiles();
    _loadMedicines();
    _loadNfcStatus();
  }

  // ... (ฟังก์ชัน Load ต่างๆ และ UI Helpers เหมือนเดิม) ...
  // (ข้ามมาส่วนที่สำคัญคือ _handleSave)

  Future<void> _loadNfcStatus() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/pillmate/appstatus.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content);
          if (data is Map) {
            setState(() {
              _isNfcEnabled = data['nfc_enabled'] ?? false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('CarlendarAdd: error loading NFC status: $e');
      setState(() {
        _isNfcEnabled = false;
      });
    }
  }

  Future<void> _loadProfiles() async {
    // ... (โค้ดเดิม) ...
    setState(() {
      _isLoading = true;
    });

    try {
      final db = await dbHelper.database;
      final profiles = <Map<String, dynamic>>[];
      final masterUser = await dbHelper.getUser(widget.username);
      if (masterUser != null) {
        profiles.add({
          'name': masterUser['userid'],
          'createby': widget.username,
          'image': masterUser['image_base64'],
        });
      }
      final List<Map<String, dynamic>> subs = await db.query(
        'users',
        where: 'sub_profile = ?',
        whereArgs: [widget.username],
      );
      for (var p in subs) {
        profiles.add({
          'name': p['userid'],
          'createby': widget.username,
          'image': p['image_base64'],
        });
      }
      setState(() {
        _profiles = profiles;
        _selectedProfileName = profiles.isNotEmpty
            ? profiles.first['name']?.toString()
            : null;
      });
    } catch (e) {
      debugPrint('CarlendarAdd: error loading profiles DB: $e');
      setState(() {
        _profiles = [];
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMedicines() async {
    // ... (โค้ดเดิม) ...
    setState(() {
      _isLoadingMedicines = true;
    });

    try {
      final db = await dbHelper.database;
      final List<Map<String, dynamic>> result = await db.query(
        'medicines',
        where: 'createby = ?',
        whereArgs: [widget.username],
      );
      // Debug: แสดงค่า before_meal/after_meal ของแต่ละยา
      for (final m in result) {
        debugPrint('💊 _loadMedicines: id=${m['id']}, name=${m['name']}, before_meal=${m['before_meal']}, after_meal=${m['after_meal']}');
      }
      setState(() {
        _medicines = List<Map<String, dynamic>>.from(result);
        if (_medicines.isNotEmpty && _selectedMedicineId == null) {
          _selectedMedicineId = _medicines.first['id']?.toString();
        }
      });
    } catch (e) {
      debugPrint('CarlendarAdd: error loading medicines DB: $e');
      setState(() {
        _medicines = [];
      });
    } finally {
      setState(() {
        _isLoadingMedicines = false;
      });
    }
  }

  // ... (ฟังก์ชัน UI: _buildProfileAvatar, _buildMedicineAvatar, _goTo..., Pickers) ...
  // (เพื่อให้โค้ดกระชับ ขอละไว้ในฐานที่เข้าใจ เพราะไม่ได้แก้ไขส่วนนี้)

  Widget _buildProfileAvatar(dynamic imageData) {
    if (imageData == null || imageData.toString().isEmpty) {
      return const CircleAvatar(
        radius: 16,
        child: Icon(Icons.person, size: 18),
      );
    }
    try {
      final bytes = base64Decode(imageData.toString());
      return CircleAvatar(radius: 16, backgroundImage: MemoryImage(bytes));
    } catch (e) {
      return const CircleAvatar(
        radius: 16,
        child: Icon(Icons.person, size: 18),
      );
    }
  }

  Widget _buildMedicineAvatar(dynamic imageData) {
    if (imageData == null || imageData.toString().isEmpty) {
      return const CircleAvatar(
        radius: 16,
        child: Icon(Icons.medication, size: 18),
      );
    }
    final str = imageData.toString();
    if (str.startsWith('assets/')) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: Colors.white,
        child: ClipOval(child: Image.asset(str, fit: BoxFit.contain)),
      );
    }
    try {
      final bytes = base64Decode(str);
      return CircleAvatar(radius: 16, backgroundImage: MemoryImage(bytes));
    } catch (e) {
      return const CircleAvatar(
        radius: 16,
        child: Icon(Icons.medication, size: 18),
      );
    }
  }

  Future<void> _goToCreateProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateProfilePage()),
    );
    await _loadProfiles();
  }

  Future<void> _goToAddMedicine() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MedicineAddPage(username: widget.username),
      ),
    );
    await _loadMedicines();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('th', 'TH'),
    );
    if (picked == null) return;
    setState(() {
      _startDateTime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _startDateTime.hour,
        _startDateTime.minute,
      );
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('th', 'TH'),
    );
    if (picked == null) return;
    setState(() {
      _endDateTime = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _endDateTime.hour,
        _endDateTime.minute,
      );
    });
  }

  Future<void> _showTimePickerSheet({
    required int initialHour,
    required int initialMinute,
    required void Function(int hour, int minute) onSelected,
  }) async {
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
              const Text(
                'เลือกเวลา (24 ชั่วโมง)',
                textAlign: TextAlign.center,
                style: TextStyle(
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
                      onSelected(selectedHour, selectedMinute);
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

  Future<void> _pickStartTime() async {
    await _showTimePickerSheet(
      initialHour: _startDateTime.hour,
      initialMinute: _startDateTime.minute,
      onSelected: (h, m) {
        setState(() {
          _startDateTime = DateTime(
            _startDateTime.year,
            _startDateTime.month,
            _startDateTime.day,
            h,
            m,
          );
        });
      },
    );
  }

  Future<void> _pickEndTime() async {
    await _showTimePickerSheet(
      initialHour: _endDateTime.hour,
      initialMinute: _endDateTime.minute,
      onSelected: (h, m) {
        setState(() {
          _endDateTime = DateTime(
            _endDateTime.year,
            _endDateTime.month,
            _endDateTime.day,
            h,
            m,
          );
        });
      },
    );
  }

  String _formatIntervalLabel() {
    final h = _intervalMinutes ~/ 60;
    final m = _intervalMinutes % 60;
    return '${h.toString().padLeft(2, '0')}.${m.toString().padLeft(2, '0')}';
  }

  Future<void> _pickIntervalMinutes() async {
    int tempHour = _intervalMinutes ~/ 60;
    int tempMinute = _intervalMinutes % 60;

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
              const Text(
                'เลือกช่วงเวลาห่างในการแจ้งเตือน (ชั่วโมง.นาที)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: tempHour.clamp(0, 24),
                        ),
                        itemExtent: 32,
                        magnification: 1.1,
                        useMagnifier: true,
                        onSelectedItemChanged: (index) {
                          tempHour = index;
                        },
                        children: List.generate(
                          25, // 0..24
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
                          initialItem: tempMinute.clamp(0, 59),
                        ),
                        itemExtent: 32,
                        magnification: 1.1,
                        useMagnifier: true,
                        onSelectedItemChanged: (index) {
                          tempMinute = index;
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
                      int total = tempHour * 60 + tempMinute;
                      if (total <= 0) total = 1;
                      if (total > 24 * 60) total = 24 * 60;

                      setState(() {
                        _intervalMinutes = total;
                      });
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

  String _formatDate(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    return '$day/$month/$year';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // ✅ แสดงสรรพคุณยาของเม็ดยาที่เลือก
  List<Widget> _buildMedicinePropertiesSection() {
    Map<String, dynamic>? med;
    try {
      med = _medicines.firstWhere(
        (m) => m['id']?.toString() == _selectedMedicineId,
      );
    } catch (_) {
      med = null;
    }
    if (med == null) return [];

    final name = med['name']?.toString() ?? '-';
    final detail = med['detail']?.toString() ?? '';
    final beforeMeal = (med['before_meal'] == 1);
    final afterMeal = (med['after_meal'] == 1);

    String mealLabel = '-';
    if (beforeMeal && afterMeal) {
      mealLabel = 'ก่อนอาหาร / หลังอาหาร';
    } else if (beforeMeal) {
      mealLabel = 'ก่อนอาหาร';
    } else if (afterMeal) {
      mealLabel = 'หลังอาหาร';
    }

    return [
      const Text(
        'สรรพคุณยา',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.medication, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                detail,
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.restaurant_menu, color: Colors.orange, size: 16),
                const SizedBox(width: 4),
                Text(
                  'การทานยา: $mealLabel',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  // ✅ แก้ไข Logic การบันทึก: ลบ Trigger ออก (เพราะหน้า Dashboard ทำหน้าที่แทนแล้ว)
  Future<void> _handleSave() async {
    if (_isSaving) return;

    if (_selectedProfileName == null || _selectedProfileName!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกโปรไฟล์ผู้รับยา')),
      );
      return;
    }

    if (_selectedMedicineId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกตัวยาที่ต้องการแจ้งเตือน')),
      );
      return;
    }

    // หาเม็ดยาที่เลือกจาก List ที่โหลดมาจาก DB
    Map<String, dynamic>? med;
    try {
      med = _medicines.firstWhere(
        (m) => m['id']?.toString() == _selectedMedicineId,
      );
    } catch (_) {
      med = null;
    }

    if (med == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ไม่พบข้อมูลตัวยาที่เลือก')));
      return;
    }

    var name = med['name']?.toString() ?? '';
    var detail = med['detail']?.toString() ?? '';

    if (name.length > 50) name = name.substring(0, 50);
    if (detail.length > 100) detail = detail.substring(0, 100);

    bool beforeMeal = (med['before_meal'] == 1);
    bool afterMeal = (med['after_meal'] == 1);

    debugPrint('🔍 _handleSave: medicine before_meal=${med['before_meal']} (${med['before_meal'].runtimeType}), after_meal=${med['after_meal']} (${med['after_meal'].runtimeType})');
    debugPrint('🔍 _handleSave: parsed beforeMeal=$beforeMeal, afterMeal=$afterMeal');

    if (!beforeMeal && !afterMeal) {
      beforeMeal = true;
      afterMeal = false;
      debugPrint('🔍 _handleSave: FALLBACK -> beforeMeal=true (ทั้งคู่เป็น false)');
    } else if (beforeMeal && afterMeal) {
      afterMeal = false;
      debugPrint('🔍 _handleSave: OVERRIDE -> afterMeal=false (ทั้งคู่เป็น true)');
    }

    debugPrint('🔍 _handleSave: FINAL beforeMeal=$beforeMeal, afterMeal=$afterMeal');

    final flag = beforeMeal ? '1' : '2';

    final h = _intervalMinutes ~/ 60;
    final m = _intervalMinutes % 60;
    final et =
        '${h.toString().padLeft(2, '0')}.${m.toString().padLeft(2, '0')}';

    final profileName = _selectedProfileName!.trim();

    final payloadText = '$name~$detail~e=$flag~et=$et~$profileName';

    setState(() {
      _isSaving = true;
    });

    String? nfcTagId;

    // ✅ Logic ใหม่: เช็คตามการตั้งค่า NFC ใน json
    if (_isNfcEnabled) {
      // ===== กรณีเปิดใช้ NFC =====
      BuildContext? scanDialogContext;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          scanDialogContext = ctx;
          return AlertDialog(
            backgroundColor: Colors.white,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.nfc, size: 50, color: Colors.black),
                SizedBox(height: 16),
                Text(
                  'กรุณาแตะ tag nfc ที่เซ็นเซอร์เพื่อบันทึกค่า',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                },
                child: const Text(
                  'ยกเลิก',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          );
        },
      );

      try {
        final availability = await FlutterNfcKit.nfcAvailability;
        if (availability != NFCAvailability.available) {
          throw 'อุปกรณ์นี้ไม่รองรับ NFC หรือยังไม่ได้เปิดใช้งาน';
        }

        final tag = await FlutterNfcKit.poll(
          timeout: const Duration(seconds: 15),
          iosMultipleTagMessage: 'พบหลายแท็ก',
          iosAlertMessage: 'แตะแท็กที่ต้องการ',
        );

        if (tag.ndefWritable != true) {
          throw 'แท็กนี้ไม่สามารถเขียน NDEF ได้';
        }

        final record = ndef.TextRecord(language: 'th', text: payloadText);
        await FlutterNfcKit.writeNDEFRecords([record]);

        nfcTagId = tag.id;

        try {
          await FlutterNfcKit.finish(iosAlertMessage: 'สำเร็จ');
        } catch (_) {}

        if (scanDialogContext != null && scanDialogContext!.mounted) {
          Navigator.pop(scanDialogContext!);
          scanDialogContext = null;
        }
      } catch (e) {
        debugPrint('CarlendarAdd: NFC write error: $e');

        try {
          await FlutterNfcKit.finish(iosErrorMessage: 'ล้มเหลว');
        } catch (_) {}

        if (scanDialogContext != null && scanDialogContext!.mounted) {
          Navigator.pop(scanDialogContext!);
          scanDialogContext = null;
        }

        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.white,
              title: const Text(
                'ผิดพลาด',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: const Text(
                'การบันทึกข้อมูลลง NFC ไม่สำเร็จ\nกรุณาตรวจสอบระบบ sensor และ tag nfc',
                style: TextStyle(color: Colors.black),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'ตกลง',
                    style: TextStyle(color: Colors.teal),
                  ),
                ),
              ],
            ),
          );

          setState(() {
            _isSaving = false;
          });
        }
        return;
      }
    } else {
      // ===== กรณีปิด NFC =====
      debugPrint('CarlendarAdd: NFC is disabled. Saving to DB only.');
      nfcTagId = 'MANUAL-${DateTime.now().millisecondsSinceEpoch}';
    }

    // *** ส่วนการบันทึกลง SQLite ***
    try {
      final now = DateTime.now();
      final db = await dbHelper.database;

      final Map<String, dynamic> row = {
        'id': now.millisecondsSinceEpoch.toString(),
        'createby': widget.username,
        'profile_name': profileName,
        'medicine_id': _selectedMedicineId,
        'medicine_name': name,
        'medicine_detail': detail,
        'medicine_before_meal': beforeMeal ? 1 : 0,
        'medicine_after_meal': afterMeal ? 1 : 0,
        'start_date_time': _startDateTime.toIso8601String(),
        'end_date_time': _endDateTime.toIso8601String(),
        'notify_by_time': _notifyMode == 'interval' ? 1 : 0,
        'notify_by_meal': _notifyMode == 'meal' ? 1 : 0,
        'notify_mode': _notifyMode,
        'interval_minutes': _intervalMinutes,
        'interval_hours': (_intervalMinutes / 60).round(),
        'et': et,
        'nfc_id': nfcTagId,
        'payload': payloadText,
        'created_at': now.toIso8601String(),
      };

      debugPrint('📝 calendar_alerts INSERT: medicine_before_meal=${row['medicine_before_meal']}, medicine_after_meal=${row['medicine_after_meal']}, notify_mode=${row['notify_mode']}');

      await db.insert('calendar_alerts', row);

      // ❌ ลบ Trigger ออก (เพราะหน้า Dashboard จะจัดการเมื่อ pop กลับไป)
      // scheduleNotificationForNewAlert(row);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกการแจ้งเตือนในระบบเรียบร้อย')),
      );

      setState(() {
        _isSaving = false;
      });

      // ส่ง row กลับไปให้ Dashboard (เพื่อ trigger reload)
      Navigator.pop(context, row);
    } catch (e) {
      debugPrint('CarlendarAdd: SQLite save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ไม่สามารถบันทึกในระบบได้: $e')));
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ... (ส่วน UI เหมือนเดิม) ...
    return SafeArea(
      top: false,
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
          ),
          child: ListView(
            controller: widget.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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

              const SizedBox(height: 8),

              // เลือกโปรไฟล์
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'เลือกโปรไฟล์',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  IconButton(
                    onPressed: _goToCreateProfile,
                    icon: const Icon(Icons.add_circle_outline),
                    color: Colors.blue,
                    tooltip: 'เพิ่มโปรไฟล์ใหม่',
                  ),
                ],
              ),

              const SizedBox(height: 8),

              if (_isLoading)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_profiles.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'ยังไม่มีโปรไฟล์',
                    style: TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _profiles.map((p) {
                        final name = p['name']?.toString() ?? '-';
                        final isSelected = _selectedProfileName == name;

                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedProfileName = name;
                              });
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.blue
                                    : Colors.grey[300],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildProfileAvatar(p['image']),
                                  const SizedBox(width: 6),
                                  Text(
                                    name,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // เริ่มต้นแจ้งเตือน
              const Text(
                'วันเวลา/เริ่มต้นแจ้งเตือน',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _pickStartDate,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        backgroundColor: Colors.grey[200],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(
                        Icons.calendar_today,
                        color: Colors.black87,
                      ),
                      label: Text(
                        _formatDate(_startDateTime),
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _pickStartTime,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        backgroundColor: Colors.grey[200],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(
                        Icons.access_time,
                        color: Colors.black87,
                      ),
                      label: Text(
                        _formatTime(_startDateTime),
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // สิ้นสุดแจ้งเตือน
              const Text(
                'วันเวลา/สิ้นสุดการแจ้งเตือน',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _pickEndDate,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        backgroundColor: Colors.grey[200],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(
                        Icons.calendar_today,
                        color: Colors.black87,
                      ),
                      label: Text(
                        _formatDate(_endDateTime),
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _pickEndTime,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        backgroundColor: Colors.grey[200],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(
                        Icons.access_time,
                        color: Colors.black87,
                      ),
                      label: Text(
                        _formatTime(_endDateTime),
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // รูปแบบการแจ้งเตือน
              const Text(
                'รูปแบบการแจ้งเตือน',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'แจ้งเตือนตามเวลา',
                        style: TextStyle(color: Colors.black, fontSize: 14),
                      ),
                      value: 'interval',
                      groupValue: _notifyMode,
                      onChanged: (v) {
                        setState(() {
                          _notifyMode = v ?? 'interval';
                        });
                      },
                      activeColor: Colors.teal,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'แจ้งเตือนตามมื้ออาหาร',
                        style: TextStyle(color: Colors.black, fontSize: 14),
                      ),
                      value: 'meal',
                      groupValue: _notifyMode,
                      onChanged: (v) {
                        setState(() {
                          _notifyMode = v ?? 'meal';
                        });
                      },
                      activeColor: Colors.teal,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // เลือกตัวยา
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'เลือกตัวยา',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  IconButton(
                    onPressed: _goToAddMedicine,
                    icon: const Icon(Icons.add_circle_outline),
                    color: Colors.blue,
                    tooltip: 'เพิ่มตัวยา',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_isLoadingMedicines)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_medicines.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'ยังไม่มีตัวยา',
                    style: TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _medicines.map((m) {
                        final id = m['id']?.toString() ?? '';
                        final name = m['name']?.toString() ?? '-';
                        final isSelected = _selectedMedicineId == id;

                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedMedicineId = id;
                              });
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.blue
                                    : Colors.grey[300],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildMedicineAvatar(m['image']),
                                  const SizedBox(width: 6),
                                  Text(
                                    name,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // สรรพคุณยา (Medicine Properties)
              if (_selectedMedicineId != null) ..._buildMedicinePropertiesSection(),

              const SizedBox(height: 16),

              // ระยะช่วงเวลาที่จะแจ้งเตือน (แสดงเฉพาะโหมด interval)
              if (_notifyMode == 'interval') ...[
                const Text(
                  'ระยะช่วงเวลาที่จะแจ้งเตือน (ชั่วโมง.นาที)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _pickIntervalMinutes,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    backgroundColor: Colors.grey[200],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.schedule, color: Colors.black87),
                  label: Text(
                    'ทุก ${_formatIntervalLabel()} ชั่วโมง',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],

              // ข้อความแนะนำโหมดมื้ออาหาร
              if (_notifyMode == 'meal') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.restaurant, color: Colors.teal, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ระบบจะแจ้งเตือนตามเวลามื้ออาหารที่ตั้งไว้ในโปรไฟล์ (เช้า/กลางวัน/เย็น/ก่อนนอน)',
                          style: TextStyle(color: Colors.teal[800], fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // ปุ่มบันทึกการแจ้งเตือน
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
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
                      : Text(
                          // ✅ ข้อความเปลี่ยนตามสถานะ NFC
                          _isNfcEnabled
                              ? 'บันทึกการแจ้งเตือนบน NFC'
                              : 'บันทึกการแจ้งเตือน',
                          style: const TextStyle(
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
