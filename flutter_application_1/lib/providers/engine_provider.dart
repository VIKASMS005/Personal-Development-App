import 'package:flutter/material.dart';
import '../models/habit.dart';
import '../models/todo.dart';
import '../models/journal_entry.dart';
import '../models/finance_transaction.dart';
import '../models/timetable_slot.dart';
import '../models/reminder.dart';
import '../engine/grow_engine.dart';
import '../engine/insight_engine.dart';

/// EngineProvider — exposes Personal Development Engine data to the UI and AI.
class EngineProvider extends ChangeNotifier {
  GrowEngine? _engine;

  GrowEngine? get engine => _engine;
  bool get hasData => _engine != null;

  TodayProgress? get todayProgress => _engine?.todayProgress;
  List<GrowInsight> get insights => _engine?.currentInsights ?? [];
  String get summaryLine => _engine?.summaryLine ?? 'Loading your data…';

  double get weeklyHabitRate => _engine?.habits.overallWeeklyRate() ?? 0.0;
  int get habitsCompletedToday => _engine?.habits.completedTodayCount() ?? 0;
  int get habitsTotal => _engine?.habits.habits.length ?? 0;
  int get bestStreak => _engine?.habits.bestCurrentStreak() ?? 0;
  int get tasksPending => _engine?.tasks.pendingCount ?? 0;
  int get tasksCompletedToday => _engine?.tasks.completedTodayCount ?? 0;
  double get taskCompletionRate => _engine?.tasks.completionPercentage ?? 0.0;

  /// Rebuild the engine with fresh data from all providers across the whole app.
  void rebuild({
    required List<Habit> habits,
    required List<Todo> todos,
    required List<JournalEntry> journals,
    required List<FinanceTransaction> transactions,
    List<TimetableSlot> timetableSlots = const [],
    List<Reminder> reminders = const [],
    String userName = '',
    int todaySteps = 0,
    int stepGoal = 6000,
    double todayCalories = 0.0,
    double todayDistanceKm = 0.0,
    int todayActiveMinutes = 0,
    String todayScreenTime = '0h 0m',
    double totalFinanceBalance = 0.0,
  }) {
    _engine = GrowEngine(
      habits: habits,
      todos: todos,
      journals: journals,
      transactions: transactions,
      timetableSlots: timetableSlots,
      reminders: reminders,
      userName: userName,
      todaySteps: todaySteps,
      stepGoal: stepGoal,
      todayCalories: todayCalories,
      todayDistanceKm: todayDistanceKm,
      todayActiveMinutes: todayActiveMinutes,
      todayScreenTime: todayScreenTime,
      totalFinanceBalance: totalFinanceBalance,
    );
    notifyListeners();
  }

  void clear() {
    _engine = null;
    notifyListeners();
  }
}
