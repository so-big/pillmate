// lib/nortification_setting.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class NortificationSettingPage extends StatefulWidget {
  const NortificationSettingPage({super.key});

  @override
  State<NortificationSettingPage> createState() =>
      _NortificationSettingPageState();
}

class _NortificationSettingPageState extends State<NortificationSettingPage> {
  // เสียง (ตอนนี้มีตัวเลือกเดียว ไว้ขยายในอนาคต)
  String _selectedSound = 'system_default';

  // หน่วยเป็น "นาที"
  int _advanceMinutes = 30; // แจ้งเตือนล่วงหน้า
  int _afterMinutes = 30; // แจ้งเตือนต่อหลังจากถึงเวลา
  int _playDurationMinutes =
      1; // ระยะเวลาเล่นเสียงต่อครั้ง (ยังใช้เป็น info เฉย ๆ)
  int _repeatGapMinutes = 5; // ช่วงห่างระหว่างแจ้งเตือนซ้ำ

  bool _isLoading = true;
  bool _isSaving = false;

  Future<File> _settingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/nortification_setting.json');
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final file = await _settingsFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final json = jsonDecode(content);
          if (json is Map<String, dynamic>) {
            _selectedSound = json['sound']?.toString() ?? 'system_default';
            _advanceMinutes =
                int.tryParse('${json['advanceMinutes'] ?? 30}') ?? 30;
            _afterMinutes = int.tryParse('${json['afterMinutes'] ?? 30}') ?? 30;
            _playDurationMinutes =
                int.tryParse('${json['playDurationMinutes'] ?? 1}') ?? 1;
            _repeatGapMinutes =
                int.tryParse('${json['repeatGapMinutes'] ?? 5}') ?? 5;
          }
        }
      }
    } catch (e) {
      debugPrint('NortificationSetting: load error $e');
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final file = await _settingsFile();
      final map = {
        'sound': _selectedSound,
        'advanceMinutes': _advanceMinutes,
        'afterMinutes': _afterMinutes,
        'playDurationMinutes': _playDurationMinutes,
        'repeatGapMinutes': _repeatGapMinutes,
      };
      await file.writeAsString(jsonEncode(map), flush: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกการตั้งค่าการแจ้งเตือนเรียบร้อย'),
          ),
        );
      }
    } catch (e) {
      debugPrint('NortificationSetting: save error $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกการตั้งค่าไม่สำเร็จ: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  List<DropdownMenuItem<int>> _buildMinutesItems(int start, int end) {
    return List<DropdownMenuItem<int>>.generate(end - start + 1, (i) {
      final v = start + i;
      return DropdownMenuItem(
        value: v,
        child: Text(
          v.toString().padLeft(2, '0'),
          style: const TextStyle(color: Colors.black),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่าการแจ้งเตือน')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  const Text(
                    'เสียงแจ้งเตือน',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedSound,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'system_default',
                        child: Text(
                          'ใช้เสียงแจ้งเตือนของระบบ',
                          style: TextStyle(color: Colors.black87),
                        ),
                      ),
                      // จะเพิ่มเสียงอื่นจาก assets ค่อยมาเติม
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _selectedSound = v;
                      });
                    },
                  ),

                  const SizedBox(height: 24),

                  // แจ้งเตือนล่วงหน้า
                  const Text(
                    'แจ้งเตือนล่วงหน้า (นาที)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _advanceMinutes.clamp(0, 60),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          items: _buildMinutesItems(0, 60),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _advanceMinutes = v;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'นาที',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // แจ้งเตือนต่อหลังจากถึงเวลา
                  const Text(
                    'แจ้งเตือนต่อหลังจากถึงเวลา (นาที)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _afterMinutes.clamp(0, 60),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          items: _buildMinutesItems(0, 60),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _afterMinutes = v;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'นาที',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'ระยะเวลาที่แจ้งเตือนต่อครั้ง (นาที)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _playDurationMinutes.clamp(1, 5),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          items: _buildMinutesItems(1, 5),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _playDurationMinutes = v;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'นาที (ใช้เพื่ออธิบายความยาวเสียงเท่านั้น)',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'ช่วงเวลาเว้นระหว่างการแจ้งเตือนซ้ำ (นาที)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _repeatGapMinutes.clamp(1, 30),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          items: _buildMinutesItems(1, 30),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _repeatGapMinutes = v;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'นาที',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'บันทึกการตั้งค่า',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
