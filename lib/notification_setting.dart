// lib/notification_setting.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

class NortificationSettingPage extends StatefulWidget {
  final String username;

  const NortificationSettingPage({super.key, required this.username});

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
  // Default gap between repeated time-mode notifications.
  int _timeModeSnoozeDuration = 5;
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
          final userSettings = _readUserTimeModeSettings(data);

          // ⚠️ แก้ไข: เมื่อโหลดต้องใช้ List _availableSounds ในการตรวจสอบ (ซึ่งเก็บ path เต็ม)
          // หากค่าที่โหลดมาเป็นชื่อ Raw Resource Name (ไม่มี path) จะต้องแปลงกลับเป็น path เต็ม
          String? loadedSound = userSettings['time_mode_sound']?.toString();

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

          if (userSettings['time_mode_snooze_duration'] != null) {
            final val =
                int.tryParse(
                  userSettings['time_mode_snooze_duration'].toString(),
                ) ??
                5;
            _timeModeSnoozeDuration = val.clamp(2, 15);
          }
          if (userSettings['time_mode_repeat_count'] != null) {
            final val =
                int.tryParse(
                  userSettings['time_mode_repeat_count'].toString(),
                ) ??
                1;
            _timeModeRepeatCount = val.clamp(1, 3);
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

  Map<String, dynamic> _readUserTimeModeSettings(Map<String, dynamic> data) {
    final settingsByUser = data['time_mode_settings_by_user'];
    if (settingsByUser is Map) {
      final settings = settingsByUser[widget.username];
      if (settings is Map) {
        return Map<String, dynamic>.from(settings);
      }
    }
    return {};
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

      final settingsByUser = data['time_mode_settings_by_user'] is Map
          ? Map<String, dynamic>.from(data['time_mode_settings_by_user'] as Map)
          : <String, dynamic>{};

      final userSettings = <String, dynamic>{};

      // ⭐️⭐️ NEW: บันทึกเฉพาะชื่อ Raw Resource Name ⭐️⭐️
      if (_timeModeSound != null) {
        userSettings['time_mode_sound'] = _extractRawResourceName(
          _timeModeSound!,
        );
      } else {
        userSettings['time_mode_sound'] = null;
      }

      userSettings['time_mode_snooze_duration'] = _timeModeSnoozeDuration;
      userSettings['time_mode_repeat_count'] = _timeModeRepeatCount;
      userSettings['updated_at'] = DateTime.now().toIso8601String();
      settingsByUser[widget.username] = userSettings;
      data['time_mode_settings_by_user'] = settingsByUser;

      data.remove('meal_mode_sound');
      data.remove('meal_breakfast_time');
      data.remove('meal_lunch_time');
      data.remove('meal_dinner_time');

      data['updated_at'] = DateTime.now().toIso8601String();

      await file.writeAsString(jsonEncode(data));

      if (mounted) {
        await _showSaveProgressAndReturn();
      }
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  Future<void> _showSaveProgressAndReturn() async {
    final pageNavigator = Navigator.of(context);
    final dailyNotificationContext = pageNavigator.context;

    await _showTimedStatusDialog(
      context: context,
      icon: Icons.hourglass_top,
      message: 'กำลังบันทึกการตั้งค่า',
      detail: 'โปรดรอสักครู่...',
      showProgress: true,
    );

    if (!mounted) return;

    pageNavigator.popUntil((route) => route.isFirst);
    await Future.delayed(const Duration(milliseconds: 120));

    if (!dailyNotificationContext.mounted) return;

    await _showTimedStatusDialog(
      context: dailyNotificationContext,
      icon: Icons.check_circle_outline,
      message: 'บันทึกการตั้งค่าเรียบร้อยแล้ว',
      detail: 'กลับสู่หน้าการแจ้งเตือนรายวันแล้ว',
      showProgress: false,
    );
  }

  Future<void> _showTimedStatusDialog({
    required BuildContext context,
    required IconData icon,
    required String message,
    required String detail,
    required bool showProgress,
  }) async {
    final dialogNavigator = Navigator.of(context, rootNavigator: true);

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _StatusDialog(
          icon: icon,
          message: message,
          detail: detail,
          showProgress: showProgress,
        ),
      ),
    );

    await Future.delayed(const Duration(seconds: 1));

    if (dialogNavigator.canPop()) {
      dialogNavigator.pop();
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              border: Border.all(color: Colors.teal.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, color: Colors.teal, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'ตั้งไว้ตอนนี้:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Text(
                  '$_timeModeSnoozeDuration นาที',
                  style: const TextStyle(
                    color: Colors.teal,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _timeModeSnoozeDuration.toDouble(),
                  min: 2,
                  max: 15,
                  divisions: 13,
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
            '* ต่ำสุด 2 นาที สูงสุด 15 นาที',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),

          const SizedBox(height: 24),

          // 3. จำนวนครั้งการแจ้งเตือน
          const Text(
            'จำนวนครั้งการแจ้งเตือน',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'จำนวนครั้งการแจ้งเตือน',
              labelStyle: const TextStyle(color: Colors.teal),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.grey),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.teal),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _timeModeRepeatCount,
                isExpanded: true,
                items: List.generate(3, (index) {
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

class _StatusDialog extends StatelessWidget {
  final IconData icon;
  final String message;
  final String detail;
  final bool showProgress;

  const _StatusDialog({
    required this.icon,
    required this.message,
    required this.detail,
    required this.showProgress,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFE9EEF5),
                borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: const Text(
                'Pillmate',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: Colors.teal, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (showProgress) ...const [
                    SizedBox(height: 18),
                    LinearProgressIndicator(
                      minHeight: 6,
                      color: Colors.teal,
                      backgroundColor: Color(0xFFE0E0E0),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(detail, style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
