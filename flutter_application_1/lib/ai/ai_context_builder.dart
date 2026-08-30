import '../engine/grow_engine.dart';
import '../repositories/app_data_repository.dart';

/// Decides whether to include personal Grow data in an AI request,
/// and if so, builds a clean structured context block from the central AppDataRepository.
///
/// The AI has FULL access to all user data — daily, weekly, monthly, yearly,
/// and historical metrics across habits, tasks, steps, screen time, finance, journal,
/// and reminders — so it can accurately answer any question or comparison.
class AiContextBuilder {
  /// Injects complete authoritative user context into every AI request so the bot
  /// can answer questions about today, this week, last week, this month, trends, and comparisons.
  static String? buildIfRelevant({
    required String message,
    required GrowEngine engine,
  }) {
    final repoContext = AppDataRepository.instance.buildAiContext();
    if (repoContext.isNotEmpty && repoContext != 'Error loading app data context.') {
      return repoContext;
    }
    return engine.buildAiContext();
  }

  /// Returns full context from authoritative data repository.
  static String buildFull(GrowEngine engine) {
    final repoContext = AppDataRepository.instance.buildAiContext();
    if (repoContext.isNotEmpty && repoContext != 'Error loading app data context.') {
      return repoContext;
    }
    return engine.buildAiContext();
  }

  /// Short inline summary if needed.
  static String buildCompact(GrowEngine engine) {
    final p = engine.todayProgress;
    final parts = <String>[];

    parts.add('Steps today: ${engine.todaySteps}/${engine.stepGoal}');
    parts.add('Screen time: ${engine.todayScreenTime}');

    if (p.habitsTotal > 0) {
      parts.add(
          'Habits: ${p.habitsCompleted}/${p.habitsTotal} done today, '
          '${(p.weeklyHabitRate * 100).round()}% this week');
    }
    if (p.tasksPending > 0 || p.tasksCompletedToday > 0) {
      parts.add(
          'Tasks: ${p.tasksCompletedToday} done today, ${p.tasksPending} pending');
    }
    if (p.bestStreak > 0) {
      parts.add('Best streak: ${p.bestStreak} days');
    }
    parts.add('Finance balance: ₹${engine.totalFinanceBalance.toStringAsFixed(0)}');

    if (parts.isEmpty) return '';
    return 'User\'s Grow data — ${parts.join("; ")}';
  }
}