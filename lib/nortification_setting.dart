// lib/nortification_setting.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // สำหรับ rootBundle (AssetManifest)
import 'package:path_provider/path_provider.dart';

class NortificationSettingPage extends StatefulWidget {
  const NortificationSettingPage({super.key});

  @override
  State<NortificationSettingPage> createState() =>
      _NortificationSettingPageState();
}

class _NortificationSettingPageState extends State<NortificationSettingPage> {
  bool _isLoading = true;

  // --- รายชื่อไฟล์เสียงที่อ่านจาก assets ---
  List<String> _availableSounds = [];

  // --- ตัวแปรสำหรับโหมดแจ้งเตือนตามเวลา ---
  String? _timeModeSound;
  int _timeModeSnoozeDuration = 5; // Default 5 นาที (ต่ำสุด 3)
  int _timeModeRepeatCount = 3; // Default 3 ครั้ง (1-10)

  // --- ตัวแปรสำหรับโหมดแจ้งเตือนตามมื้ออาหาร ---
  String? _mealModeSound;
  TimeOfDay _breakfastTime = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _lunchTime = const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay _dinnerTime = const TimeOfDay(hour: 18, minute: 0);

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await _loadSoundAssets();
    await _loadSettingsFromJson();
    setState(() {
      _isLoading = false;
    });
  }

  // ✅ 1. โหลดรายชื่อไฟล์เสียงจาก assets/sound_norti/
  Future<void> _loadSoundAssets() async {
    try {
      final manifestContent = await DefaultAssetBundle.of(
        context,
      ).loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      // กรองเอาเฉพาะไฟล์ใน folder assets/sound_norti/
      final sounds = manifestMap.keys
          .where((key) => key.contains('assets/sound_norti/'))
          .toList();

      // เอาแค่ชื่อไฟล์เพื่อให้แสดงผลง่ายขึ้น (แต่ตอนเก็บค่า เก็บ path เต็มหรือชื่อไฟล์ก็ได้)
      // ในที่นี้ขอเก็บ path เต็ม เพื่อความชัวร์เวลาเรียกใช้
      setState(() {
        _availableSounds = sounds;
        if (_availableSounds.isNotEmpty) {
          // Default sound ถ้ายังไม่มีค่า
          _timeModeSound = _availableSounds.first;
          _mealModeSound = _availableSounds.first;
        }
      });
    } catch (e) {
      debugPrint('Error loading sound assets: $e');
    }
  }

  // ✅ 2. โหลดค่า Setting จาก appstatus.json
  Future<void> _loadSettingsFromJson() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/pillmate/appstatus.json');

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content) as Map<String, dynamic>;

          // --- โหมดเวลา ---
          if (data['time_mode_sound'] != null &&
              _availableSounds.contains(data['time_mode_sound'])) {
            _timeModeSound = data['time_mode_sound'];
          }
          if (data['time_mode_snooze_duration'] != null) {
            int val = data['time_mode_snooze_duration'];
            if (val < 3) val = 3; // บังคับขั้นต่ำ 3
            _timeModeSnoozeDuration = val;
          }
          if (data['time_mode_repeat_count'] != null) {
            _timeModeRepeatCount = data['time_mode_repeat_count'];
          }

          // --- โหมดมื้ออาหาร ---
          if (data['meal_mode_sound'] != null &&
              _availableSounds.contains(data['meal_mode_sound'])) {
            _mealModeSound = data['meal_mode_sound'];
          }
          if (data['meal_breakfast_time'] != null) {
            _breakfastTime = _parseTime(data['meal_breakfast_time']);
          }
          if (data['meal_lunch_time'] != null) {
            _lunchTime = _parseTime(data['meal_lunch_time']);
          }
          if (data['meal_dinner_time'] != null) {
            _dinnerTime = _parseTime(data['meal_dinner_time']);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading settings json: $e');
    }
  }

  // ✅ 3. บันทึกค่าลง appstatus.json
  Future<void> _saveSettings() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/pillmate/appstatus.json');

      Map<String, dynamic> data = {};
      // อ่านข้อมูลเก่าก่อน (เพื่อไม่ให้ทับค่า nfc_enabled)
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          data = jsonDecode(content) as Map<String, dynamic>;
        }
      }

      // อัปเดตค่าใหม่
      data['time_mode_sound'] = _timeModeSound;
      data['time_mode_snooze_duration'] = _timeModeSnoozeDuration;
      data['time_mode_repeat_count'] = _timeModeRepeatCount;

      data['meal_mode_sound'] = _mealModeSound;
      data['meal_breakfast_time'] = _formatTime(_breakfastTime);
      data['meal_lunch_time'] = _formatTime(_lunchTime);
      data['meal_dinner_time'] = _formatTime(_dinnerTime);

      data['updated_at'] = DateTime.now().toIso8601String();

      await file.writeAsString(jsonEncode(data));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกการตั้งค่าเรียบร้อยแล้ว')),
        );
      }
    } catch (e) {
      debugPrint('Error saving settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก: $e')),
        );
      }
    }
  }

  // Helper แปลง String HH:mm -> TimeOfDay
  TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  // Helper แปลง TimeOfDay -> String HH:mm
  String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _getFileName(String path) {
    return path.split('/').last;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ตั้งค่าการแจ้งเตือน'),
          backgroundColor: Colors.teal,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'แจ้งเตือนตามเวลา'),
              Tab(text: 'แจ้งเตือนตามมื้ออาหาร'),
            ],
            indicatorColor: Colors.white,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveSettings,
              tooltip: 'บันทึก',
            ),
          ],
        ),
        body: TabBarView(
          children: [_buildTimeModeView(), _buildMealModeView()],
        ),
      ),
    );
  }

  // ---------- UI: โหมดแจ้งเตือนตามเวลา ----------
  Widget _buildTimeModeView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ตั้งค่าเสียงและการย้ำเตือน',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // 1. เลือกไฟล์เสียง
          _buildSoundSelector(
            label: 'เสียงแจ้งเตือน',
            value: _timeModeSound,
            onChanged: (val) {
              setState(() {
                _timeModeSound = val;
              });
            },
          ),

          const SizedBox(height: 24),

          // 2. ระยะเวลาการย้ำเตือน (Snooze Duration)
          const Text('ระยะเวลาย้ำเตือน (นาที)', style: TextStyle(fontSize: 16)),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _timeModeSnoozeDuration.toDouble(),
                  min: 3, // ต่ำสุด 3 นาที
                  max: 60,
                  divisions: 57,
                  label: '$_timeModeSnoozeDuration นาที',
                  activeColor: Colors.teal,
                  onChanged: (val) {
                    setState(() {
                      _timeModeSnoozeDuration = val.toInt();
                    });
                  },
                ),
              ),
              Text(
                '$_timeModeSnoozeDuration นาที',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Text(
            '* ต่ำสุด 3 นาที',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),

          const SizedBox(height: 24),

          // 3. จำนวนครั้งการย้ำเตือน (Repeat Count)
          const Text('จำนวนครั้งการย้ำเตือน', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _timeModeRepeatCount,
                isExpanded: true,
                items: List.generate(10, (index) {
                  int count = index + 1;
                  return DropdownMenuItem(
                    value: count,
                    child: Text('$count ครั้ง'),
                  );
                }),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _timeModeRepeatCount = val;
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- UI: โหมดแจ้งเตือนตามมื้ออาหาร ----------
  Widget _buildMealModeView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ตั้งค่าเสียงและเวลามื้ออาหาร',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // 1. เลือกไฟล์เสียง
          _buildSoundSelector(
            label: 'เสียงแจ้งเตือนมื้ออาหาร',
            value: _mealModeSound,
            onChanged: (val) {
              setState(() {
                _mealModeSound = val;
              });
            },
          ),

          const SizedBox(height: 24),
          const Text(
            'กำหนดเวลามื้ออาหาร (ค่าเริ่มต้น)',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),

          // 2. เวลามื้อเช้า
          _buildTimePickerRow(
            label: 'มื้อเช้า',
            time: _breakfastTime,
            onChanged: (newTime) {
              setState(() => _breakfastTime = newTime);
            },
          ),
          const Divider(),

          // 3. เวลามื้อเที่ยง
          _buildTimePickerRow(
            label: 'มื้อเที่ยง',
            time: _lunchTime,
            onChanged: (newTime) {
              setState(() => _lunchTime = newTime);
            },
          ),
          const Divider(),

          // 4. เวลามื้อเย็น
          _buildTimePickerRow(
            label: 'มื้อเย็น',
            time: _dinnerTime,
            onChanged: (newTime) {
              setState(() => _dinnerTime = newTime);
            },
          ),
        ],
      ),
    );
  }

  // Widget เลือกไฟล์เสียง
  Widget _buildSoundSelector({
    required String label,
    required String? value,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              hint: const Text('เลือกไฟล์เสียง'),
              isExpanded: true,
              items: _availableSounds.isEmpty
                  ? [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('ไม่พบไฟล์เสียง'),
                      ),
                    ]
                  : _availableSounds.map((soundPath) {
                      return DropdownMenuItem(
                        value: soundPath,
                        child: Text(_getFileName(soundPath)),
                      );
                    }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  // Widget เลือกเวลา
  Widget _buildTimePickerRow({
    required String label,
    required TimeOfDay time,
    required Function(TimeOfDay) onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.teal.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.teal),
        ),
        child: Text(
          _formatTime(time),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.teal,
          ),
        ),
      ),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(alwaysUse24HourFormat: true),
              child: child!,
            );
          },
        );
        if (picked != null) {
          onChanged(picked);
        }
      },
    );
  }
}
