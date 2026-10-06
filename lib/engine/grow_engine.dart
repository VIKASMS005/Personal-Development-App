import '../models/habit.dart';
import '../models/todo.dart';
import '../models/journal_entry.dart';
import '../models/finance_transaction.dart';
import '../models/timetable_slot.dart';
import '../models/reminder.dart';
import 'habit_engine.dart';
import 'task_engine.dart';
import 'insight_engine.dart';

/// GrowEngine — the central Personal Development Engine.
///
/// Orchestrates HabitEngine, TaskEngine, and InsightEngine.
/// Receives all user data from providers (no direct DB access).
/// Holds full multi-domain context (habits, tasks, timetable, reminders,
/// steps, screen time, finance, journal) for the AI assistant.
class GrowEngine {
  late final HabitEngine _habitEngine;
  late final TaskEngine _taskEngine;
  late final InsightEngine _insightEngine;

  // Enrichment data for AI context
  final String userName;
  final int todaySteps;
  final int stepGoal;
  final double todayCalories;
  final double todayDistanceKm;
  final int todayActiveMinutes;
  final String todayScreenTime;
  final double totalFinanceBalance;
  final List<FinanceTransaction> transactions;
  final List<JournalEntry> journals;
  final List<TimetableSlot> timetableSlots;
  final List<Reminder> reminders;

  GrowEngine._({
    required HabitEngine habitEngine,
    required TaskEngine taskEngine,
    required InsightEngine insightEngine,
    required this.userName,
    required this.todaySteps,
    required this.stepGoal,
    required this.todayCalories,
    required this.todayDistanceKm,
    required this.todayActiveMinutes,
    required this.todayScreenTime,
    required this.totalFinanceBalance,
    required this.transactions,
    required this.journals,
    required this.timetableSlots,
    required this.reminders,
  })  : _habitEngine = habitEngine,
        _taskEngine = taskEngine,
        _insightEngine = insightEngine;

  factory GrowEngine({
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
    final habitEngine = HabitEngine(habits);
    final taskEngine = TaskEngine(todos);
    final insightEngine = InsightEngine(
      habitEngine: habitEngine,
      taskEngine: taskEngine,
      journals: journals,
      transactions: transactions,
    );
    return GrowEngine._(
      habitEngine: habitEngine,
      taskEngine: taskEngine,
      insightEngine: insightEngine,
      userName: userName,
      todaySteps: todaySteps,
      stepGoal: stepGoal,
      todayCalories: todayCalories,
      todayDistanceKm: todayDistanceKm,
      todayActiveMinutes: todayActiveMinutes,
      todayScreenTime: todayScreenTime,
      totalFinanceBalance: totalFinanceBalance,
      transactions: transactions,
      journals: journals,
      timetableSlots: timetableSlots,
      reminders: reminders,
    );
  }

  // ─── Engine Accessors ─────────────────────────────────────────────────────

  HabitEngine get habits => _habitEngine;
  TaskEngine get tasks => _taskEngine;
  InsightEngine get insights => _insightEngine;

  // ─── Convenience Computed Properties ─────────────────────────────────────

  /// Overall today's progress summary.
  TodayProgress get todayProgress => TodayProgress(
        habitsCompleted: _habitEngine.completedTodayCount(),
        habitsTotal: _habitEngine.habits.length,
        tasksCompletedToday: _taskEngine.completedTodayCount,
        tasksPending: _taskEngine.pendingCount,
        bestStreak: _habitEngine.bestCurrentStreak(),
        weeklyHabitRate: _habitEngine.overallWeeklyRate(),
        weeklyTasksCompleted: _taskEngine.completedThisWeek,
      );

  /// All insights for dashboard display.
  List<GrowInsight> get currentInsights =>
      _insightEngine.generateInsights(maxInsights: 5);

  /// Short one-line summary for compact display.
  String get summaryLine => _insightEngine.summaryLine();

  // ─── Full Context String for AI ──────────────────────────────────────────

  /// Build a rich, structured context block with ALL user data for the AI.
  String buildAiContext() {
    final p = todayProgress;
    final buffer = StringBuffer();
    final now = DateTime.now();

    buffer.writeln('=== GROW APP — FULL USER DATA SNAPSHOT ===');
    buffer.writeln('Date: ${now.toIso8601String().split('T')[0]} | Day: ${_dayOfWeekName(now.weekday)}');

    if (userName.isNotEmpty) {
      buffer.writeln('User Name: $userName');
    }

    // 1. Steps & Physical Activity
    buffer.writeln('\n🚶 STEPS & ACTIVITY TODAY:');
    buffer.writeln('  • Steps: $todaySteps / $stepGoal goal');
    final stepPct = stepGoal > 0 ? ((todaySteps / stepGoal) * 100).round() : 0;
    buffer.writeln('  • Progress: $stepPct%');
    if (todayCalories > 0 || todayDistanceKm > 0 || todayActiveMinutes > 0) {
      buffer.writeln('  • Calories: ${todayCalories.toStringAsFixed(0)} kcal | Distance: ${todayDistanceKm.toStringAsFixed(2)} km | Active: $todayActiveMinutes mins');
    }

    // 2. Screen Time
    buffer.writeln('\n📱 SCREEN TIME TODAY: $todayScreenTime');

    // 3. Habits
    if (_habitEngine.habits.isNotEmpty) {
      buffer.writeln('\n🎯 HABITS (${_habitEngine.habits.length} active):');
      for (final h in _habitEngine.habits.take(10)) {
        final rate = (_habitEngine.completionRateThisWeek(h) * 100).round();
        final streak = h.streak;
        buffer.writeln(
            '  • ${h.title} — $rate% this week'
            '${streak > 0 ? ", $streak-day streak" : ""}');
      }
      buffer.writeln(
          '  • Overall habit rate: ${(p.weeklyHabitRate * 100).round()}% this week '
          '(vs ${(_habitEngine.overallPreviousWeekRate() * 100).round()}% last week)');
    }

    // 4. Tasks & Todos
    buffer.writeln('\n✅ TASKS & TODOS:');
    buffer.writeln('  • Completed today: ${p.tasksCompletedToday}');
    buffer.writeln('  • Pending: ${p.tasksPending}');
    if (_taskEngine.overdueCount > 0) {
      buffer.writeln('  • Overdue: ${_taskEngine.overdueCount}');
    }
    if (_taskEngine.urgentImportantTasks.isNotEmpty) {
      buffer.writeln('  • High Priority (Urgent):');
      for (final t in _taskEngine.urgentImportantTasks.take(5)) {
        buffer.writeln('    - ${t.title}');
      }
    }
    buffer.writeln('  • Completed this week: ${p.weeklyTasksCompleted}');

    // 5. Timetable / Daily Schedule
    if (timetableSlots.isNotEmpty) {
      buffer.writeln('\n📅 TIMETABLE & ROUTINE:');
      final todaySlots = timetableSlots.where((s) {
        final day = _dayOfWeekName(now.weekday);
        return s.dayOfWeek.toLowerCase() == 'daily' ||
            s.dayOfWeek.toLowerCase() == day.toLowerCase();
      }).toList();

      if (todaySlots.isNotEmpty) {
        buffer.writeln('  Today\'s Schedule:');
        for (final s in todaySlots) {
          buffer.writeln('    • ${s.startTime} - ${s.endTime}: ${s.title} (${s.category})');
        }
      } else {
        buffer.writeln('  Total active timetable slots: ${timetableSlots.length}');
      }
    }

    // 6. Reminders
    if (reminders.isNotEmpty) {
      final activeReminders = reminders.where((r) => !r.isCompleted).take(5).toList();
      if (activeReminders.isNotEmpty) {
        buffer.writeln('\n⏰ UPCOMING REMINDERS:');
        for (final r in activeReminders) {
          buffer.writeln('  • ${r.title} (${r.dateTime.toLocal().toString().substring(0, 16)})');
        }
      }
    }

    // 7. Finance
    buffer.writeln('\n💰 FINANCE:');
    buffer.writeln('  • Total balance: ₹${totalFinanceBalance.toStringAsFixed(0)}');
    if (transactions.isNotEmpty) {
      final incomeList = transactions.where((t) => t.amount > 0).take(3).toList();
      final expenseList = transactions.where((t) => t.amount < 0).take(3).toList();
      if (incomeList.isNotEmpty) {
        final recentIncome = incomeList
            .map((t) => '₹${t.amount.abs().toStringAsFixed(0)} (${t.category})')
            .join(', ');
        buffer.writeln('  • Recent income: $recentIncome');
      }
      if (expenseList.isNotEmpty) {
        final recentExpense = expenseList
            .map((t) => '₹${t.amount.abs().toStringAsFixed(0)} (${t.category})')
            .join(', ');
        buffer.writeln('  • Recent expenses: $recentExpense');
      }
    }

    // 8. Journal
    if (journals.isNotEmpty) {
      buffer.writeln('\n📖 JOURNAL:');
      buffer.writeln('  • Total entries: ${journals.length}');
      for (final j in journals.take(2)) {
        final text = j.text;
        final preview = text.length > 80 ? '${text.substring(0, 80)}…' : text;
        buffer.writeln('  • "$preview" (Mood: ${j.mood})');
      }
    }

    // 9. Best Streak
    if (p.bestStreak > 0) {
      final bestHabit = _habitEngine.bestStreakHabit();
      buffer.writeln(
          '\n🔥 BEST STREAK: ${p.bestStreak} days'
          '${bestHabit != null ? " (${bestHabit.title})" : ""}');
    }

    buffer.writeln('\n=== END OF USER CONTEXT ===');
    return buffer.toString();
  }

  static String _dayOfWeekName(int weekday) {
    switch (weekday) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return 'Today';
    }
  }

  bool messageNeedsPersonalContext(String message) => true;
}

// ─── Value Objects ─────────────────────────────────────────────────────────

class TodayProgress {
  final int habitsCompleted;
  final int habitsTotal;
  final int tasksCompletedToday;
  final int tasksPending;
  final int bestStreak;
  final double weeklyHabitRate;
  final int weeklyTasksCompleted;

  const TodayProgress({
    required this.habitsCompleted,
    required this.habitsTotal,
    required this.tasksCompletedToday,
    required this.tasksPending,
    required this.bestStreak,
    required this.weeklyHabitRate,
    required this.weeklyTasksCompleted,
  });
}
