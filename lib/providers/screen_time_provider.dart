import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/screen_time_record.dart';
import '../services/screen_time_service.dart';
import '../services/database_service.dart';

class ScreenTimeProvider extends ChangeNotifier {
  final ScreenTimeService _service = ScreenTimeService.instance;
  final DatabaseService _db = DatabaseService.instance;
  static const _channel = MethodChannel('com.grow.app/settings');

  DailyScreenTimeSummary? _todaySummary;
  List<DailyScreenTimeSummary> _weeklySummaries = [];
  List<DailyScreenTimeSummary> _prevWeeklySummaries = [];
  bool _isLoading = false;
  bool _hasPermission = true;
  bool _permissionChecked = false;

  DailyScreenTimeSummary? get todaySummary => _todaySummary;
  List<DailyScreenTimeSummary> get weeklySummaries => _weeklySummaries;
  List<DailyScreenTimeSummary> get prevWeeklySummaries => _prevWeeklySummaries;
  bool get isLoading => _isLoading;
  bool get hasPermission => _hasPermission;
  bool get permissionChecked => _permissionChecked;

  String get todayFormattedTotal {
    if (_todaySummary == null) return '0h 0m';
    final dur = _todaySummary!.totalDuration;
    final h = dur.inHours;
    final m = dur.inMinutes % 60;
    return '${h}h ${m}m';
  }

  double get weeklyDailyAverageHours {
    if (_weeklySummaries.isEmpty) return 0.0;
    final totalSec =
        _weeklySummaries.fold(0, (sum, s) => sum + s.totalDuration.inSeconds);
    return (totalSec / (_weeklySummaries.length * 3600.0));
  }

  Duration get thisWeekTotalDuration {
    final sec =
        _weeklySummaries.fold(0, (sum, s) => sum + s.totalDuration.inSeconds);
    return Duration(seconds: sec);
  }

  Duration get lastWeekTotalDuration {
    final sec = _prevWeeklySummaries.fold(
        0, (sum, s) => sum + s.totalDuration.inSeconds);
    return Duration(seconds: sec);
  }

  /// Percentage change in screen time compared to previous week (e.g. -12.5% or +8.0%)
  double get weeklyPercentChange {
    final lastSec = lastWeekTotalDuration.inSeconds;
    final thisSec = thisWeekTotalDuration.inSeconds;
    if (lastSec <= 0) return 0.0;
    return ((thisSec - lastSec) / lastSec) * 100.0;
  }

  Future<DailyScreenTimeSummary> _summaryForRange({
    required String uid,
    required DateTime startDate,
    required DateTime endDate,
    required String dateLabel,
  }) async {
    final live = await _service.getSummaryForRange(
      startDate: startDate,
      endDate: endDate,
      dateLabel: dateLabel,
    );
    if (live.totalDuration > Duration.zero) {
      if (startDate.year == endDate.year &&
          startDate.month == endDate.month &&
          startDate.day == endDate.day) {
        await _db.upsertScreenTimeSummary(uid, live);
      }
      return live;
    }

    final apps = <AppUsageRecord>[];
    var total = Duration.zero;
    final categories = <String, Duration>{};
    var day = DateTime(startDate.year, startDate.month, startDate.day);
    final lastDay = DateTime(endDate.year, endDate.month, endDate.day);
    while (!day.isAfter(lastDay)) {
      final stored = await _db.getScreenTimeSummary(uid, _dateKey(day));
      if (stored != null) {
        total += stored.totalDuration;
        apps.addAll(stored.appUsages);
        for (final entry in stored.categoryBreakdown.entries) {
          categories[entry.key] =
              (categories[entry.key] ?? Duration.zero) + entry.value;
        }
      }
      day = day.add(const Duration(days: 1));
    }
    return DailyScreenTimeSummary(
      date: dateLabel,
      totalDuration: total,
      appUsages: apps,
      categoryBreakdown: categories,
    );
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> loadScreenTime(
      {bool isResume = false, String uid = 'local_user'}) async {
    if (!Platform.isAndroid) return;

    if (isResume &&
        _weeklySummaries.isNotEmpty &&
        _prevWeeklySummaries.isNotEmpty) {
      try {
        final todayStr = DateTime.now().toIso8601String().split('T')[0];
        final now = DateTime.now();
        _todaySummary = await _summaryForRange(
          uid: uid,
          startDate: DateTime(now.year, now.month, now.day),
          endDate: now,
          dateLabel: todayStr,
        );
        final idx = _weeklySummaries.indexWhere((s) => s.date == todayStr);
        if (idx != -1 && _todaySummary != null) {
          _weeklySummaries[idx] = _todaySummary!;
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('ScreenTimeProvider fast-resume error: $e');
      }
    }

    _isLoading = true;
    notifyListeners();

    try {
      _hasPermission = await _service.hasPermission();
      _permissionChecked = true;
      final todayNow = DateTime.now();
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      _todaySummary = await _summaryForRange(
        uid: uid,
        startDate: DateTime(todayNow.year, todayNow.month, todayNow.day),
        endDate: todayNow,
        dateLabel: todayStr,
      );
      final now = DateTime.now();

      // Current week (Monday to Sunday)
      final mondayThisWeek = now.subtract(Duration(days: now.weekday - 1));
      final List<DailyScreenTimeSummary> thisWeekList = [];
      for (int i = 0; i < 7; i++) {
        final d = DateTime(
            mondayThisWeek.year, mondayThisWeek.month, mondayThisWeek.day + i);
        final dateStr = d.toIso8601String().split('T')[0];

        if (d.isAfter(DateTime(now.year, now.month, now.day))) {
          // Future day of the week: 0 usage
          thisWeekList.add(DailyScreenTimeSummary(
            date: dateStr,
            totalDuration: Duration.zero,
            appUsages: [],
            categoryBreakdown: {},
          ));
        } else {
          final isToday =
              d.year == now.year && d.month == now.month && d.day == now.day;
          final start = DateTime(d.year, d.month, d.day);
          final end =
              isToday ? now : DateTime(d.year, d.month, d.day, 23, 59, 59);

          final sum = await _summaryForRange(
              uid: uid, startDate: start, endDate: end, dateLabel: dateStr);
          thisWeekList.add(sum);
        }
      }
      _weeklySummaries = thisWeekList;

      // Previous week (Monday to Sunday of last week)
      final mondayLastWeek = mondayThisWeek.subtract(const Duration(days: 7));
      final List<DailyScreenTimeSummary> lastWeekList = [];
      for (int i = 0; i < 7; i++) {
        final d = DateTime(
            mondayLastWeek.year, mondayLastWeek.month, mondayLastWeek.day + i);
        final dateStr = d.toIso8601String().split('T')[0];
        final start = DateTime(d.year, d.month, d.day);
        final end = DateTime(d.year, d.month, d.day, 23, 59, 59);

        final sum = await _summaryForRange(
            uid: uid, startDate: start, endDate: end, dateLabel: dateStr);
        lastWeekList.add(sum);
      }
      _prevWeeklySummaries = lastWeekList;
    } catch (e) {
      debugPrint('ScreenTimeProvider error: $e');
      _hasPermission = false;
      _permissionChecked = true;
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Query 7 days (Monday..Sunday) for any selected week.
  Future<List<DailyScreenTimeSummary>> getWeekDays(
      DateTime anyDateInWeek) async {
    final now = DateTime.now();
    final monday =
        anyDateInWeek.subtract(Duration(days: anyDateInWeek.weekday - 1));
    final List<DailyScreenTimeSummary> result = [];

    for (int i = 0; i < 7; i++) {
      final d = DateTime(monday.year, monday.month, monday.day + i);
      final dateStr = d.toIso8601String().split('T')[0];

      if (d.isAfter(DateTime(now.year, now.month, now.day))) {
        // Future day
        result.add(DailyScreenTimeSummary(
          date: dateStr,
          totalDuration: Duration.zero,
          appUsages: [],
          categoryBreakdown: {},
        ));
      } else {
        final isToday =
            d.year == now.year && d.month == now.month && d.day == now.day;
        final start = DateTime(d.year, d.month, d.day);
        final end =
            isToday ? now : DateTime(d.year, d.month, d.day, 23, 59, 59);

        final sum = await _summaryForRange(
          uid: 'local_user',
          startDate: start,
          endDate: end,
          dateLabel: dateStr,
        );
        result.add(sum);
      }
    }
    return result;
  }

  /// Query week-by-week summaries for a specific month (Week 1: 1-7, Week 2: 8-14, etc.)
  Future<List<DailyScreenTimeSummary>> getMonthWeeks(
      int year, int month) async {
    final now = DateTime.now();
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final List<DailyScreenTimeSummary> result = [];

    // Break into weeks: 1-7, 8-14, 15-21, 22-28, 29-end
    final weekRanges = [
      {'start': 1, 'end': 7, 'label': 'Week 1 (1-7)'},
      {'start': 8, 'end': 14, 'label': 'Week 2 (8-14)'},
      {'start': 15, 'end': 21, 'label': 'Week 3 (15-21)'},
      {'start': 22, 'end': 28, 'label': 'Week 4 (22-28)'},
      if (daysInMonth > 28)
        {'start': 29, 'end': daysInMonth, 'label': 'Week 5 (29-$daysInMonth)'},
    ];

    for (final r in weekRanges) {
      final startDay = r['start'] as int;
      final endDay = r['end'] as int;
      final label = r['label'] as String;

      final start = DateTime(year, month, startDay);
      final end = DateTime(year, month, endDay, 23, 59, 59);

      if (start.isAfter(now)) {
        // Future week
        result.add(DailyScreenTimeSummary(
          date: label,
          totalDuration: Duration.zero,
          appUsages: [],
          categoryBreakdown: {},
        ));
      } else {
        final effectiveEnd = end.isAfter(now) ? now : end;
        final sum = await _summaryForRange(
          uid: 'local_user',
          startDate: start,
          endDate: effectiveEnd,
          dateLabel: label,
        );
        result.add(sum);
      }
    }
    return result;
  }

  /// Query month-by-month summaries for a specific year (Jan..Dec).
  /// Future months (e.g. Sep, Oct, Nov, Dec in August) will be strictly 0h — no fake data!
  Future<List<DailyScreenTimeSummary>> getYearMonths(int year) async {
    final now = DateTime.now();
    final List<DailyScreenTimeSummary> result = [];

    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    for (int m = 1; m <= 12; m++) {
      final monthName = monthNames[m - 1];
      final start = DateTime(year, m, 1);
      final daysInMonth = DateUtils.getDaysInMonth(year, m);
      final end = DateTime(year, m, daysInMonth, 23, 59, 59);

      if (start.isAfter(now)) {
        // Future month in current year: 0h
        result.add(DailyScreenTimeSummary(
          date: monthName,
          totalDuration: Duration.zero,
          appUsages: [],
          categoryBreakdown: {},
        ));
      } else {
        final effectiveEnd = end.isAfter(now) ? now : end;
        final sum = await _summaryForRange(
          uid: 'local_user',
          startDate: start,
          endDate: effectiveEnd,
          dateLabel: monthName,
        );
        result.add(sum);
      }
    }
    return result;
  }

  /// Opens Android Usage Access settings directly.
  Future<void> requestUsagePermission() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('openUsageAccessSettings');
      } catch (e) {
        debugPrint('Could not open usage access settings: $e');
      }
    }
  }

  Future<void> recheckAndLoad() async {
    _service.clearCache();
    await loadScreenTime();
  }
}
