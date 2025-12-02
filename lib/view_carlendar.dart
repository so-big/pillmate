// lib/view_carlendar.dart

import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'add_carlendar.dart';
import 'create_profile.dart';
import 'manage_profile.dart';
import 'view_menu.dart';
import 'add_medicine.dart';
import 'manage_medicine.dart';
import 'main.dart'; // สำหรับกลับไปหน้า LoginPage ตอน logout

class CarlendarPage extends StatefulWidget {
  final String username;

  const CarlendarPage({super.key, required this.username});

  @override
  State<CarlendarPage> createState() => _CarlendarPageState();
}

class _CarlendarPageState extends State<CarlendarPage> {
  late DateTime _weekStart; // วันเริ่มต้นสัปดาห์ (จันทร์)

  final List<String> _thaiWeekdayShort = const [
    'จ', // Monday
    'อ',
    'พ',
    'พฤ',
    'ศ',
    'ส',
    'อา',
  ];

  final List<String> _thaiMonthShort = const [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];

  // ข้อมูลจาก carlendar.json
  List<Map<String, dynamic>> _calendarEntries = [];
  bool _isLoadingCalendar = true;

  @override
  void initState() {
    super.initState();
    _weekStart = _startOfWeek(DateTime.now());
    _loadCalendarEntries();
  }

  DateTime _startOfWeek(DateTime date) {
    // ให้วันจันทร์เป็นวันเริ่มต้น (weekday: 1 = Monday)
    final int diff = date.weekday - DateTime.monday;
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: diff));
  }

  List<DateTime> _daysInWeek(DateTime start) {
    return List.generate(7, (i) => start.add(Duration(days: i)));
  }

  String _formatWeekRange(DateTime start) {
    final end = start.add(const Duration(days: 6));

    final String startDay = start.day.toString();
    final String startMonth = _thaiMonthShort[start.month - 1];
    final String startYearShort = (start.year + 543).toString().substring(
      2,
    ); // พ.ศ. 2 หลัก

    final String endDay = end.day.toString();
    final String endMonth = _thaiMonthShort[end.month - 1];
    final String endYearShort = (end.year + 543).toString().substring(
      2,
    ); // พ.ศ. 2 หลัก

    if (start.month == end.month && start.year == end.year) {
      return 'วันที่ $startDay - $endDay $endMonth $endYearShort';
    }

    return 'วันที่ $startDay $startMonth $startYearShort - '
        '$endDay $endMonth $endYearShort';
  }

  String _weekdayLabel(DateTime day) {
    // weekday: 1 = Monday => index 0
    final index = (day.weekday - 1) % 7;
    final label = _thaiWeekdayShort[index];
    return '$label ${day.day}';
  }

  Future<Directory> _appDir() async {
    return getApplicationDocumentsDirectory();
  }

  Future<File> _userStatFile() async {
    final dir = await _appDir();
    return File('${dir.path}/user-stat.json');
  }

  Future<File> _calendarFile() async {
    final dir = await _appDir();
    return File('${dir.path}/carlendar.json');
  }

  Future<void> _loadCalendarEntries() async {
    setState(() {
      _isLoadingCalendar = true;
    });

    try {
      final file = await _calendarFile();
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
              return e['createby'] == widget.username;
            }
            if (e is Map) return e['createby'] == widget.username;
            return false;
          })
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();

      setState(() {
        _calendarEntries = filtered;
      });
    } catch (e) {
      debugPrint('Calendar: load entries error: $e');
      setState(() {
        _calendarEntries = [];
      });
    } finally {
      setState(() {
        _isLoadingCalendar = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    try {
      final file = await _userStatFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // ลบไม่ได้ก็ช่าง
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
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.25,
          maxChildSize: 1.0, // แก้ให้ลากได้สุดจอ
          expand: false,
          builder: (ctx, scrollController) {
            return CarlendarAddSheet(
              username: widget.username,
              scrollController: scrollController, // ส่ง controller เข้าไป
            );
          },
        );
      },
    );

    if (result != null) {
      debugPrint('New reminder from calendar: $result');
      // โหลดข้อมูลใหม่จากไฟล์ ให้ตารางอัปเดต
      await _loadCalendarEntries();
    }
  }

  // สร้าง key สำหรับช่องตาราง: ปี-เดือน-วัน-ชั่วโมง
  String _slotKey(DateTime dt) => '${dt.year}-${dt.month}-${dt.day}-${dt.hour}';

  /// สร้าง map ของช่องในสัปดาห์ปัจจุบัน ว่าช่องไหนมีแจ้งเตือนบ้าง
  ///
  /// key: year-month-day-hour
  /// value: list ของ entry ที่มาตกช่องนั้น
  Map<String, List<Map<String, dynamic>>> _buildWeekOccurrences(
    DateTime weekStart,
  ) {
    final Map<String, List<Map<String, dynamic>>> result = {};
    final weekEnd = weekStart.add(const Duration(days: 7)); // [start, end)

    for (final r in _calendarEntries) {
      try {
        final startStr = r['startDateTime']?.toString();
        if (startStr == null || startStr.isEmpty) continue;
        final start = DateTime.tryParse(startStr);
        if (start == null) continue;

        DateTime? end;
        final endStr = r['endDateTime']?.toString();
        if (endStr != null && endStr.isNotEmpty) {
          end = DateTime.tryParse(endStr);
        }

        final notifyByTime = r['notifyByTime'] == true;
        final intervalHours =
            int.tryParse(r['intervalHours']?.toString() ?? '') ?? 0;

        // กรณีไม่ใช่แจ้งเตือนตามเวลา หรือ interval <= 0 => ถือว่าเป็นครั้งเดียวที่เวลา start
        if (!notifyByTime || intervalHours <= 0) {
          final t = start;
          if (!t.isBefore(weekStart) && t.isBefore(weekEnd)) {
            final slotTime = DateTime(t.year, t.month, t.day, t.hour);
            final key = _slotKey(slotTime);
            result.putIfAbsent(key, () => []).add(r);
          }
          continue;
        }

        // ตรวจว่า series นี้มีโอกาสตัดกับช่วงสัปดาห์นี้ไหม
        if (start.isAfter(weekEnd)) continue;
        if (end != null && end.isBefore(weekStart)) continue;

        final stepMinutes = intervalHours * 60;
        if (stepMinutes <= 0) continue;

        final rangeStart = weekStart.isAfter(start)
            ? weekStart
            : start; // เริ่มคิดจากตรงนี้

        DateTime first;
        if (!rangeStart.isAfter(start)) {
          // ถ้า rangeStart <= start => ครั้งแรกคือ start เลย
          first = start;
        } else {
          final diffMinutes = rangeStart.difference(start).inMinutes;
          final steps = (diffMinutes / stepMinutes).ceil();
          first = start.add(Duration(minutes: steps * stepMinutes));
        }

        var t = first;
        while (t.isBefore(weekEnd) && (end == null || !t.isAfter(end))) {
          final slotTime = DateTime(t.year, t.month, t.day, t.hour);
          final key = _slotKey(slotTime);
          result.putIfAbsent(key, () => []).add(r);

          t = t.add(Duration(minutes: stepMinutes));
        }
      } catch (e) {
        debugPrint('Calendar: error building occurrences: $e');
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final weekDays = _daysInWeek(_weekStart);
    final headerText = _formatWeekRange(_weekStart);

    final double screenWidth = MediaQuery.of(context).size.width;
    const double timeColumnWidth = 60;
    const double horizontalPadding = 12;

    // คำนวณความกว้างของแต่ละวันให้พอดีกับหน้าจอ 7 วัน
    final double availableWidth =
        screenWidth - (horizontalPadding * 2) - timeColumnWidth;
    final double dayCellWidth = availableWidth / 7;
    const double cellHeight = 48;

    final weekOccurrences = _buildWeekOccurrences(_weekStart);

    return Scaffold(
      appBar: AppBar(title: const Text('จัดการปฏิทินแจ้งเตือน')),
      drawer: LeftMenu(
        username: widget.username,
        onManageCalendar: () {
          // อยู่หน้านี้อยู่แล้ว แค่ปิดเมนู
          Navigator.pop(context);
        },
        onCreateProfile: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateProfilePage()),
          );
        },
        onmanage_profile: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  manage_profilePage(username: widget.username),
            ),
          );
        },
        onAddMedicine: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MedicineAddPage(username: widget.username),
            ),
          );
        },
        onManageMedicine: () {
          Navigator.pop(context);
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
      body: Container(
        color: Colors.white, // พื้นหลังขาว
        child: Column(
          children: [
            const SizedBox(height: 12),

            // แถวเปลี่ยนสัปดาห์ + ช่วงวันที่
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: horizontalPadding,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _weekStart = _weekStart.subtract(
                          const Duration(days: 7),
                        );
                      });
                    },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        headerText,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _weekStart = _weekStart.add(const Duration(days: 7));
                      });
                    },
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // หัวตาราง: ช่องว่างเวลา + หัววัน/วันที่ 7 ช่อง
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: horizontalPadding,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: timeColumnWidth,
                    child: const Center(
                      child: Text('', style: TextStyle(color: Colors.black)),
                    ),
                  ),
                  Row(
                    children: weekDays.map((day) {
                      return SizedBox(
                        width: dayCellWidth,
                        child: Center(
                          child: Text(
                            _weekdayLabel(day),
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 12, // ทำให้ตัวเล็กลงหน่อย
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // ตารางเวลา 0:00 - 23:00 × 7 วัน
            Expanded(
              child: Stack(
                children: [
                  SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // คอลัมน์เวลา
                          SizedBox(
                            width: timeColumnWidth,
                            child: Column(
                              children: List.generate(24, (hour) {
                                final label =
                                    '${hour.toString().padLeft(2, '0')}:00';
                                return Container(
                                  height: cellHeight,
                                  alignment: Alignment.topCenter,
                                  child: Text(
                                    label,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 12,
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),

                          // กริด 7 คอลัมน์ (กว้างพอดีกับ header)
                          SizedBox(
                            width: dayCellWidth * 7,
                            child: Column(
                              children: List.generate(24, (hour) {
                                return Row(
                                  children: List.generate(7, (dayIndex) {
                                    final day = weekDays[dayIndex];
                                    final slotTime = DateTime(
                                      day.year,
                                      day.month,
                                      day.day,
                                      hour,
                                    );
                                    final key = _slotKey(slotTime);
                                    final events = weekOccurrences[key];
                                    final hasEvents =
                                        events != null && events.isNotEmpty;

                                    String label = '';
                                    if (hasEvents) {
                                      if (events!.length == 1) {
                                        label =
                                            (events[0]['medicineName']
                                                        ?.toString() ??
                                                    '')
                                                .trim();
                                        if (label.isEmpty) {
                                          label = 'ยา';
                                        }
                                      } else {
                                        label = '${events.length} รายการ';
                                      }
                                    }

                                    return Container(
                                      width: dayCellWidth,
                                      height: cellHeight,
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                          width: 0.5,
                                        ),
                                        color: hasEvents
                                            ? Colors.teal.withOpacity(0.15)
                                            : Colors.transparent,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                        vertical: 2,
                                      ),
                                      child: hasEvents
                                          ? Center(
                                              child: Text(
                                                label,
                                                textAlign: TextAlign.center,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.teal,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            )
                                          : null,
                                    );
                                  }),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_isLoadingCalendar)
                    const Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.only(top: 16.0),
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddReminderSheet,
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add),
      ),
    );
  }
}
