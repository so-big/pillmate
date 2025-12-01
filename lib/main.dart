// lib/main.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'forgotPassword.dart';
import 'createAccount.dart';
import 'dashboard.dart';

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

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  Future<Directory> _appDir() async {
    return getApplicationDocumentsDirectory();
  }

  Future<File> _userFile() async {
    final dir = await _appDir();
    return File('${dir.path}/user.json');
  }

  Future<File> _userStatFile() async {
    final dir = await _appDir();
    return File('${dir.path}/user-stat.json');
  }

  @override
  void initState() {
    super.initState();
    _loadRememberMeAndMaybeAutoLogin();
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

  Future<Map<String, dynamic>?> _findUser(
    String username,
    String password,
  ) async {
    try {
      final file = await _userFile();
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;

      final list = jsonDecode(content);
      if (list is! List) return null;

      for (final u in list) {
        if (u is Map || u is Map<String, dynamic>) {
          final map = Map<String, dynamic>.from(u);
          if (map['userid'] == username && map['password'] == password) {
            return map;
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error reading user.json: $e');
      return null;
    }
  }

  Future<void> _handleLogin({bool auto = false}) async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (!auto) {
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

    // ไปหน้า Dashboard (แทนที่หน้า Login)
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DashboardPage(username: username),
      ),
    );
  }

  @override
  void dispose() {
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

                // Login Button
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF90EE90), Color(0xFF32CD32)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        spreadRadius: 2,
                        blurRadius: 5,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isLoading
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
                            : const Text(
                                'LOG IN',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                      ),
                    ),
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
