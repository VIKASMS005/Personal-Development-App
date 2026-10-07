import 'package:flutter/material.dart';
import '../models/habit.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../utils/month_weeks.dart';

class HabitProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<Habit> _habits = [];

  List<Habit> get habits => _habits;
  int get activeCount => _habits.length;

  void clear() {
    _habits = [];
    notifyListeners();
  }

  Future<void> loadHabits(String uid) async {
    final loaded = await _db.getHabits(uid);
    _habits = loaded.map((h) {
      final accurateStreak = Habit.streakFor(h.frequency, h.history);
      return h.copyWith(streak: accurateStreak);
    }).toList();
    notifyListeners();
    // Keep each habit's warning in line with its real state
    // (also re-arms warnings an older build switched off).
    for (final h in _habits) {
      try {
        await _scheduleWarning(h);
      } catch (_) {}
    }
  }

  /// Daily habits: 8:30 PM every day not yet done. Weekly habits: 8:30 PM on
  /// the last day of a week (1–7, 8–14, ...) they haven't been done in.
  static Future<void> _scheduleWarning(Habit h) {
    return NotificationService.scheduleHabitStreakWarning(
      id: NotificationService.stableId(h.id),
      habitTitle: h.title,
      doneToday: h.isDoneThisPeriod,
      weekly: h.isWeekly,
    );
  }

  Future<void> addHabit(Habit habit) async {
    final accurateStreak = Habit.streakFor(habit.frequency, habit.history);
    final newHabit = habit.copyWith(streak: accurateStreak);
    _habits.insert(0, newHabit);
    notifyListeners();
    await _db.upsertHabit(newHabit);
    await _scheduleWarning(newHabit);
  }

  Future<void> updateHabit(Habit habit) async {
    final idx = _habits.indexWhere((h) => h.id == habit.id);
    if (idx != -1) {
      final accurateStreak = Habit.streakFor(habit.frequency, habit.history);
      final updated = habit.copyWith(streak: accurateStreak, updatedAt: DateTime.now());
      _habits[idx] = updated;
      notifyListeners();
      await _db.upsertHabit(updated);
      // The warning text carries the title and frequency, so an edit re-schedules it.
      await _scheduleWarning(updated);
    }
  }

  Future<void> toggleDay(Habit habit, String dateStr) async {
    final history = Map<String, bool>.from(habit.history);
    final wasDone = history[dateStr] ?? false;
    history[dateStr] = !wasDone;
    await _saveHistory(habit, history);
  }

  /// The main check button. A daily habit toggles today. A weekly habit that
  /// is already done this week (on any day) is un-done for the whole week;
  /// otherwise today is marked done.
  Future<void> toggleCurrentPeriod(Habit habit) async {
    if (!habit.isWeekly || !habit.isDoneThisPeriod) {
      await toggleDay(habit, _getTodayStr());
      return;
    }
    final history = Map<String, bool>.from(habit.history);
    for (final d in monthWeekOf(DateTime.now()).days) {
      history.remove(_dateKey(d));
    }
    await _saveHistory(habit, history);
  }

  Future<void> _saveHistory(Habit habit, Map<String, bool> history) async {
    final updated = habit.copyWith(
      history: history,
      streak: Habit.streakFor(habit.frequency, history),
      updatedAt: DateTime.now(),
    );

    final idx = _habits.indexWhere((h) => h.id == habit.id);
    if (idx != -1) {
      _habits[idx] = updated;
      notifyListeners();
      await _db.upsertHabit(updated);
    }

    // Re-arm the warning from the real state. (Cancelling it on completion, as
    // an older build did, switched the warning off for good.) A change to an
    // old date leaves the current period's state unchanged, so this is a no-op then.
    await _scheduleWarning(updated);
  }

  Future<void> deleteHabit(String id) async {
    _habits.removeWhere((h) => h.id == id);
    notifyListeners();
    await NotificationService.cancel(NotificationService.stableId(id));
    await _db.softDeleteHabit(id);
  }

  static String _getTodayStr() => _dateKey(DateTime.now());

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
