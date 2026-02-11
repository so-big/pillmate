// lib/providers/providers.dart
//
// Riverpod providers for the entire app.
// Centralizes all state management and dependency injection.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database_helper.dart';
import '../services/auth_service.dart';

// ---------------------------------------------------------------------------
// DATABASE
// ---------------------------------------------------------------------------

/// Global DatabaseHelper instance provider.
final databaseProvider = Provider<DatabaseHelper>((ref) {
  return DatabaseHelper();
});

// ---------------------------------------------------------------------------
// AUTH STATE
// ---------------------------------------------------------------------------

/// Holds the currently logged-in username (null = not logged in).
final currentUsernameProvider = StateProvider<String?>((ref) => null);

/// Auth service provider (stateless utility, no instance needed).
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

// ---------------------------------------------------------------------------
// MEDICINE STATE
// ---------------------------------------------------------------------------

/// Fetches all medicines for the current user.
final medicinesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final username = ref.watch(currentUsernameProvider);
  if (username == null) return [];
  final db = ref.read(databaseProvider);
  return await db.getMedicines(username);
});

// ---------------------------------------------------------------------------
// PROFILE STATE
// ---------------------------------------------------------------------------

/// Fetches all sub-profiles for the current user.
final subProfilesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final username = ref.watch(currentUsernameProvider);
  if (username == null) return [];
  final db = ref.read(databaseProvider);
  return await db.getSubProfiles(username);
});

/// Fetches the current user's full profile data.
final currentUserProfileProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final username = ref.watch(currentUsernameProvider);
  if (username == null) return null;
  final db = ref.read(databaseProvider);
  return await db.getUser(username);
});

// ---------------------------------------------------------------------------
// CALENDAR ALERTS STATE
// ---------------------------------------------------------------------------

/// Fetches all calendar alerts for the current user.
final calendarAlertsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final username = ref.watch(currentUsernameProvider);
  if (username == null) return [];
  final db = ref.read(databaseProvider);
  return await db.getCalendarAlerts(username);
});

// ---------------------------------------------------------------------------
// TAKEN DOSES STATE
// ---------------------------------------------------------------------------

/// Fetches all taken dose records for the current user.
final takenDosesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final username = ref.watch(currentUsernameProvider);
  if (username == null) return [];
  final db = ref.read(databaseProvider);
  return await db.getTakenDoses(username);
});

// ---------------------------------------------------------------------------
// NFC STATE
// ---------------------------------------------------------------------------

/// Whether NFC is enabled for the current session.
final nfcEnabledProvider = StateProvider<bool>((ref) => false);
