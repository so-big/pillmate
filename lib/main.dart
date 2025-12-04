// lib/main.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // เพิ่มสำหรับ rootBundle
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'forgotPassword.dart';
import 'create_account.dart';
import 'view_dashboard.dart';
import 'database_helper.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pillmate App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(0.8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide.none,
          ),
          hintStyle: TextStyle(color: Colors.grey[600]),
          prefixIconColor: Colors.grey[600],
        ),
      ),

      // ✅ เพิ่ม localizations สำหรับภาษาไทยทั้งแอป
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('th', 'TH')],
      locale: const Locale('th', 'TH'),

      home: const LoginPage(),
    );
  }
}

// ==================== Login Page ====================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _rememberMe = false;
  bool _isLoading = false;
  String _message = '';

  // เพิ่มตัวแปรเช็คความยาวรหัสผ่าน
  bool _isPasswordValid = false;

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // เรียกใช้ Database Helper
  final dbHelper = DatabaseHelper();

  Future<Directory> _appDir() async {
    return getApplicationDocumentsDirectory();
  }

  Future<File> _userStatFile() async {
    final dir = await _appDir();
    // ตรวจสอบและสร้างโฟลเดอร์ pillmate ก่อน
    final pillmateDir = Directory('${dir.path}/pillmate');
    if (!(await pillmateDir.exists())) {
      await pillmateDir.create(recursive: true);
    }
    return File('${dir.path}/pillmate/user-stat.json');
  }

  // ✅ NEW: ฟังก์ชันสำหรับหา/สร้างไฟล์ appstatus.json
  Future<File> _appStatusFile() async {
    final dir = await _appDir();
    // ตรวจสอบและสร้างโฟลเดอร์ pillmate ก่อน
    final pillmateDir = Directory('${dir.path}/pillmate');
    if (!(await pillmateDir.exists())) {
      await pillmateDir.create(recursive: true);
    }
    return File('${dir.path}/pillmate/appstatus.json');
  }

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_validatePasswordLength);
    // 🔔 เรียกใช้ฟังก์ชันเตรียมไฟล์สถานะก่อนโหลดข้อมูลอื่นๆ
    _initializeAppStatusFile();
    _loadRememberMeAndMaybeAutoLogin();
  }

  // =========================================================================
  // ✅ NEW: 1. ฟังก์ชันคัดลอกไฟล์ appstatus.json จาก assets
  // =========================================================================
  Future<void> _initializeAppStatusFile() async {
    try {
      final appStatusFile = await _appStatusFile();

      if (!(await appStatusFile.exists())) {
        debugPrint('AppStatus file not found. Copying from assets...');
        // โหลดเนื้อหาจาก assets
        final assetContent = await rootBundle.loadString(
          'assets/db/appstatus.json',
        );

        // บันทึกเนื้อหาลงใน Application Documents Directory
        await appStatusFile.writeAsString(assetContent, flush: true);
        debugPrint(
          'AppStatus file copied successfully to: ${appStatusFile.path}',
        );
      }
    } catch (e) {
      debugPrint('Error initializing appstatus.json: $e');
      // ในกรณีที่ไฟล์ assets/db/appstatus.json ไม่มีอยู่จริง ให้แสดงข้อความเตือน
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: ไม่พบไฟล์ตั้งค่าเริ่มต้น (assets/db/appstatus.json): $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  // =========================================================================

  // ✅ ฟังก์ชันตรวจสอบความยาวรหัสผ่าน
  void _validatePasswordLength() {
    setState(() {
      // ต้องมากกว่า 7 ตัวอักษร (8 ตัวขึ้นไป) ถึงจะให้กดได้
      // วิธีนี้จะกัน Child Profile ที่มีรหัสแค่ '-' (1 ตัวอักษร) ได้แน่นอน
      _isPasswordValid = _passwordController.text.length > 7;
    });
  }

  Future<void> _loadRememberMeAndMaybeAutoLogin() async {
    try {
      final statFile = await _userStatFile();
      if (await statFile.exists()) {
        final content = await statFile.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content);
          if (data is Map) {
            final remember = data['rememberMe'] == true;
            final username = data['username']?.toString() ?? '';
            final password = data['password']?.toString() ?? '';

            setState(() {
              _rememberMe = remember;
              _usernameController.text = username;
              _passwordController.text = password;
            });

            // ตรวจสอบความยาวรหัสผ่านหลังจากโหลด Auto Fill ด้วย
            _validatePasswordLength();

            // ถ้ามี rememberMe จริง และ username/password ไม่ว่าง → auto login
            if (remember && username.isNotEmpty && password.isNotEmpty) {
              _handleLogin(auto: true);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading user-stat.json: $e');
    }
  }

  Future<void> _saveUserStat({
    required String username,
    required String password,
    required bool rememberMe,
  }) async {
    try {
      final file = await _userStatFile();
      final data = {
        'username': username,
        'password': password,
        'rememberMe': rememberMe,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving user-stat.json: $e');
    }
  }

  // --------------------------------------------------------------------------
  // ดึงข้อมูล User จาก SQLite
  // --------------------------------------------------------------------------
  Future<Map<String, dynamic>?> _findUser(
    String username,
    String password,
  ) async {
    try {
      // 1. ดึงข้อมูล User จาก SQLite ตาม username
      final user = await dbHelper.getUser(username);

      // 2. ถ้าไม่มี User หรือ รหัสผ่านไม่ตรงกัน
      if (user == null) {
        return null;
      }

      // 3. เช็ครหัสผ่าน (user['password'] มาจาก SQLite)
      if (user['password'] == password) {
        return user;
      } else {
        return null; // รหัสผิด
      }
    } catch (e) {
      debugPrint('Error reading from SQLite: $e');
      return null;
    }
  }
  // --------------------------------------------------------------------------

  Future<void> _handleLogin({bool auto = false}) async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (!auto) {
      // ✅ เพิ่ม Logic กันเหนียว: ถ้ารหัสสั้นกว่า 8 ตัว ให้ return เลย (ถึงแม้ปุ่มจะกดไม่ได้ก็ตาม)
      if (password.length <= 7) {
        setState(() {
          _message = 'รหัสผ่านต้องมีความยาวมากกว่าหรือเท่ากับ 8 ตัวอักษร';
        });
        return;
      }

      if (username.isEmpty || password.isEmpty) {
        setState(() {
          _message = 'กรุณากรอก Username และ Password';
        });
        return;
      }
    }

    setState(() {
      _isLoading = true;
      if (!auto) _message = '';
    });

    final user = await _findUser(username, password);

    if (!mounted) return;

    if (user == null) {
      setState(() {
        _isLoading = false;
        if (!auto) {
          _message = 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง';
        }
      });
      return;
    }

    // ล็อกอินสำเร็จ → บันทึก rememberMe
    await _saveUserStat(
      username: username,
      password: password,
      rememberMe: _rememberMe,
    );

    setState(() {
      _isLoading = false;
      _message = '';
    });

    // ไปหน้า Dashboard
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DashboardPage(username: username),
      ),
    );
  }

  @override
  void dispose() {
    // ✅ อย่าลืม remove listener
    _passwordController.removeListener(_validatePasswordLength);
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Background Image/Gradient
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF86E3CE), Color(0xFFD0F0C0)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // Logo
                Image.asset('assets/logo255x195.png', width: 255, height: 195),
                const SizedBox(height: 20),

                // App Title
                Text(
                  'PILLMATE',
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 5),

                // Tagline
                Text(
                  'Your Health, Your Reminder.',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[700],
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 40),

                // Username TextField
                TextField(
                  controller: _usernameController,
                  style: const TextStyle(color: Colors.black),
                  decoration: const InputDecoration(
                    hintText: 'Username',
                    prefixIcon: Icon(Icons.person_outline),
                    suffixIcon: Icon(
                      Icons.lock_outline,
                      color: Color(0xFF9E9E9E),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Password TextField
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.black),
                  decoration: const InputDecoration(
                    hintText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                    suffixIcon: Icon(
                      Icons.lock_outline,
                      color: Color(0xFF9E9E9E),
                    ),
                  ),
                ),

                // Checkbox "Remember Me"
                Padding(
                  padding: const EdgeInsets.only(top: 10.0, bottom: 10.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        onChanged: (bool? newValue) {
                          setState(() {
                            _rememberMe = newValue ?? false;
                          });
                        },
                        activeColor: Colors.green[600],
                        checkColor: Colors.white,
                      ),
                      Text(
                        'Remember Me',
                        style: TextStyle(color: Colors.grey[700], fontSize: 16),
                      ),
                    ],
                  ),
                ),

                // Status message
                if (_message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                const SizedBox(height: 10),

                // ✅ Login Button (แก้ไขให้เช็ค _isPasswordValid)
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    // ถ้า Password ยังไม่ครบ 9 ตัว ให้เป็นสีเทา ถ้าครบแล้วให้เป็นสีเขียว
                    gradient: _isPasswordValid
                        ? const LinearGradient(
                            colors: [Color(0xFF90EE90), Color(0xFF32CD32)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          )
                        : const LinearGradient(
                            colors: [
                              Colors.grey,
                              Colors.grey,
                            ], // สีปุ่ม Disable
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                    boxShadow: _isPasswordValid
                        ? [
                            const BoxShadow(
                              color: Colors.black26,
                              spreadRadius: 2,
                              blurRadius: 5,
                              offset: Offset(0, 3),
                            ),
                          ]
                        : [], // ไม่มีเงาถ้าปุ่มกดไม่ได้
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      // ถ้ากำลังโหลด หรือ รหัสผ่านไม่ถูกต้อง (สั้นเกินไป) ให้กดไม่ได้ (null)
                      onTap: (_isLoading || !_isPasswordValid)
                          ? null
                          : () => _handleLogin(auto: false),
                      borderRadius: BorderRadius.circular(10),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'LOG IN',
                                style: TextStyle(
                                  // ถ้าปุ่ม Disable ให้ตัวหนังสือจางลงหน่อย
                                  color: _isPasswordValid
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),

                // คำอธิบายเล็กๆ ใต้ปุ่ม (Optional: เพื่อบอก user ว่าทำไมกดไม่ได้)
                if (!_isPasswordValid && _passwordController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      '* รหัสผ่านต้องมากกว่า 8 ตัวอักษร',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),

                const SizedBox(height: 25),

                // Forgot Password and Create Account
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ForgotPasswordPage(),
                          ),
                        );
                      },
                      child: Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: Colors.blue[700],
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CreateAccountPage(),
                          ),
                        );
                      },
                      child: Text(
                        'Create Account',
                        style: TextStyle(
                          color: Colors.blue[700],
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
