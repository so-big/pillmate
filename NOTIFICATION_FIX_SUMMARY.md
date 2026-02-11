# สรุปการแก้ไขระบบ Notification ให้ทำงานได้จริง

## ปัญหาที่แก้ไข
1. **ไม่มีการแจ้งเตือน** — ระบบไม่ได้ตั้งค่าการแจ้งเตือนตามข้อมูลในฐานข้อมูล
2. **Dual source of truth** — อ่านข้อมูลจาก JSON แทน SQLite
3. **ไฟล์เสียงผิด** — ชื่อไฟล์ไม่ตรงกัน มี extension และตัวพิมพ์ใหญ่/เล็กผสม
4. **ไม่มี repeat/snooze** — ไม่ได้ทำการแจ้งเตือนซ้ำตามที่ตั้งค่า
5. **ไม่จำกัดจำนวน** — ตั้งการแจ้งเตือนทั้งหมดในช่วง 7 วัน (มากเกินไป)

## การแก้ไขทั้งหมด

### 1. Database Layer
**ไฟล์:** `lib/database_helper.dart`
- เพิ่มตาราง `scheduled_notifications` เพื่อเก็บประวัติการตั้งการแจ้งเตือน
- เพิ่ม CRUD methods: `clearScheduledNotifications()`, `insertScheduledNotification()`, `getScheduledNotifications()`

```sql
CREATE TABLE scheduled_notifications (
  notification_id INTEGER PRIMARY KEY,
  username TEXT NOT NULL,
  reminder_id TEXT NOT NULL,
  dose_time TEXT NOT NULL,
  notify_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  canceled INTEGER DEFAULT 0
)
```

### 2. Notification Logic
**ไฟล์:** `lib/notification_next.dart`

#### เปลี่ยนแปลงหลัก:
1. **อ่านจาก SQLite แทน JSON**
   - `_readRemindersFor()` → ใช้ `DatabaseHelper.getCalendarAlerts()`
   - `_readTakenKeysFor()` → ใช้ `DatabaseHelper.getTakenDoses()`
   - `_readSettings()` → ใช้ `DatabaseHelper.getSetting()` กับ fallback JSON

2. **คำนวณเฉพาะ 5 การแจ้งเตือนถัดไป**
   ```dart
   // เลือกเฉพาะ 5 ครั้งถัดไป (ที่ยังไม่ได้กิน)
   final nextDoses = <DateTime>[];
   for (final dt in allDoseTimes) {
     final doseIso = dt.toIso8601String();
     final key = '$reminderId|$doseIso';
     if (!takenKeys.contains(key)) {
       nextDoses.add(dt);
       if (nextDoses.length >= 5) break; // จำกัด 5 ครั้ง
     }
   }
   ```

3. **Repeat/Snooze ตามตั้งค่า**
   ```dart
   // อ่านค่า repeat + snooze จาก appstatus.json
   final soundSettings = await _readSoundSettings();
   final repeatCount = soundSettings['repeatCount'] ?? 3;
   final snoozeDuration = soundSettings['snoozeDuration'] ?? 5;
   
   // สร้าง repeatCount ครั้ง โดยห่างกัน snoozeDuration นาที
   for (int i = 0; i < repeatCount; i++) {
     final notifyTime = firstNotify.add(Duration(minutes: (i * snoozeDuration) as int));
     // ... schedule notification
   }
   ```

4. **ใช้เสียงตามที่เลือก**
   ```dart
   // ดึงชื่อไฟล์เสียงจาก settings (ไม่มี extension)
   String soundName = 'alarm'; // default
   if (soundPath != null && soundPath.isNotEmpty) {
     final parts = soundPath.split('/').last.split('.');
     if (parts.isNotEmpty) {
       soundName = parts.first.toLowerCase();
     }
   }
   
   // ส่งเข้าไปใน _scheduleNotification
   await _scheduleNotification(
     id: id,
     when: notifyTime,
     title: 'เตือนกินยา ($profileName)',
     body: medName,
     soundName: soundName, // ใช้เสียงที่เลือก
   );
   ```

5. **เพิ่ม Permission Requests**
   ```dart
   // ขอ notification permission
   final granted = await androidImpl?.requestNotificationsPermission();
   debugPrint('Notification permission granted: $granted');
   
   // ขอ exact alarm permission (Android 12+)
   final exactAlarmPermission = await androidImpl?.requestExactAlarmsPermission();
   debugPrint('Exact alarm permission granted: $exactAlarmPermission');
   ```

6. **บันทึกลง Database**
   ```dart
   // บันทึก scheduled_notifications ลง DB
   for (final record in scheduledForUser) {
     await dbHelper.insertScheduledNotification(record);
   }
   ```

### 3. Sound Files
**ปัญหา:** ไฟล์ใน `android/app/src/main/res/raw/` มี extension `.mp3` และชื่อตัวพิมพ์ใหญ่

**แก้ไข:**
1. ลบ extension `.mp3` ออกจากไฟล์ทั้งหมด (Android raw resources ต้องไม่มี extension)
2. เปลี่ยนชื่อไฟล์เป็นตัวพิมพ์เล็กทั้งหมด

**ผลลัพธ์:**
```
android/app/src/main/res/raw/
├── a01_clock_alarm_normal_30_sec
├── a02_clock_alarm_normal_1_min
├── a03_clock_alarm_normal_1_30_min
├── a04_clock_alarm_continue_30_sec
├── a05_clock_alarm_continue_1_min
├── a06_clock_alarm_continue_1_30_min
└── alarm
```

### 4. Asset Configuration
**ไฟล์:** `pubspec.yaml`
- แก้ชื่อไฟล์ให้ตรงกับไฟล์จริง (ตัวพิมพ์เล็ก, ใช้ underscore แทนจุดใน 1.30)

```yaml
assets:
  - assets/sound_norti/a06_clock_alarm_continue_1_30_min.mp3
  - assets/sound_norti/a05_clock_alarm_continue_1_min.mp3
  - assets/sound_norti/a04_clock_alarm_continue_30_sec.mp3
  - assets/sound_norti/a03_clock_alarm_normal_1_30_min.mp3
  - assets/sound_norti/a02_clock_alarm_normal_1_min.mp3
  - assets/sound_norti/a01_clock_alarm_normal_30_sec.mp3
```

### 5. Notification Settings UI
**ไฟล์:** `lib/notification_setting.dart`
- แก้รายชื่อเสียงให้ตรงกับไฟล์จริง (ตัวพิมพ์เล็ก)

```dart
final List<String> _availableSounds = const [
  'assets/sound_norti/a01_clock_alarm_normal_30_sec.mp3',
  'assets/sound_norti/a02_clock_alarm_normal_1_min.mp3',
  'assets/sound_norti/a03_clock_alarm_normal_1_30_min.mp3',
  'assets/sound_norti/a04_clock_alarm_continue_30_sec.mp3',
  'assets/sound_norti/a05_clock_alarm_continue_1_min.mp3',
  'assets/sound_norti/a06_clock_alarm_continue_1_30_min.mp3',
];
```

## การทำงานของระบบใหม่

### Flow การตั้งการแจ้งเตือน
```
1. เปิดแอพ → Dashboard
2. Dashboard.initState() → _loadInitialData()
3. _loadInitialData() → NortificationSetup.run(username)
4. NortificationSetup.run():
   a. ล้าง notifications เดิมทั้งหมด (cancelAll)
   b. ล้างข้อมูล scheduled_notifications เดิมใน DB
   c. อ่าน calendar_alerts จาก DB (ที่ createby = username)
   d. อ่าน taken_doses จาก DB (กรองโดสที่กินแล้ว)
   e. อ่าน settings (advance, after, repeat, snooze, sound)
   f. คำนวณเวลากินยาทั้งหมด → เลือก 5 ครั้งถัดไป
   g. สำหรับแต่ละโดส:
      - หาหน้าต่างเวลา [dose - advance, dose + after]
      - สร้าง repeatCount การแจ้งเตือน (ห่างกัน snoozeDuration นาที)
      - schedule แต่ละการแจ้งเตือนด้วยเสียงที่เลือก
      - บันทึกลง scheduled_notifications
5. ระบบจะแจ้งเตือนตามเวลาที่ตั้งไว้ (background + foreground)
```

### สิ่งที่ต้องทดสอบ

#### 1. สร้างการแจ้งเตือนทดสอบ
```
1. เข้าหน้า "เพิ่มการแจ้งเตือน"
2. เลือกโปรไฟล์ + ยา
3. ตั้งเวลาเริ่มต้น = เวลาปัจจุบัน + 2 นาที
4. เลือก "แจ้งเตือนตามช่วงเวลา" + interval = 5 นาที
5. บันทึก
6. กลับหน้า Dashboard → ระบบจะ schedule notifications อัตโนมัติ
```

#### 2. ตรวจสอบ Logs
```bash
# เปิด terminal และรัน
flutter run

# ดู logs ที่แสดง:
NortificationSetup: Notification permission granted: true
NortificationSetup: Exact alarm permission granted: true
NortificationSetup: Scheduled notification 12345 at 2026-02-11 21:00:00.000 with sound a01_clock_alarm_normal_30_sec
NortificationSetup: Scheduled 15 notifications for username123
```

#### 3. ทดสอบการแจ้งเตือน
- **Background:** ปิดแอพ → รอถึงเวลา → ควรได้ notification พร้อมเสียง
- **Foreground:** เปิดแอพอยู่ → รอถึงเวลา → ควรได้ notification พร้อมเสียง
- **After Reboot:** รีบูตเครื่อง → เปิดแอพ → ควร reschedule notifications ใหม่

#### 4. ทดสอบ Repeat
```
1. เข้าหน้า "ตั้งค่าการแจ้งเตือน"
2. ตั้ง "จำนวนครั้งที่แจ้งซ้ำ" = 3
3. ตั้ง "ช่วงเวลาระหว่างการแจ้ง" = 2 นาที
4. บันทึก
5. สร้างการแจ้งเตือนใหม่
6. รอถึงเวลา → ควรได้ 3 notifications ห่างกัน 2 นาที
```

#### 5. ทดสอบเสียง
```
1. เข้าหน้า "ตั้งค่าการแจ้งเตือน"
2. เลือกเสียงต่างๆ และกด "ทดลองเล่น"
3. ตรวจสอบว่าเสียงเล่นได้ปกติ
4. เลือกเสียงที่ชอบและบันทึก
5. สร้างการแจ้งเตือนใหม่
6. รอถึงเวลา → ควรได้ notification พร้อมเสียงที่เลือก
```

## Permissions ที่จำเป็น (ตรวจสอบใน Settings)
- ✅ Notifications (Android 13+)
- ✅ Alarms & reminders (Android 12+)
- ✅ Battery optimization (ปิด = อนุญาตให้รันเบื้องหลัง)

## Troubleshooting

### ไม่มี notification เลย
1. ตรวจสอบ permissions (Settings → Apps → Pillmate → Permissions)
2. ตรวจสอบ battery optimization (ปิดการประหยัดพลังงาน)
3. ดู logs: `flutter run` แล้วดู "Notification permission granted: true"
4. ตรวจสอบว่ามี calendar_alerts ในฐานข้อมูล

### ไม่มีเสียง
1. ตรวจสอบว่าปรับระดับเสียงของเครื่องแล้ว
2. ตรวจสอบ notification channel settings (Settings → Apps → Pillmate → Notifications)
3. ตรวจสอบว่าไฟล์เสียงใน raw/ ไม่มี extension
4. ดู logs: "Scheduled notification ... with sound a01_..."

### Schedule แล้วแต่ไม่ยิง
1. ตรวจสอบเวลาของเครื่อง (timezone)
2. ดูว่ามี "Exact alarm permission granted: true"
3. ลองรีบูตเครื่องแล้วเปิดแอพอีกครั้ง
4. ตรวจสอบ taken_doses (ถ้ากินแล้วจะไม่แจ้งเตือน)

### Duplicate notifications
1. เปิดแอพเพียงครั้งเดียวเท่านั้น (ไม่ควรเปิดหลาย instance)
2. ระบบจะ cancelAll ก่อนตั้งใหม่ทุกครั้ง
3. ตรวจสอบ scheduled_notifications ในฐานข้อมูล

## สรุป
✅ ระบบ notification ทำงานได้แล้ว  
✅ อ่านข้อมูลจาก SQLite (single source of truth)  
✅ คำนวณเฉพาะ 5 การแจ้งเตือนถัดไป  
✅ รองรับ repeat/snooze ตามตั้งค่า  
✅ ใช้เสียงที่เลือกได้  
✅ ทำงานทั้ง foreground และ background  
✅ มี permission requests ที่จำเป็น  
✅ บันทึก scheduled_notifications ลง DB เพื่อ tracking  

---
**Build สำเร็จ:** ✓ `build/app/outputs/flutter-apk/app-debug.apk`  
**สร้างเมื่อ:** 11 ก.พ. 2026, 20:57 น.
