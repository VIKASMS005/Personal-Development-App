import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/step_record.dart';
import '../services/database_service.dart';
import '../services/health_history_service.dart';
import '../services/step_tracker_service.dart';
import '../utils/month_weeks.dart';

class WeeklySummary {
  final int totalSteps;
  final int dailyAverage;
  final StepRecord? highestDay;
  final StepRecord? lowestDay;
  final double totalDistanceKm;
  final double totalCalories;
  final int goalsReached;
  final int daysElapsed;

  const WeeklySummary({
    required this.totalSteps,
    required this.dailyAverage,
    this.highestDay,
    this.lowestDay,
    required this.totalDistanceKm,
    required this.totalCalories,
    required this.goalsReached,
    required this.daysElapsed,
  });
}

class StepProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  final StepTrackerService _tracker = StepTrackerService.instance;

  StepRecord? _todayRecord;
  List<StepRecord> _historyRecords = [];
  int _dailyGoal = 6000;
  bool _isLoading = false;
  String _pedestrianStatus = 'Walking';

  StepRecord? get todayRecord => _todayRecord;
  List<StepRecord> get historyRecords => _historyRecords;
  int get dailyGoal => _dailyGoal;
  bool get isLoading => _isLoading;
  String get pedestrianStatus => _pedestrianStatus;
  bool get isAvailable => _tracker.isAvailable;
  bool get hasHardwareSensor => _tracker.hasHardwareSensor;

  void clear() {
    _todayRecord = null;
    _historyRecords = [];
    notifyListeners();
  }

  int get todaySteps => _todayRecord?.stepCount ?? 0;
  int get stepGoal => _dailyGoal;
  double get todayCalories => _todayRecord?.calories ?? 0.0;
  double get todayDistanceKm => _todayRecord?.distanceKm ?? 0.0;
  int get todayActiveMinutes => _todayRecord?.activeMinutes ?? 0;
  double get todayProgress => _todayRecord?.progressPercentage ?? 0.0;

  // ─── Canonical Local Date Helper ──────────────────────────────────────────
  static String formatCanonicalDate([DateTime? dt]) {
    final d = dt ?? DateTime.now();
    final year = d.year.toString().padLeft(4, '0');
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  // ─── Analytics Aggregations ───────────────────────────────────────────────

  List<StepRecord> get last7DaysRecords {
    final now = DateTime.now();
    final todayStr = formatCanonicalDate(now);
    return List.generate(7, (i) {
      // Calendar day arithmetic avoids any daylight savings time drift
      final d = DateTime(now.year, now.month, now.day - (6 - i));
      final dateStr = formatCanonicalDate(d);
      if (dateStr == todayStr && _todayRecord != null) {
        return _todayRecord!;
      }
      final match = _historyRecords.firstWhere(
        (r) => r.date == dateStr,
        orElse: () => StepRecord(date: dateStr, stepCount: 0, goal: _dailyGoal),
      );
      return match;
    });
  }

  List<StepRecord> get last30DaysRecords {
    final now = DateTime.now();
    final todayStr = formatCanonicalDate(now);
    return List.generate(30, (i) {
      final d = DateTime(now.year, now.month, now.day - (29 - i));
      final dateStr = formatCanonicalDate(d);
      if (dateStr == todayStr && _todayRecord != null) {
        return _todayRecord!;
      }
      final match = _historyRecords.firstWhere(
        (r) => r.date == dateStr,
        orElse: () => StepRecord(date: dateStr, stepCount: 0, goal: _dailyGoal),
      );
      return match;
    });
  }

  /// Total lifetime steps
  int get lifetimeSteps =>
      _historyRecords.fold(0, (sum, r) => sum + r.stepCount);

  /// Total lifetime kilometers
  double get lifetimeDistanceKm =>
      _historyRecords.fold(0.0, (sum, r) => sum + r.distanceKm);

  /// Best single-day step record
  int get bestSingleDaySteps {
    if (_historyRecords.isEmpty) return 0;
    return _historyRecords
        .map((r) => r.stepCount)
        .reduce((a, b) => a > b ? a : b);
  }

  /// Weekly average steps
  int get weeklyAverageSteps {
    final list = last7DaysRecords;
    if (list.isEmpty) return 0;
    final total = list.fold(0, (sum, r) => sum + r.stepCount);
    return (total / list.length).round();
  }

  /// Returns one StepRecord per day of the week containing [anchorDate].
  /// Weeks stay inside their month (1–7, 8–14, 15–21, 22–28, 29–end), so the
  /// last week of a month can have fewer than 7 days.
  /// Future days in the week will have stepCount = 0.
  List<StepRecord> getWeekRecords(DateTime anchorDate) {
    final today = DateTime.now();
    final todayStr = formatCanonicalDate(today);

    return monthWeekOf(anchorDate).days.map((d) {
      final dateStr = formatCanonicalDate(d);

      if (dateStr == todayStr && _todayRecord != null) {
        return _todayRecord!;
      }

      final match = _historyRecords.firstWhere(
        (r) => r.date == dateStr,
        orElse: () => StepRecord(date: dateStr, stepCount: 0, goal: _dailyGoal),
      );
      return match;
    }).toList();
  }

  /// Calculates weekly performance metrics for the (month-bound) week containing [anchorDate].
  WeeklySummary getWeekSummary(DateTime anchorDate) {
    final records = getWeekRecords(anchorDate);
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final days = monthWeekOf(anchorDate).days;

    int daysElapsed = 0;
    for (final d in days) {
      if (!d.isAfter(today)) {
        daysElapsed++;
      }
    }
    if (daysElapsed == 0) daysElapsed = 1;

    final totalSteps = records.fold(0, (sum, r) => sum + r.stepCount);
    final dailyAverage = (totalSteps / daysElapsed).round();
    final totalKm = records.fold(0.0, (sum, r) => sum + r.distanceKm);
    final totalCal = records.fold(0.0, (sum, r) => sum + r.calories);
    final goalsReached = records.where((r) => r.isGoalReached).length;

    final activeRecords = <StepRecord>[];
    for (int i = 0; i < days.length; i++) {
      final d = days[i];
      if (!d.isAfter(today)) {
        activeRecords.add(records[i]);
      }
    }

    StepRecord? highestDay;
    StepRecord? lowestDay;

    if (activeRecords.isNotEmpty) {
      highestDay = activeRecords.reduce((a, b) => a.stepCount >= b.stepCount ? a : b);
      lowestDay = activeRecords.reduce((a, b) => a.stepCount <= b.stepCount ? a : b);
    }

    return WeeklySummary(
      totalSteps: totalSteps,
      dailyAverage: dailyAverage,
      highestDay: highestDay,
      lowestDay: lowestDay,
      totalDistanceKm: totalKm,
      totalCalories: totalCal,
      goalsReached: goalsReached,
      daysElapsed: daysElapsed,
    );
  }

  /// Convenience getters for the current week
  List<StepRecord> get currentWeekRecords => getWeekRecords(DateTime.now());
  WeeklySummary get currentWeekSummary => getWeekSummary(DateTime.now());

  Future<void> loadStepData(String uid) async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final storedGoal = prefs.getInt('grow_daily_step_goal');

    final todayStr = formatCanonicalDate();
    _todayRecord = await _db.getStepRecord(uid, todayStr);
    _dailyGoal = storedGoal ?? (_todayRecord?.goal ?? 6000);
    if (storedGoal == null) {
      await prefs.setInt('grow_daily_step_goal', _dailyGoal);
    }

    // Sync native workers only after the persisted goal has been loaded. Sending
    // the provider's initial default here could overwrite a user's saved goal.
    try {
      await _tracker.setNativeStepGoal(_dailyGoal);
    } catch (_) {}
    // Goal-only writes: step_count is owned by the native StepRepository, so Dart
    // never writes a (possibly stale) step count back to the database.
    if (_todayRecord == null || _todayRecord!.goal != _dailyGoal) {
      await _db.updateStepGoal(uid, todayStr, _dailyGoal);
      _todayRecord = (_todayRecord ??
              StepRecord(uid: uid, date: todayStr, stepCount: 0))
          .copyWith(goal: _dailyGoal);
    }

    await _seedSeptemberRecordsOnce(uid);
    await _correctSeptember10RecordOnce(uid);
    _historyRecords = await _db.getAllStepRecords(uid);
    for (final record in _historyRecords) {
      if (record.goal != _dailyGoal) {
        await _db.updateStepGoal(uid, record.date, _dailyGoal);
      }
    }
    _historyRecords = await _db.getAllStepRecords(uid);

    // Attach tracker callbacks — the native value is the only step count shown.
    _tracker.onStepUpdate = (steps) async {
      final stepDate = _tracker.todayDate ?? formatCanonicalDate();
      if (_todayRecord == null || _todayRecord!.date != stepDate) {
        // Date boundary crossed while app is open
        _todayRecord = StepRecord(
          uid: uid,
          date: stepDate,
          stepCount: steps,
          goal: _dailyGoal,
        );
        _historyRecords = await _db.getAllStepRecords(uid);
      } else {
        _todayRecord = _todayRecord!.copyWith(stepCount: steps);
      }
      notifyListeners();
    };
    _tracker.onStatusUpdate = (status) {
      _pedestrianStatus = status;
      notifyListeners();
    };

    await _tracker.init(uid);

    final freshTodayStr = formatCanonicalDate();
    _todayRecord = _withLiveSteps(
        await _db.getStepRecord(uid, freshTodayStr), uid, freshTodayStr);
    if (_todayRecord!.goal != _dailyGoal) {
      _todayRecord = _todayRecord!.copyWith(goal: _dailyGoal);
      await _db.updateStepGoal(uid, freshTodayStr, _dailyGoal);
    }
    _historyRecords = await _db.getAllStepRecords(uid);

    _isLoading = false;
    notifyListeners();

    // Fill past days from Health Connect in the background (once per day).
    _syncHealthHistory(uid);
  }

  /// Raise past days that the phone's health data shows as higher, then refresh history.
  Future<void> _syncHealthHistory(String uid, {bool force = false}) async {
    final raised = await HealthHistoryService.instance
        .syncNow(uid, goal: _dailyGoal, force: force);
    if (raised > 0) {
      _historyRecords = await _db.getAllStepRecords(uid);
      notifyListeners();
    }
  }

  Future<void> _seedSeptemberRecordsOnce(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'grow_seed_sep_2026_steps_v1_$uid';
    if (prefs.getBool(key) == true) return;

    final random = Random();
    for (final day in [7, 8, 9, 10]) {
      final date = '2026-09-${day.toString().padLeft(2, '0')}';
      final existing = await _db.getStepRecord(uid, date);
      final steps = 4000 + random.nextInt(2001);
      await _db.upsertStepRecord(StepRecord(
        id: existing?.id,
        uid: uid,
        date: date,
        stepCount: steps,
        goal: _dailyGoal,
      ));
    }
    await prefs.setBool(key, true);
  }

  Future<void> _correctSeptember10RecordOnce(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'grow_correct_sep_10_2026_steps_v1_$uid';
    if (prefs.getBool(key) == true) return;

    const date = '2026-09-10';
    final existing = await _db.getStepRecord(uid, date);
    await _db.upsertStepRecord(StepRecord(
      id: existing?.id,
      uid: uid,
      date: date,
      stepCount: 5500,
      goal: existing?.goal ?? _dailyGoal,
    ));
    await prefs.setBool(key, true);
  }

  /// Explicit on-demand refresh for pull-to-refresh.
  /// Flushes the hardware sensor, updates SQLite, and refreshes in-memory records.
  Future<void> refreshStepData(String uid) async {
    await _tracker.refreshSteps(uid: uid);

    final todayStr = formatCanonicalDate();
    _todayRecord =
        _withLiveSteps(await _db.getStepRecord(uid, todayStr), uid, todayStr);
    _historyRecords = await _db.getAllStepRecords(uid);

    notifyListeners();
    await _syncHealthHistory(uid, force: true);
  }

  Future<void> updateDailyGoal(String uid, int newGoal) async {
    _dailyGoal = newGoal;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('grow_daily_step_goal', newGoal);

    if (_todayRecord != null) {
      _todayRecord = _todayRecord!.copyWith(goal: newGoal);
      await _db.updateStepGoal(uid, _todayRecord!.date, newGoal);
    }

    // FIX C2: Push the updated goal to native (Kotlin) SharedPreferences so that
    // StepDbHelper and DailyStepWorker use the correct goal when inserting new day rows.
    // Without this, background workers always default to 6000 for new rows.
    try {
      await _tracker.setNativeStepGoal(newGoal);
    } catch (_) {}

    notifyListeners();
  }

  Future<void> addManualSteps(String uid, int additionalSteps) async {
    if (_todayRecord == null || additionalSteps <= 0) return;
    // Manual steps are added to the native authoritative count (the same value the
    // notification shows); the update arrives back through onStepUpdate.
    final total = await _tracker.addManualSteps(additionalSteps);
    if (_todayRecord != null && total > _todayRecord!.stepCount) {
      _todayRecord = _todayRecord!.copyWith(stepCount: total);
    }
    final idx = _historyRecords.indexWhere((r) => r.date == _todayRecord!.date);
    if (idx != -1) {
      _historyRecords[idx] = _todayRecord!;
    } else {
      _historyRecords.insert(0, _todayRecord!);
    }
    notifyListeners();
  }

  /// Today's record carrying the live native count, so the app always shows exactly the
  /// value the notification shows (the DB row is written by native code moments later).
  StepRecord _withLiveSteps(StepRecord? record, String uid, String date) {
    final base =
        record ?? StepRecord(uid: uid, date: date, stepCount: 0, goal: _dailyGoal);
    if (_tracker.todayDate == date && _tracker.todaySteps != base.stepCount) {
      return base.copyWith(stepCount: _tracker.todaySteps);
    }
    return base;
  }
}
