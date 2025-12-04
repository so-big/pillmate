// lib/nortification_setting.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

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

  // 1. รายชื่อไฟล์เสียง (Hardcode ตามชื่อไฟล์จริง)
  final List<String> _availableSounds = const [
    'assets/sound_norti/a01_clock_alarm_normal_30_sec.mp3', // ⬅️ เริ่มที่ 01
    'assets/sound_norti/a02_clock_alarm_normal_1_min.mp3',
    'assets/sound_norti/a03_clock_alarm_normal_1.30_min.mp3',
    'assets/sound_norti/a04_ clock_alarm_continue_30_sec.mp3',
    'assets/sound_norti/a05_clock_alarm_continue_1_min.mp3',
    'assets/sound_norti/a06_clock_alarm_continue_1.30_min.mp3',
  ];

  // --- ตัวแปรโหมดเวลา ---
  String? _timeModeSound;
  // ✅ เปลี่ยน Default: 5 -> 2 นาที
  int _timeModeSnoozeDuration = 2;
  // ✅ เปลี่ยน Default: 3 -> 1 ครั้ง
  int _timeModeRepeatCount = 1;

  @override
  void initState() {
    super.initState();
    // ตั้งค่าเริ่มต้น
    if (_availableSounds.isNotEmpty) {
      _timeModeSound = _availableSounds.first;
    }
    _initData();
  }

  @override
  void dispose() {
    _audioPlayer.dispose(); // คืนค่า Memory
    super.dispose();
  }

  Future<void> _initData() async {
    await _loadSettingsFromJson();
    setState(() {
      _isLoading = false;
    });
  }

  // ฟังก์ชันเล่นเสียงตัวอย่าง
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

          // ⚠️ แก้ไข: เมื่อโหลดต้องใช้ List _availableSounds ในการตรวจสอบ (ซึ่งเก็บ path เต็ม)
          // หากค่าที่โหลดมาเป็นชื่อ Raw Resource Name (ไม่มี path) จะต้องแปลงกลับเป็น path เต็ม
          String? loadedSound = data['time_mode_sound']?.toString();

          if (loadedSound != null) {
            String fullPathMatch = _availableSounds.firstWhere(
              // ลองหาจากชื่อ Raw Resource Name (ที่บันทึกใน JSON)
              (path) => path.contains(loadedSound),
              orElse: () => '',
            );

            if (fullPathMatch.isNotEmpty) {
              _timeModeSound = fullPathMatch;
            } else if (_availableSounds.contains(loadedSound)) {
              // Fallback: ถ้าค่าที่โหลดมาเป็น Path เต็มอยู่แล้ว (อาจเป็นค่าเดิมก่อนแก้ไข)
              _timeModeSound = loadedSound;
            }
          }

          // ตรวจสอบความถูกต้องของค่าที่โหลด
          if (_timeModeSound == null ||
              !_availableSounds.contains(_timeModeSound)) {
            _timeModeSound = _availableSounds.first;
          }

          if (data['time_mode_snooze_duration'] != null) {
            int val = data['time_mode_snooze_duration'];
            // ✅ เปลี่ยน Min validation: 3 -> 2
            if (val < 2) val = 2;
            _timeModeSnoozeDuration = val;
          }
          if (data['time_mode_repeat_count'] != null) {
            _timeModeRepeatCount = data['time_mode_repeat_count'];
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading settings json: $e');
    }
  }

  // Helper function to extract Raw Resource Name
  String _extractRawResourceName(String fullPath) {
    // e.g. "assets/sound_norti/a01_clock_alarm_normal_30_sec.mp3"
    final fileNameWithExtension = fullPath.split('/').last; // a01_...mp3
    final parts = fileNameWithExtension.split('.');
    if (parts.length > 1) {
      parts.removeLast(); // Remove .mp3
    }
    return parts.join('.').toLowerCase(); // a01_..._30_sec
  }

  Future<void> _saveSettings() async {
    try {
      // ⚠️ ก่อนบันทึกให้หยุดเสียง Preview ก่อน
      await _audioPlayer.stop();

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/pillmate/appstatus.json');

      Map<String, dynamic> data = {};
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          data = jsonDecode(content) as Map<String, dynamic>;
        }
      }

      // ⭐️⭐️ NEW: บันทึกเฉพาะชื่อ Raw Resource Name ⭐️⭐️
      if (_timeModeSound != null) {
        data['time_mode_sound'] = _extractRawResourceName(_timeModeSound!);
      } else {
        data['time_mode_sound'] = null;
      }

      data['time_mode_snooze_duration'] = _timeModeSnoozeDuration;
      data['time_mode_repeat_count'] = _timeModeRepeatCount;

      data.remove('meal_mode_sound');
      data.remove('meal_breakfast_time');
      data.remove('meal_lunch_time');
      data.remove('meal_dinner_time');

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

  String _getFileName(String path) {
    // ตัด path ยาวๆ ให้เหลือแค่ชื่อไฟล์
    return path.split('/').last;
  }

  // Widget ปุ่มบันทึกขนาดเต็มจอ
  Widget _buildSaveButton() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _saveSettings,
        icon: const Icon(Icons.save),
        label: const Text(
          'บันทึกการตั้งค่า',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ตั้งค่าการแจ้งเตือนตามเวลา'),
        backgroundColor: Colors.teal,
        actions: const [],
      ),
      body: _buildTimeModeView(),
    );
  }

  // ---------- UI: โหมดแจ้งเตือนตามเวลา (เหลือแค่ฟังก์ชันนี้) ----------
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
                  // ✅ เปลี่ยน Min value: 3 -> 2
                  min: 2,
                  max: 60,
                  // ✅ เปลี่ยน Divisions: 57 -> 58
                  divisions: 58,
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
            // ✅ เปลี่ยน Note: 3 -> 2
            '* ต่ำสุด 2 นาที',
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

          // ✅ เพิ่มช่องว่างก่อนปุ่มบันทึก
          const SizedBox(height: 32),

          // ✅ NEW: ปุ่มบันทึก
          _buildSaveButton(),
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
}
