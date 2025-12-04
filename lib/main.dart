// lib/main.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

// ✅ Import Plugin
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'forgotPassword.dart';
import 'create_account.dart';
import 'view_dashboard.dart';
import 'database_helper.dart';
import 'nortification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. เริ่มต้นระบบแจ้งเตือน
  await initializeNotifications();

  // ====================================================================
  // ✅ NEW: ส่วนขออนุญาต (Permission) แก้ไขให้ถูกต้องสำหรับ v17+
  // ====================================================================

  // 1. ขออนุญาต Android
  final androidImplementation = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  if (androidImplementation != null) {
    await androidImplementation.requestNotificationsPermission();
  }

  // 2. ขออนุญาต iOS (v17+ ยังใช้ IOSFlutterLocalNotificationsPlugin ในการ resolve ครับ)
  final iosImplementation = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >(); // ✅ ใช้ IOS... แทน Darwin...

  if (iosImplementation != null) {
    await iosImplementation.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  // 3. (แถม) ขออนุญาต macOS (ถ้ามีแผนจะทำลง Mac ด้วย)
  /*
  final macosImplementation = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
          
  if (macosImplementation != null) {
    await macosImplementation.requestPermissions(
      alert: true, 
      badge: true, 
      sound: true,
    );
  }
  */

  // ====================================================================

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

      // ✅ localizations ภาษาไทย
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
  bool _isPasswordValid = false;

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final dbHelper = DatabaseHelper();

  Future<Directory> _appDir() async {
    return getApplicationDocumentsDirectory();
  }

  Future<File> _userStatFile() async {
    final dir = await _appDir();
    final pillmateDir = Directory('${dir.path}/pillmate');
    if (!(await pillmateDir.exists())) {
      await pillmateDir.create(recursive: true);
    }
    return File('${dir.path}/pillmate/user-stat.json');
  }

  Future<File> _appStatusFile() async {
    final dir = await _appDir();
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
    _initializeAppStatusFile();
    _loadRememberMeAndMaybeAutoLogin();
  }

  Future<void> _initializeAppStatusFile() async {
    try {
      final appStatusFile = await _appStatusFile();

      if (!(await appStatusFile.exists())) {
        debugPrint('AppStatus file not found. Copying from assets...');
        final assetContent = await rootBundle.loadString(
          'assets/db/appstatus.json',
        );
        await appStatusFile.writeAsString(assetContent, flush: true);
        debugPrint(
          'AppStatus file copied successfully to: ${appStatusFile.path}',
        );
      }
    } catch (e) {
      debugPrint('Error initializing appstatus.json: $e');
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

  void _validatePasswordLength() {
    setState(() {
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

            _validatePasswordLength();

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

  Future<Map<String, dynamic>?> _findUser(
    String username,
    String password,
  ) async {
    try {
      final user = await dbHelper.getUser(username);
      if (user == null) {
        return null;
      }
      if (user['password'] == password) {
        return user;
      } else {
        return null;
      }
    } catch (e) {
      debugPrint('Error reading from SQLite: $e');
      return null;
    }
  }

  Future<void> _handleLogin({bool auto = false}) async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (!auto) {
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

    await _saveUserStat(
      username: username,
      password: password,
      rememberMe: _rememberMe,
    );

    setState(() {
      _isLoading = false;
      _message = '';
    });

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DashboardPage(username: username),
      ),
    );
  }

  @override
  void dispose() {
    _passwordController.removeListener(_validatePasswordLength);
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                Image.asset('assets/logo255x195.png', width: 255, height: 195),
                const SizedBox(height: 20),
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
                Text(
                  'Your Health, Your Reminder.',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[700],
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 40),
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
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: _isPasswordValid
                        ? const LinearGradient(
                            colors: [Color(0xFF90EE90), Color(0xFF32CD32)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          )
                        : const LinearGradient(
                            colors: [Colors.grey, Colors.grey, Colors.grey],
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
                        : [],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
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
                if (!_isPasswordValid && _passwordController.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      '* รหัสผ่านต้องมากกว่า 8 ตัวอักษร',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 25),
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
