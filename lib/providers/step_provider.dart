import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/step_record.dart';
import '../services/database_service.dart';
import '../services/step_tracker_service.dart';

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

  Future<void> loadStepData(String uid) async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    _dailyGoal = prefs.getInt('grow_daily_step_goal') ?? 6000;

    final todayStr = formatCanonicalDate();
    _todayRecord = await _db.getStepRecord(uid, todayStr);
    if (_todayRecord == null) {
      _todayRecord = StepRecord(
        uid: uid,
        date: todayStr,
        stepCount: 0,
        goal: _dailyGoal,
      );
      await _db.upsertStepRecord(_todayRecord!);
    }

    _historyRecords = await _db.getAllStepRecords(uid);

    // Attach tracker callbacks
    _tracker.onStepUpdate = (steps) async {
      final currentTodayStr = formatCanonicalDate();
      if (_todayRecord == null || _todayRecord!.date != currentTodayStr) {
        // Date boundary crossed while app is open
        _todayRecord = StepRecord(
          uid: uid,
          date: currentTodayStr,
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
    _todayRecord = await _db.getStepRecord(uid, freshTodayStr);
    _historyRecords = await _db.getAllStepRecords(uid);

    _isLoading = false;
    notifyListeners();
  }

  /// Explicit on-demand refresh for pull-to-refresh.
  /// Flushes the hardware sensor, updates SQLite, and refreshes in-memory records.
  Future<void> refreshStepData(String uid) async {
    await _tracker.refreshSteps(uid: uid);

    final todayStr = formatCanonicalDate();
    _todayRecord = await _db.getStepRecord(uid, todayStr);
    _historyRecords = await _db.getAllStepRecords(uid);

    notifyListeners();
  }

  Future<void> updateDailyGoal(String uid, int newGoal) async {
    _dailyGoal = newGoal;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('grow_daily_step_goal', newGoal);

    if (_todayRecord != null) {
      _todayRecord = _todayRecord!.copyWith(goal: newGoal);
      await _db.upsertStepRecord(_todayRecord!);
    }
    notifyListeners();
  }

  Future<void> addManualSteps(String uid, int additionalSteps) async {
    if (_todayRecord == null) return;
    final current = _todayRecord!.stepCount;
    final updated = _todayRecord!.copyWith(stepCount: current + additionalSteps);
    _todayRecord = updated;
    await _db.upsertStepRecord(updated);

    final idx = _historyRecords.indexWhere((r) => r.id == updated.id);
    if (idx != -1) {
      _historyRecords[idx] = updated;
    } else {
      _historyRecords.insert(0, updated);
    }
    notifyListeners();
  }
}
