// lib/main.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'forgot_password.dart';
import 'create_account.dart';
import 'view_dashboard.dart';
import 'database_helper.dart';
import 'notification_service.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notifications
  await initializeNotifications();

  // Request notification permissions (Android 13+)
  final androidImplementation = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (androidImplementation != null) {
    await androidImplementation.requestNotificationsPermission();
  }

  // Request notification permissions (iOS)
  final iosImplementation = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();
  if (iosImplementation != null) {
    await iosImplementation.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  runApp(const ProviderScope(child: MyApp()));
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
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('th', 'TH'), Locale('en', 'US')],
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

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_validatePasswordLength);
    _initializeAppStatusFile();
    _loadRememberMeAndMaybeAutoLogin();
  }

  /// Initialize appstatus.json if it doesn't exist (legacy support).
  Future<void> _initializeAppStatusFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final pillmateDir = Directory('${dir.path}/pillmate');
      if (!(await pillmateDir.exists())) {
        await pillmateDir.create(recursive: true);
      }
      final appStatusFile = File('${dir.path}/pillmate/appstatus.json');
      if (!(await appStatusFile.exists())) {
        final assetContent = await rootBundle.loadString(
          'assets/db/appstatus.json',
        );
        await appStatusFile.writeAsString(assetContent, flush: true);
      }
    } catch (e) {
      debugPrint('Error initializing appstatus.json: $e');
    }
  }

  void _validatePasswordLength() {
    setState(() {
      _isPasswordValid = _passwordController.text.length > 7;
    });
  }

  /// Load session from secure storage and auto-login if remember-me.
  Future<void> _loadRememberMeAndMaybeAutoLogin() async {
    try {
      final savedUsername = await AuthService.loadSession();
      if (savedUsername != null && savedUsername.isNotEmpty) {
        setState(() {
          _rememberMe = true;
          _usernameController.text = savedUsername;
        });

        // Auto-login: verify the user still exists in DB
        final user = await dbHelper.getUser(savedUsername);
        if (user != null && mounted) {
          setState(() {
            _isLoading = false;
            _message = '';
          });
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => DashboardPage(username: savedUsername),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading session: $e');
    }
  }

  /// Authenticate user with hashed password comparison.
  Future<Map<String, dynamic>?> _findUser(
    String username,
    String password,
  ) async {
    try {
      final user = await dbHelper.getUser(username);
      if (user == null) return null;

      final storedPassword = (user['password'] ?? '').toString();

      // Verify password (supports both hashed and legacy plaintext)
      if (AuthService.verifyPassword(password, storedPassword)) {
        // If the stored password is still plaintext, migrate it to hash
        if (!AuthService.isPasswordHashed(storedPassword)) {
          final hashed = AuthService.hashPassword(password);
          await dbHelper.updateUser({
            'userid': username,
            'password': hashed,
          });
          debugPrint('Migrated password for user "$username" to SHA-256');
        }
        return user;
      }
      return null;
    } catch (e) {
      debugPrint('Error authenticating user: $e');
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
        if (!auto) _message = 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง';
      });
      return;
    }

    // Save session securely (no password stored!)
    await AuthService.saveSession(
      username: username,
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
