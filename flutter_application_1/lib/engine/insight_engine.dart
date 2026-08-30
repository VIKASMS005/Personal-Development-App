import 'habit_engine.dart';
import 'task_engine.dart';
import '../models/journal_entry.dart';
import '../models/finance_transaction.dart';

/// Type of insight — controls icon and color in UI.
enum InsightType { success, warning, info }

/// A single deterministic, data-driven insight generated offline.
class GrowInsight {
  final String text;
  final InsightType type;
  final String icon;

  const GrowInsight({
    required this.text,
    required this.type,
    required this.icon,
  });
}

/// Offline Insight Engine.
/// Generates personalized insights from real user data using
/// deterministic logic only. No AI, no network. Always works offline.
class InsightEngine {
  final HabitEngine habitEngine;
  final TaskEngine taskEngine;
  final List<JournalEntry> journals;
  final List<FinanceTransaction> transactions;

  InsightEngine({
    required this.habitEngine,
    required this.taskEngine,
    required this.journals,
    required this.transactions,
  });

  /// Generate a list of relevant insights based on current user data.
  /// Returns at most [maxInsights] insights, ordered by priority.
  List<GrowInsight> generateInsights({int maxInsights = 5}) {
    final insights = <GrowInsight>[];

    // 1. Habit streak celebration
    final bestHabit = habitEngine.bestStreakHabit();
    if (bestHabit != null && bestHabit.streak >= 3) {
      insights.add(GrowInsight(
        text: 'You\'re on a ${bestHabit.streak}-day streak with "${bestHabit.title}". '
            'Keep the momentum going today!',
        type: InsightType.success,
        icon: '🔥',
      ));
    }

    // 2. Weekly habit improvement
    final thisWeekRate = habitEngine.overallWeeklyRate();
    final lastWeekRate = habitEngine.overallPreviousWeekRate();
    if (lastWeekRate > 0.05 && thisWeekRate > lastWeekRate + 0.1) {
      final diff = ((thisWeekRate - lastWeekRate) * 100).round();
      insights.add(GrowInsight(
        text: 'Your habit consistency improved by $diff% this week. '
            'You\'re building real momentum.',
        type: InsightType.success,
        icon: '📈',
      ));
    }

    // 3. Weekly habit drop
    if (lastWeekRate > 0.4 && thisWeekRate < lastWeekRate - 0.15) {
      insights.add(GrowInsight(
        text: 'Your habit completion has dropped this week. '
            'Try focusing on just one key habit to regain consistency.',
        type: InsightType.warning,
        icon: '📉',
      ));
    }

    // 4. Habits at risk (missed 2+ days)
    final atRisk = habitEngine.habitsAtRisk();
    if (atRisk.isNotEmpty) {
      final names = atRisk.take(2).map((h) => '"${h.title}"').join(' and ');
      insights.add(GrowInsight(
        text: 'You\'ve missed $names for 2+ days. '
            'A small action today is better than a missed day.',
        type: InsightType.warning,
        icon: '⚠️',
      ));
    }

    // 5. All habits done today
    final completedToday = habitEngine.completedTodayCount();
    final totalHabits = habitEngine.habits.length;
    if (totalHabits > 0 && completedToday == totalHabits) {
      insights.add(GrowInsight(
        text: 'All $totalHabits habits completed today! '
            'Outstanding discipline.',
        type: InsightType.success,
        icon: '✅',
      ));
    } else if (totalHabits > 0 && completedToday == 0) {
      final hour = DateTime.now().hour;
      if (hour >= 10) {
        insights.add(GrowInsight(
          text: 'You haven\'t completed any habits today yet. '
              'Starting with one small habit can set the tone for the rest of your day.',
          type: InsightType.info,
          icon: '💡',
        ));
      }
    }

    // 6. Overdue tasks
    final overdueCount = taskEngine.overdueCount;
    if (overdueCount == 1) {
      final task = taskEngine.overdueIncomplete.first;
      insights.add(GrowInsight(
        text: '"${task.title}" is past its deadline. '
            'Take 15 minutes to tackle it now.',
        type: InsightType.warning,
        icon: '⏰',
      ));
    } else if (overdueCount > 1) {
      insights.add(GrowInsight(
        text: 'You have $overdueCount overdue tasks. '
            'Focus on the most urgent one first — even partial progress counts.',
        type: InsightType.warning,
        icon: '⏰',
      ));
    }

    // 7. Pending high-priority tasks
    final q1 = taskEngine.q1Tasks.length;
    if (q1 > 0) {
      insights.add(GrowInsight(
        text: 'You have $q1 urgent & important task${q1 > 1 ? 's' : ''} pending. '
            'These deserve your first attention today.',
        type: InsightType.warning,
        icon: '🎯',
      ));
    }

    // 8. Task completion improvement
    final completedThisWeek = taskEngine.completedThisWeek;
    final completedLastWeek = taskEngine.completedLastWeek;
    if (completedLastWeek > 0 && completedThisWeek > completedLastWeek) {
      insights.add(GrowInsight(
        text: 'You\'ve completed more tasks this week than last week '
            '($completedThisWeek vs $completedLastWeek). Great progress!',
        type: InsightType.success,
        icon: '📋',
      ));
    }

    // 9. Journaling nudge
    if (journals.isNotEmpty) {
      final lastEntry = journals.first.createdAt;
      final daysSince = DateTime.now().difference(lastEntry).inDays;
      if (daysSince >= 3) {
        insights.add(GrowInsight(
          text: 'You haven\'t journaled in $daysSince days. '
              'A few minutes of reflection can improve your focus and clarity.',
          type: InsightType.info,
          icon: '📓',
        ));
      }
    } else {
      insights.add(GrowInsight(
        text: 'Start journaling to track your thoughts and moods over time. '
            'Even 2–3 sentences a day makes a difference.',
        type: InsightType.info,
        icon: '📓',
      ));
    }

    // 10. Finance: expenses exceeding income this month
    final now = DateTime.now();
    final monthTxns = transactions.where((t) =>
        t.date.year == now.year && t.date.month == now.month);
    final income = monthTxns
        .where((t) => t.amount > 0)
        .fold(0.0, (s, t) => s + t.amount);
    final expense = monthTxns
        .where((t) => t.amount < 0)
        .fold(0.0, (s, t) => s + t.amount.abs());
    if (income > 0 && expense > income * 0.9) {
      insights.add(GrowInsight(
        text: 'Your expenses this month are close to your income. '
            'Review your spending to stay on track financially.',
        type: InsightType.warning,
        icon: '💰',
      ));
    }

    return insights.take(maxInsights).toList();
  }

  /// Generate a single summary line for the dashboard (always offline).
  String summaryLine() {
    final habits = habitEngine.habits.length;
    final doneTodayH = habitEngine.completedTodayCount();
    final tasksDone = taskEngine.completedTodayCount;
    final tasksPending = taskEngine.pendingCount;
    final streak = habitEngine.bestCurrentStreak();

    final parts = <String>[];
    if (habits > 0) parts.add('$doneTodayH/$habits habits done today');
    if (tasksDone > 0 || tasksPending > 0) {
      parts.add('$tasksDone task${tasksDone != 1 ? 's' : ''} completed');
    }
    if (streak >= 3) parts.add('🔥 $streak-day streak');

    if (parts.isEmpty) return 'Start your day — add a habit or task!';
    return parts.join(' · ');
  }
}
