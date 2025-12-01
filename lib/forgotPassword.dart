// lib/forgotPassword.dart

import 'package:flutter/material.dart';

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // ปุ่ม Back จะปรากฏขึ้นโดยอัตโนมัติ เพราะเราใช้ Navigator.push
        title: const Text('Forgot Password'),
        backgroundColor: Colors.lightBlue, 
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'This is the Forgot Password Screen!',
              style: TextStyle(fontSize: 24, color: Colors.black54),
            ),
            const SizedBox(height: 20),
            // ปุ่มนี้จะใช้ย้อนกลับไปยังหน้า Login
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // คำสั่งย้อนกลับ
              },
              child: const Text('Go Back to Login'),
            ),
          ],
        ),
      ),
    );
  }
}