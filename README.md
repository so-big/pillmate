# Pillmate

Pillmate คือแอป Flutter สำหรับช่วยจัดการการกินยาแบบออฟไลน์ โดยรองรับทั้งโหมดปกติและโหมด NFC เพื่อยืนยันการกินยา พร้อมระบบแจ้งเตือนและติดตามประวัติการกินยาในแต่ละวัน

## จุดเด่นของแอป
- จัดการบัญชีผู้ใช้หลัก (Master) และโปรไฟล์ย่อย (เช่น ผู้สูงอายุในครอบครัว)
- จัดการข้อมูลยา (ชื่อยา, รายละเอียด, ภาพยา, ก่อน/หลังอาหาร)
- สร้างแผนแจ้งเตือนยาแบบ:
  - `interval` (ทุก X ชั่วโมง/นาที)
  - `meal` (อิงเวลามื้ออาหารของแต่ละโปรไฟล์)
- โหมด NFC:
  - เขียนข้อมูลยา/เตือนลงแท็กตอนสร้างหรือแก้ไขแผน
  - สแกนแท็กเพื่อตรวจสอบและยืนยันการกินยา
- Dashboard รายวัน + ปฏิทินรายสัปดาห์
- ตั้งค่าเสียงแจ้งเตือน, snooze, จำนวนครั้งการแจ้งซ้ำ

## Tech Stack
- Flutter / Dart
- SQLite (`sqflite`, `sqflite_common_ffi`) ผ่าน `DatabaseHelper`
- Notification: `flutter_local_notifications`, `timezone`, `flutter_timezone`
- NFC: `flutter_nfc_kit`, `ndef`
- Secure session: `flutter_secure_storage`
- รูปภาพ: `image_picker` + เก็บเป็น Base64 / asset path

## โครงสร้างข้อมูลหลัก
ตารางที่ใช้งานจริงใน SQLite (อ้างอิง `lib/database_helper.dart`):
- `users` ข้อมูลบัญชีหลัก + โปรไฟล์ย่อย + เวลามื้ออาหาร + Security Q&A
- `medicines` ข้อมูลยา
- `calendar_alerts` แผนแจ้งเตือนยา
- `taken_doses` ประวัติการกินยา
- `app_settings` ค่าตั้งค่าระบบ (เริ่มรองรับใน DB)
- `scheduled_notifications` log งานแจ้งเตือนที่ถูกตั้ง

ไฟล์ JSON ที่ยังถูกใช้งานร่วมด้วย:
- `appstatus.json` (ใน `Documents/pillmate/`) สำหรับสถานะ NFC และตั้งค่าเสียง/snooze บางส่วน
- มีบางหน้าที่ยังอ้างอิง `user-stat.json` แบบ legacy

## Flow การใช้งานโดยย่อ
1. ล็อกอิน (`main.dart`)
2. เข้า Dashboard (`view_dashboard.dart`)
3. เพิ่มโปรไฟล์/ยา/แผนแจ้งเตือนจากเมนูซ้าย (`view_menu.dart`)
4. ระบบตั้งแจ้งเตือนอัตโนมัติ (`notification_next.dart`, `notification_service.dart`)
5. ผู้ใช้ยืนยันการกินยาจาก Dashboard:
   - โหมด NFC: สแกนแท็ก
   - โหมด Manual: กดค้างเพื่อยืนยัน
6. บันทึกลง `taken_doses` และคำนวณแจ้งเตือนรอบถัดไปใหม่

## รายละเอียดแต่ละหน้าหลัก

### 1) เข้าสู่ระบบ (`lib/main.dart`)
- หน้า Login หลักของแอป
- รองรับ Remember Me และ auto-login จาก secure storage
- ตรวจรหัสผ่านผ่าน `AuthService.verifyPassword`
- หากเจอรหัสผ่านเก่าแบบ plaintext จะ migrate เป็น SHA-256 อัตโนมัติ
- ปุ่มไปหน้า:
  - สร้างบัญชี (`create_account.dart`)
  - ลืมรหัสผ่าน (`forgot_password.dart`)

### 2) สร้างบัญชี (`lib/create_account.dart`)
- สมัครบัญชี Master ใหม่
- กำหนดรูปโปรไฟล์ (เลือกจาก asset หรือ gallery)
- ตั้ง Security Question + Answer
- ตั้งเวลาอาหาร default (เช้า/กลางวัน/เย็น)
- บันทึกลง `users` โดย hash รหัสผ่านด้วย `AuthService.hashPassword`

### 3) ลืมรหัสผ่าน (`lib/forgot_password.dart`)
- ขั้นที่ 1: กรอก username
- ขั้นที่ 2: เลือกคำถามกันลืม + ตอบคำตอบ
- หากถูกต้อง เปิด dialog ตั้งรหัสผ่านใหม่และบันทึก hash ลง DB

### 4) Dashboard รายวัน (`lib/view_dashboard.dart`)
- ศูนย์กลางการใช้งานหลัก
- แสดงรายการโดสของวัน (คำนวณตาม `interval` หรือ `meal`)
- ปัดซ้าย/ขวาเพื่อเปลี่ยนวัน
- การ์ดแต่ละโดสรองรับ:
  - ยืนยันการกินยา (NFC หรือ Manual hold)
  - แก้ไขแผนแจ้งเตือน (เปิด `edit_calendar.dart`)
  - ล้างสถานะกินยา (ต้องยืนยันรหัสผ่าน)
- บันทึกผลการกินลง `taken_doses`
- เมื่อสถานะโดสเปลี่ยน จะ re-run notification scheduling

### 5) ปฏิทินรายสัปดาห์ (`lib/view_calendar.dart`)
- แสดงกริด 7 วัน x 24 ชั่วโมง
- ไฮไลต์ช่วงที่มียาตามแผน
- เลื่อนสัปดาห์ก่อนหน้า/ถัดไปได้
- เพิ่มแผนใหม่ผ่านปุ่ม `+` (เปิด `add_calendar.dart`)

### 6) เพิ่มแผนแจ้งเตือน (`lib/add_calendar.dart`)
- ทำงานแบบ Bottom Sheet
- เลือกโปรไฟล์, ยา, วันเริ่ม/สิ้นสุด, โหมดแจ้งเตือน
- โหมด `interval`: ตั้งช่วงเวลาเตือน
- โหมด `meal`: ใช้เวลามื้ออาหารจากโปรไฟล์
- หากเปิด NFC:
  - เขียน payload ลงแท็ก NDEF
- หากปิด NFC:
  - บันทึกโหมด manual ลง DB ได้ทันที
- สุดท้าย insert ลง `calendar_alerts`

### 7) แก้ไขแผนแจ้งเตือน (`lib/edit_calendar.dart`)
- แก้ไขข้อมูลแผนจากรายการเดิม
- รองรับเขียนแท็ก NFC ใหม่เมื่อเปิด NFC
- update ข้อมูลใน `calendar_alerts`
- ลบแผนได้ โดย:
  - ยืนยันรหัสผ่าน
  - ลบทั้ง `calendar_alerts` และ `taken_doses` ที่เกี่ยวข้อง

### 8) เพิ่มยา (`lib/add_medicine.dart`)
- ฟอร์มเพิ่มยาใหม่
- เลือกรูปจาก asset หรือ gallery (crop/resize ก่อนเก็บ)
- เลือกก่อนอาหารหรือหลังอาหาร
- insert ลง `medicines`

### 9) จัดการยา (`lib/manage_medicine.dart`)
- แสดงรายการยาของผู้ใช้
- เรียงชื่อ A-Z / Z-A
- เข้าแก้ไข (`edit_medicine.dart`) หรือ ลบรายการยา

### 10) แก้ไขยา (`lib/edit_medicine.dart`)
- แก้ชื่อยา/รายละเอียด/รูป/ช่วงก่อน-หลังอาหาร
- ก่อนบันทึกต้องยืนยันรหัสผ่าน Master
- update ลง `medicines`

### 11) เพิ่มโปรไฟล์ (`lib/create_profile.dart`)
- สร้าง sub-profile ใต้บัญชี Master
- ใส่ชื่อและข้อมูลเพิ่มเติม
- เลือกรูปจาก asset หรือ gallery
- บันทึกเป็น row ใหม่ใน `users` โดย `sub_profile = master_username`

### 12) จัดการโปรไฟล์ (`lib/manage_profile.dart`)
- แสดงการ์ด Master account + โปรไฟล์ย่อยทั้งหมด
- เข้าแก้ไขบัญชีหลัก (`edit_account.dart`)
- เข้าแก้ไขโปรไฟล์ (`edit_profile.dart`)
- ลบโปรไฟล์ย่อยได้ (ต้องยืนยันรหัสผ่าน)

### 13) แก้ไขบัญชีหลัก (`lib/edit_account.dart`)
- แก้รูปโปรไฟล์
- เปลี่ยนรหัสผ่าน
- เปลี่ยน Security Question/Answer
- แก้เวลาอาหาร + เปิด/ปิดการแจ้งเตือนรายมื้อ
- ก่อน save ต้องยืนยันรหัสผ่านเดิม

### 14) แก้ไขโปรไฟล์ (`lib/edit_profile.dart`)
- แก้ชื่อ/รูป/ข้อมูลโปรไฟล์ย่อย
- แก้เวลาอาหาร + เปิด/ปิดการแจ้งเตือนรายมื้อ
- บันทึกต้องยืนยันรหัสผ่าน Master
- ลบโปรไฟล์ย่อยได้ (พร้อมลบข้อมูลเตือน/ประวัติที่เกี่ยวข้อง)

### 15) เมนูซ้าย (`lib/view_menu.dart`)
- ทางเข้าแต่ละหน้าหลักในแอป
- เปิดหน้า Notification Setting
- สวิตช์เปิด/ปิด NFC (บันทึกลง `appstatus.json`)
- Logout

### 16) ตั้งค่าการแจ้งเตือน (`lib/notification_setting.dart`)
- เลือกไฟล์เสียงแจ้งเตือน + preview เสียง
- ตั้ง snooze duration
- ตั้งจำนวนครั้งการแจ้งซ้ำ
- บันทึกลง `appstatus.json`

## Notification Service
- `lib/notification_next.dart`
  - scheduler หลักที่คำนวณโดสล่วงหน้า
  - รองรับทั้ง `interval` และ `meal` mode
  - อ้างอิงเวลามื้ออาหารจากตาราง `users`
  - ตั้ง noti หลายครั้งตาม repeat/snooze
- `lib/notification_service.dart`
  - อีก service สำหรับหาโดสถัดไปและตั้งแจ้งเตือน
  - ใช้งานร่วมกับ Dashboard ในบาง flow

## โครงสร้างไฟล์ที่ควรรู้
```text
lib/
  main.dart
  view_dashboard.dart
  view_calendar.dart
  view_menu.dart
  add_calendar.dart
  edit_calendar.dart
  add_medicine.dart
  edit_medicine.dart
  manage_medicine.dart
  create_profile.dart
  edit_profile.dart
  manage_profile.dart
  create_account.dart
  edit_account.dart
  forgot_password.dart
  notification_next.dart
  notification_service.dart
  notification_setting.dart
  database_helper.dart
  services/auth_service.dart
  models/
  providers/
```

## วิธีรันโปรเจกต์
```bash
flutter pub get
flutter run
```

## หมายเหตุสำหรับทีมพัฒนา
- โปรเจกต์กำลังอยู่ในช่วงเปลี่ยนผ่านจาก JSON ไป DB ในบางส่วน
- มีไฟล์สะกดชื่อเดิม (`nortification_*`) และไฟล์ใหม่ (`notification_*`) อยู่ร่วมกัน ควรเลือกใช้งานชุดใหม่เป็นหลัก
- `providers/` และ `models/` มีโครงสร้างรองรับไว้แล้ว แต่หลายหน้ายังใช้ `StatefulWidget + setState` โดยตรง

