// lib/forgot_password.dart

import 'package:flutter/material.dart';
import 'database_helper.dart'; // Import DatabaseHelper
import 'services/auth_service.dart'; // Import AuthService

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final dbHelper = DatabaseHelper();

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _answerController = TextEditingController();

  // สถานะการทำงาน: 1: Input Username, 2: Answer Security Question
  int _currentStep = 1;
  // เก็บข้อมูลผู้ใช้ที่ดึงมาจาก DB
  Map<String, dynamic>? _userData;
  bool _isChecking = false;
  String? _usernameError;

  // ตัวแปรสำหรับ Step 2
  String? _selectedQuestionByUser; // คำถามที่ผู้ใช้เลือกจาก Dropdown

  // รายการคำถามกันลืม (ต้องตรงกับตอน Create Account)
  final List<String> _securityQuestions = const [
    'ชื่อสัตว์เลี้ยงตัวแรกของคุณ?',
    'จังหวัดที่คุณเกิด?',
    'ชื่อกลางของแม่คุณ?',
    'สีที่คุณชื่นชอบ?',
    'อาหารจานโปรดของคุณ?',
  ];

  @override
  void dispose() {
    _usernameController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  // --- Step 1 Logic: Find Account ---
  Future<void> _findAccount() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final username = _usernameController.text.trim();

    setState(() {
      _isChecking = true;
      _usernameError = null;
    });

    try {
      final user = await dbHelper.getUser(username);
      if (user == null) {
        throw 'ไม่พบชื่อผู้ใช้ "$username" ในระบบ';
      }

      // ต้องมีการตั้งคำถามกันลืมไว้ถึงจะใช้ฟังก์ชันนี้ได้
      if (user['security_question'] == null ||
          user['security_question'].toString().isEmpty) {
        throw 'บัญชีนี้ไม่ได้ตั้งคำถามกันลืมไว้';
      }

      setState(() {
        _userData = user;
        _currentStep = 2; // ย้ายไป Step 2: Answer Question
        _isChecking = false;
      });
    } catch (e) {
      setState(() {
        _isChecking = false;
        _usernameError = e.toString().contains('ไม่พบ')
            ? e.toString()
            : 'เกิดข้อผิดพลาดในการดึงข้อมูล';
      });
    }
  }

  // --- Step 2 Logic: Verify Answer ---
  void _verifyAnswerAndProceed() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedQuestionByUser == null) {
      _showErrorDialog('คำถามไม่ครบถ้วน', 'กรุณาเลือกคำถามกันลืม');
      return;
    }

    final userAnswer = _answerController.text.trim();

    // ดึงข้อมูลที่ถูกต้องจาก DB
    final storedQ = _userData!['security_question'];
    final storedA = _userData!['security_answer'];

    // ตรวจสอบทั้งคำถามที่เลือกและคำตอบที่กรอก
    final isCorrectQuestion = _selectedQuestionByUser == storedQ;
    final isCorrectAnswer = userAnswer == storedA;

    if (isCorrectQuestion && isCorrectAnswer) {
      _showPasswordResetDialog();
    } else {
      _showErrorDialog(
        'ข้อมูลไม่ถูกต้อง',
        'คำถามที่เลือกหรือคำตอบไม่ตรงกับที่บันทึกไว้',
      );
    }
  }

  // Dialog แสดง Error (พื้นหลังสีอ่อน ตัวหนังสือสีดำ)
  Future<void> _showErrorDialog(String title, String content) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Text(
            content,
            style: const TextStyle(color: Colors.black, fontSize: 14),
          ),
          backgroundColor: Colors.grey[50], // พื้นหลังสีอ่อน
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ตกลง', style: TextStyle(color: Colors.teal)),
            ),
          ],
        );
      },
    );
  }

  // Dialog สำหรับกรอกรหัสผ่านใหม่
  Future<void> _showPasswordResetDialog() async {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    String? dialogError;
    bool isPasswordValid = false;
    bool isSaving = false;

    // Helper function สำหรับตรวจสอบและอัปเดตสถานะปุ่ม/ข้อผิดพลาด
    void _updateValidationState(StateSetter setStateDialog) {
      final pwd = newPasswordController.text;
      final confirmPwd = confirmPasswordController.text;

      bool valid = pwd.length >= 8 && pwd == confirmPwd;

      if (pwd.length >= 8 && pwd != confirmPwd) {
        dialogError = 'รหัสผ่านสองช่องไม่เหมือนกัน';
      } else if (pwd.isNotEmpty && pwd.length < 8) {
        dialogError = 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร';
      } else {
        dialogError = null;
      }

      setStateDialog(() {
        isPasswordValid = valid;
      });
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            // ฟังก์ชันอัปเดตรหัสผ่านใน DB
            Future<void> _resetPassword() async {
              setStateDialog(() => isSaving = true);
              final newPassword = newPasswordController.text;

              try {
                final Map<String, dynamic> updatedValues = {
                  'userid': _usernameController.text.trim(),
                  'password': AuthService.hashPassword(newPassword), // Hash ก่อนบันทึก
                };

                await dbHelper.updateUser(updatedValues);

                if (!mounted) return;
                Navigator.of(ctx).pop(); // ปิด dialog
                Navigator.pop(context); // กลับหน้า Login

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('เปลี่ยนรหัสผ่านสำเร็จแล้ว')),
                );
              } catch (e) {
                setStateDialog(() {
                  isSaving = false;
                  dialogError = 'เกิดข้อผิดพลาดในการบันทึกรหัสผ่าน: $e';
                });
                debugPrint('Password reset error: $e');
              }
            }

            return AlertDialog(
              title: const Text('ตั้งรหัสผ่านใหม่'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'รหัสผ่านใหม่ต้องมีอย่างน้อย 8 ตัวอักษร',
                    style: TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                  const SizedBox(height: 10),

                  // ช่องรหัสผ่านใหม่
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    style: const TextStyle(
                      color: Colors.black,
                    ), // ตัวหนังสือสีดำ
                    decoration: const InputDecoration(
                      labelText: 'รหัสผ่านใหม่ (>= 8 ตัว)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _updateValidationState(setStateDialog),
                  ),
                  const SizedBox(height: 10),

                  // ช่องยืนยันรหัสผ่าน
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    style: const TextStyle(
                      color: Colors.black,
                    ), // ตัวหนังสือสีดำ
                    decoration: const InputDecoration(
                      labelText: 'ยืนยันรหัสผ่านใหม่',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _updateValidationState(setStateDialog),
                  ),

                  if (dialogError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        dialogError!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  // ปุ่มจะถูก disabled ถ้า isPasswordValid เป็น false หรือกำลังบันทึก
                  onPressed: (isSaving || !isPasswordValid)
                      ? null
                      : _resetPassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('ยืนยันการเปลี่ยนรหัสผ่าน'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ฟังก์ชันสำหรับสร้าง UI ตามขั้นตอน
  Widget _buildRecoveryStep() {
    // --- Step 1: Input Username ---
    if (_currentStep == 1) {
      return Column(
        children: [
          // ช่องกรอก Username
          TextFormField(
            controller: _usernameController,
            style: const TextStyle(color: Colors.black), // ตัวหนังสือสีดำ
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'กรุณากรอกชื่อผู้ใช้';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // ปุ่มค้นหาบัญชี (กว้างเต็มจอ)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isChecking ? null : _findAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal, // ใช้สี Teal เพื่อความเข้ากัน
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _isChecking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('ค้นหาบัญชี'), // เปลี่ยนข้อความตามที่ร้องขอ
            ),
          ),

          // แสดง Error และปุ่มลองอีกครั้ง
          if (_usernameError != null)
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Text(
                    _usernameError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Reset state เพื่อลองอีกครั้ง
                    setState(() {
                      _usernameController.clear();
                      _usernameError = null;
                    });
                  },
                  child: const Text(
                    'ลองอีกครั้ง',
                    style: TextStyle(color: Colors.blue),
                  ), // ปุ่มลองอีกครั้ง
                ),
              ],
            ),
        ],
      );
    }
    // --- Step 2: Answer Security Question ---
    else if (_currentStep == 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // แสดง Username (อ่านอย่างเดียว)
          Text(
            'บัญชี: ${_usernameController.text.trim()}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 20),

          // 1. Dropdown for Security Questions
          DropdownButtonFormField<String>(
            value: _selectedQuestionByUser,
            style: const TextStyle(color: Colors.black), // ตัวหนังสือสีดำ
            hint: const Text('เลือกคำถามกันลืม *'),
            decoration: const InputDecoration(
              labelText: 'เลือกคำถามกันลืม *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.help_outline),
            ),
            items: _securityQuestions.map((String question) {
              return DropdownMenuItem<String>(
                value: question,
                child: Text(question),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                _selectedQuestionByUser = newValue;
              });
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'กรุณาเลือกคำถามกันลืม';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // 2. Answer Field
          TextFormField(
            controller: _answerController,
            style: const TextStyle(color: Colors.black), // ตัวหนังสือสีดำ
            decoration: const InputDecoration(
              labelText: 'คำตอบของคุณ',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.security),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'กรุณากรอกคำตอบ';
              }
              return null;
            },
          ),
          const SizedBox(height: 30),

          // 3. Verify Button
          ElevatedButton(
            onPressed: _verifyAnswerAndProceed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('ยืนยันคำตอบ'),
          ),
          const SizedBox(height: 10),

          // ปุ่ม Back (กลับไป Step 1)
          TextButton(
            onPressed: () {
              setState(() {
                _currentStep = 1;
                _userData = null;
                _answerController.clear();
                _selectedQuestionByUser = null;
                _usernameError = null;
              });
            },
            child: const Text('เปลี่ยนชื่อผู้ใช้'),
          ),
        ],
      );
    }

    return Container(); // Fallback
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('กู้คืนรหัสผ่าน'),
        backgroundColor: Colors.teal, // ปรับสีให้เข้ากับหน้า Create Account
      ),
      body: Container(
        padding: const EdgeInsets.all(30.0),
        child: Center(
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'ขั้นตอนการกู้คืนรหัสผ่าน',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 30),

                  _buildRecoveryStep(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
