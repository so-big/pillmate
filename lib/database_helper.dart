// lib/database_helper.dart
//
// Modernized SQLite singleton with:
// - Migration support (version tracking)
// - CRUD for all tables: users, medicines, calendar_alerts, taken_doses, app_settings
// - Consolidated app settings (replaces appstatus.json)
// - Password hash migration on first upgrade

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'services/auth_service.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // ---------------------------------------------------------------------------
  // DATABASE INITIALIZATION
  // ---------------------------------------------------------------------------

  Future<Database> _initDatabase() async {
    // Configure FFI for desktop platforms
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final pillmateDirPath = join(documentsDirectory.path, 'pillmate');

    // Ensure the pillmate directory exists
    final pillmateDir = Directory(pillmateDirPath);
    if (!await pillmateDir.exists()) {
      await pillmateDir.create(recursive: true);
      debugPrint('DatabaseHelper: Created directory at $pillmateDirPath');
    }

    final dbPath = join(pillmateDirPath, 'user');

    // Copy the seed database from assets if it doesn't exist
    if (FileSystemEntity.typeSync(dbPath) == FileSystemEntityType.notFound) {
      try {
        final ByteData data = await rootBundle.load('assets/db/user');
        final List<int> bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        await File(dbPath).writeAsBytes(bytes, flush: true);
        debugPrint('DatabaseHelper: Copied seed DB from assets to $dbPath');
      } catch (e) {
        debugPrint('DatabaseHelper: Error copying seed DB: $e');
      }
    }

    return await openDatabase(
      dbPath,
      version: 2,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        await _ensureTables(db);
      },
    );
  }

  /// Handle database version upgrades.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint(
      'DatabaseHelper: Upgrading DB from v$oldVersion to v$newVersion',
    );
    if (oldVersion < 2) {
      await _ensureTables(db);
      await _migratePasswords(db);
    }
  }

  /// Ensure all required tables and columns exist.
  Future<void> _ensureTables(Database db) async {
    // app_settings table (replaces appstatus.json)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // scheduled_notifications table (track scheduled notifications)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scheduled_notifications (
        notification_id INTEGER PRIMARY KEY,
        username TEXT NOT NULL,
        reminder_id TEXT NOT NULL,
        dose_time TEXT NOT NULL,
        notify_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        canceled INTEGER DEFAULT 0
      )
    ''');

    // Ensure columns exist on users table (safe ALTER TABLE)
    final userColumns = await _getColumnNames(db, 'users');
    final requiredUserColumns = {
      'security_question': 'TEXT DEFAULT ""',
      'security_answer': 'TEXT DEFAULT ""',
      'breakfast': 'TEXT DEFAULT "06:00"',
      'lunch': 'TEXT DEFAULT "12:00"',
      'dinner': 'TEXT DEFAULT "18:00"',
      'bedtime': 'TEXT DEFAULT "21:00"',
      'breakfast_notify': 'INTEGER DEFAULT 1',
      'lunch_notify': 'INTEGER DEFAULT 1',
      'dinner_notify': 'INTEGER DEFAULT 1',
      'bedtime_notify': 'INTEGER DEFAULT 1',
      'info': 'TEXT DEFAULT ""',
      'sub_profile': 'TEXT DEFAULT ""',
      'image_base64': 'TEXT DEFAULT ""',
    };

    for (final entry in requiredUserColumns.entries) {
      if (!userColumns.contains(entry.key)) {
        try {
          await db.execute(
            'ALTER TABLE users ADD COLUMN ${entry.key} ${entry.value}',
          );
        } catch (_) {
          // Column may already exist from the seed DB
        }
      }
    }

    // Ensure columns exist on calendar_alerts table
    final calendarColumns = await _getColumnNames(db, 'calendar_alerts');
    final requiredCalendarColumns = {
      'notify_mode': 'TEXT DEFAULT "interval"',
    };

    for (final entry in requiredCalendarColumns.entries) {
      if (!calendarColumns.contains(entry.key)) {
        try {
          await db.execute(
            'ALTER TABLE calendar_alerts ADD COLUMN ${entry.key} ${entry.value}',
          );
        } catch (_) {
          // Column may already exist
        }
      }
    }
  }

  Future<Set<String>> _getColumnNames(Database db, String table) async {
    try {
      final result = await db.rawQuery('PRAGMA table_info($table)');
      return result.map((row) => row['name'].toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Migrate all plaintext passwords to SHA-256 hashes.
  Future<void> _migratePasswords(Database db) async {
    try {
      final users = await db.query('users');
      for (final user in users) {
        final password = (user['password'] ?? '').toString();
        final userid = (user['userid'] ?? '').toString();
        if (password == '-' || password.isEmpty) continue;
        if (AuthService.isPasswordHashed(password)) continue;

        final hashed = AuthService.hashPassword(password);
        await db.update(
          'users',
          {'password': hashed},
          where: 'userid = ?',
          whereArgs: [userid],
        );
        debugPrint('DatabaseHelper: Migrated password for "$userid"');
      }
    } catch (e) {
      debugPrint('DatabaseHelper: Error migrating passwords: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // USER CRUD
  // ---------------------------------------------------------------------------

  Future<int> insertUser(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert('users', row);
  }

  Future<Map<String, dynamic>?> getUser(String userid) async {
    final db = await database;
    final maps = await db.query(
      'users',
      where: 'userid = ?',
      whereArgs: [userid],
    );
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  Future<int> updateUser(Map<String, dynamic> row) async {
    final db = await database;
    final userid = row['userid'];
    return await db.update(
      'users',
      row,
      where: 'userid = ?',
      whereArgs: [userid],
    );
  }

  Future<int> deleteUser(String userid) async {
    final db = await database;
    return await db.delete('users', where: 'userid = ?', whereArgs: [userid]);
  }

  Future<List<Map<String, dynamic>>> getSubProfiles(
    String masterUsername,
  ) async {
    final db = await database;
    return await db.query(
      'users',
      where: 'sub_profile = ?',
      whereArgs: [masterUsername],
    );
  }

  // ---------------------------------------------------------------------------
  // MEDICINE CRUD
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getMedicines(String username) async {
    final db = await database;
    return await db.query(
      'medicines',
      where: 'createby = ?',
      whereArgs: [username],
    );
  }

  Future<int> insertMedicine(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert('medicines', row);
  }

  Future<int> updateMedicine(String id, Map<String, dynamic> values) async {
    final db = await database;
    return await db.update(
      'medicines',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteMedicine(String id) async {
    final db = await database;
    return await db.delete('medicines', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // CALENDAR ALERTS CRUD
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getCalendarAlerts(
    String username,
  ) async {
    final db = await database;
    return await db.query(
      'calendar_alerts',
      where: 'createby = ?',
      whereArgs: [username],
    );
  }

  Future<int> insertCalendarAlert(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert('calendar_alerts', row);
  }

  Future<int> updateCalendarAlert(
    String id,
    Map<String, dynamic> values,
  ) async {
    final db = await database;
    return await db.update(
      'calendar_alerts',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteCalendarAlert(String id) async {
    final db = await database;
    return await db.delete(
      'calendar_alerts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // TAKEN DOSES CRUD
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getTakenDoses(String username) async {
    final db = await database;
    return await db.query(
      'taken_doses',
      where: 'userid = ?',
      whereArgs: [username],
    );
  }

  Future<int> insertTakenDose(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert('taken_doses', row);
  }

  Future<int> deleteTakenDosesForReminder(String reminderId) async {
    final db = await database;
    return await db.delete(
      'taken_doses',
      where: 'reminder_id = ?',
      whereArgs: [reminderId],
    );
  }

  Future<int> deleteTakenDosesForProfile(String profileName) async {
    final db = await database;
    return await db.delete(
      'taken_doses',
      where: 'profile_name = ?',
      whereArgs: [profileName],
    );
  }

  // ---------------------------------------------------------------------------
  // APP SETTINGS (replaces appstatus.json for new data)
  // ---------------------------------------------------------------------------

  Future<String?> getSetting(String key) async {
    final db = await database;
    final result = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (result.isNotEmpty) return result.first['value'] as String?;
    return null;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String>> getAllSettings() async {
    final db = await database;
    final result = await db.query('app_settings');
    final map = <String, String>{};
    for (final row in result) {
      map[row['key'] as String] = row['value'] as String;
    }
    return map;
  }

  // ---------------------------------------------------------------------------
  // SCHEDULED NOTIFICATIONS CRUD
  // ---------------------------------------------------------------------------

  Future<void> clearScheduledNotifications(String username) async {
    final db = await database;
    await db.delete(
      'scheduled_notifications',
      where: 'username = ?',
      whereArgs: [username],
    );
  }

  Future<void> insertScheduledNotification(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert(
      'scheduled_notifications',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getScheduledNotifications(
    String username,
  ) async {
    final db = await database;
    return await db.query(
      'scheduled_notifications',
      where: 'username = ? AND canceled = 0',
      whereArgs: [username],
    );
  }
}
