// lib/view_dashboard.dart
import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'nortification_next.dart';
import 'view_carlendar.dart';
import 'add_carlendar.dart';
import 'edit_carlendar.dart';
import 'create_profile.dart';
import 'manage_profile.dart';
import 'view_menu.dart';
import 'add_medicine.dart';
import 'manage_medicine.dart';
import 'main.dart'; // มี LoginPage อยู่ในนี้

import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;

// ✅ เรียกใช้ DatabaseHelper
import 'database_helper.dart';

// ✅ Import Notification Service
import 'nortification_service.dart';

class DashboardPage extends StatefulWidget {
  final String username;
  final DateTime? initialDateTime; // ใช้ตอนกดจาก Calendar

  const DashboardPage({
    super.key,
    required this.username,
    this.initialDateTime,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

// 1 dose = 1 การ์ด
class _DoseItem {
  final Map<String, dynamic> reminder;
  final DateTime? time;

  _DoseItem({required this.reminder, required this.time});
}

class _DashboardPageState extends State<DashboardPage> {
  // ---------- FILE HELPERS ----------

  Future<Directory> _appDir() async {
    return getApplicationDocumentsDirectory();
  }

  Future<File> _userStatFile() async {
    final dir = await _appDir();
    return File('${dir.path}/pillmate/user-stat.json');
  }

  Future<File> _appStatusFile() async {
    final dir = await _appDir();
    return File('${dir.path}/pillmate/appstatus.json');
  }

  // ---------- STATE ----------

  // โปรไฟล์ของคนที่ต้องกินยา (รวมโปรไฟล์ self ที่ชื่อ = username)
  List<Map<String, dynamic>> _profiles = [];
  bool _isLoadingProfiles = true;

  // รายการ reminder จาก DB
  List<Map<String, dynamic>> _reminders = [];
  bool _isLoadingReminders = true;

  // log การกินยา (เฉพาะที่ confirm แล้ว)
  List<Map<String, dynamic>> _eated = [];
  bool _isLoadingEated = true;

  // set key = '$reminderId|$doseDateTimeIso'
  Set<String> _takenDoseKeys = {};

  // ใช้ highlight ขณะกำลังสแกน
  bool _isScanningNfc = false;
  String? _scanningDoseKey;

  // วันที่ใช้ดูแบบรายวัน (ของหน้าปัจจุบัน)
  late DateTime _selectedDateTime;

  // ใช้สำหรับแปลง page index -> วัน
  static const int _initialPage = 10000;
  late DateTime _baseDate;
  late PageController _pageController;

  // ✅ ตัวแปรสถานะ NFC (สำหรับแสดงผล UI เท่านั้น Logic จริงจะอ่านไฟล์)
  bool _isNfcEnabled = false;

  // ✅ Timer สำหรับจับเวลาการกดค้าง (Manual Mode)
  Timer? _manualHoldTimer;

  // ✅ Database Helper
  final dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    // ถ้ามาจาก Calendar ให้ใช้เวลาช่องนั้น ไม่งั้นใช้ตอนนี้
    _selectedDateTime = widget.initialDateTime ?? DateTime.now();
    _selectedDateTime = _dateOnly(_selectedDateTime);

    _baseDate = _selectedDateTime;
    _pageController = PageController(initialPage: _initialPage);

    _loadInitialNfcStatus(); // โหลดสถานะเริ่มต้นเพื่อแสดงผล
    _loadInitialData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _manualHoldTimer?.cancel(); // ยกเลิก Timer ถ้าออกจากหน้า
    super.dispose();
  }

  // โหลดค่า NFC Status ครั้งแรกเพื่อใช้แสดงผล Text ใน UI
  Future<void> _loadInitialNfcStatus() async {
    final status = await _getNfcStatusFromFile();
    if (mounted) {
      setState(() {
        _isNfcEnabled = status;
      });
    }
  }

  // ✅ ฟังก์ชันอ่านสถานะ NFC จากไฟล์ appstatus.json โดยตรง (ใช้ตรวจสอบ Logic)
  Future<bool> _getNfcStatusFromFile() async {
    try {
      final file = await _appStatusFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content);
          if (data is Map) {
            return data['nfc_enabled'] ?? false;
          }
        }
      }
    } catch (e) {
      debugPrint('Dashboard: error reading NFC status file: $e');
    }
    return false; // Default ถ้าอ่านไม่ได้ หรือไฟล์ไม่มี
  }

  Future<void> _loadInitialData() async {
    // รอให้โหลดข้อมูลทุกอย่างเสร็จก่อน
    await Future.wait([_loadProfiles(), _loadReminders(), _loadEated()]);

    // Setup Notification (Logics อื่นๆ)
    await NortificationSetup.run(context: context, username: widget.username);

    // ✅ เรียก Service Trigger ตรงนี้ (ท้ายสุด = โหลดเสร็จ 100%)
    // ไม่ต้องส่ง parameter ใดๆ ตามที่นายท่านสั่ง
    scheduleNotificationForNewAlert();
  }

  // ✅ แก้ไข: โหลด Profiles จาก SQLite
  Future<void> _loadProfiles() async {
    setState(() {
      _isLoadingProfiles = true;
    });

    try {
      final db = await dbHelper.database;
      final profiles = <Map<String, dynamic>>[];

      // 1. Master Profile
      final masterUser = await dbHelper.getUser(widget.username);
      if (masterUser != null) {
        profiles.add({
          'name': masterUser['userid'],
          'createby': widget.username,
          'image': masterUser['image_base64'], // ใช้ image_base64
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

      setState(() {
        _profiles = profiles;
      });
    } catch (e) {
      debugPrint('Dashboard: error loading profiles DB: $e');
      setState(() {
        _profiles = [];
      });
    } finally {
      setState(() {
        _isLoadingProfiles = false;
      });
    }
  }

  // ✅ แก้ไข: โหลด Reminders จาก SQLite (calendar_alerts)
  Future<void> _loadReminders() async {
    setState(() {
      _isLoadingReminders = true;
    });

    try {
      final db = await dbHelper.database;

      // ดึงข้อมูลที่สร้างโดย user นี้
      final List<Map<String, dynamic>> results = await db.query(
        'calendar_alerts',
        where: 'createby = ?',
        whereArgs: [widget.username],
      );

      // ❌ ลบ Loop ที่เคยเรียก scheduleNotificationForNewAlert(row) ออกแล้ว
      // เพื่อไปเรียกทีเดียวตอนท้าย _loadInitialData

      // แปลง key จาก snake_case (DB) -> camelCase (UI เดิม)
      final List<Map<String, dynamic>> mappedList = results.map((row) {
        return {
          'id': row['id'],
          'createby': row['createby'],
          'profileName': row['profile_name'],
          'medicineId': row['medicine_id'],
          'medicineName': row['medicine_name'],
          'medicineDetail': row['medicine_detail'],
          // แปลง int 0/1 เป็น bool
          'beforeMeal': row['medicine_before_meal'] == 1,
          'afterMeal': row['medicine_after_meal'] == 1,
          'startDateTime': row['start_date_time'],
          'endDateTime': row['end_date_time'],
          'notifyByTime': row['notify_by_time'] == 1,
          'notifyByMeal': row['notify_by_meal'] == 1,
          'intervalMinutes': row['interval_minutes'],
          'et': row['et'],
          'payload': row['payload'],
        };
      }).toList();

      setState(() {
        _reminders = mappedList;
      });
    } catch (e) {
      debugPrint('Dashboard: error loading reminders DB: $e');
      setState(() {
        _reminders = [];
      });
    } finally {
      setState(() {
        _isLoadingReminders = false;
      });
    }
  }

  // ✅ แก้ไข: โหลดประวัติการกินจาก SQLite (taken_doses)
  Future<void> _loadEated() async {
    setState(() {
      _isLoadingEated = true;
    });

    try {
      final db = await dbHelper.database;

      final List<Map<String, dynamic>> results = await db.query(
        'taken_doses',
        where: 'userid = ?',
        whereArgs: [widget.username],
      );

      final keys = <String>{};
      final List<Map<String, dynamic>> mappedList = [];

      for (final row in results) {
        final reminderId = row['reminder_id']?.toString();
        final doseStr = row['dose_date_time']?.toString();

        if (reminderId != null && doseStr != null) {
          keys.add('$reminderId|$doseStr');
        }

        // map กลับให้ตรงกับ structure ที่ UI อาจจะใช้ (ถ้ามี)
        mappedList.add({
          'userid': row['userid'],
          'reminderId': row['reminder_id'],
          'doseDateTime': row['dose_date_time'],
          'takenAt': row['taken_at'],
        });
      }

      setState(() {
        _eated = mappedList;
        _takenDoseKeys = keys;
      });
    } catch (e) {
      debugPrint('Dashboard: error loading eated DB: $e');
      setState(() {
        _eated = [];
        _takenDoseKeys = {};
      });
    } finally {
      setState(() {
        _isLoadingEated = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    try {
      final file = await _userStatFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _openAddReminderSheet() async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.25,
          maxChildSize: 1.0,
          expand: true,
          builder: (ctx, scrollController) {
            return CarlendarAddSheet(
              username: widget.username,
              scrollController: scrollController,
            );
          },
        );
      },
    );

    // เมื่อกลับมา ให้โหลดข้อมูลใหม่
    if (result != null) {
      // เรียก _loadInitialData เลยเพื่อให้ Trigger ทำงานด้วย
      await _loadInitialData();
    }
  }

  // ✅ แก้ไข: เรียก CarlendarEditSheet ขึ้นมาในแบบ DraggableScrollableSheet
  Future<void> _openEditReminderSheet(Map<String, dynamic> reminder) async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true, // ทำให้แสดงผลเต็มจอได้
      useSafeArea: true,
      enableDrag: true,
      backgroundColor:
          Colors.transparent, // โปร่งใสเพื่อให้เห็นมุมโค้งของ Sheet
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.25,
          maxChildSize: 1.0,
          expand: true,
          builder: (ctx, scrollController) {
            // สมมติชื่อคลาสใน edit_carlendar.dart คือ CarlendarEditSheet
            // และรับ parameter 'reminder' หรือ 'data'
            return CarlendarEditSheet(
              username: widget.username,
              reminder: reminder, // ส่งข้อมูลที่ต้องการแก้ไขเข้าไป
              scrollController: scrollController,
            );
          },
        );
      },
    );

    // หากมีการบันทึกและปิดหน้า (result != null) ให้โหลดข้อมูลใหม่
    if (result != null) {
      // เรียก _loadInitialData เลยเพื่อให้ Trigger ทำงานด้วย
      await _loadInitialData();
    }
  }

  // ---------- PASSWORD VERIFY / CLEAR TAKEN ----------

  Future<bool> _verifyPassword(String inputPassword) async {
    try {
      final user = await dbHelper.getUser(widget.username);
      if (user != null) {
        if (user['password'] == inputPassword) {
          return true;
        }
      }
    } catch (e) {
      debugPrint('Dashboard: verifyPassword error: $e');
    }
    return false;
  }

  Future<bool?> _showClearTakenConfirmDialog() async {
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
              title: const Text('ยืนยันการเคลียร์สถานะการกินยา'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'เพื่อเคลียร์สถานะการกินยาของรายการนี้ให้เป็น "ยังไม่ได้กิน"\nกรุณากรอกรหัสผ่านของคุณเพื่อยืนยัน',
                    style: TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    style: const TextStyle(color: Colors.black),
                    decoration: InputDecoration(
                      labelText: 'รหัสผ่าน',
                      labelStyle: const TextStyle(color: Colors.black),
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

  Future<void> _clearTakenForReminder(
    Map<String, dynamic> reminder,
    DateTime? time,
  ) async {
    final reminderId = reminder['id']?.toString();
    final doseIso = time?.toIso8601String();

    if (reminderId == null || doseIso == null) return;

    try {
      final db = await dbHelper.database;

      await db.delete(
        'taken_doses',
        where: 'userid = ? AND reminder_id = ? AND dose_date_time = ?',
        whereArgs: [widget.username, reminderId, doseIso],
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('เคลียร์สถานะการกินยาของโดสนี้เรียบร้อยแล้ว'),
        ),
      );

      await _loadEated();
      await NortificationSetup.run(context: context, username: widget.username);
    } catch (e) {
      debugPrint('Dashboard: clearTakenForReminder error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเคลียร์สถานะการกินยาได้')),
      );
    }
  }

  // ---------- UTILS ----------

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$d/$m/$y';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  List<DateTime> _computeDoseTimesForDay(
    Map<String, dynamic> reminder,
    DateTime viewDate,
  ) {
    final selectedDay = _dateOnly(viewDate);

    final startStr = reminder['startDateTime']?.toString();
    if (startStr == null || startStr.isEmpty) {
      return [];
    }
    final start = DateTime.tryParse(startStr);
    if (start == null) return [];

    final endStr = reminder['endDateTime']?.toString();
    DateTime? end;
    if (endStr != null && endStr.isNotEmpty) {
      end = DateTime.tryParse(endStr);
    }

    final notifyByTime = reminder['notifyByTime'] == true;

    final intervalMinutes =
        int.tryParse(reminder['intervalMinutes']?.toString() ?? '') ?? 0;

    final startDateOnly = _dateOnly(start);
    final DateTime? endDateOnly = end != null ? _dateOnly(end) : null;

    if (selectedDay.isBefore(startDateOnly)) {
      return [];
    }

    if (endDateOnly != null && selectedDay.isAfter(endDateOnly)) {
      return [];
    }

    final dayStart = selectedDay;
    final dayEnd = dayStart.add(const Duration(days: 1));

    if (!notifyByTime || intervalMinutes <= 0) {
      final t = start;
      if (t.isBefore(dayStart) || !t.isBefore(dayEnd)) {
        return [];
      }
      return [t];
    }

    if (dayEnd.isBefore(start)) return [];
    if (end != null && dayStart.isAfter(end)) return [];

    final stepMinutes = intervalMinutes;
    if (stepMinutes <= 0) return [];

    DateTime first;
    if (!dayStart.isAfter(start)) {
      first = start;
    } else {
      final diffMinutes = dayStart.difference(start).inMinutes;
      final steps = (diffMinutes / stepMinutes).ceil();
      first = start.add(Duration(minutes: steps * stepMinutes));
    }

    final result = <DateTime>[];
    var t = first;

    while (t.isBefore(dayEnd) && (end == null || !t.isAfter(end))) {
      result.add(t);
      t = t.add(Duration(minutes: stepMinutes));
    }

    return result;
  }

  // ---------- CHECK DOSE ----------

  String? _doseKey(Map<String, dynamic> reminder, DateTime? time) {
    if (time == null) return null;
    final reminderId = reminder['id']?.toString();
    if (reminderId == null || reminderId.isEmpty) return null;
    return '$reminderId|${time.toIso8601String()}';
  }

  bool _isDoseTaken(Map<String, dynamic> reminder, DateTime? time) {
    final key = _doseKey(reminder, time);
    if (key == null) return false;
    return _takenDoseKeys.contains(key);
  }

  bool _isDoseScanning(Map<String, dynamic> reminder, DateTime? time) {
    final key = _doseKey(reminder, time);
    if (!_isScanningNfc || key == null) return false;
    return key == _scanningDoseKey;
  }

  // ✅ บันทึกว่ากินยาแล้ว (ลง SQLite)
  Future<void> _markDoseTaken(
    Map<String, dynamic> reminder,
    DateTime? time,
  ) async {
    if (time == null) return;
    final key = _doseKey(reminder, time);
    if (key == null) return;

    final reminderId = reminder['id']?.toString();
    if (reminderId == null || reminderId.isEmpty) return;

    final doseIso = time.toIso8601String();

    try {
      final isCurrentlyTaken = _takenDoseKeys.contains(key);
      if (isCurrentlyTaken) return;

      final nowIso = DateTime.now().toIso8601String();
      final db = await dbHelper.database;

      // Insert ลงตาราง taken_doses
      await db.insert('taken_doses', {
        'userid': widget.username,
        'reminder_id': reminderId,
        'dose_date_time': doseIso,
        'taken_at': nowIso,
      });

      if (!mounted) return;

      // อัปเดต UI ทันที
      await _loadEated();

      // กินยาแล้ว -> อัปเดต noti
      await NortificationSetup.run(context: context, username: widget.username);
    } catch (e) {
      debugPrint('Dashboard: mark dose taken error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกสถานะการกินยาไม่สำเร็จ')),
      );
    }
  }

  // ---------- ACTION LOGIC ----------

  // ✅ ฟังก์ชันสแกน NFC (สำหรับโหมดใช้ NFC เท่านั้น)
  Future<void> _scanDoseWithNfc(
    Map<String, dynamic> reminder,
    DateTime? time,
  ) async {
    if (time == null) return;
    final doseKey = _doseKey(reminder, time);
    if (doseKey == null) return;

    // ถ้ากำลังสแกนการ์ดใบเดิมอยู่ -> ยกเลิกการสแกน
    if (_isScanningNfc && _scanningDoseKey == doseKey) {
      try {
        await FlutterNfcKit.finish(iosErrorMessage: 'ยกเลิกการสแกน');
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isScanningNfc = false;
          _scanningDoseKey = null;
        });
      }
      return;
    }

    if (_isScanningNfc && _scanningDoseKey != doseKey) {
      return;
    }

    setState(() {
      _isScanningNfc = true;
      _scanningDoseKey = doseKey;
    });

    try {
      final availability = await FlutterNfcKit.nfcAvailability;
      if (availability != NFCAvailability.available) {
        if (!mounted) return;
        await _showAutoDismissDialog(
          'ไม่สามารถใช้ NFC',
          'อุปกรณ์นี้ไม่รองรับ NFC หรือยังไม่ได้เปิดใช้งาน',
        );
        return;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาแตะแท็ก NFC ที่ยานี้ เพื่อยืนยันการกินยา'),
        ),
      );

      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
        iosMultipleTagMessage: 'พบหลายแท็ก',
        iosAlertMessage: 'แตะแท็กที่ต้องการ',
      );

      debugPrint('Dashboard: NFC tag = $tag');

      List<dynamic> ndefRecords = [];
      try {
        ndefRecords = await FlutterNfcKit.readNDEFRecords();
      } catch (e) {
        debugPrint('Dashboard: readNDEF error: $e');
      }

      String? textPayload;
      for (final rec in ndefRecords) {
        if (rec is ndef.TextRecord) {
          textPayload = rec.text;
          break;
        }
      }

      final expectedPayloadFull = reminder['payload']?.toString().trim();
      final medName = reminder['medicineName']?.toString().trim() ?? '';
      final medDetail = reminder['medicineDetail']?.toString().trim() ?? '';
      final expectedPrefix = medDetail.isNotEmpty
          ? '$medName~$medDetail'
          : medName;

      bool match = false;
      if (textPayload != null) {
        final t = textPayload.trim();

        if (expectedPayloadFull != null && expectedPayloadFull.isNotEmpty) {
          if (t == expectedPayloadFull) {
            match = true;
          } else if (t.startsWith(expectedPrefix)) {
            match = true;
          }
        } else {
          if (expectedPrefix.isNotEmpty && t.startsWith(expectedPrefix)) {
            match = true;
          }
        }
      }

      if (!mounted) return;

      if (!match) {
        await _showAutoDismissDialog(
          'ยาที่สแกนไม่ตรงกัน',
          'ยาที่สแกนไม่ตรงกับรายการนี้ กรุณาตรวจสอบชื่อยาให้ถูกต้องก่อนรับประทาน',
        );
        try {
          await FlutterNfcKit.finish(
            iosErrorMessage: 'แท็กไม่ตรงกับยาที่เลือก',
          );
        } catch (_) {}
        return;
      }

      // ถ้าตรง ถือว่าสแกนผ่าน -> mark ว่ากินแล้ว
      await _markDoseTaken(reminder, time);

      if (!mounted) return;

      await _showAutoDismissDialog(
        'บันทึกสำเร็จ',
        'ยืนยันการกินยาด้วย NFC แล้ว',
      );

      try {
        await FlutterNfcKit.finish(iosAlertMessage: 'สำเร็จ');
      } catch (_) {}
    } catch (e) {
      debugPrint('Dashboard: NFC scan error: $e');
      if (mounted) {
        await _showAutoDismissDialog(
          'สแกน NFC ไม่สำเร็จ',
          'เกิดข้อผิดพลาดในการสแกน NFC: $e',
        );
      }
      try {
        await FlutterNfcKit.finish(iosErrorMessage: 'ล้มเหลว');
      } catch (_) {}
    } finally {
      if (mounted) {
        setState(() {
          _isScanningNfc = false;
          _scanningDoseKey = null;
        });
      }
    }
  }

  Future<void> _showAutoDismissDialog(String title, String message) async {
    if (!mounted) return;
    Timer? timer;
    bool closedByButton = false;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        timer ??= Timer(const Duration(seconds: 3), () {
          if (!closedByButton && Navigator.of(ctx).canPop()) {
            Navigator.of(ctx).pop();
          }
        });

        return AlertDialog(
          title: Text(title, style: const TextStyle(color: Colors.black87)),
          content: Text(message, style: const TextStyle(color: Colors.black87)),
          actions: [
            TextButton(
              onPressed: () {
                closedByButton = true;
                Navigator.of(ctx).pop();
              },
              child: const Text('ตกลง'),
            ),
          ],
        );
      },
    );

    timer?.cancel();
  }

  // ---------- DATE SELECTOR & DAY CHANGE ----------

  void _goToPrevDay() {
    if (_pageController.hasClients) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    } else {
      setState(() {
        _selectedDateTime = _selectedDateTime.subtract(const Duration(days: 1));
      });
    }
  }

  void _goToNextDay() {
    if (_pageController.hasClients) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    } else {
      setState(() {
        _selectedDateTime = _selectedDateTime.add(const Duration(days: 1));
      });
    }
  }

  Widget _buildDateSelector(DateTime date) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _goToPrevDay,
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: _pickDashboardDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(
                'วันที่ ${_formatDate(date)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.black87,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _goToNextDay,
          ),
        ],
      ),
    );
  }

  Future<void> _pickDashboardDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('th', 'TH'),
    );
    if (picked == null) return;

    final targetDate = _dateOnly(picked);
    final diffDays = targetDate.difference(_dateOnly(_baseDate)).inDays;
    final targetPage = _initialPage + diffDays;

    if (_pageController.hasClients) {
      _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    } else {
      setState(() {
        _selectedDateTime = targetDate;
      });
    }
  }

  // ---------- CARD ----------

  Widget _buildCardActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(24),
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 20),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildDoseCard(_DoseItem item) {
    final r = item.reminder;
    final profileName = r['profileName']?.toString() ?? widget.username;
    final medicineName = r['medicineName']?.toString() ?? '-';
    final medicineDetail = r['medicineDetail']?.toString() ?? '';

    String timeText;
    if (item.time != null) {
      final t = item.time!;
      timeText = 'เวลากินยา: ${_formatDate(t)} ${_formatTime(t)}';
    } else {
      timeText = 'เวลากินยา: -';
    }

    final isTaken = _isDoseTaken(r, item.time);
    final isScanning = _isDoseScanning(r, item.time);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isScanning ? Colors.blueAccent : Colors.transparent,
          width: isScanning ? 2 : 0,
        ),
      ),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // ✅ Logic การแตะ: อ่านไฟล์สถานะล่าสุดก่อนทำงานเสมอ
        onTap: () async {
          if (isTaken)
            return; // ถ้ากินแล้ว แตะธรรมดาไม่ต้องทำอะไร (รอ Long Press)

          // 1. อ่านสถานะ NFC ล่าสุดจากไฟล์
          final realTimeNfcStatus = await _getNfcStatusFromFile();
          if (mounted) {
            setState(() {
              _isNfcEnabled = realTimeNfcStatus;
            });
          }

          // 2. แยกการทำงานตามโหมด
          if (realTimeNfcStatus) {
            // โหมด NFC: สแกน
            _scanDoseWithNfc(r, item.time);
          } else {
            // โหมด Manual: แจ้งเตือนให้กดค้าง
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('กดค้างไว้ 2 วินาทีเพื่อยืนยันการกินยา'),
              ),
            );
          }
        },
        // ✅ Logic การกดค้าง (สำหรับ Manual Mode และ เพิ่ม Clear Taken Logic)
        onTapDown: (_) {
          // ไม่ return แล้ว ถ้า isTaken เป็น true เพื่อให้เข้าสู่ Timer Logic

          // เริ่มจับเวลา 2 วินาที
          _manualHoldTimer = Timer(const Duration(seconds: 2), () async {
            if (isTaken) {
              // ----------------------------------------------------------
              // ✨ NEW: ถ้ากินแล้ว ให้เรียกฟังก์ชันยกเลิก (ต้องใส่ Password)
              // ----------------------------------------------------------
              if (!mounted) return;

              // เรียก Dialog ยืนยันการลบ (ต้องใส่ password ตามโค้ดเดิม)
              final ok = await _showClearTakenConfirmDialog();
              if (ok == true) {
                await _clearTakenForReminder(r, item.time);
              }
            } else {
              // ----------------------------------------------------------
              // ✨ OLD: ถ้ายันไม่กิน ให้ยืนยันการกิน (Manual Mode)
              // ----------------------------------------------------------
              // เมื่อครบ 2 วินาที ตรวจสอบสถานะจากไฟล์อีกครั้งเพื่อความชัวร์
              final realTimeNfcStatus = await _getNfcStatusFromFile();
              if (mounted) {
                setState(() {
                  _isNfcEnabled = realTimeNfcStatus;
                });
              }

              // ถ้ายังเป็นโหมด Manual (ปิด NFC) ให้บันทึก
              if (!realTimeNfcStatus) {
                await _markDoseTaken(r, item.time);
                if (mounted) {
                  await _showAutoDismissDialog(
                    'บันทึกสำเร็จ',
                    'ยืนยันการกินยาเรียบร้อยแล้ว (Manual Mode)',
                  );
                }
              }
            }
          });
        },
        onTapUp: (_) {
          // ปล่อยนิ้ว -> ยกเลิก timer
          _manualHoldTimer?.cancel();
        },
        onTapCancel: () {
          // ลากนิ้วออก -> ยกเลิก timer
          _manualHoldTimer?.cancel();
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildProfileAvatarFor(profileName),
                  const SizedBox(height: 8),
                  _buildCardActionButton(
                    icon: Icons.edit,
                    color: Colors.teal,
                    tooltip: 'แก้ไขการแจ้งเตือน',
                    onPressed: () => _openEditReminderSheet(r),
                  ),
                  const SizedBox(height: 6),
                  _buildCardActionButton(
                    icon: Icons.cleaning_services,
                    color: Colors.redAccent,
                    tooltip: 'เคลียร์สถานะการกินยา',
                    onPressed: () async {
                      final ok = await _showClearTakenConfirmDialog();
                      if (ok == true) {
                        await _clearTakenForReminder(r, item.time);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      profileName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ยาที่ต้องกิน: $medicineName',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    if (medicineDetail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        medicineDetail,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      timeText,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isTaken
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: isTaken ? Colors.green[700] : Colors.red[700],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isTaken ? 'กินแล้ว (ยืนยันด้วย NFC)' : 'ยังไม่ได้กิน',
                          style: TextStyle(
                            fontSize: 13,
                            color: isTaken
                                ? Colors.green[700]
                                : Colors.red[700],
                            fontWeight: isTaken
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // คำอธิบายเปลี่ยนตามโหมด
                    Text(
                      isTaken
                          ? 'กดค้างไว้ 2 วินาที เพื่อยกเลิกสถานะ' // เพิ่ม Hint สำหรับกรณีที่กินแล้ว
                          : (_isNfcEnabled
                                ? 'แตะการ์ดเพื่อสแกน NFC ยา'
                                : 'กดค้างไว้ 2 วินาที เพื่อยืนยันการกินยา'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileAvatarFor(String? profileName) {
    final name = profileName ?? widget.username;

    Map<String, dynamic>? profile;
    for (final p in _profiles) {
      final n = p['name']?.toString();
      if (n == name) {
        profile = p;
        break;
      }
    }

    final imageData = profile?['image'];

    if (imageData == null || imageData.toString().isEmpty) {
      return const CircleAvatar(
        radius: 22,
        child: Icon(Icons.person, size: 22),
      );
    }

    try {
      final imgStr = imageData.toString();
      // รูป asset ยังมีโอกาสเจอใน profile
      if (imgStr.startsWith('assets/')) {
        return CircleAvatar(radius: 22, backgroundImage: AssetImage(imgStr));
      }

      final bytes = base64Decode(imgStr);
      return CircleAvatar(radius: 22, backgroundImage: MemoryImage(bytes));
    } catch (e) {
      debugPrint('Dashboard: decode profile image fail: $e');
      return const CircleAvatar(
        radius: 22,
        child: Icon(Icons.person, size: 22),
      );
    }
  }

  // ---------- BODY CONTENT (ต่อ 1 วัน) ----------

  Widget _buildBodyContent(DateTime viewDate) {
    if (_isLoadingReminders || _isLoadingProfiles || _isLoadingEated) {
      return Column(
        children: [
          _buildDateSelector(viewDate),
          const Expanded(
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ],
      );
    }

    if (_reminders.isEmpty) {
      return Column(
        children: [
          _buildDateSelector(viewDate),
          const Expanded(
            child: Center(
              child: Text(
                'ยังไม่มีข้อมูลการแจ้งเตือน\n(หน้าหลัก Dashboard)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.black87),
              ),
            ),
          ),
        ],
      );
    }

    final List<_DoseItem> doseItems = [];

    for (final r in _reminders) {
      final times = _computeDoseTimesForDay(r, viewDate);
      for (final t in times) {
        doseItems.add(_DoseItem(reminder: r, time: t));
      }
    }

    if (doseItems.isEmpty) {
      return Column(
        children: [
          _buildDateSelector(viewDate),
          const Expanded(
            child: Center(
              child: Text(
                'ไม่มีเวลากินยาสำหรับวันที่เลือก',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ),
          ),
        ],
      );
    }

    doseItems.sort((a, b) {
      if (a.time == null && b.time == null) return 0;
      if (a.time == null) return 1;
      if (b.time == null) return -1;
      return a.time!.compareTo(b.time!);
    });

    return Column(
      children: [
        _buildDateSelector(viewDate),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: doseItems.length,
            scrollDirection: Axis.vertical,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            itemBuilder: (context, index) => _buildDoseCard(doseItems[index]),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
          ),
        ),
      ],
    );
  }

  // ---------- BODY: PAGEVIEW (เลื่อนตามนิ้ว) ----------

  Widget _buildBody() {
    return GestureDetector(
      // ให้การเลื่อนซ้ายขวา "แรง ๆ" เท่านั้นที่เปลี่ยนวัน
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0.0;
        // ต้องแรงหน่อย: เกิน 400 px/s
        if (velocity.abs() < 400) return;

        if (velocity < 0) {
          // ปัดจากขวาไปซ้าย -> วันถัดไป
          _goToNextDay();
        } else {
          // ปัดจากซ้ายไปขวา -> วันก่อนหน้า
          _goToPrevDay();
        }
      },
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.horizontal,
        physics:
            const NeverScrollableScrollPhysics(), // ปิด scroll ปกติของ PageView
        onPageChanged: (pageIndex) {
          final diff = pageIndex - _initialPage;
          final date = _baseDate.add(Duration(days: diff));
          setState(() {
            _selectedDateTime = _dateOnly(date);
          });
        },
        itemBuilder: (context, index) {
          final diff = index - _initialPage;
          final date = _baseDate.add(Duration(days: diff));
          final viewDate = _dateOnly(date);
          return _buildBodyContent(viewDate);
        },
      ),
    );
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('การแจ้งเตือน')),
      drawer: LeftMenu(
        username: widget.username,
        // 1. ไปหน้า Dashboard: (เราอยู่หน้านี้อยู่แล้ว)
        onShowDashboard: () {
          // ไม่ต้องทำอะไร
        },

        // 2. ไปหน้าปฏิทิน: สั่ง Push ไป
        onManageCalendar: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CarlendarPage(username: widget.username),
            ),
          );
        },

        onCreateProfile: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateProfilePage()),
          );
        },
        onmanage_profile: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  manage_profilePage(username: widget.username),
            ),
          );
        },
        onAddMedicine: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MedicineAddPage(username: widget.username),
            ),
          );
        },
        onManageMedicine: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  MedicineManagePage(username: widget.username),
            ),
          );
        },
        onLogout: _handleLogout,
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddReminderSheet,
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add),
      ),
    );
  }
}
