import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_service.dart';

/// HealthHistoryService — fills in step counts for PAST days from Android Health Connect.
///
/// The phone's own step sensor only keeps one running total since boot, so days the app
/// missed (service killed, app not installed yet, or recorded by the old buggy counter)
/// cannot be rebuilt from it. Health Connect keeps per-day history written by Google Fit,
/// Samsung Health, the system pedometer on newer Android versions, wearables, etc.
///
/// Rules:
///  * Only days BEFORE today are touched. Today stays owned by the native StepRepository,
///    so the app and the notification keep showing the same live number.
///  * A day is only ever raised, never lowered (see DatabaseService.raiseStepCount).
///  * The permission prompt is shown at most once automatically; after that the user can
///    trigger it again with [syncNow(prompt: true)].
class HealthHistoryService {
  static final HealthHistoryService instance = HealthHistoryService._internal();
  HealthHistoryService._internal();

  static const _types = [HealthDataType.STEPS];
  static const _access = [HealthDataAccess.READ];
  static const _promptedKey = 'grow_hc_permission_prompted';
  static const _lastSyncKey = 'grow_hc_last_sync_date';

  /// How many past days to fill in.
  static const int backfillDays = 90;

  final Health _health = Health();
  bool _configured = false;
  bool _running = false;

  /// Returns the number of days whose step count was raised from Health Connect.
  /// [force] re-reads even if a sync already ran today; [prompt] allows showing the
  /// permission dialog again after the first automatic attempt.
  Future<int> syncNow(String uid,
      {required int goal, bool force = false, bool prompt = false}) async {
    if (kIsWeb || !Platform.isAndroid || _running) return 0;
    _running = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = _dateStr(DateTime.now());
      if (!force && prefs.getString(_lastSyncKey) == today) return 0;

      if (!_configured) {
        await _health.configure();
        _configured = true;
      }
      if (!await _health.isHealthConnectAvailable()) {
        debugPrint('[HealthHistory] Health Connect not available on this device');
        return 0;
      }

      var granted = await _health.hasPermissions(_types, permissions: _access) ?? false;
      if (!granted) {
        final alreadyPrompted = prefs.getBool(_promptedKey) ?? false;
        if (alreadyPrompted && !prompt) return 0;
        await prefs.setBool(_promptedKey, true);
        granted = await _health.requestAuthorization(_types, permissions: _access);
        if (!granted) return 0;
      }

      // Without this, Health Connect only returns the last 30 days.
      try {
        if (await _health.isHealthDataHistoryAvailable() &&
            !await _health.isHealthDataHistoryAuthorized()) {
          await _health.requestHealthDataHistoryAuthorization();
        }
      } catch (e) {
        debugPrint('[HealthHistory] history authorization skipped: $e');
      }

      final raised = await _backfill(uid, goal);
      await prefs.setString(_lastSyncKey, today);
      debugPrint('[HealthHistory] raised $raised day(s) from Health Connect');
      return raised;
    } catch (e) {
      debugPrint('[HealthHistory] sync failed: $e');
      return 0;
    } finally {
      _running = false;
    }
  }

  static const _inventedDaysRepairedKey = 'grow_repair_invented_sep_2026_steps_v1';

  /// An earlier build wrote random counts (4,000–6,000) for 7–9 Sep 2026 and a
  /// fixed 5,500 for 10 Sep 2026, over whatever was stored. Those values are not
  /// the user's activity. This replaces each of those days with the phone's own
  /// Health Connect total when it has one, and otherwise deletes the row so the
  /// day shows no data. Runs once. Returns true if anything changed.
  Future<bool> repairInventedSeptemberDays(String uid, {required int goal}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_inventedDaysRepairedKey}_$uid';
    if (prefs.getBool(key) == true) return false;
    // Only users who ran the build that wrote them have these rows.
    if (prefs.getBool('grow_seed_sep_2026_steps_v1_$uid') != true &&
        prefs.getBool('grow_correct_sep_10_2026_steps_v1_$uid') != true) {
      await prefs.setBool(key, true);
      return false;
    }

    // Read the real totals first; if Health Connect fails mid-way, try again next launch.
    final real = <String, int>{};
    var canRead = false;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        if (!_configured) {
          await _health.configure();
          _configured = true;
        }
        canRead = await _health.isHealthConnectAvailable() &&
            (await _health.hasPermissions(_types, permissions: _access) ?? false);
      } catch (e) {
        debugPrint('[HealthHistory] repair: availability check failed: $e');
        return false;
      }
    }
    for (final day in [7, 8, 9, 10]) {
      final start = DateTime(2026, 9, day);
      final end = DateTime(2026, 9, day + 1);
      if (!canRead) continue;
      try {
        final steps = await _health.getTotalStepsInInterval(start, end);
        if (steps != null && steps > 0) real[_dateStr(start)] = steps;
      } catch (e) {
        debugPrint('[HealthHistory] repair: read failed for ${_dateStr(start)}: $e');
        return false;
      }
    }

    final db = DatabaseService.instance;
    for (final day in [7, 8, 9, 10]) {
      final date = _dateStr(DateTime(2026, 9, day));
      final steps = real[date];
      if (steps != null) {
        await db.setStepCountExactly(uid, date, steps, goal);
      } else {
        await db.deleteStepRecord(uid, date);
      }
    }
    await prefs.setBool(key, true);
    return true;
  }

  Future<int> _backfill(String uid, int goal) async {
    final db = DatabaseService.instance;
    final now = DateTime.now();
    var raised = 0;
    // Start from yesterday; today is owned by the native step counter.
    for (var i = 1; i <= backfillDays; i++) {
      final start = DateTime(now.year, now.month, now.day - i);
      final end = DateTime(now.year, now.month, now.day - i + 1);
      int? steps;
      try {
        steps = await _health.getTotalStepsInInterval(start, end);
      } catch (e) {
        debugPrint('[HealthHistory] read failed for ${_dateStr(start)}: $e');
      }
      if (steps == null || steps <= 0) continue;
      if (await db.raiseStepCount(uid, _dateStr(start), steps, goal)) raised++;
    }
    return raised;
  }

  static String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
