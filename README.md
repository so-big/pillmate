# 💊 Pillmate — Smart Medication Reminder & Compliance Tracker

> A Flutter-based mobile application that helps patients and caregivers manage medication schedules, verify drug intake via NFC tag scanning, and receive persistent, configurable audio notifications — ensuring no dose is ever missed.

---

## 📖 The "Why" (Business Value)

### The Problem
Medication non-adherence is a global healthcare crisis. The WHO estimates that **50% of patients with chronic diseases** do not take their medications as prescribed. This leads to disease progression, hospitalizations, and preventable deaths. Elderly patients, patients managing multiple drugs, and caregivers managing medications for dependents are the most affected.

### The Solution
**Pillmate** provides a multi-layered safety net:

1.  **Scheduled Reminders:** Time-interval-based alerts that ring persistently until acknowledged.
2.  **NFC Verification:** An optional mode where patients must physically scan an NFC tag attached to their pill box to confirm they've taken the correct medicine. This prevents "dismissing the alarm and forgetting."
3.  **Multi-Profile Management:** A single "Master" user (e.g., a caregiver or family member) can create and manage medication schedules for multiple dependents (e.g., elderly parents, children).
4.  **Dose History Tracking:** A calendar view and daily dashboard show which doses were taken and which were missed.

### Target Audience
- Elderly patients or their caregivers.
- Patients with chronic conditions requiring complex drug regimens.
- Families managing medication for multiple members.
- Thai-speaking users (the entire UI is in Thai, `th_TH` locale).

---

## 🏗️ Current Architecture

### Tech Stack

| Layer              | Technology                                                                 |
|--------------------|----------------------------------------------------------------------------|
| **Framework**      | Flutter (Dart) — Cross-platform (Android, iOS, Linux, Windows, Web)        |
| **Local Database** | SQLite via `sqflite` package ([`DatabaseHelper`](lib/database_helper.dart)) |
| **Local Storage**  | JSON files on disk (`path_provider`) for settings, session state, and notification logs |
| **NFC**            | `flutter_nfc_kit` + `ndef` packages                                        |
| **Notifications**  | `flutter_local_notifications` + `flutter_timezone` + `timezone`            |
| **Image Handling** | `image_picker`, manual Base64 encoding/decoding, raw `dart:ui` canvas ops  |
| **State Mgmt**     | `setState` (vanilla StatefulWidget) — no external state management library |
| **Backend**        | **None.** This is a fully offline, client-side application.                |

### Data Flow & Logic

```
┌─────────────────────────────────────────────────────────┐
│                       UI Layer                          │
│  main.dart (Login) → view_dashboard.dart (Hub)          │
│  ├── view_carlendar.dart (Weekly calendar view)         │
│  ├── add_carlendar.dart (Create reminder + NFC write)   │
│  ├── edit_carlendar.dart (Edit reminder + NFC rewrite)  │
│  ├── add_medicine.dart / edit_medicine.dart / manage_*   │
│  ├── create_profile.dart / edit_Profile.dart / manage_*  │
│  ├── nortification_setting.dart (Sound & snooze config) │
│  └── view_menu.dart (Drawer navigation)                 │
├─────────────────────────────────────────────────────────┤
│                    Service Layer                        │
│  nortification_service.dart (Background dose finder)    │
│  nortification_next.dart (Batch schedule next 2 days)   │
│  database_helper.dart (SQLite singleton)                │
├─────────────────────────────────────────────────────────┤
│                    Data Layer                           │
│  SQLite DB: users, medicines, calendar_alerts, eated    │
│  JSON Files: user-stat.json, appstatus.json,            │
│              nortification_setup.json                   │
│  Assets: pill images, profile avatars, alarm sounds     │
└─────────────────────────────────────────────────────────┘
```

### Key Architectural Decisions
- **Hybrid Storage:** The app uses SQLite as the primary database ([`DatabaseHelper`](lib/database_helper.dart)) but *also* reads/writes raw JSON files to disk for settings (`appstatus.json`), session persistence (`user-stat.json`), and notification scheduling logs. This creates a dual-source-of-truth problem.
- **Offline-First:** There is **no server, no API, no cloud sync**. All data lives on the device. If the device is lost, all data is lost.
- **NFC as Verification:** NFC tags are written with a structured payload (`medicineName~detail~e=flag~et=interval~profileName`) and read back to verify the patient is taking the correct drug.

---

## ✅ Key Features (What Works Now)

| Feature | File(s) | Description |
|---|---|---|
| **User Auth (Local)** | [`main.dart`](lib/main.dart), [`create_account.dart`](lib/create_account.dart) | Username/password login stored in local SQLite. "Remember Me" via JSON file. Security questions for password recovery. |
| **Multi-Profile** | [`create_profile.dart`](lib/create_profile.dart), [`manage_profile.dart`](lib/manage_profile.dart), [`edit_Profile.dart`](lib/edit_Profile.dart) | Master user can create sub-profiles with custom avatars (asset or camera), names, info, and per-profile meal times. |
| **Medicine Management** | [`add_medicine.dart`](lib/add_medicine.dart), [`edit_medicine.dart`](lib/edit_medicine.dart), [`manage_medicine.dart`](lib/manage_medicine.dart) | CRUD for medicines with name, detail, before/after meal flag, and pill images (asset or gallery with crop/resize). |
| **Calendar Alerts (Reminders)** | [`add_carlendar.dart`](lib/add_carlendar.dart), [`edit_carlendar.dart`](lib/edit_carlendar.dart) | Create time-interval-based reminders linking a medicine to a profile, with start/end dates and NFC tag binding. |
| **Dashboard** | [`view_dashboard.dart`](lib/view_dashboard.dart) | Daily view with horizontal date pager. Shows all doses for the day, their taken/scanning status, and quick actions. |
| **Calendar View** | [`view_carlendar.dart`](lib/view_carlendar.dart) | Weekly calendar showing scheduled medications per day. |
| **NFC Read/Write** | [`add_carlendar.dart`](lib/add_carlendar.dart), [`edit_carlendar.dart`](lib/edit_carlendar.dart), [`view_dashboard.dart`](lib/view_dashboard.dart) | Write medicine data to NFC tags when creating reminders; read and verify NFC tags when confirming dose intake. |
| **Local Notifications** | [`nortification_service.dart`](lib/nortification_service.dart), [`nortification_next.dart`](lib/nortification_next.dart) | Schedule OS-level notifications with custom alarm sounds and configurable snooze/repeat. |
| **Notification Settings** | [`nortification_setting.dart`](lib/nortification_setting.dart) | Choose alarm sound, snooze interval (min 2 min), and repeat count (1–10). |
| **Forgot Password** | [`forgotPassword.dart`](lib/forgotPassword.dart) | Security question-based password recovery flow. |
| **Account Editing** | [`edit_account.dart`](lib/edit_account.dart) | Edit avatar, password, security question, and per-profile meal times. |

---

## 🔧 Setup & Installation

### Prerequisites
- Flutter SDK (stable channel, ≥ 3.x recommended)
- Android Studio or Xcode (for emulators)
- A physical Android device with NFC for full feature testing

### Steps

```bash
# 1. Clone the repository
git clone <repository-url>
cd pillmate

# 2. Install dependencies
flutter pub get

# 3. Ensure assets are declared in pubspec.yaml
#    (pill images, profile avatars, sounds, DB seed files)

# 4. Run on a connected device or emulator
flutter run

# 5. For Android release build
flutter build apk --release
```

### Important Notes
- The SQLite database is bootstrapped from [`assets/db/`](assets/db/) on first launch. See [`DatabaseHelper.initDatabase()`](lib/database_helper.dart).
- The `appstatus.json` settings file is copied from [`assets/db/appstatus.json`](assets/db/appstatus.json) on first launch. See [`_initializeAppStatusFile()`](lib/main.dart).
- NFC features require a physical device with NFC hardware. They will gracefully degrade (manual mode) if NFC is disabled.

---

## ⚠️ The Analysis & Critique

### 🔴 Critical Red Flags

#### 1. **Plaintext Password Storage** — SEVERITY: CRITICAL
Passwords are stored **in plaintext** in the SQLite database. There is no hashing, no salting, no encryption whatsoever.

```dart
// filepath: lib/edit_carlendar.dart (line ~693)
if (user['password'] == inputPassword) {
  return true;
}
```

The same pattern exists in [`manage_profile.dart`](lib/manage_profile.dart), [`view_dashboard.dart`](lib/view_dashboard.dart), and [`edit_account.dart`](lib/edit_account.dart). Passwords are also written to `user-stat.json` on disk in plaintext for the "Remember Me" feature (see [`main.dart`](lib/main.dart) line ~240).

#### 2. **No Database Encryption**
The SQLite database file is stored unencrypted on the device filesystem. Any rooted device or backup extraction tool can read all user data, medications, and health information.

#### 3. **Session Credentials on Disk in Plaintext**
The "Remember Me" feature writes `{ "username": "...", "password": "..." }` to a JSON file. See [`_saveUserStat()`](lib/main.dart).

#### 4. **Hardcoded Timezone**
The notification system hardcodes `Asia/Bangkok` in [`nortification_next.dart`](lib/nortification_next.dart) (line ~108):
```dart
return 'Asia/Bangkok';
```
This will break for any user outside the ICT timezone.

### 🟡 Architectural Concerns

#### 5. **Dual Source of Truth**
Data is split between SQLite and raw JSON files. Notification settings live in `appstatus.json`, reminder data is queried from SQLite, but [`nortification_next.dart`](lib/nortification_next.dart) reads from `reminders.json` and `eated.json` files (lines 48–56). This creates synchronization bugs.

#### 6. **No State Management**
The entire application uses `setState` with massive `StatefulWidget` classes. [`view_dashboard.dart`](lib/view_dashboard.dart) is a single file with **1200+ lines** containing UI, business logic, NFC scanning, file I/O, database queries, and notification scheduling all interleaved.

#### 7. **No Separation of Concerns**
There are no models, no repositories, no services (beyond the notification files), no dependency injection. Business logic is embedded directly in widget `build()` methods and `onPressed` handlers.

#### 8. **Inconsistent Naming Conventions**
- `nortification_*` (misspelled "notification" throughout the entire codebase)
- `edit_Profile.dart` (capital P) vs `edit_medicine.dart` (lowercase)
- `add_carlendar.dart` (misspelled "calendar")
- `CarlendarEditSheet` class name

#### 9. **No Tests**
The `test/` directory exists but contains no meaningful test files based on the project structure. Zero unit tests, zero widget tests, zero integration tests.

#### 10. **No Error Boundaries or Crash Reporting**
Errors are caught with `try/catch` and silently `debugPrint`-ed. There is no crash reporting (Sentry, Firebase Crashlytics, etc.).

#### 11. **Image Handling Bloat**
Profile and medicine images are stored as **full Base64 strings** in the SQLite database. This will cause severe performance degradation as the database grows, since every query that touches these tables pulls massive Base64 blobs into memory.

#### 12. **No Localization Framework**
Despite being entirely in Thai, the app uses **hardcoded Thai strings** everywhere. There is no `intl`, no `.arb` files, no localization infrastructure. Adding English or any other language would require touching every single file.

#### 13. **Manual NFC Payload Parsing**
NFC payloads use a custom tilde-delimited format (`name~detail~e=flag~et=interval~profile`) that is parsed with string splitting. No schema validation, no versioning.

### 🟢 What's Done Well
- The **feature scope is ambitious and complete** for a student/personal project. NFC verification is a genuinely creative idea.
- The **UI is consistent** with a teal/green medical theme and proper Thai typography.
- **Graceful NFC degradation** — the app works in "manual mode" when NFC is disabled.
- [`DatabaseHelper`](lib/database_helper.dart) properly uses a **singleton pattern** for the database connection.

---

## 🚀 Future Roadmap (The Revival Plan)

### 🏃 Short-Term: Quick Wins (1–2 Sprints)

| # | Action | Impact |
|---|--------|--------|
| 1 | **Hash all passwords** using `bcrypt` or `argon2`. Migrate existing plaintext passwords on first login. | 🔒 Critical security fix |
| 2 | **Remove password from `user-stat.json`**. Use a secure token or `flutter_secure_storage` for session persistence. | 🔒 Critical security fix |
| 3 | **Fix the timezone hardcoding**. Use `FlutterTimezone.getLocalTimezone()` consistently (it's already imported in [`nortification_service.dart`](lib/nortification_service.dart) but not used in [`nortification_next.dart`](lib/nortification_next.dart)). | 🐛 Bug fix |
| 4 | **Fix typos in filenames and classes**: `nortification` → `notification`, `carlendar` → `calendar`, `edit_Profile` → `edit_profile`. Use a rename script + IDE refactor. | 🧹 Code hygiene |
| 5 | **Add `.gitignore` for `android/build/`**. The `android/build/reports/` directory is committed to version control with a 660+ line HTML report. | 🧹 Repo hygiene |
| 6 | **Store images as files on disk**, reference by path in DB instead of Base64 blobs. Migrate existing data. | ⚡ Performance |

### 🏗️ Mid-Term: Modernization (1–3 Months)

| # | Action | Impact |
|---|--------|--------|
| 7 | **Introduce state management** — Riverpod 2.0 or Bloc. Extract all business logic from widgets into providers/cubits. | 🏗️ Architecture |
| 8 | **Create a proper data layer**: `models/`, `repositories/`, `services/`. Define Dart data classes with `freezed` + `json_serializable`. | 🏗️ Architecture |
| 9 | **Eliminate JSON file storage**. Consolidate all data into SQLite. Use a proper `shared_preferences` or SQLite table for app settings. | 🏗️ Data integrity |
| 10 | **Add `flutter_intl` / `intl`** for localization. Extract all Thai strings into `.arb` files. Add English as a second language. | 🌍 Accessibility |
| 11 | **Encrypt the database** using `sqflite_sqlcipher` or `drift` with encryption. | 🔒 Security |
| 12 | **Write tests**: Unit tests for business logic, widget tests for forms, integration tests for the NFC flow. Aim for 70%+ coverage. | ✅ Reliability |
| 13 | **Add CI/CD**: GitHub Actions for `flutter analyze`, `flutter test`, and automated APK/IPA builds. | 🚀 DevOps |
| 14 | **Replace manual NFC payload parsing** with a structured format (JSON or Protobuf) with schema versioning. | 🏗️ Maintainability |

### 🔭 Long-Term: Vision (3–12 Months)

| # | Action | Impact |
|---|--------|--------|
| 15 | **Cloud Sync & Multi-Device Support**: Add a backend (Firebase / Supabase / custom API) for cross-device sync. A caregiver's phone and the patient's phone should stay in sync. | ☁️ Product expansion |
| 16 | **Caregiver Dashboard (Web)**: A web portal where caregivers can monitor medication adherence across all dependents remotely. | 📊 Product expansion |
| 17 | **AI-Powered Drug Interaction Checker**: Integrate a drug interaction database (e.g., RxNorm, OpenFDA) to warn when newly added medicines conflict with existing ones. | 🤖 AI feature |
| 18 | **Smart Reminders with ML**: Use on-device ML to learn the patient's actual medication-taking patterns and optimize reminder timing (e.g., "this patient always takes their morning pill at 7:30, not 6:00"). | 🤖 AI feature |
| 19 | **Bluetooth Pill Dispenser Integration**: Partner with hardware manufacturers to integrate with smart pill dispensers via BLE, replacing NFC tags. | 🔌 IoT integration |
| 20 | **Health Data Export**: Generate PDF/CSV adherence reports that can be shared with doctors. Integrate with Apple Health / Google Fit. | 📋 Clinical utility |
| 21 | **Accessibility Audit**: Add screen reader support, high-contrast mode, and larger touch targets for elderly users. | ♿ Accessibility |
| 22 | **Migrate to Drift (formerly Moor)**: Replace raw `sqflite` with `drift` for type-safe, reactive database queries with migration support. | 🏗️ DX improvement |

---

## 📁 Project Structure

```
lib/
├── main.dart                    # Entry point, login page, app initialization
├── database_helper.dart         # SQLite singleton (users, medicines, calendar_alerts, eated)
├── view_dashboard.dart          # Main hub — daily dose view, NFC scan, mark-as-taken
├── view_carlendar.dart          # Weekly calendar view
├── view_menu.dart               # Drawer/navigation menu
├── add_carlendar.dart           # Create new reminder (+ NFC write)
├── edit_carlendar.dart          # Edit existing reminder (+ NFC rewrite)
├── add_medicine.dart            # Add new medicine to the database
├── edit_medicine.dart           # Edit existing medicine
├── manage_medicine.dart         # List/sort/delete medicines
├── create_profile.dart          # Create sub-profile (dependent)
├── edit_Profile.dart            # Edit sub-profile
├── manage_profile.dart          # List/edit/delete profiles
├── create_account.dart          # New user registration
├── edit_account.dart            # Edit account settings
├── forgotPassword.dart          # Security-question-based password recovery
├── nortification_service.dart   # Core notification logic (find next dose, schedule OS alerts)
├── nortification_next.dart      # Batch schedule notifications for next 2 days
└── nortification_setting.dart   # UI for notification sound/snooze configuration
```

---

## 📄 License

Not specified. Please add a `LICENSE` file before open-sourcing.

---

## 🤝 Contributing

This project is currently in a **stabilization phase**. Before contributing new features, priority should be given to the Short-Term items in the roadmap above, particularly the security fixes (items 1–2).

---

*This README was generated as a strategic handover document. It reflects the state of the codebase as of its last commit and is intended to guide the next development team.*