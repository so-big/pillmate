// lib/edit_carlendar.dart

import 'dart:convert';
import 'dart:io';
import 'dart:ui'; // <--- เพิ่ม import นี้เพื่อใช้ PointerDeviceKind

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';

import 'create_profile.dart';
import 'add_medicine.dart';

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

  // เดิม int _intervalHours = 4;
  int _intervalMinutes = 4 * 60;

  bool _isSaving = false;

  Future<File> get _profilesFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/profiles.json');
  }

  Future<File> get _usersFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/user.json');
  }

  Future<File> get _pillProfileFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/pillprofile.json');
  }

  Future<File> get _calendarFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/carlendar.json');
  }

  Future<File> get _remindersFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/reminders.json');
  }

  Future<File> get _eatedFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/eated.json');
  }

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
    if (intervalMinutes <= 0) {
      final hours = int.tryParse(r['intervalHours']?.toString() ?? '') ?? 4;
      intervalMinutes = hours * 60;
    }
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
  }

  // ---------- โหลดข้อมูลโปรไฟล์ / ยา ----------

  Future<void> _loadProfiles() async {
    setState(() {
      _isLoadingProfiles = true;
    });

    try {
      String? accountImage;
      try {
        final usersFile = await _usersFile;
        if (await usersFile.exists()) {
          final content = await usersFile.readAsString();
          if (content.trim().isNotEmpty) {
            final list = jsonDecode(content);
            if (list is List) {
              for (final u in list) {
                if (u is Map || u is Map<String, dynamic>) {
                  final map = Map<String, dynamic>.from(u);
                  if (map['userid'] == widget.username) {
                    final img = map['image'];
                    if (img != null && img.toString().isNotEmpty) {
                      accountImage = img.toString();
                    }
                    break;
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('CarlendarEdit: error loading user image: $e');
      }

      final file = await _profilesFile;
      List<dynamic> raw = [];

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          raw = jsonDecode(content);
        }
      }

      final filtered = raw
          .where((p) {
            if (p is Map<String, dynamic>) {
              return p['createby'] == widget.username;
            }
            if (p is Map) return p['createby'] == widget.username;
            return false;
          })
          .map<Map<String, dynamic>>((p) => Map<String, dynamic>.from(p));

      final profiles = <Map<String, dynamic>>[];

      profiles.add({
        'name': widget.username,
        'createby': widget.username,
        'image': accountImage,
      });

      profiles.addAll(filtered);

      String? selected = _selectedProfileName;
      if (selected == null ||
          profiles.every((p) => p['name']?.toString() != selected)) {
        selected = profiles.isNotEmpty
            ? profiles.first['name']?.toString()
            : null;
      }

      setState(() {
        _profiles = profiles;
        _selectedProfileName = selected;
      });
    } catch (e) {
      debugPrint('CarlendarEdit: error loading profiles: $e');
      setState(() {
        _profiles = [];
      });
    } finally {
      setState(() {
        _isLoadingProfiles = false;
      });
    }
  }

  Future<void> _loadMedicines() async {
    setState(() {
      _isLoadingMedicines = true;
    });

    try {
      final file = await _pillProfileFile;
      List<dynamic> raw = [];

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          raw = jsonDecode(content);
        }
      }

      final filtered = raw
          .where((m) {
            if (m is Map<String, dynamic>) {
              return m['createby'] == widget.username;
            }
            if (m is Map) return m['createby'] == widget.username;
            return false;
          })
          .map<Map<String, dynamic>>((m) => Map<String, dynamic>.from(m))
          .toList();

      String? selected = _selectedMedicineId;
      if (selected == null ||
          filtered.every((m) => m['id']?.toString() != selected)) {
        if (filtered.isNotEmpty) {
          selected = filtered.first['id']?.toString();
        } else {
          selected = null;
        }
      }

      setState(() {
        _medicines = filtered;
        _selectedMedicineId = selected;
      });
    } catch (e) {
      debugPrint('CarlendarEdit: error loading medicines: $e');
      setState(() {
        _medicines = [];
      });
    } finally {
      setState(() {
        _isLoadingMedicines = false;
      });
    }
  }

  // ---------- UI helper ----------

  Widget _buildProfileAvatar(dynamic imageData) {
    if (imageData == null || imageData.toString().isNotEmpty == false) {
      return const CircleAvatar(
        radius: 16,
        child: Icon(Icons.person, size: 18),
      );
    }
    try {
      final bytes = base64Decode(imageData.toString());
      return CircleAvatar(radius: 16, backgroundImage: MemoryImage(bytes));
    } catch (e) {
      debugPrint('CarlendarEdit: decode image fail: $e');
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
      debugPrint('CarlendarEdit: decode medicine image fail: $e');
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

  // ฟอร์แมตช่วงเวลาเป็น HH.MM
  String _formatIntervalLabel() {
    final h = _intervalMinutes ~/ 60;
    final m = _intervalMinutes % 60;
    return '${h.toString().padLeft(2, '0')}.${m.toString().padLeft(2, '0')}';
  }

  // เลือกช่วงเวลาแบบชั่วโมง.นาที (0–24 ชม.)
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

  // ---------- DELETE: ลบการแจ้งเตือนนี้จากทุกไฟล์ที่เกี่ยวข้อง ----------

  Future<void> _handleDelete() async {
    if (_isSaving) return;

    final original = widget.reminder;
    final reminderId = original['id']?.toString();

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
            'หากต้องการใช้งานอีกครั้ง คุณต้องสร้างการแจ้งเตือนใหม่',
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
      // 1) ลบจาก carlendar.json
      final calFile = await _calendarFile;
      List<dynamic> calList = [];

      if (await calFile.exists()) {
        final content = await calFile.readAsString();
        if (content.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(content);
            if (decoded is List) {
              calList = decoded;
            }
          } catch (e) {
            debugPrint(
              'CarlendarEdit: calendar JSON decode error on delete: $e',
            );
          }
        }
      }

      calList = calList.where((item) {
        if (item is Map || item is Map<String, dynamic>) {
          final map = Map<String, dynamic>.from(item);
          final id = map['id']?.toString();
          final createby = map['createby']?.toString();
          if (id == reminderId && createby == widget.username) {
            return false; // ลบ
          }
        }
        return true;
      }).toList();

      await calFile.writeAsString(jsonEncode(calList), flush: true);

      // 2) ลบจาก reminders.json
      final remindersFile = await _remindersFile;
      List<dynamic> remList = [];
      if (await remindersFile.exists()) {
        final content = await remindersFile.readAsString();
        if (content.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(content);
            if (decoded is List) {
              remList = decoded;
            }
          } catch (e) {
            debugPrint(
              'CarlendarEdit: reminders JSON decode error on delete: $e',
            );
          }
        }
      }

      remList = remList.where((item) {
        if (item is Map || item is Map<String, dynamic>) {
          final map = Map<String, dynamic>.from(item);
          final id = map['id']?.toString();
          final createby = map['createby']?.toString();
          if (id == reminderId && createby == widget.username) {
            return false; // ลบ
          }
        }
        return true;
      }).toList();

      await remindersFile.writeAsString(jsonEncode(remList), flush: true);

      // 3) ลบจาก eated.json (log การกินของ reminder นี้)
      final eatedFile = await _eatedFile;
      List<dynamic> eatedList = [];
      if (await eatedFile.exists()) {
        final content = await eatedFile.readAsString();
        if (content.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(content);
            if (decoded is List) {
              eatedList = decoded;
            }
          } catch (e) {
            debugPrint('CarlendarEdit: eated JSON decode error on delete: $e');
          }
        }
      }

      eatedList = eatedList.where((item) {
        if (item is Map || item is Map<String, dynamic>) {
          final map = Map<String, dynamic>.from(item);
          final uid = map['userid']?.toString();
          final rid = map['reminderId']?.toString();
          if (uid == widget.username && rid == reminderId) {
            return false; // ลบ
          }
        }
        return true;
      }).toList();

      await eatedFile.writeAsString(jsonEncode(eatedList), flush: true);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ลบการแจ้งเตือนนี้จากระบบเรียบร้อยแล้ว')),
      );

      setState(() {
        _isSaving = false;
      });

      // ส่งผลลัพธ์กลับไปให้หน้า Dashboard รู้ว่า "ลบแล้ว"
      Navigator.pop(context, {
        'id': reminderId,
        'createby': widget.username,
        'deleted': true,
      });
    } catch (e) {
      debugPrint('CarlendarEdit: delete error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ไม่สามารถลบการแจ้งเตือนได้: $e')));
      setState(() {
        _isSaving = false;
      });
    }
  }

  // ---------- SAVE: เขียนลง NFC + อัปเดตไฟล์ + ส่งข้อมูลกลับ ----------

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

    // ลองดึงจากรายการยา (pillprofile)
    if (medicineId != null && medicineId.isNotEmpty) {
      try {
        final med = _medicines.firstWhere(
          (m) => m['id']?.toString() == medicineId,
        );
        medicineName = med['name']?.toString() ?? '';
        medicineDetail = med['detail']?.toString() ?? '';
        beforeMeal = med['beforeMeal'] == true;
        afterMeal = med['afterMeal'] == true;
      } catch (_) {}
    }

    // ถ้าหาใน pillprofile ไม่ได้ ใช้ค่าจาก reminder เดิม
    if (medicineName.isEmpty) {
      medicineName = original['medicineName']?.toString() ?? '';
    }
    if (medicineDetail.isEmpty) {
      medicineDetail = original['medicineDetail']?.toString() ?? '';
    }
    if (!beforeMeal && !afterMeal) {
      beforeMeal = original['medicineBeforeMeal'] == true;
      afterMeal = original['medicineAfterMeal'] == true;
    }

    // กันเน่าทั้งหมด
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

    // --- ส่วนที่เพิ่ม/แก้ไข เพื่อรองรับ PC Mode ---
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    String? nfcTagId;
    bool nfcWriteSuccess = false;

    if (isDesktop) {
      // โหมด PC: ข้าม NFC
      debugPrint(
        'CarlendarEdit: Running on PC/Desktop. Skipping NFC operation.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกแก้ไขในโหมด PC (ไม่ใช้ NFC)')),
      );
      nfcWriteSuccess = true;
      // ใช้ ID เดิม หรือ สร้าง dummy
      nfcTagId =
          original['nfcId']?.toString() ??
          'PC-MODE-${DateTime.now().millisecondsSinceEpoch}';
    } else {
      // โหมด Mobile (NFC)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาแตะแท็ก NFC เพื่อบันทึกการแก้ไขการแจ้งเตือน'),
        ),
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

        debugPrint('CarlendarEdit: NFC tag = $tag');

        if (tag.ndefWritable != true) {
          throw 'แท็กนี้ไม่สามารถเขียน NDEF ได้';
        }

        final record = ndef.TextRecord(language: 'th', text: payloadText);
        await FlutterNfcKit.writeNDEFRecords([record]);

        nfcTagId = tag.id;
        nfcWriteSuccess = true;

        try {
          await FlutterNfcKit.finish(iosAlertMessage: 'สำเร็จ');
        } catch (_) {}
      } catch (e) {
        debugPrint('CarlendarEdit: NFC/save error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ไม่สามารถบันทึกบน NFC ได้: $e')),
          );
          setState(() {
            _isSaving = false;
          });
        }
        try {
          await FlutterNfcKit.finish(iosErrorMessage: 'ล้มเหลว');
        } catch (_) {}
        return; // ออกถ้า NFC พังในโหมดมือถือ
      }
    }

    // *** ส่วนการบันทึกลงไฟล์ JSON ***
    if (!nfcWriteSuccess) {
      setState(() {
        _isSaving = false;
      });
      return;
    }

    try {
      // อัปเดตไฟล์ carlendar.json
      final calFile = await _calendarFile;
      List<dynamic> calList = [];
      if (await calFile.exists()) {
        final content = await calFile.readAsString();
        if (content.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(content);
            if (decoded is List) calList = decoded;
          } catch (e) {
            debugPrint('CarlendarEdit: calendar JSON decode error: $e');
          }
        }
      }

      final now = DateTime.now();
      final reminderId =
          original['id']?.toString() ?? now.millisecondsSinceEpoch.toString();

      bool updated = false;

      for (int i = 0; i < calList.length; i++) {
        final item = calList[i];
        if (item is Map || item is Map<String, dynamic>) {
          final map = Map<String, dynamic>.from(item);
          final id = map['id']?.toString();
          final createby = map['createby']?.toString();

          if (id == reminderId && createby == widget.username) {
            final entry = Map<String, dynamic>.from(map);
            entry['profileName'] = profileName;
            entry['medicineId'] = medicineId;
            entry['medicineName'] = medicineName;
            entry['medicineDetail'] = medicineDetail;
            entry['medicineBeforeMeal'] = beforeMeal;
            entry['medicineAfterMeal'] = afterMeal;

            entry['startDateTime'] = _startDateTime.toIso8601String();
            entry['endDateTime'] = _endDateTime.toIso8601String();
            entry['notifyByTime'] = _notifyByTime;
            entry['notifyByMeal'] = _notifyByMeal;
            entry['intervalMinutes'] = _intervalMinutes;
            entry['intervalHours'] = (_intervalMinutes / 60).round();
            entry['et'] = et;

            entry['nfcId'] = nfcTagId;
            entry['payload'] = payloadText;

            entry['updatedAt'] = now.toIso8601String();

            calList[i] = entry;
            updated = true;
            break;
          }
        }
      }

      if (!updated) {
        final entry = {
          'id': reminderId,
          'createby': widget.username,
          'profileName': profileName,
          'medicineId': medicineId,
          'medicineName': medicineName,
          'medicineDetail': medicineDetail,
          'medicineBeforeMeal': beforeMeal,
          'medicineAfterMeal': afterMeal,
          'startDateTime': _startDateTime.toIso8601String(),
          'endDateTime': _endDateTime.toIso8601String(),
          'notifyByTime': _notifyByTime,
          'notifyByMeal': _notifyByMeal,
          'intervalMinutes': _intervalMinutes,
          'intervalHours': (_intervalMinutes / 60).round(),
          'et': et,
          'nfcId': nfcTagId,
          'payload': payloadText,
          'createdAt': now.toIso8601String(),
        };
        calList.add(entry);
      }

      await calFile.writeAsString(jsonEncode(calList), flush: true);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('แก้ไขการแจ้งเตือนเรียบร้อย')),
      );

      setState(() {
        _isSaving = false;
      });

      // ส่งข้อมูลกลับให้ Dashboard เพื่ออัปเดต reminders.json
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
        'et': et,
        'nfcId': nfcTagId,
        'payload': payloadText,
      };

      Navigator.pop(context, result);
    } catch (e) {
      debugPrint('CarlendarEdit: File save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ไม่สามารถบันทึกไฟล์ได้: $e')));
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // --------------------------------------------------------------------------
  // ส่วน Build UI ที่แก้ไขให้รองรับเมาส์ลากบน PC
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),

        // --- 1. ครอบ ScrollConfiguration ---
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse, // อนุญาตให้ใช้เมาส์ลาก
            },
          ),
          child: ListView(
            controller: widget.scrollController,
            // --- 2. บังคับ Physics ---
            physics: const AlwaysScrollableScrollPhysics(),

            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // แถบลาก
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
                      : const Text(
                          'บันทึกการแก้ไขการแจ้งเตือนบน NFC',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 12),

              // ปุ่มลบการแจ้งเตือนทั้งหมด (สีแดง)
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
