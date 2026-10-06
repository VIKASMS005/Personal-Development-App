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
      id: NotificationService.stableId(habit.id),
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

    // BUG 7 FIX: Only touch notification scheduling when toggling TODAY.
    // Toggling a past date must never cancel or reschedule future streak reminders.
    final todayStr = _getTodayStr();
    if (dateStr == todayStr) {
      if (!wasDone) {
        // Completed today — cancel today's streak warning
        await NotificationService.cancel(NotificationService.stableId(habit.id));
      } else {
        // Uncompleted today — reschedule streak warning
        await NotificationService.scheduleHabitStreakWarning(
          id: NotificationService.stableId(habit.id),
          habitTitle: habit.title,
        );
      }
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
    await NotificationService.cancel(NotificationService.stableId(id));
    await _db.softDeleteHabit(id);
  }

  static String _getTodayStr() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}
