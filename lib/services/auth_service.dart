// lib/services/auth_service.dart

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service handling password hashing and secure session storage.
///
/// Uses SHA-256 for password hashing and flutter_secure_storage
/// for session persistence (replacing plaintext user-stat.json).
class AuthService {
  static const _storage = FlutterSecureStorage();

  // Session keys
  static const _keyUsername = 'pillmate_session_username';
  static const _keyToken = 'pillmate_session_token';
  static const _keyRememberMe = 'pillmate_remember_me';

  // ---------------------------------------------------------------------------
  // Password Hashing
  // ---------------------------------------------------------------------------

  /// Hash a plaintext password using SHA-256.
  static String hashPassword(String plaintext) {
    final bytes = utf8.encode(plaintext);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verify a plaintext password against a stored hash.
  /// Also supports legacy plaintext comparison for migration.
  static bool verifyPassword(String plaintext, String storedHash) {
    // Check if the stored value is already a SHA-256 hash (64 hex chars)
    if (_isSha256Hash(storedHash)) {
      return hashPassword(plaintext) == storedHash;
    }
    // Legacy plaintext comparison (for migration)
    return plaintext == storedHash;
  }

  /// Check whether a stored password is already hashed.
  static bool isPasswordHashed(String storedPassword) {
    return _isSha256Hash(storedPassword);
  }

  static bool _isSha256Hash(String value) {
    if (value.length != 64) return false;
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
  }

  // ---------------------------------------------------------------------------
  // Secure Session Storage (replaces user-stat.json)
  // ---------------------------------------------------------------------------

  /// Save session after successful login.
  static Future<void> saveSession({
    required String username,
    required bool rememberMe,
  }) async {
    try {
      // Generate a simple session token (not a password!)
      final token = hashPassword('${username}_${DateTime.now().toIso8601String()}');
      await _storage.write(key: _keyUsername, value: username);
      await _storage.write(key: _keyToken, value: token);
      await _storage.write(
        key: _keyRememberMe,
        value: rememberMe.toString(),
      );
    } catch (e) {
      debugPrint('AuthService: Error saving session: $e');
    }
  }

  /// Load saved session. Returns username if remember-me is active.
  static Future<String?> loadSession() async {
    try {
      final rememberMe = await _storage.read(key: _keyRememberMe);
      if (rememberMe == 'true') {
        return await _storage.read(key: _keyUsername);
      }
    } catch (e) {
      debugPrint('AuthService: Error loading session: $e');
    }
    return null;
  }

  /// Get the currently logged-in username (regardless of remember-me).
  static Future<String?> getCurrentUsername() async {
    try {
      return await _storage.read(key: _keyUsername);
    } catch (e) {
      debugPrint('AuthService: Error reading username: $e');
      return null;
    }
  }

  /// Clear the saved session (logout).
  static Future<void> clearSession() async {
    try {
      await _storage.delete(key: _keyUsername);
      await _storage.delete(key: _keyToken);
      await _storage.delete(key: _keyRememberMe);
    } catch (e) {
      debugPrint('AuthService: Error clearing session: $e');
    }
  }
}
