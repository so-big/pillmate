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

    // 1. กำหนด path ของโฟลเดอร์ pillmate
    String pillmateDirPath = join(documentsDirectory.path, "pillmate");

    // 2. ✅ ตรวจสอบและสร้างโฟลเดอร์ pillmate หากยังไม่มี
    if (!await Directory(pillmateDirPath).exists()) {
      try {
        // สร้างโฟลเดอร์แบบ recursive (ถ้า Documents ไม่ใช่ root)
        await Directory(pillmateDirPath).create(recursive: true);
        print("Created pillmate directory at: $pillmateDirPath");
      } catch (e) {
        print("Error creating directory: $e");
        // ถ้าสร้างไม่ได้ อาจจะเกิดปัญหาในการบันทึกไฟล์ database ต่อไป
        // แต่เราจะลองไปต่อเผื่อมี error อื่นๆ
      }
    }

    // 3. กำหนด path ของไฟล์ database ภายในโฟลเดอร์นั้น
    String path = join(
      pillmateDirPath,
      "user",
    ); // ไฟล์จะอยู่ที่ .../Documents/pillmate/user

    // 4. ตรวจสอบว่ามีไฟล์ DB หรือยัง ถ้าไม่มีให้ copy จาก assets
    if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
      try {
        ByteData data = await rootBundle.load("assets/db/user");
        List<int> bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        // การเขียนไฟล์จะสำเร็จเพราะโฟลเดอร์ปลายทาง (pillmateDirPath) ถูกสร้างแล้ว
        await File(path).writeAsBytes(bytes, flush: true);
        print("Copied DB from assets to $path");
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
