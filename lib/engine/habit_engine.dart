import '../models/habit.dart';

/// Pure computation engine for Habit analytics.
/// Maps: date string (ISO8601 date part) → bool (completed)
/// No database access, no Flutter dependencies.
/// Takes `List<Habit>` and performs all statistical calculations.
class HabitEngine {
  final List<Habit> habits;

  HabitEngine(this.habits);

  // ─── Week Boundaries ───────────────────────────────────────────────────────

  static DateTime _startOfWeek(DateTime ref) {
    final monday = ref.subtract(Duration(days: ref.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  static DateTime _startOfPreviousWeek(DateTime ref) {
    return _startOfWeek(ref).subtract(const Duration(days: 7));
  }

  static String _dateStr(DateTime d) => d.toIso8601String().split('T')[0];

  // ─── Per-Habit Calculations ────────────────────────────────────────────────

  /// Returns true if this habit was completed today.
  bool isCompletedToday(Habit h) {
    return h.history[_dateStr(DateTime.now())] == true;
  }

  /// How many days (in the last [lookbackDays]) did the user complete [h].
  int completedDaysIn(Habit h, {required int lookbackDays}) {
    final now = DateTime.now();
    int count = 0;
    for (int i = 0; i < lookbackDays; i++) {
      final d = now.subtract(Duration(days: i));
      if (h.history[_dateStr(d)] == true) count++;
    }
    return count;
  }

  /// Completion rate for [h] in the current week (Mon–today), 0.0–1.0.
  double completionRateThisWeek(Habit h) {
    final now = DateTime.now();
    final weekStart = _startOfWeek(now);
    final daysElapsed = now.difference(weekStart).inDays + 1;
    if (daysElapsed == 0) return 0.0;
    int done = 0;
    for (int i = 0; i < daysElapsed; i++) {
      final d = weekStart.add(Duration(days: i));
      if (h.history[_dateStr(d)] == true) done++;
    }
    return done / daysElapsed;
  }

  /// Completion rate for [h] in the previous complete week (Mon–Sun), 0.0–1.0.
  double completionRateLastWeek(Habit h) {
    final prevStart = _startOfPreviousWeek(DateTime.now());
    int done = 0;
    for (int i = 0; i < 7; i++) {
      final d = prevStart.add(Duration(days: i));
      if (h.history[_dateStr(d)] == true) done++;
    }
    return done / 7.0;
  }

  /// Current streak for [h] counting consecutive days ending today (or yesterday).
  int currentStreak(Habit h) => h.streak;

  /// Longest streak ever recorded for [h] by scanning full history.
  int longestStreak(Habit h) {
    if (h.history.isEmpty) return 0;
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
      if (prev == null || d.difference(prev).inDays == 1) {
        current++;
      } else {
        current = 1;
      }
      if (current > longest) longest = current;
      prev = d;
    }
    return longest;
  }

  /// Number of days missed in last [lookbackDays].
  int missedDays(Habit h, {int lookbackDays = 7}) {
    return lookbackDays - completedDaysIn(h, lookbackDays: lookbackDays);
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
    if (habits.isEmpty) return 0.0;
    final rates = habits.map(completionRateLastWeek).toList();
    return rates.reduce((a, b) => a + b) / rates.length;
  }

  /// Count habits completed today.
  int completedTodayCount() => habits.where(isCompletedToday).length;

  /// Best streak across all habits.
  int bestCurrentStreak() {
    if (habits.isEmpty) return 0;
    return habits.map(currentStreak).reduce((a, b) => a > b ? a : b);
  }

  /// Habit with the best current streak.
  Habit? bestStreakHabit() {
    if (habits.isEmpty) return null;
    return habits.reduce(
        (a, b) => currentStreak(a) >= currentStreak(b) ? a : b);
  }

  /// Habits that have been missed for 2+ consecutive days (at risk).
  List<Habit> habitsAtRisk() {
    return habits.where((h) {
      final today = _dateStr(DateTime.now());
      final yesterday =
          _dateStr(DateTime.now().subtract(const Duration(days: 1)));
      final doneToday = h.history[today] == true;
      final doneYesterday = h.history[yesterday] == true;
      return !doneToday && !doneYesterday;
    }).toList();
  }
}
