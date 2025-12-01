// lib/database.dart

import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// จำเป็นต้องมีบรรทัดนี้เพื่อให้ build_runner ทำงาน
part 'database.g.dart';

// 1. ตาราง Users (แทน user.json)
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text().unique()(); // บังคับห้ามซ้ำ
  TextColumn get password => text()();
  TextColumn get image => text().nullable()(); // เก็บ Base64
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// 2. ตาราง AppSettings (แทน user-stat.json สำหรับ Remember Me)
class AppSettings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get key => text().unique()(); // เช่น 'remember_user'
  TextColumn get value => text()(); // เก็บ username
  TextColumn get value2 => text().nullable()(); // เก็บ password (ถ้าจำเป็น)
  BoolColumn get isRemember => boolean().withDefault(const Constant(false))();
}

// 3. ตัว Database Class
@DriftDatabase(tables: [Users, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // --- ฟังก์ชันสำหรับ Users ---
  
  // สมัครสมาชิก
  Future<int> createUser(String username, String password, String? image) {
    return into(users).insert(UsersCompanion(
      username: Value(username),
      password: Value(password),
      image: Value(image),
    ));
  }

  // หา User ตอน Login
  Future<User?> getUser(String username, String password) {
    return (select(users)
      ..where((tbl) => tbl.username.equals(username))
      ..where((tbl) => tbl.password.equals(password))
    ).getSingleOrNull();
  }

  // เช็คว่ามี username นี้หรือยัง
  Future<User?> getUserByUsername(String username) {
    return (select(users)..where((tbl) => tbl.username.equals(username))).getSingleOrNull();
  }

  // --- ฟังก์ชันสำหรับ Remember Me ---
  
  // บันทึกสถานะ Remember Me
  Future<void> saveRememberMe(String username, String password, bool remember) async {
    // ใช้ท่า "Upsert" (ถ้ามีให้แก้ ถ้าไม่มีให้เพิ่ม)
    await into(appSettings).insertOnConflictUpdate(AppSettingsCompanion(
      id: const Value(1), // บังคับใช้ ID 1 เสมอ เพราะเราเก็บแค่ user เดียว
      key: const Value('last_login'),
      value: Value(username),
      value2: Value(password),
      isRemember: Value(remember),
    ));
  }

  // ดึงค่า Remember Me
  Future<AppSetting?> getRememberMe() {
    return (select(appSettings)..where((tbl) => tbl.id.equals(1))).getSingleOrNull();
  }

  // ล้างค่า Remember Me
  Future<void> clearRememberMe() async {
     await (update(appSettings)..where((t) => t.id.equals(1))).write(
       const AppSettingsCompanion(isRemember: Value(false), value: Value(''), value2: Value(''))
     );
  }
}

// ฟังก์ชันเปิด Connection (รองรับ Windows/Android)
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'pillmate.sqlite'));
    return NativeDatabase(file);
  });
}

// สร้างตัวแปร Global ให้เรียกใช้ได้ทั่วแอป
late AppDatabase db;