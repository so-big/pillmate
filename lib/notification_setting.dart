// lib/notification_setting.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

import 'database_helper.dart';

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

  // 1. รายชื่อไฟล์เสียง (ใช้ชื่อไฟล์พิมพ์เล็กที่มีอยู่จริง)
  final List<String> _availableSounds = const [
    'assets/sound_norti/a01_clock_alarm_normal_30_sec.mp3',
    'assets/sound_norti/a02_clock_alarm_normal_1_min.mp3',
    'assets/sound_norti/a03_clock_alarm_normal_1_30_min.mp3',
    'assets/sound_norti/a04_clock_alarm_continue_30_sec.mp3',
    'assets/sound_norti/a05_clock_alarm_continue_1_min.mp3',
    'assets/sound_norti/a06_clock_alarm_continue_1_30_min.mp3',
  ];

  // --- ตัวแปรโหมดเวลา ---
  String? _timeModeSound;
  // ✅ เปลี่ยน Default: 5 -> 2 นาที
  int _timeModeSnoozeDuration = 2;
  // ✅ เปลี่ยน Default: 3 -> 1 ครั้ง
  int _timeModeRepeatCount = 1;

  // ✅ Notification Strategy: TYPE_A (legacy) or TYPE_B (meal-based, default)
  String _activeStrategy = 'TYPE_B';
  final dbHelper = DatabaseHelper();

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
    await _loadStrategy();
    setState(() {
      _isLoading = false;
    });
  }

  /// Load notification strategy from DB
  Future<void> _loadStrategy() async {
    try {
      final strategy = await dbHelper.getSetting('notification_strategy');
      if (strategy == 'TYPE_A' || strategy == 'TYPE_B') {
        _activeStrategy = strategy!;
      }
    } catch (e) {
      debugPrint('Error loading strategy: $e');
    }
  }

  /// Save notification strategy to DB
  Future<void> _saveStrategy(String strategy) async {
    try {
      await dbHelper.setSetting('notification_strategy', strategy);
    } catch (e) {
      debugPrint('Error saving strategy: $e');
    }
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
    // e.g. "assets/sound_norti/A01_clock_alarm_normal_30_sec.mp3"
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

      // ✅ บันทึก strategy ลง DB
      await _saveStrategy(_activeStrategy);

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
        title: const Text('ตั้งค่าการแจ้งเตือน'),
        backgroundColor: Colors.teal,
        actions: const [],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ Strategy Selector (TYPE_A vs TYPE_B)
            _buildStrategySelector(),
            const SizedBox(height: 24),
            // Sound + Repeat settings
            ..._buildTimeModeWidgets(),
            const SizedBox(height: 32),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  /// ✅ NEW: Strategy selector — TYPE_A (legacy) or TYPE_B (meal-based)
  Widget _buildStrategySelector() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'โหมดการแจ้งเตือน',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 12),
            RadioListTile<String>(
              title: const Text('📅 Meal-Based (แนะนำ)'),
              subtitle: const Text(
                'แจ้งเตือนตามมื้ออาหาร — เช้า/กลางวัน/เย็น/ก่อนนอน, ล่วงหน้า 48 ชม.',
                style: TextStyle(fontSize: 12),
              ),
              value: 'TYPE_B',
              groupValue: _activeStrategy,
              activeColor: Colors.teal,
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _activeStrategy = val;
                  });
                }
              },
            ),
            RadioListTile<String>(
              title: const Text('⏱ Time-Interval (Legacy)'),
              subtitle: const Text(
                'แจ้งเตือนตามช่วงเวลา — ซ้ำ 5× repeat, ขั้นต่ำ 24 ชม.',
                style: TextStyle(fontSize: 12),
              ),
              value: 'TYPE_A',
              groupValue: _activeStrategy,
              activeColor: Colors.orange,
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _activeStrategy = val;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------- UI: Sound + repeat settings ----------
  List<Widget> _buildTimeModeWidgets() {
    return [
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
              min: 2,
              max: 60,
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
    ];
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
