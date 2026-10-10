import '../models/habit.dart';
import '../utils/month_weeks.dart';

/// Pure computation engine for Habit analytics.
/// Maps: date string (ISO8601 date part) → bool (completed)
/// No database access, no Flutter dependencies.
/// Takes `List<Habit>` and performs all statistical calculations.
class HabitEngine {
  final List<Habit> habits;

  HabitEngine(this.habits);

  // ─── Week Boundaries ───────────────────────────────────────────────────────

  // Weeks stay inside their month (1–7, 8–14, ...); see month_weeks.dart.

  static String _dateStr(DateTime d) => d.toIso8601String().split('T')[0];

  /// The day [h] was added, or null when unknown (older habits).
  static DateTime? _createdDay(Habit h) {
    final c = h.createdAt;
    return c == null ? null : DateTime(c.year, c.month, c.day);
  }

  /// True if [h] already existed on [day]; days before a habit was added
  /// are not counted as missed.
  static bool existedOn(Habit h, DateTime day) {
    final c = _createdDay(h);
    return c == null || !DateTime(day.year, day.month, day.day).isBefore(c);
  }

  // ─── Per-Habit Calculations ────────────────────────────────────────────────

  /// True if this habit is done for its current period: today for a daily
  /// habit, this week for a weekly one.
  bool isCompletedToday(Habit h) => h.isDoneThisPeriod;

  /// How many days (in the last [lookbackDays]) did the user complete [h].
  int completedDaysIn(Habit h, {required int lookbackDays}) {
    final now = DateTime.now();
    int count = 0;
    for (int i = 0; i < lookbackDays; i++) {
      final d = DateTime(now.year, now.month, now.day - i);
      if (h.history[_dateStr(d)] == true) count++;
    }
    return count;
  }

  /// Completion rate for [h] in the current week (week start–today), 0.0–1.0.
  /// A weekly habit is 1.0 once it is done any day this week, else 0.0.
  double completionRateThisWeek(Habit h) {
    final now = DateTime.now();
    if (h.isWeekly) return h.isDoneInPeriodOf(now) ? 1.0 : 0.0;
    var weekStart = monthWeekOf(now).start;
    final created = _createdDay(h);
    if (created != null && created.isAfter(weekStart)) weekStart = created;
    final daysElapsed = now.day - weekStart.day + 1;
    if (daysElapsed <= 0) return 0.0;
    int done = 0;
    for (int i = 0; i < daysElapsed; i++) {
      final d = DateTime(weekStart.year, weekStart.month, weekStart.day + i);
      if (h.history[_dateStr(d)] == true) done++;
    }
    return done / daysElapsed;
  }

  /// Completion rate for [h] in the previous complete week, 0.0–1.0.
  double completionRateLastWeek(Habit h) {
    final prev = previousMonthWeek(monthWeekOf(DateTime.now()));
    if (h.isWeekly) return h.isDoneInPeriodOf(prev.start) ? 1.0 : 0.0;
    int done = 0, counted = 0;
    for (final d in prev.days) {
      if (!existedOn(h, d)) continue;
      counted++;
      if (h.history[_dateStr(d)] == true) done++;
    }
    return counted == 0 ? 0.0 : done / counted;
  }

  /// Current streak for [h] counting consecutive days ending today (or yesterday).
  int currentStreak(Habit h) => h.streak;

  /// Longest streak ever recorded for [h] by scanning full history
  /// (in weeks for a weekly habit).
  int longestStreak(Habit h) {
    if (h.history.isEmpty) return 0;
    if (h.isWeekly) return _longestWeeklyStreak(h);
    final sortedDates = h.history.keys.toList()..sort();
    int longest = 0;
    int current = 0;
    DateTime? prev;
    for (final ds in sortedDates) {
      if (h.history[ds] != true) {
        current = 0;
        prev = null;
        continue;
      }
      final d = DateTime.tryParse(ds);
      if (d == null) continue;
      // Calendar-day step (DST-safe): compare with the day after prev.
      if (prev == null || d == DateTime(prev.year, prev.month, prev.day + 1)) {
        current++;
      } else {
        current = 1;
      }
      if (current > longest) longest = current;
      prev = d;
    }
    return longest;
  }

  int _longestWeeklyStreak(Habit h) {
    final doneDates = h.history.entries
        .where((e) => e.value)
        .map((e) => DateTime.tryParse(e.key))
        .whereType<DateTime>()
        .toList()
      ..sort();
    if (doneDates.isEmpty) return 0;
    var week = monthWeekOf(doneDates.first);
    final last = monthWeekOf(DateTime.now());
    int longest = 0, current = 0;
    while (!week.start.isAfter(last.start)) {
      if (h.isDoneInPeriodOf(week.start)) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 0;
      }
      week = monthWeekOf(week.end);
    }
    return longest;
  }

  /// Number of days missed in last [lookbackDays].
  int missedDays(Habit h, {int lookbackDays = 7}) {
    final now = DateTime.now();
    var existing = 0;
    for (int i = 0; i < lookbackDays; i++) {
      if (existedOn(h, DateTime(now.year, now.month, now.day - i))) existing++;
    }
    return existing - completedDaysIn(h, lookbackDays: lookbackDays);
  }

  // ─── Aggregate Calculations ────────────────────────────────────────────────

  /// Overall weekly completion rate across all habits (0.0–1.0).
  double overallWeeklyRate() {
    if (habits.isEmpty) return 0.0;
    final rates = habits.map(completionRateThisWeek).toList();
    return rates.reduce((a, b) => a + b) / rates.length;
  }

  /// Overall previous week completion rate across all habits.
  double overallPreviousWeekRate() {
    // Habits added after last week ended have no last week to compare.
    final prevLast = previousMonthWeek(monthWeekOf(DateTime.now())).last;
    final rates = habits
        .where((h) => existedOn(h, prevLast))
        .map(completionRateLastWeek)
        .toList();
    if (rates.isEmpty) return 0.0;
    return rates.reduce((a, b) => a + b) / rates.length;
  }

  /// Count habits completed today.
  int completedTodayCount() => habits.where(isCompletedToday).length;

  /// A streak's length in days, so day and week streaks can be compared.
  static int _streakDays(Habit h) => h.isWeekly ? h.streak * 7 : h.streak;

  /// Habit with the best current streak (a week counts as 7 days).
  Habit? bestStreakHabit() {
    if (habits.isEmpty) return null;
    return habits.reduce(
        (a, b) => _streakDays(a) >= _streakDays(b) ? a : b);
  }

  /// The best habit's streak, in that habit's own unit (see [bestStreakUnit]).
  int bestCurrentStreak() => bestStreakHabit()?.streak ?? 0;

  /// 'day' or 'week': the unit of [bestCurrentStreak].
  String bestStreakUnit() => bestStreakHabit()?.streakUnit ?? 'day';

  /// Habits that have been missed for 2+ consecutive days (at risk), or for a
  /// weekly habit, missed last week and not yet done this week.
  List<Habit> habitsAtRisk() {
    final n0 = DateTime.now();
    return habits.where((h) {
      // Too new to have missed anything yet.
      if (h.isWeekly) {
        if (!existedOn(h, previousMonthWeek(monthWeekOf(n0)).last)) return false;
      } else if (!existedOn(h, DateTime(n0.year, n0.month, n0.day - 1))) {
        return false;
      }
      if (h.isWeekly) {
        final week = monthWeekOf(DateTime.now());
        return !h.isDoneInPeriodOf(week.start) &&
            !h.isDoneInPeriodOf(previousMonthWeek(week).start);
      }
      final today = _dateStr(DateTime.now());
      final n = DateTime.now();
      final yesterday = _dateStr(DateTime(n.year, n.month, n.day - 1));
      final doneToday = h.history[today] == true;
      final doneYesterday = h.history[yesterday] == true;
      return !doneToday && !doneYesterday;
    }).toList();
  }
}
