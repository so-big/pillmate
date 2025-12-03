// lib/nortification_setting.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // ไม่ใช้แล้ว
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

class NortificationSettingPage extends StatefulWidget {
  const NortificationSettingPage({super.key});

  @override
  State<NortificationSettingPage> createState() =>
      _NortificationSettingPageState();
}

class _NortificationSettingPageState extends State<NortificationSettingPage> {
  bool _isLoading = true;

  // --- Audio Player ---
  final AudioPlayer _audioPlayer = AudioPlayer();

  // ✅ 1. รายชื่อไฟล์เสียง (Hardcode ตามชื่อไฟล์จริง)
  // ⚠️ สำคัญ: ชื่อตรงนี้ต้องตรงกับชื่อไฟล์ใน assets/sound_norti/ ทุกตัวอักษร
  final List<String> _availableSounds = const [
    'assets/sound_norti/01_clock_alarm_normal_30_sec.mp3', // ⬅️ เริ่มที่ 01
    'assets/sound_norti/02_clock_alarm_normal_1_min.mp3',
    'assets/sound_norti/03_clock_alarm_normal_1.30_min.mp3',
    'assets/sound_norti/04_clock_alarm_continue_30_sec.mp3', // *ย้ายขึ้นมา*
    'assets/sound_norti/05_clock_alarm_continue_1_min.mp3',
    'assets/sound_norti/06_clock_alarm_continue_1.30_min.mp3',
  ];

  // --- ตัวแปรโหมดเวลา ---
  String? _timeModeSound;
  int _timeModeSnoozeDuration = 5;
  int _timeModeRepeatCount = 3;

  // --- ตัวแปรโหมดมื้ออาหาร ---
  String? _mealModeSound;
  TimeOfDay _breakfastTime = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _lunchTime = const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay _dinnerTime = const TimeOfDay(hour: 18, minute: 0);

  @override
  void initState() {
    super.initState();
    // ตั้งค่าเริ่มต้น
    if (_availableSounds.isNotEmpty) {
      _timeModeSound = _availableSounds.first;
      _mealModeSound = _availableSounds.first;
    }
    _initData();
  }

  @override
  void dispose() {
    _audioPlayer.dispose(); // คืนค่า Memory
    super.dispose();
  }

  Future<void> _initData() async {
    // โหลดการตั้งค่าอย่างเดียว ไม่มีการ Test Notification
    await _loadSettingsFromJson();
    setState(() {
      _isLoading = false;
    });
  }

  // ✅ ฟังก์ชันเล่นเสียงตัวอย่าง
  Future<void> _playPreview(String? soundPath) async {
    if (soundPath == null) return;
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setVolume(1.0); // เร่งเสียงให้สุด

      String cleanPath = soundPath;
      // ตัด 'assets/' ออกเพราะ AudioPlayers เติมให้เอง
      if (cleanPath.startsWith('assets/')) {
        cleanPath = cleanPath.substring(7);
      }

      await _audioPlayer.play(AssetSource(cleanPath));
    } catch (e) {
      debugPrint('Error playing sound: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เล่นไฟล์เสียงไม่สำเร็จ: $e')));
      }
    }
  }

  Future<void> _stopPreview() async {
    await _audioPlayer.stop();
  }

  Future<void> _loadSettingsFromJson() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/pillmate/appstatus.json');

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content) as Map<String, dynamic>;

          if (data['time_mode_sound'] != null &&
              _availableSounds.contains(data['time_mode_sound'])) {
            _timeModeSound = data['time_mode_sound'];
          }
          if (data['time_mode_snooze_duration'] != null) {
            int val = data['time_mode_snooze_duration'];
            if (val < 3) val = 3;
            _timeModeSnoozeDuration = val;
          }
          if (data['time_mode_repeat_count'] != null) {
            _timeModeRepeatCount = data['time_mode_repeat_count'];
          }

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

  Future<void> _saveSettings() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/pillmate/appstatus.json');

      Map<String, dynamic> data = {};
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          data = jsonDecode(content) as Map<String, dynamic>;
        }
      }

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
    }
  }

  TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

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

          // 1. เลือกไฟล์เสียง + ปุ่มเล่น
          _buildSoundSelector(
            label: 'เสียงแจ้งเตือน',
            value: _timeModeSound,
            onChanged: (val) {
              setState(() {
                _timeModeSound = val;
              });
              _playPreview(val);
            },
          ),

          const SizedBox(height: 24),

          // 2. ระยะห่างระหว่างการแจ้งเตือน
          const Text(
            'ระยะห่างระหว่างการแจ้งเตือน(นาที)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _timeModeSnoozeDuration.toDouble(),
                  min: 3,
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

          // 3. จำนวนครั้งการย้ำเตือน
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

          // 1. เลือกไฟล์เสียง + ปุ่มเล่น
          _buildSoundSelector(
            label: 'เสียงแจ้งเตือนมื้ออาหาร',
            value: _mealModeSound,
            onChanged: (val) {
              setState(() {
                _mealModeSound = val;
              });
              _playPreview(val);
            },
          ),

          const SizedBox(height: 24),
          const Text(
            'กำหนดเวลามื้ออาหาร (ค่าเริ่มต้น)',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),

          _buildTimePickerRow(
            label: 'มื้อเช้า',
            time: _breakfastTime,
            onChanged: (newTime) => setState(() => _breakfastTime = newTime),
          ),
          const Divider(),
          _buildTimePickerRow(
            label: 'มื้อเที่ยง',
            time: _lunchTime,
            onChanged: (newTime) => setState(() => _lunchTime = newTime),
          ),
          const Divider(),
          _buildTimePickerRow(
            label: 'มื้อเย็น',
            time: _dinnerTime,
            onChanged: (newTime) => setState(() => _dinnerTime = newTime),
          ),
        ],
      ),
    );
  }

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
              items: _availableSounds.map((soundPath) {
                return DropdownMenuItem(
                  value: soundPath,
                  child: Text(_getFileName(soundPath)),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),

        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            ElevatedButton.icon(
              onPressed: value == null ? null : () => _playPreview(value),
              icon: const Icon(Icons.play_arrow),
              label: const Text('เล่นเสียง'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal[50],
                foregroundColor: Colors.teal,
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _stopPreview,
              icon: const Icon(Icons.stop),
              label: const Text('หยุด'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        ),
      ],
    );
  }

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
