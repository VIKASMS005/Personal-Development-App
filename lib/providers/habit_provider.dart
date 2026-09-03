import 'package:flutter/material.dart';
import '../models/habit.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

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
    _habits = await _db.getHabits(uid);
    notifyListeners();
    for (final h in _habits) {
      if (h.streak > 0) {
        final todayStr = DateTime.now().toIso8601String().split('T')[0];
        if (h.history[todayStr] != true) {
          NotificationService.scheduleHabitStreakWarning(
            id: h.id.hashCode,
            habitTitle: h.title,
          );
        }
      }
    }
  }

  Future<void> addHabit(Habit habit) async {
    _habits.insert(0, habit);
    notifyListeners();
    await _db.upsertHabit(habit);
    NotificationService.scheduleHabitStreakWarning(
      id: habit.id.hashCode,
      habitTitle: habit.title,
    );
  }

  Future<void> updateHabit(Habit habit) async {
    final idx = _habits.indexWhere((h) => h.id == habit.id);
    if (idx != -1) {
      _habits[idx] = habit.copyWith(updatedAt: DateTime.now());
      notifyListeners();
      await _db.upsertHabit(_habits[idx]);
    }
  }

  Future<void> toggleDay(Habit habit, String dateStr) async {
    final history = Map<String, bool>.from(habit.history);
    final wasDone = history[dateStr] ?? false;
    history[dateStr] = !wasDone;

    int newStreak = habit.streak;
    if (!wasDone) {
      newStreak++;
      // If completed today, cancel warning
      await NotificationService.cancel(habit.id.hashCode);
    } else {
      if (newStreak > 0) newStreak--;
      // Reschedule warning if uncompleted today
      await NotificationService.scheduleHabitStreakWarning(
        id: habit.id.hashCode,
        habitTitle: habit.title,
      );
    }

    final updated = habit.copyWith(
      history: history,
      streak: newStreak,
      updatedAt: DateTime.now(),
    );

    final idx = _habits.indexWhere((h) => h.id == habit.id);
    if (idx != -1) {
      _habits[idx] = updated;
      notifyListeners();
      await _db.upsertHabit(updated);
    }
  }

  Future<void> deleteHabit(String id) async {
    _habits.removeWhere((h) => h.id == id);
    notifyListeners();
    await NotificationService.cancel(id.hashCode);
    await _db.softDeleteHabit(id);
  }
}
