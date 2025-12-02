// lib/database_helper.dart

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // import สำหรับ FFI

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    // กำหนดค่า databaseFactory สำหรับ Windows/Linux/Mac
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, "user");

    // ตรวจสอบว่ามีไฟล์ DB หรือยัง ถ้าไม่มีให้ copy จาก assets
    if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
      try {
        ByteData data = await rootBundle.load("assets/db/user");
        List<int> bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        await File(path).writeAsBytes(bytes);
        print("Copied DB from assets");
      } catch (e) {
        print("Error copying DB: $e");
      }
    }

    return await openDatabase(path, version: 1);
  }

  // เพิ่มข้อมูลผู้ใช้ใหม่
  Future<int> insertUser(Map<String, dynamic> row) async {
    Database db = await database;
    return await db.insert('users', row);
  }

  // ดึงข้อมูลผู้ใช้ตาม userid
  Future<Map<String, dynamic>?> getUser(String userid) async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      'users',
      where: 'userid = ?',
      whereArgs: [userid],
    );
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  // ✅ เพิ่มฟังก์ชันนี้: อัปเดตข้อมูลผู้ใช้
  Future<int> updateUser(Map<String, dynamic> row) async {
    Database db = await database;
    String userid = row['userid']; // ใช้ userid เป็นตัวระบุแถวที่จะแก้
    return await db.update(
      'users',
      row,
      where: 'userid = ?',
      whereArgs: [userid],
    );
  }
}
