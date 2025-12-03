// lib/edit_carlendar.dart

import 'dart:convert';
import 'dart:io';
import 'dart:async'; // เพิ่มเพื่อใช้ Timer
import 'dart:ui'; // เพื่อใช้ PointerDeviceKind

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';

import 'create_profile.dart';
import 'add_medicine.dart';
import 'database_helper.dart'; // ✅ เรียกใช้ DatabaseHelper

import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;

class CarlendarEditSheet extends StatefulWidget {
  final String username;
  final Map<String, dynamic> reminder;
  final ScrollController? scrollController;

  const CarlendarEditSheet({
    super.key,
    required this.username,
    required this.reminder,
    this.scrollController,
  });

  @override
  State<CarlendarEditSheet> createState() => _CarlendarEditSheetState();
}

class _CarlendarEditSheetState extends State<CarlendarEditSheet> {
  // โปรไฟล์ผู้รับยา
  List<Map<String, dynamic>> _profiles = [];
  String? _selectedProfileName;
  bool _isLoadingProfiles = true;

  // ยา
  List<Map<String, dynamic>> _medicines = [];
  String? _selectedMedicineId;
  bool _isLoadingMedicines = false;

  // สถานะเวลา
  late DateTime _startDateTime;
  late DateTime _endDateTime;

  // รูปแบบแจ้งเตือน
  bool _notifyByTime = true;
  bool _notifyByMeal = false;

  int _intervalMinutes = 4 * 60;

  bool _isSaving = false;

  // ✅ ตัวแปรเก็บสถานะ NFC จาก json (Config App)
  bool _isNfcEnabled = false;

  // ✅ Database Helper Instance
  final dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();

    final r = widget.reminder;

    _selectedProfileName =
        (r['profileName']?.toString().trim().isNotEmpty ?? false)
        ? r['profileName'].toString()
        : widget.username;

    final startStr = r['startDateTime']?.toString();
    final endStr = r['endDateTime']?.toString();
    _startDateTime = startStr != null
        ? (DateTime.tryParse(startStr) ?? DateTime.now())
        : DateTime.now();
    _endDateTime = endStr != null
        ? (DateTime.tryParse(endStr) ?? _startDateTime)
        : _startDateTime;

    _notifyByTime = r['notifyByTime'] == true;
    _notifyByMeal = r['notifyByMeal'] == true;

    // แปลง interval จากข้อมูลเดิม
    int intervalMinutes =
        int.tryParse(r['intervalMinutes']?.toString() ?? '') ?? 0;
    // fallback ถ้าไม่มี minutes ลองดู hours (เผื่อข้อมูลเก่า)
    if (intervalMinutes <= 0) {
      final hours = int.tryParse(r['intervalHours']?.toString() ?? '') ?? 4;
      intervalMinutes = hours * 60;
    }
    // ถ้ายัง 0 อีก ให้ default 4 ชม.
    if (intervalMinutes <= 0) {
      intervalMinutes = 4 * 60;
    }
    if (intervalMinutes > 24 * 60) {
      intervalMinutes = 24 * 60;
    }
    _intervalMinutes = intervalMinutes;

    _selectedMedicineId = r['medicineId']?.toString();

    _loadProfiles();
    _loadMedicines();
    _loadNfcStatus(); // ✅ โหลดสถานะ NFC Config
  }

  // ✅ ฟังก์ชันโหลดสถานะ NFC จาก appstatus.json (ส่วนนี้ยังคงใช้ไฟล์เพราะเป็น Config เครื่อง)
  Future<void> _loadNfcStatus() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/appstatus.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content);
          if (data is Map) {
            if (mounted) {
              setState(() {
                _isNfcEnabled = data['nfc_enabled'] ?? false;
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('CarlendarEdit: error loading NFC status: $e');
      if (mounted) {
        setState(() {
          _isNfcEnabled = false;
        });
      }
    }
  }

  // ---------- โหลดข้อมูลโปรไฟล์ / ยา จาก SQLite ----------

  Future<void> _loadProfiles() async {
    setState(() {
      _isLoadingProfiles = true;
    });

    try {
      final db = await dbHelper.database;
      final profiles = <Map<String, dynamic>>[];

      // 1. Master User
      final masterUser = await dbHelper.getUser(widget.username);
      if (masterUser != null) {
        profiles.add({
          'name': masterUser['userid'],
          'createby': widget.username,
          'image': masterUser['image_base64'],
        });
      }

      // 2. Sub-profiles
      final List<Map<String, dynamic>> subs = await db.query(
        'users',
        where: 'sub_profile = ?',
        whereArgs: [widget.username],
      );

      for (var s in subs) {
        profiles.add({
          'name': s['userid'],
          'createby': widget.username,
          'image': s['image_base64'],
        });
      }

      // ตรวจสอบ selection
      String? selected = _selectedProfileName;
      if (selected == null ||
          profiles.every((p) => p['name']?.toString() != selected)) {
        selected = profiles.isNotEmpty
            ? profiles.first['name']?.toString()
            : null;
      }

      if (mounted) {
        setState(() {
          _profiles = profiles;
          _selectedProfileName = selected;
        });
      }
    } catch (e) {
      debugPrint('CarlendarEdit: error loading profiles DB: $e');
      if (mounted) {
        setState(() {
          _profiles = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingProfiles = false;
        });
      }
    }
  }

  Future<void> _loadMedicines() async {
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

      final medList = List<Map<String, dynamic>>.from(result);

      String? selected = _selectedMedicineId;
      if (selected == null ||
          medList.every((m) => m['id']?.toString() != selected)) {
        if (medList.isNotEmpty) {
          selected = medList.first['id']?.toString();
        } else {
          selected = null;
        }
      }

      if (mounted) {
        setState(() {
          _medicines = medList;
          _selectedMedicineId = selected;
        });
      }
    } catch (e) {
      debugPrint('CarlendarEdit: error loading medicines DB: $e');
      if (mounted) {
        setState(() {
          _medicines = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMedicines = false;
        });
      }
    }
  }

  // ---------- UI helper ----------

  Widget _buildProfileAvatar(dynamic imageData) {
    if (imageData == null || imageData.toString().isEmpty) {
      return const CircleAvatar(
        radius: 16,
        child: Icon(Icons.person, size: 18),
      );
    }
    try {
      final str = imageData.toString();
      if (str.startsWith('assets/')) {
        return CircleAvatar(radius: 16, backgroundImage: AssetImage(str));
      }
      final bytes = base64Decode(str);
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

    // ถ้ามีการส่ง id กลับมา (เพิ่มยาสำเร็จ) ให้เลือกตัวนั้นเลย
    if (result is Map && result['id'] != null) {
      setState(() {
        _selectedMedicineId = result['id'].toString();
      });
    }
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
                          25,
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

  // ---------- DELETE: ลบจาก SQLite ----------

  Future<void> _handleDelete() async {
    if (_isSaving) return;

    final reminderId = widget.reminder['id']?.toString();

    if (reminderId == null || reminderId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบรหัสการแจ้งเตือน ไม่สามารถลบได้')),
      );
      return;
    }

    // ยืนยันก่อนลบ
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(
            'ลบการแจ้งเตือนนี้ทั้งหมด?',
            style: TextStyle(color: Colors.black87),
          ),
          content: const Text(
            'การลบนี้จะลบข้อมูลการแจ้งเตือนของยานี้ออกจากระบบทั้งหมด\n'
            'รวมถึงประวัติการกินยาที่เกี่ยวข้องด้วย',
            style: TextStyle(color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('ยกเลิก'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('ลบ'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final db = await dbHelper.database;

      // 1. ลบจาก calendar_alerts (ใช้ SQLite)
      await db.delete(
        'calendar_alerts',
        where: 'id = ?',
        whereArgs: [reminderId],
      );

      // 2. ลบประวัติการกินยาที่เกี่ยวข้องออกจาก taken_doses (Cascade Logic)
      await db.delete(
        'taken_doses',
        where: 'reminder_id = ?',
        whereArgs: [reminderId],
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ลบการแจ้งเตือนและข้อมูลที่เกี่ยวข้องเรียบร้อยแล้ว'),
        ),
      );

      setState(() {
        _isSaving = false;
      });

      // ส่งผลลัพธ์กลับไป
      Navigator.pop(context, {
        'id': reminderId,
        'createby': widget.username,
        'deleted': true,
      });
    } catch (e) {
      debugPrint('CarlendarEdit: delete DB error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ไม่สามารถลบการแจ้งเตือนได้: $e')));
      setState(() {
        _isSaving = false;
      });
    }
  }

  // ---------- SAVE: บันทึกลง SQLite (+ NFC ถ้าเปิด) ----------

  Future<void> _handleSave() async {
    if (_isSaving) return;

    if (_selectedProfileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกโปรไฟล์ผู้รับยา')),
      );
      return;
    }

    final profileName = _selectedProfileName!.trim();
    final original = widget.reminder;

    // เตรียมข้อมูลยา
    String? medicineId = _selectedMedicineId;
    String medicineName = '';
    String medicineDetail = '';
    bool beforeMeal = false;
    bool afterMeal = false;

    // 1. ดึงข้อมูลยาใหม่จาก ID (จาก SQLite Medicines List)
    if (medicineId != null && medicineId.isNotEmpty) {
      try {
        final med = _medicines.firstWhere(
          (m) => m['id']?.toString() == medicineId,
        );
        medicineName = med['name']?.toString() ?? '';
        medicineDetail = med['detail']?.toString() ?? '';
        beforeMeal = (med['before_meal'] == 1);
        afterMeal = (med['after_meal'] == 1);
      } catch (_) {}
    }

    // 2. ถ้าหาไม่เจอ ใช้ค่าเดิม
    if (medicineName.isEmpty) {
      medicineName = original['medicineName']?.toString() ?? '';
    }
    if (medicineDetail.isEmpty) {
      medicineDetail = original['medicineDetail']?.toString() ?? '';
    }
    // ถ้าไม่เคยโหลด med ใหม่เลย ใช้ค่า meal เดิม
    if (!beforeMeal && !afterMeal) {
      beforeMeal = original['beforeMeal'] == true;
      afterMeal = original['afterMeal'] == true;
    }

    // กันเน่า
    if (!beforeMeal && !afterMeal) {
      beforeMeal = true;
      afterMeal = false;
    }

    if (medicineName.length > 50) {
      medicineName = medicineName.substring(0, 50);
    }
    if (medicineDetail.length > 100) {
      medicineDetail = medicineDetail.substring(0, 100);
    }

    final flag = beforeMeal ? '1' : '2';

    final h = _intervalMinutes ~/ 60;
    final m = _intervalMinutes % 60;
    final et =
        '${h.toString().padLeft(2, '0')}.${m.toString().padLeft(2, '0')}';

    final payloadText =
        '$medicineName~$medicineDetail~e=$flag~et=$et~$profileName';

    setState(() {
      _isSaving = true;
    });

    String? nfcTagId;

    // --- ส่วนการจัดการ NFC ---
    if (_isNfcEnabled) {
      // ===== กรณีเปิดใช้ NFC =====
      BuildContext? scanDialogContext;

      await showDialog(
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
                  'กรุณาแตะ tag nfc ที่เซ็นเซอร์เพื่อบันทึกค่าแก้ไข',
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

      // ถ้า user ยกเลิก dialog ไปแล้ว จะไม่ต้อง scan
      // แต่ในโค้ด dialog ด้านบน รอ await ไม่ได้ return ค่า
      // ต้อง check ว่าจะทำต่อไหม

      try {
        // (Logic การเขียน NFC เหมือนเดิม)
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
        debugPrint('CarlendarEdit: NFC write error: $e');
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
          return;
        }
      }
    } else {
      // ===== กรณีปิด NFC (PC Mode หรือ User ปิด) =====
      debugPrint('CarlendarEdit: NFC is disabled. Saving DB only.');
      nfcTagId =
          original['nfcId']?.toString() ??
          'MANUAL-EDIT-${DateTime.now().millisecondsSinceEpoch}';
    }

    // *** ส่วนการบันทึกลง SQLite ***
    try {
      final now = DateTime.now();
      final reminderId =
          original['id']?.toString() ?? now.millisecondsSinceEpoch.toString();
      final db = await dbHelper.database;

      final Map<String, dynamic> row = {
        'createby': widget.username,
        'profile_name': profileName,
        'medicine_id': medicineId,
        'medicine_name': medicineName,
        'medicine_detail': medicineDetail,
        'medicine_before_meal': beforeMeal ? 1 : 0,
        'medicine_after_meal': afterMeal ? 1 : 0,
        'start_date_time': _startDateTime.toIso8601String(),
        'end_date_time': _endDateTime.toIso8601String(),
        'notify_by_time': _notifyByTime ? 1 : 0,
        'notify_by_meal': _notifyByMeal ? 1 : 0,
        'interval_minutes': _intervalMinutes,
        'interval_hours': (_intervalMinutes / 60).round(),
        'et': et,
        'nfc_id': nfcTagId,
        'payload': payloadText,
        'updated_at': now.toIso8601String(), // บันทึกเวลาที่อัปเดต
      };

      // Update Database Table 'calendar_alerts'
      await db.update(
        'calendar_alerts',
        row,
        where: 'id = ?',
        whereArgs: [reminderId],
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('แก้ไขการแจ้งเตือนเรียบร้อย')),
      );

      setState(() {
        _isSaving = false;
      });

      // ส่งข้อมูลกลับ (Dashboard จะได้รับค่านี้ไปอัปเดต List)
      final result = {
        'id': reminderId,
        'createby': widget.username,
        'profileName': profileName,
        'startDateTime': _startDateTime.toIso8601String(),
        'endDateTime': _endDateTime.toIso8601String(),
        'notifyByTime': _notifyByTime,
        'notifyByMeal': _notifyByMeal,
        'intervalMinutes': _intervalMinutes,
        'intervalHours': (_intervalMinutes / 60).round(),
        'medicineId': medicineId,
        'medicineName': medicineName,
        'medicineDetail': medicineDetail,
        'medicineBeforeMeal': beforeMeal,
        'medicineAfterMeal': afterMeal,
        'beforeMeal': beforeMeal,
        'afterMeal': afterMeal,
        'et': et,
        'nfcId': nfcTagId,
        'payload': payloadText,
      };

      Navigator.pop(context, result);
    } catch (e) {
      debugPrint('CarlendarEdit: DB save error: $e');
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

  // --------------------------------------------------------------------------
  // Build UI
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
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
              if (_isLoadingProfiles)
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
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'แจ้งเตือนตามเวลา',
                        style: TextStyle(color: Colors.black, fontSize: 14),
                      ),
                      value: _notifyByTime,
                      onChanged: (v) {
                        setState(() {
                          _notifyByTime = v ?? false;
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ),
                  Expanded(
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'แจ้งเตือนตามมื้ออาหาร',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      value: _notifyByMeal,
                      onChanged: null,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

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
                onPressed: _notifyByTime ? _pickIntervalMinutes : null,
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
                  style: TextStyle(
                    color: _notifyByTime ? Colors.black87 : Colors.black38,
                    fontSize: 14,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ปุ่มบันทึก
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
                          _isNfcEnabled
                              ? 'บันทึกการแก้ไขการแจ้งเตือนบน NFC'
                              : 'บันทึกการแก้ไขการแจ้งเตือน',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 12),

              // ปุ่มลบการแจ้งเตือนทั้งหมด
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : _handleDelete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.delete),
                  label: const Text(
                    'ลบการแจ้งเตือนทั้งหมดของยานี้',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
