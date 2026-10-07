import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/screen_time_record.dart';
import '../services/screen_time_service.dart';
import '../services/database_service.dart';
import '../utils/month_weeks.dart';

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
    // No reading (not loaded yet, or no usage access) is not "0h 0m".
    if (_todaySummary == null || !_hasPermission) return '—';
    final dur = _todaySummary!.totalDuration;
    final h = dur.inHours;
    final m = dur.inMinutes % 60;
    return '${h}h ${m}m';
  }

  /// Days of this week that have happened (future days hold no data).
  List<DailyScreenTimeSummary> get _elapsedThisWeek {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return _weeklySummaries
        .where((s) => !(DateTime.tryParse(s.date)?.isAfter(today) ?? false))
        .toList();
  }

  /// Average per day over the days of this week so far.
  double get weeklyDailyAverageHours {
    final days = _elapsedThisWeek;
    if (days.isEmpty) return 0.0;
    final totalSec = days.fold(0, (sum, s) => sum + s.totalDuration.inSeconds);
    return totalSec / (days.length * 3600.0);
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

  /// Change versus last week, comparing the same number of days from the
  /// start of each week (a half-finished week isn't judged against a whole
  /// one). Null when last week has no usage to compare with.
  double? get weeklyPercentChange {
    final days = _elapsedThisWeek.length;
    final lastSec = _prevWeeklySummaries
        .take(days)
        .fold(0, (sum, s) => sum + s.totalDuration.inSeconds);
    final thisSec = thisWeekTotalDuration.inSeconds;
    if (lastSec <= 0) return null;
    return ((thisSec - lastSec) / lastSec) * 100.0;
  }

  Future<DailyScreenTimeSummary> _summaryForRange({
    required String uid,
    required DateTime startDate,
    required DateTime endDate,
    required String dateLabel,
  }) async {
    final firstDay = DateTime(startDate.year, startDate.month, startDate.day);
    final lastDay = DateTime(endDate.year, endDate.month, endDate.day);
    if (firstDay == lastDay) {
      return _singleDay(uid, startDate, endDate, dateLabel);
    }

    // Multi-day ranges (a month-week, a month) are built day by day. Android
    // only keeps detailed usage events for a limited time, so a single live
    // query over a whole month can miss most of it. Each day uses whichever
    // is larger: the live value, or what was saved for that day earlier.
    final live = await _service.getDailySummaries(startDate: startDate, endDate: endDate);
    final today = DateTime.now();
    final todayKey = _dateKey(today);

    var total = Duration.zero;
    final appTotals = <String, AppUsageRecord>{};
    final categories = <String, Duration>{};
    for (var day = firstDay; !day.isAfter(lastDay); day = DateTime(day.year, day.month, day.day + 1)) {
      final key = _dateKey(day);
      final stored = await _db.getScreenTimeSummary(uid, key);
      final fresh = live[key];
      DailyScreenTimeSummary? best = stored;
      if (fresh != null && fresh.totalDuration > (stored?.totalDuration ?? Duration.zero)) {
        best = fresh;
        // Save finished days so the history survives after Android prunes its events.
        if (key != todayKey) await _db.upsertScreenTimeSummary(uid, fresh);
      }
      if (best == null) continue;
      total += best.totalDuration;
      for (final app in best.appUsages) {
        final prev = appTotals[app.packageName];
        appTotals[app.packageName] = AppUsageRecord(
          packageName: app.packageName,
          appName: app.appName,
          usage: (prev?.usage ?? Duration.zero) + app.usage,
          startDate: startDate,
          endDate: endDate,
          category: app.category,
          iconBase64: app.iconBase64 ?? prev?.iconBase64,
        );
      }
      for (final entry in best.categoryBreakdown.entries) {
        categories[entry.key] = (categories[entry.key] ?? Duration.zero) + entry.value;
      }
    }
    final apps = appTotals.values.toList()..sort((a, b) => b.usage.compareTo(a.usage));
    return DailyScreenTimeSummary(
      date: dateLabel,
      totalDuration: total,
      appUsages: apps,
      categoryBreakdown: categories,
    );
  }

  /// One day (or part of today): the larger of the live value and the saved one.
  Future<DailyScreenTimeSummary> _singleDay(
      String uid, DateTime startDate, DateTime endDate, String dateLabel) async {
    final live = await _service.getSummaryForRange(
      startDate: startDate,
      endDate: endDate,
      dateLabel: dateLabel,
    );
    final stored = await _db.getScreenTimeSummary(uid, _dateKey(startDate));
    if (stored != null && stored.totalDuration > live.totalDuration) {
      return DailyScreenTimeSummary(
        date: dateLabel,
        totalDuration: stored.totalDuration,
        appUsages: stored.appUsages,
        categoryBreakdown: stored.categoryBreakdown,
      );
    }
    if (live.totalDuration > Duration.zero) {
      await _db.upsertScreenTimeSummary(uid, live);
    }
    return live;
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

      // Current week (weeks stay inside their month: 1–7, 8–14, ...)
      final thisWeek = monthWeekOf(now);
      final List<DailyScreenTimeSummary> thisWeekList = [];
      for (final d in thisWeek.days) {
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

      // Previous week
      final List<DailyScreenTimeSummary> lastWeekList = [];
      for (final d in previousMonthWeek(thisWeek).days) {
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

  /// Query every day of the (month-bound) week containing [anyDateInWeek].
  Future<List<DailyScreenTimeSummary>> getWeekDays(
      DateTime anyDateInWeek) async {
    final now = DateTime.now();
    final List<DailyScreenTimeSummary> result = [];

    for (final d in monthWeekOf(anyDateInWeek).days) {
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
