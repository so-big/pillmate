// lib/view_dashboard.dart

import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'nortification_setup.dart';
import 'view_carlendar.dart';
import 'add_carlendar.dart';
import 'edit_carlendar.dart'; // หน้าแก้ไข
import 'create_profile.dart';
import 'manage_profile.dart';
import 'view_menu.dart';
import 'add_medicine.dart';
import 'manage_medicine.dart';
import 'main.dart'; // มี LoginPage อยู่ในนี้

import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;

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
    return File('${dir.path}/user-stat.json');
  }

  Future<File> _remindersFile() async {
    final dir = await _appDir();
    return File('${dir.path}/reminders.json');
  }

  Future<File> _profilesFile() async {
    final dir = await _appDir();
    return File('${dir.path}/profiles.json');
  }

  Future<File> _usersFile() async {
    final dir = await _appDir();
    return File('${dir.path}/user.json');
  }

  Future<File> _eatedFile() async {
    final dir = await _appDir();
    return File('${dir.path}/eated.json');
  }

  // ---------- STATE ----------

  // โปรไฟล์ของคนที่ต้องกินยา (รวมโปรไฟล์ self ที่ชื่อ = username)
  List<Map<String, dynamic>> _profiles = [];
  bool _isLoadingProfiles = true;

  // รายการ reminder จาก JSON
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

  @override
  void initState() {
    super.initState();
    // ถ้ามาจาก Calendar ให้ใช้เวลาช่องนั้น ไม่งั้นใช้ตอนนี้
    _selectedDateTime = widget.initialDateTime ?? DateTime.now();
    _selectedDateTime = _dateOnly(_selectedDateTime);

    _baseDate = _selectedDateTime;
    _pageController = PageController(initialPage: _initialPage);

    _loadInitialData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([_loadProfiles(), _loadReminders(), _loadEated()]);
    // โหลดข้อมูลเสร็จแล้ว -> setup noti ล่วงหน้า
    await NortificationSetup.run(context: context, username: widget.username);
  }

  Future<void> _loadProfiles() async {
    setState(() {
      _isLoadingProfiles = true;
    });

    try {
      String? accountImage;
      try {
        final usersFile = await _usersFile();
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
        debugPrint('Dashboard: error loading user image: $e');
      }

      final file = await _profilesFile();
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
          .map<Map<String, dynamic>>((p) => Map<String, dynamic>.from(p))
          .toList();

      final profiles = <Map<String, dynamic>>[];

      // โปรไฟล์ตัวเอง
      profiles.add({
        'name': widget.username,
        'createby': widget.username,
        'image': accountImage,
      });

      // โปรไฟล์อื่น ๆ ที่ผู้ใช้สร้าง
      profiles.addAll(filtered);

      setState(() {
        _profiles = profiles;
      });
    } catch (e) {
      debugPrint('Dashboard: error loading profiles: $e');
      setState(() {
        _profiles = [];
      });
    } finally {
      setState(() {
        _isLoadingProfiles = false;
      });
    }
  }

  Future<void> _loadReminders() async {
    setState(() {
      _isLoadingReminders = true;
    });

    try {
      final file = await _remindersFile();
      List<dynamic> raw = [];

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          raw = jsonDecode(content);
        }
      }

      final filtered = raw
          .where((r) {
            if (r is Map<String, dynamic>) {
              return r['createby'] == widget.username;
            }
            if (r is Map) return r['createby'] == widget.username;
            return false;
          })
          .map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r))
          .toList();

      setState(() {
        _reminders = filtered;
      });
    } catch (e) {
      debugPrint('Dashboard: error loading reminders: $e');
      setState(() {
        _reminders = [];
      });
    } finally {
      setState(() {
        _isLoadingReminders = false;
      });
    }
  }

  Future<void> _loadEated() async {
    setState(() {
      _isLoadingEated = true;
    });

    try {
      final file = await _eatedFile();
      List<dynamic> raw = [];

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          raw = jsonDecode(content);
        }
      }

      final filtered = raw
          .where((e) {
            if (e is Map<String, dynamic>) {
              return e['userid'] == widget.username;
            }
            if (e is Map) return e['userid'] == widget.username;
            return false;
          })
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();

      final keys = <String>{};
      for (final m in filtered) {
        final reminderId = m['reminderId']?.toString();
        final doseStr = m['doseDateTime']?.toString();
        if (reminderId != null && doseStr != null && doseStr.isNotEmpty) {
          keys.add('$reminderId|$doseStr');
        }
      }

      setState(() {
        _eated = filtered;
        _takenDoseKeys = keys;
      });
    } catch (e) {
      debugPrint('Dashboard: error loading eated: $e');
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

  Future<void> _appendReminder(Map<String, dynamic> result) async {
    try {
      final file = await _remindersFile();
      List<dynamic> list = [];

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          list = jsonDecode(content);
        }
      }

      final now = DateTime.now();

      final reminder = <String, dynamic>{};
      reminder.addAll(result);
      reminder['id'] ??= now.millisecondsSinceEpoch.toString();
      reminder['createby'] = widget.username;
      reminder['createdAt'] ??= now.toIso8601String();

      list.add(reminder);

      await file.writeAsString(jsonEncode(list), flush: true);

      await _loadReminders();
      // เพิ่ม reminder ใหม่ -> ตั้ง noti ใหม่ให้ด้วย
      await NortificationSetup.run(context: context, username: widget.username);
    } catch (e) {
      debugPrint('Dashboard: append reminder error: $e');
    }
  }

  Future<void> _updateReminder(
    Map<String, dynamic> edited,
    Map<String, dynamic> original,
  ) async {
    try {
      final file = await _remindersFile();
      List<dynamic> list = [];

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          list = jsonDecode(content);
        }
      }

      final now = DateTime.now();
      final originalId =
          original['id']?.toString() ??
          edited['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString();

      bool replaced = false;

      for (int i = 0; i < list.length; i++) {
        final item = list[i];
        if (item is Map || item is Map<String, dynamic>) {
          final map = Map<String, dynamic>.from(item);
          final id = map['id']?.toString();
          final createby = map['createby']?.toString();

          if (id == originalId && createby == widget.username) {
            final updated = <String, dynamic>{};
            updated.addAll(map); // ค่าของเดิม
            updated.addAll(edited); // ทับด้วยค่าที่แก้ไข
            updated['id'] = originalId;
            updated['createby'] = widget.username;
            updated['updatedAt'] = now.toIso8601String();

            list[i] = updated;
            replaced = true;
            break;
          }
        }
      }

      if (!replaced) {
        final newMap = <String, dynamic>{};
        newMap.addAll(edited);
        newMap['id'] = originalId;
        newMap['createby'] = widget.username;
        newMap['updatedAt'] = now.toIso8601String();
        list.add(newMap);
      }

      await file.writeAsString(jsonEncode(list), flush: true);

      await _loadReminders();
      // แก้ไข reminder -> ตั้ง noti ใหม่
      await NortificationSetup.run(context: context, username: widget.username);
    } catch (e) {
      debugPrint('Dashboard: update reminder error: $e');
    }
  }

  Future<void> _handleLogout() async {
    try {
      final file = await _userStatFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // ลบไม่ได้ก็แล้วไป
    }

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
      isScrollControlled: true, // จำเป็นมาก เพื่อให้ขยายเกินครึ่งจอได้
      useSafeArea: true, // ช่วยให้ขยายเต็มพื้นที่ Safe Area ได้สวยงามขึ้น
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5, // เริ่มต้นครึ่งจอ
          minChildSize: 0.25, // หดต่ำสุด
          maxChildSize: 1.0, // ขยายสูงสุด (เต็มจอ)
          expand: true, // ต้องเป็น false เพื่อให้ยืดหดตามการลาก
          builder: (ctx, scrollController) {
            // สำคัญ: ต้องส่ง scrollController นี้เข้าไปใน Widget ลูก
            return CarlendarAddSheet(
              username: widget.username,
              scrollController: scrollController,
            );
          },
        );
      },
    );

    if (result != null && result is Map<String, dynamic>) {
      debugPrint('New reminder from dashboard: $result');
      await _appendReminder(result);
    }
  }

  Future<void> _openEditReminderSheet(Map<String, dynamic> reminder) async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.25,
          maxChildSize: 1.0,
          expand: true,
          builder: (ctx, scrollController) {
            return CarlendarEditSheet(
              username: widget.username,
              reminder: reminder,
              scrollController: scrollController,
            );
          },
        );
      },
    );

    if (result != null && result is Map<String, dynamic>) {
      debugPrint('Edited reminder from dashboard: $result');
      await _updateReminder(result, reminder);
    }
  }

  // ---------- PASSWORD VERIFY / CLEAR TAKEN ----------

  Future<bool> _verifyPassword(String inputPassword) async {
    try {
      final file = await _usersFile();
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

    if (reminderId == null || reminderId.isEmpty || doseIso == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่พบข้อมูลการ์ดยา ไม่สามารถเคลียร์สถานะได้'),
        ),
      );
      return;
    }

    try {
      final file = await _eatedFile();
      List<dynamic> list = [];

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is List) {
            list = decoded;
          }
        }
      }

      // ลบเฉพาะ record ของ user + reminder + เวลา (โดสนี้เท่านั้น)
      list = list.where((e) {
        if (e is Map || e is Map<String, dynamic>) {
          final m = Map<String, dynamic>.from(e);
          final uid = m['userid']?.toString();
          final rid = m['reminderId']?.toString();
          final d = m['doseDateTime']?.toString();
          if (uid == widget.username && rid == reminderId && d == doseIso) {
            return false;
          }
        }
        return true;
      }).toList();

      await file.writeAsString(jsonEncode(list), flush: true);

      // สร้าง eated + takenKeys ใหม่สำหรับ user นี้
      final filteredForUser = list
          .where((e) {
            if (e is Map<String, dynamic>) {
              return e['userid'] == widget.username;
            }
            if (e is Map) return e['userid'] == widget.username;
            return false;
          })
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();

      final newKeys = <String>{};
      for (final m in filteredForUser) {
        final rid = m['reminderId']?.toString();
        final d = m['doseDateTime']?.toString();
        if (rid != null && d != null && d.isNotEmpty) {
          newKeys.add('$rid|$d');
        }
      }

      if (!mounted) return;
      setState(() {
        _eated = filteredForUser;
        _takenDoseKeys = newKeys;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('เคลียร์สถานะการกินยาของโดสนี้เรียบร้อยแล้ว'),
        ),
      );

      // เคลียร์สถานะแล้ว -> ให้ noti future ปรับตาม
      await NortificationSetup.run(context: context, username: widget.username);
    } catch (e) {
      debugPrint('Dashboard: clearTakenForReminder error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเคลียร์สถานะการกินยาได้')),
      );
    }
  }

  // ---------- UTILS (DATE / TIME / DOSES) ----------

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

  /// คืน list ของเวลาที่ต้องกินยา "ในวันเดียวกับ viewDate"
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

    // ใช้ intervalMinutes แบบใหม่อย่างเดียว ข้อมูลเก่าไม่สนใจ
    final intervalMinutes =
        int.tryParse(reminder['intervalMinutes']?.toString() ?? '') ?? 0;

    final startDateOnly = _dateOnly(start);
    final DateTime? endDateOnly = end != null ? _dateOnly(end) : null;

    // ก่อนวันเริ่ม -> ไม่แสดง
    if (selectedDay.isBefore(startDateOnly)) {
      return [];
    }

    // ถ้ามี end แล้ววันเลือกหลัง end -> ไม่แสดง
    if (endDateOnly != null && selectedDay.isAfter(endDateOnly)) {
      return [];
    }

    final dayStart = selectedDay;
    final dayEnd = dayStart.add(const Duration(days: 1));

    // ถ้าไม่แจ้งเตือนตามเวลา หรือ intervalMinutes <= 0 -> มีแค่ start ครั้งเดียว
    if (!notifyByTime || intervalMinutes <= 0) {
      final t = start;
      if (t.isBefore(dayStart) || !t.isBefore(dayEnd)) {
        return [];
      }
      return [t];
    }

    // เคสมี interval เป็นนาที
    if (dayEnd.isBefore(start)) return [];
    if (end != null && dayStart.isAfter(end)) return [];

    final stepMinutes = intervalMinutes;
    if (stepMinutes <= 0) return [];

    // หาเวลาแรกของวันนั้น
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

  // ---------- NFC / TAKEN BY NFC ----------

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
      final file = await _eatedFile();
      List<dynamic> list = [];

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is List) {
            list = decoded;
          }
        }
      }

      final isCurrentlyTaken = _takenDoseKeys.contains(key);
      if (isCurrentlyTaken) {
        // กินไปแล้ว ไม่ต้องทำอะไรเพิ่ม
        return;
      }

      final nowIso = DateTime.now().toIso8601String();
      final newRecord = {
        'userid': widget.username,
        'reminderId': reminderId,
        'doseDateTime': doseIso,
        'takenAt': nowIso,
      };
      list.add(newRecord);

      await file.writeAsString(jsonEncode(list), flush: true);

      if (!mounted) return;
      setState(() {
        _takenDoseKeys.add(key);
        _eated.add(Map<String, dynamic>.from(newRecord));
      });

      // กินยาแล้ว -> อัปเดต noti ให้ไม่เตือนโดสนี้อีก
      await NortificationSetup.run(context: context, username: widget.username);
    } catch (e) {
      debugPrint('Dashboard: mark dose taken error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกสถานะการกินยาไม่สำเร็จ')),
      );
    }
  }

  // lib/dashboard.dart (เฉพาะส่วนที่แก้ไขในคลาส _DashboardPageState)

  // ... โค้ดส่วนบน (ตัดออก) ...

  Future<void> _scanDoseWithNfc(
    Map<String, dynamic> reminder,
    DateTime? time,
  ) async {
    if (time == null) return;

    final doseKey = _doseKey(reminder, time);
    if (doseKey == null) return;

    // ตรวจสอบว่าโดสนี้ถูกกินไปแล้วหรือไม่
    final isTaken = _isDoseTaken(reminder, time);

    // --- [ส่วนที่ 1: จัดการกรณีที่ "กินแล้ว" -> ให้ยกเลิกสถานะ] ---
    if (isTaken) {
      // 1. ถามรหัสผ่านเพื่อยืนยันการยกเลิกสถานะ
      final ok = await _showClearTakenConfirmDialog();

      if (ok == true) {
        // 2. ถ้าผู้ใช้ยืนยันรหัสผ่านถูกต้อง -> เคลียร์สถานะการกินยา
        await _clearTakenForReminder(reminder, time);
      } else {
        // ยกเลิก หรือรหัสผ่านไม่ถูกต้อง
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ยกเลิกการเคลียร์สถานะ')));
      }
      return; // ออกจากฟังก์ชัน ไม่ต้องดำเนินการสแกน NFC
    }
    // --- [สิ้นสุด ส่วนที่ 1] ---

    // --- [ส่วนที่ 2: จัดการกรณีที่ "ยังไม่ได้กิน" -> ให้บันทึกสถานะ] ---

    // ตรวจสอบโหมด PC/Desktop
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    if (isDesktop) {
      debugPrint('Dashboard: Running on PC/Desktop. Skipping NFC scan.');

      // Mark as taken immediately in PC mode
      await _markDoseTaken(reminder, time);

      if (!mounted) return;
      await _showAutoDismissDialog(
        'บันทึกสำเร็จ (PC MODE)',
        'ยืนยันการกินยาในโหมด PC (ไม่ใช้ NFC) แล้ว',
      );

      if (mounted) {
        setState(() {
          _isScanningNfc = false;
          _scanningDoseKey = null;
        });
      }
      return;
    }
    // --- [สิ้นสุด โหมด PC] ---

    // โค้ดเดิม: จัดการการสแกน NFC

    // ถ้ากำลังสแกนการ์ดใบเดิมอยู่ แล้วกดซ้ำ -> ยกเลิกการสแกน
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

    // ถ้ากำลังสแกนการ์ดอื่นอยู่ -> ไม่ทำอะไร
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

      // ถ้าตรง ถือว่าสแกนผ่าน -> mark ว่ากินแล้ว (ไม่ toggle)
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
  // ... โค้ดส่วนล่าง (ตัดออก) ...

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
        onTap: () => _scanDoseWithNfc(r, item.time),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ซ้าย: รูปโปรไฟล์ + ปุ่ม edit / clear (แนวตั้ง)
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
              // ขวา: ข้อความทั้งหมด
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
                    const Text(
                      'แตะการ์ดเพื่อสแกน NFC ยา\n(แตะซ้ำที่การ์ดเดิมเพื่อยกเลิกการสแกน)',
                      style: TextStyle(fontSize: 11, color: Colors.black38),
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
        // --- ส่วนที่ต้องกำหนด ---

        // 1. ไปหน้า Dashboard: (เราอยู่หน้านี้อยู่แล้ว) -> ปล่อยว่างเลย
        onShowDashboard: () {
          // ไม่ต้องทำอะไร (LeftMenu ปิด drawer ให้เอง)
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

        // -----------------------
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
