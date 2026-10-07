import '../models/task_session.dart';
import '../models/todo.dart';
import '../utils/month_weeks.dart';

/// Analytics periods. There is deliberately no "all time" period.
enum AnalyticsPeriod { daily, weekly, monthly, yearly }

/// Half-open date range [start, end).
class DateRange {
  final DateTime start;
  final DateTime end;
  const DateRange(this.start, this.end);
  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);
}

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Clamps [date] so it is never after today. Every analytics and timer
/// history lookup goes through this, so future dates can't be shown even if
/// a caller asks for one.
DateTime clampToToday(DateTime date, {DateTime? now}) {
  final today = dayOf(now ?? DateTime.now());
  final d = dayOf(date);
  return d.isAfter(today) ? today : d;
}

/// The period that contains [anchor].
DateRange rangeFor(AnalyticsPeriod period, DateTime anchor) {
  final d = dayOf(anchor);
  switch (period) {
    case AnalyticsPeriod.daily:
      return DateRange(d, DateTime(d.year, d.month, d.day + 1));
    case AnalyticsPeriod.weekly:
      final week = monthWeekOf(d);
      return DateRange(week.start, week.end);
    case AnalyticsPeriod.monthly:
      return DateRange(DateTime(d.year, d.month), DateTime(d.year, d.month + 1));
    case AnalyticsPeriod.yearly:
      return DateRange(DateTime(d.year), DateTime(d.year + 1));
  }
}

/// Anchor of the period before the one containing [anchor].
DateTime previousAnchor(AnalyticsPeriod period, DateTime anchor) {
  final d = dayOf(anchor);
  switch (period) {
    case AnalyticsPeriod.daily:
      return DateTime(d.year, d.month, d.day - 1);
    case AnalyticsPeriod.weekly:
      return previousMonthWeek(monthWeekOf(d)).start;
    case AnalyticsPeriod.monthly:
      return DateTime(d.year, d.month - 1, 1);
    case AnalyticsPeriod.yearly:
      return DateTime(d.year - 1, 1, 1);
  }
}

/// Anchor of the next period, or null when that period would start after
/// today (forward navigation into the future is not allowed).
DateTime? nextAnchor(AnalyticsPeriod period, DateTime anchor, {DateTime? now}) {
  final next = rangeFor(period, anchor).end;
  final today = dayOf(now ?? DateTime.now());
  if (next.isAfter(today)) return null;
  // Land on today when moving into the current period, else on its first day.
  return rangeFor(period, today).contains(next) ? today : next;
}

/// Task counts and timer totals for one range.
class TaskCounts {
  final int completed;
  final int missed;
  final int pending;

  /// Total timed focus, from saved timer sessions.
  final int focusSeconds;
  final int sessionCount;
  final int longestSessionSeconds;

  const TaskCounts({
    required this.completed,
    required this.missed,
    required this.pending,
    required this.focusSeconds,
    this.sessionCount = 0,
    this.longestSessionSeconds = 0,
  });

  int get total => completed + missed + pending;

  /// Completed share of all tasks in the range, 0..100. Null when there were
  /// no tasks, so callers never show a made-up 0% or an infinite change.
  int? get completionRate => total == 0 ? null : ((completed / total) * 100).round();
}

/// Total focus on one task.
class TaskTime {
  final String title;
  final int seconds;
  final int sessions;
  const TaskTime({required this.title, required this.seconds, required this.sessions});
}

/// One bar in a period chart.
class ChartBucket {
  final String label;
  final TaskCounts counts;

  /// True for buckets that have not happened yet (e.g. later days this week).
  final bool isFuture;
  final bool isCurrent;

  const ChartBucket({
    required this.label,
    required this.counts,
    this.isFuture = false,
    this.isCurrent = false,
  });
}

class PeriodReport {
  final AnalyticsPeriod period;
  final DateRange range;
  final TaskCounts current;
  final TaskCounts previous;
  final List<ChartBucket> chart;

  /// Average focus seconds per day: over the elapsed days of the current
  /// period, and over the compared days of the previous one.
  final int dailyAverageFocus;
  final int previousDailyAverageFocus;

  /// When the current period is still in progress, both periods are compared
  /// over their first [comparedDays] days (like for like). Null when whole
  /// periods are compared.
  final int? comparedDays;

  const PeriodReport({
    required this.period,
    required this.range,
    required this.current,
    required this.previous,
    required this.chart,
    required this.dailyAverageFocus,
    required this.previousDailyAverageFocus,
    this.comparedDays,
  });

  /// Change in focus time versus the previous period, in seconds.
  int get focusChange => current.focusSeconds - previous.focusSeconds;

  /// Change in focus time as a percentage. Null when the previous period had
  /// no focus time, so an infinite or undefined change is never shown.
  int? get focusChangePercent {
    if (previous.focusSeconds == 0) return null;
    return ((focusChange / previous.focusSeconds) * 100).round();
  }

  /// Change in completed tasks versus the previous period.
  int get completedChange => current.completed - previous.completed;

  /// Change in completion rate, in percentage points. Null when either period
  /// had no tasks, because a comparison would be meaningless.
  int? get rateChange {
    final a = current.completionRate;
    final b = previous.completionRate;
    if (a == null || b == null) return null;
    return a - b;
  }
}

/// Computes task analytics from stored tasks and timer sessions. Goals are
/// excluded: analytics are for tasks only.
class TaskAnalytics {
  final List<Todo> tasks;
  final List<TaskSession> sessions;
  final DateTime now;

  TaskAnalytics({
    required List<Todo> todos,
    required List<TaskSession> sessions,
    DateTime? now,
  })  : tasks = todos.where((t) => t.isTask && !t.isDeleted).toList(),
        now = now ?? DateTime.now(),
        sessions = _taskSessions(todos, sessions);

  /// Sessions of tasks that still exist. Time from goals, and from tasks the
  /// user deleted, is left out.
  static List<TaskSession> _taskSessions(List<Todo> todos, List<TaskSession> sessions) {
    final liveTaskIds = todos.where((t) => t.isTask && !t.isDeleted).map((t) => t.id).toSet();
    return sessions.where((s) => liveTaskIds.contains(s.taskId)).toList();
  }

  /// When a completed task was completed. Older records without a completion
  /// time fall back to their last update.
  static DateTime completedTime(Todo t) => t.completedAt ?? t.updatedAt;

  bool _isMissed(Todo t) =>
      !t.completed && t.dueDate != null && now.isAfter(t.dueDate!.add(Todo.gracePeriod));

  /// Counts for [range], clipped so nothing after now is counted.
  ///
  /// * completed: tasks completed inside the range
  /// * missed: unfinished tasks whose deadline (plus grace) fell inside the range
  /// * pending: unfinished tasks due inside the range that can still be done;
  ///   tasks with no deadline count as pending in the range containing today
  /// * focus: timer sessions recorded on days inside the range
  TaskCounts countsFor(DateRange range) {
    final today = dayOf(now);
    final includesToday = range.contains(today);
    var completed = 0, missed = 0, pending = 0;
    for (final t in tasks) {
      if (t.completed) {
        if (range.contains(completedTime(t))) completed++;
        continue;
      }
      if (t.dueDate == null) {
        if (includesToday) pending++;
        continue;
      }
      if (!range.contains(t.dueDate!)) continue;
      if (_isMissed(t)) {
        missed++;
      } else if (!dayOf(t.dueDate!).isAfter(today) || includesToday) {
        pending++;
      }
    }
    final inRange = sessions.where((s) {
      final day = DateTime.tryParse(s.date);
      return day != null && range.contains(day) && !day.isAfter(today);
    }).toList();
    return TaskCounts(
      completed: completed,
      missed: missed,
      pending: pending,
      focusSeconds: inRange.fold<int>(0, (sum, s) => sum + s.durationSeconds),
      sessionCount: inRange.length,
      longestSessionSeconds: inRange.fold<int>(0, (m, s) => s.durationSeconds > m ? s.durationSeconds : m),
    );
  }

  PeriodReport report(AnalyticsPeriod period, DateTime anchor) {
    final a = clampToToday(anchor, now: now);
    final range = rangeFor(period, a);
    var prevRange = rangeFor(period, previousAnchor(period, a));
    final current = countsFor(range);
    final today = dayOf(now);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);

    // A period still in progress is compared with the same number of days
    // at the start of the previous period, so a half-finished week isn't
    // judged against a full one.
    int? comparedDays;
    if (range.end.isAfter(tomorrow)) {
      final days = DateTime.utc(today.year, today.month, today.day)
              .difference(DateTime.utc(range.start.year, range.start.month, range.start.day))
              .inDays +
          1;
      var prevEnd = DateTime(prevRange.start.year, prevRange.start.month, prevRange.start.day + days);
      if (prevEnd.isAfter(prevRange.end)) prevEnd = prevRange.end;
      prevRange = DateRange(prevRange.start, prevEnd);
      comparedDays = days;
    }

    int days(DateRange r) => (r.end.difference(r.start).inHours / 24).round();
    final elapsedEnd = range.end.isAfter(tomorrow) ? tomorrow : range.end;
    final elapsedDays = days(DateRange(range.start, elapsedEnd));
    final prevDays = days(prevRange);
    final previous = countsFor(prevRange);

    return PeriodReport(
      period: period,
      range: range,
      current: current,
      previous: previous,
      chart: _chart(period, a, range),
      dailyAverageFocus: elapsedDays <= 0 ? 0 : current.focusSeconds ~/ elapsedDays,
      previousDailyAverageFocus: prevDays <= 0 ? 0 : previous.focusSeconds ~/ prevDays,
      comparedDays: comparedDays,
    );
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

  List<ChartBucket> _chart(AnalyticsPeriod period, DateTime anchor, DateRange range) {
    final today = dayOf(now);
    ChartBucket bucket(String label, DateTime start, DateTime end, {bool current = false}) {
      return ChartBucket(
        label: label,
        counts: countsFor(DateRange(start, end)),
        isFuture: start.isAfter(today),
        isCurrent: current,
      );
    }

    switch (period) {
      case AnalyticsPeriod.daily:
        // The selected day and the six days before it.
        return List.generate(7, (i) {
          final day = DateTime(anchor.year, anchor.month, anchor.day - 6 + i);
          return bucket(_weekdays[day.weekday - 1].substring(0, 1), day,
              DateTime(day.year, day.month, day.day + 1),
              current: i == 6);
        });
      case AnalyticsPeriod.weekly:
        // Every day of the week, which stays inside its month.
        return monthWeekOf(range.start).days.map((day) {
          return bucket('${_weekdays[day.weekday - 1]}\n${day.day}', day,
              DateTime(day.year, day.month, day.day + 1),
              current: day == today);
        }).toList();
      case AnalyticsPeriod.monthly:
        // Week-sized slices of the month: 1–7, 8–14, 15–21, 22–28, 29–end.
        final buckets = <ChartBucket>[];
        for (var startDay = 1; ; startDay += 7) {
          final start = DateTime(range.start.year, range.start.month, startDay);
          if (!start.isBefore(range.end)) break;
          var end = DateTime(range.start.year, range.start.month, startDay + 7);
          if (end.isAfter(range.end)) end = range.end;
          final lastDay = DateTime(end.year, end.month, end.day - 1).day;
          buckets.add(bucket(startDay == lastDay ? '$startDay' : '$startDay–$lastDay', start, end,
              current: DateRange(start, end).contains(today)));
        }
        return buckets;
      case AnalyticsPeriod.yearly:
        return List.generate(12, (i) {
          final start = DateTime(range.start.year, i + 1);
          final end = DateTime(range.start.year, i + 2);
          return bucket(_months[i], start, end, current: DateRange(start, end).contains(today));
        });
    }
  }

  /// Tasks with the most timed focus inside [range], highest first.
  List<TaskTime> topTasksByTime(DateRange range, {int limit = 10}) {
    final today = dayOf(now);
    final byTask = <String, TaskTime>{};
    for (final s in sessions) {
      final day = DateTime.tryParse(s.date);
      if (day == null || !range.contains(day) || day.isAfter(today)) continue;
      final prev = byTask[s.taskId];
      byTask[s.taskId] = TaskTime(
        title: prev?.title ?? s.taskTitle,
        seconds: (prev?.seconds ?? 0) + s.durationSeconds,
        sessions: (prev?.sessions ?? 0) + 1,
      );
    }
    final list = byTask.values.toList()..sort((a, b) => b.seconds.compareTo(a.seconds));
    return list.take(limit).toList();
  }

  /// Timer sessions that happened on [day]. Never returns anything for a
  /// future day.
  List<TaskSession> sessionsOnDay(DateTime day) => sessionsOn(sessions, day, now: now);

  static List<TaskSession> sessionsOn(List<TaskSession> sessions, DateTime day, {DateTime? now}) {
    final d = dayOf(day);
    if (d.isAfter(dayOf(now ?? DateTime.now()))) return const [];
    final key = TaskSession.formatDate(d);
    return sessions.where((s) => s.date == key).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }
}
