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
    final loaded = await _db.getHabits(uid);
    _habits = loaded.map((h) {
      final accurateStreak = Habit.calculateStreak(h.history);
      return h.copyWith(streak: accurateStreak);
    }).toList();
    notifyListeners();
  }

  Future<void> addHabit(Habit habit) async {
    final accurateStreak = Habit.calculateStreak(habit.history);
    final newHabit = habit.copyWith(streak: accurateStreak);
    _habits.insert(0, newHabit);
    notifyListeners();
    await _db.upsertHabit(newHabit);
    NotificationService.scheduleHabitStreakWarning(
      id: habit.id.hashCode,
      habitTitle: habit.title,
    );
  }

  Future<void> updateHabit(Habit habit) async {
    final idx = _habits.indexWhere((h) => h.id == habit.id);
    if (idx != -1) {
      final accurateStreak = Habit.calculateStreak(habit.history);
      final updated = habit.copyWith(streak: accurateStreak, updatedAt: DateTime.now());
      _habits[idx] = updated;
      notifyListeners();
      await _db.upsertHabit(updated);
    }
  }

  Future<void> toggleDay(Habit habit, String dateStr) async {
    final history = Map<String, bool>.from(habit.history);
    final wasDone = history[dateStr] ?? false;
    history[dateStr] = !wasDone;

    final newStreak = Habit.calculateStreak(history);
    if (!wasDone) {
      // If completed today, cancel warning
      await NotificationService.cancel(habit.id.hashCode);
    } else {
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
