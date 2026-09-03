import 'package:flutter/foundation.dart';
import '../providers/app_providers.dart';

/// AppDataRepository — single authoritative source of truth for all app domains.
///
/// Both the UI screens and Grow Bot read directly from this repository.
/// Exposes complete daily, weekly, monthly, yearly, and historical data + comparisons.
class AppDataRepository {
  static final AppDataRepository instance = AppDataRepository._internal();
  AppDataRepository._internal();

  // Injected providers — synchronized with live application state
  StepProvider? _steps;
  ScreenTimeProvider? _screenTime;
  HabitProvider? _habits;
  TodoProvider? _todos;
  FinanceProvider? _finance;
  JournalProvider? _journal;
  ReminderProvider? _reminders;
  ProfileProvider? _profile;
  TimetableProvider? _timetable;

  void init({
    required StepProvider steps,
    required ScreenTimeProvider screenTime,
    required HabitProvider habits,
    required TodoProvider todos,
    required FinanceProvider finance,
    required JournalProvider journal,
    required ReminderProvider reminders,
    required ProfileProvider profile,
    TimetableProvider? timetable,
  }) {
    _steps = steps;
    _screenTime = screenTime;
    _habits = habits;
    _todos = todos;
    _finance = finance;
    _journal = journal;
    _reminders = reminders;
    _profile = profile;
    _timetable = timetable;
  }

  // ─── Complete Step Snapshot (Daily, Weekly, Monthly, Historical) ──────────

  Map<String, dynamic> stepSnapshot() {
    final p = _steps;
    if (p == null) return {};

    final last7 = p.last7DaysRecords;
    final last30 = p.last30DaysRecords;
    final totalLast7 = last7.fold(0, (sum, r) => sum + r.stepCount);
    final totalLast30 = last30.fold(0, (sum, r) => sum + r.stepCount);

    return {
      'todaySteps': p.todaySteps,
      'dailyGoal': p.dailyGoal,
      'progressPercent': ((p.todaySteps / (p.dailyGoal > 0 ? p.dailyGoal : 1)) * 100).clamp(0, 100).round(),
      'calories': p.todayCalories.toStringAsFixed(1),
      'distanceKm': p.todayDistanceKm.toStringAsFixed(2),
      'activeMinutes': p.todayActiveMinutes,
      'weeklyTotalSteps': totalLast7,
      'weeklyDailyAverage': p.weeklyAverageSteps,
      'monthlyTotalSteps': totalLast30,
      'monthlyDailyAverage': last30.isEmpty ? 0 : (totalLast30 / last30.length).round(),
      'bestSingleDaySteps': p.bestSingleDaySteps,
      'lifetimeSteps': p.lifetimeSteps,
      'lifetimeDistanceKm': p.lifetimeDistanceKm.toStringAsFixed(2),
      'last7DaysBreakdown': last7.map((r) => {
        'date': r.date,
        'steps': r.stepCount,
        'goal': r.goal,
        'achieved': r.stepCount >= r.goal,
      }).toList(),
      'last30DaysSummary': {
        'totalSteps': totalLast30,
        'daysWithGoalMet': last30.where((r) => r.stepCount >= r.goal && r.stepCount > 0).length,
      },
    };
  }

  // ─── Complete Screen Time Snapshot (Daily, Weekly, Monthly, Trends) ───────

  Map<String, dynamic> screenTimeSnapshot() {
    final p = _screenTime;
    if (p == null) return {};

    final today = p.todaySummary;
    final weeklySummaries = p.weeklySummaries;

    // Top apps across the entire week
    final Map<String, int> weeklyAppMinutes = {};
    for (final day in weeklySummaries) {
      for (final app in day.appUsages) {
        weeklyAppMinutes[app.appName] = (weeklyAppMinutes[app.appName] ?? 0) + app.usage.inMinutes;
      }
    }
    final topWeeklyApps = weeklyAppMinutes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {
      'todayTotalMinutes': today?.totalDuration.inMinutes ?? 0,
      'todayFormatted': today != null ? _formatDuration(today.totalDuration) : '0m',
      'todayTopApps': today?.appUsages.take(7).map((a) => {
        'app': a.appName,
        'durationFormatted': _formatDuration(a.usage),
        'minutes': a.usage.inMinutes,
        'category': a.category,
      }).toList() ?? [],
      'thisWeekTotal': _formatDuration(p.thisWeekTotalDuration),
      'thisWeekMinutes': p.thisWeekTotalDuration.inMinutes,
      'thisWeekDailyAverage': '${p.weeklyDailyAverageHours.toStringAsFixed(1)}h/day',
      'lastWeekTotal': _formatDuration(p.lastWeekTotalDuration),
      'lastWeekMinutes': p.lastWeekTotalDuration.inMinutes,
      'weekOverWeekPercentChange': '${p.weeklyPercentChange >= 0 ? "+" : ""}${p.weeklyPercentChange.toStringAsFixed(1)}%',
      'topAppsThisWeek': topWeeklyApps.take(7).map((e) => {
        'app': e.key,
        'minutes': e.value,
        'formatted': '${e.value ~/ 60}h ${e.value % 60}m',
      }).toList(),
      'weeklyDaysBreakdown': weeklySummaries.map((s) => {
        'date': s.date,
        'totalMinutes': s.totalDuration.inMinutes,
        'formatted': _formatDuration(s.totalDuration),
      }).toList(),
    };
  }

  // ─── Complete Habit Snapshot (Streaks, Rates, History) ────────────────────

  Map<String, dynamic> habitSnapshot() {
    final p = _habits;
    if (p == null) return {};
    final habits = p.habits;
    final completedToday = habits.where((h) => h.isCompletedToday).length;

    return {
      'totalHabits': habits.length,
      'completedToday': completedToday,
      'todayCompletionRate': habits.isEmpty ? 0 : ((completedToday / habits.length) * 100).round(),
      'bestStreak': habits.isEmpty ? 0 : habits.map((h) => h.streak).reduce((a, b) => a > b ? a : b),
      'habits': habits.map((h) => {
        'title': h.title,
        'completedToday': h.isCompletedToday,
        'streak': h.streak,
        'frequency': h.frequency.name,
      }).toList(),
    };
  }

  // ─── Complete Task Snapshot (Pending, Completed, Grace, Missed) ───────────

  Map<String, dynamic> taskSnapshot() {
    final p = _todos;
    if (p == null) return {};

    final all = p.todos;
    final pending = all.where((t) => !t.completed && !t.isMissed).toList();
    final inGrace = all.where((t) => t.isInGracePeriod).toList();
    final missed = p.missedTodos;
    final completed = all.where((t) => t.completed).toList();

    return {
      'total': all.length,
      'completed': completed.length,
      'pending': pending.length,
      'inGracePeriod': inGrace.length,
      'missed': missed.length,
      'upcomingTasks': pending.where((t) => t.dueDate != null).take(8).map((t) => {
        'title': t.title,
        'dueDate': t.dueDate?.toIso8601String(),
        'priority': t.priority,
        'category': t.category,
        'inGrace': t.isInGracePeriod,
      }).toList(),
      'missedTasks': missed.take(5).map((t) => {
        'title': t.title,
        'dueDate': t.dueDate?.toIso8601String(),
      }).toList(),
    };
  }

  // ─── Complete Finance Snapshot (Income, Expense, Balance, Trends) ─────────

  Map<String, dynamic> financeSnapshot() {
    final p = _finance;
    if (p == null) return {};

    return {
      'totalBalance': p.totalBalance,
      'totalIncome': p.totalIncome,
      'totalExpense': p.totalExpense,
      'netSavingsRate': p.totalIncome > 0 ? (((p.totalIncome - p.totalExpense) / p.totalIncome) * 100).round() : 0,
      'recentTransactions': p.transactions.take(8).map((t) => {
        'title': t.title,
        'amount': t.amount,
        'type': t.amount >= 0 ? 'income' : 'expense',
        'category': t.category,
        'date': t.date.toIso8601String().split('T')[0],
      }).toList(),
    };
  }

  // ─── Complete Journal Snapshot (Mood Distribution & Reflections) ──────────

  Map<String, dynamic> journalSnapshot() {
    final p = _journal;
    if (p == null) return {};

    final entries = p.entries;
    final Map<String, int> moodCounts = {};
    for (final e in entries) {
      moodCounts[e.mood] = (moodCounts[e.mood] ?? 0) + 1;
    }

    return {
      'totalEntries': entries.length,
      'moodDistribution': moodCounts,
      'recentEntries': entries.take(4).map((e) => {
        'date': e.createdAt.toIso8601String().split('T')[0],
        'mood': e.mood,
        'text': e.text.length > 120 ? '${e.text.substring(0, 120)}...' : e.text,
      }).toList(),
    };
  }

  // ─── Complete Reminders Snapshot ──────────────────────────────────────────

  Map<String, dynamic> reminderSnapshot() {
    final p = _reminders;
    if (p == null) return {};

    return {
      'upcomingCount': p.upcomingReminders.length,
      'upcoming': p.upcomingReminders.take(8).map((r) => {
        'title': r.title,
        'dateTime': r.dateTime.toIso8601String(),
        'category': r.category,
      }).toList(),
    };
  }

  // ─── Complete Timetable Snapshot ──────────────────────────────────────────

  Map<String, dynamic> timetableSnapshot() {
    final p = _timetable;
    if (p == null) return {};

    return {
      'totalSlots': p.slots.length,
      'slots': p.slots.map((s) => {
        'title': s.title,
        'day': s.dayOfWeek,
        'startTime': s.startTime,
        'endTime': s.endTime,
        'category': s.category,
      }).toList(),
    };
  }

  // ─── Authoritative AI Context Builder for Grow Bot ─────────────────────────

  /// Generates the complete, rich multi-domain context for Grow Bot.
  /// Gives Grow Bot full visibility into Daily, Weekly, Monthly, and Historical data.
  String buildAiContext() {
    try {
      final userName = _profile?.profile?.name ?? 'User';
      final now = DateTime.now();

      final steps = stepSnapshot();
      final screen = screenTimeSnapshot();
      final habits = habitSnapshot();
      final tasks = taskSnapshot();
      final finance = financeSnapshot();
      final journal = journalSnapshot();
      final reminders = reminderSnapshot();
      final timetable = timetableSnapshot();

      final buf = StringBuffer();
      buf.writeln('=== GROW APP AUTHORITATIVE DATA REPOSITORY [${now.toIso8601String()}] ===');
      buf.writeln('User Name: $userName');
      buf.writeln('Current Date: ${now.toIso8601String().split("T")[0]}');
      buf.writeln();

      // 1. SCREEN TIME (Daily + Weekly + Trends + Top Apps)
      buf.writeln('--- 📱 SCREEN TIME & DIGITAL USAGE ---');
      buf.writeln('• Today\'s Total Screen Time: ${screen["todayFormatted"]} (${screen["todayTotalMinutes"]} mins)');
      final todayTop = screen['todayTopApps'] as List? ?? [];
      if (todayTop.isNotEmpty) {
        buf.writeln('  Today\'s Used Apps:');
        for (final a in todayTop) {
          buf.writeln('    - ${a["app"]}: ${a["durationFormatted"]} (${a["category"]})');
        }
      }
      buf.writeln('• This Week Total: ${screen["thisWeekTotal"]} | Daily Avg: ${screen["thisWeekDailyAverage"]}');
      buf.writeln('• Last Week Total: ${screen["lastWeekTotal"]}');
      buf.writeln('• Week-over-Week Change: ${screen["weekOverWeekPercentChange"]}');
      final weekTop = screen['topAppsThisWeek'] as List? ?? [];
      if (weekTop.isNotEmpty) {
        buf.writeln('• Top Apps This Week: ${weekTop.map((a) => "${a['app']} (${a['formatted']})").join(", ")}');
      }
      final weekDays = screen['weeklyDaysBreakdown'] as List? ?? [];
      if (weekDays.isNotEmpty) {
        buf.writeln('• Daily Breakdown This Week: ${weekDays.map((d) => "${d['date']}: ${d['formatted']}").join(", ")}');
      }
      buf.writeln();

      // 2. STEPS & PHYSICAL ACTIVITY (Daily + Weekly + Monthly + Lifetime)
      buf.writeln('--- 🚶 STEPS & PHYSICAL ACTIVITY ---');
      buf.writeln('• Today\'s Steps: ${steps["todaySteps"]} / ${steps["dailyGoal"]} goal (${steps["progressPercent"]}%)');
      buf.writeln('• Today\'s Calories: ${steps["calories"]} kcal | Distance: ${steps["distanceKm"]} km | Active Time: ${steps["activeMinutes"]} mins');
      buf.writeln('• Weekly Total (Last 7 Days): ${steps["weeklyTotalSteps"]} steps (Avg: ${steps["weeklyDailyAverage"]} steps/day)');
      buf.writeln('• Monthly Total (Last 30 Days): ${steps["monthlyTotalSteps"]} steps (Avg: ${steps["monthlyDailyAverage"]} steps/day)');
      buf.writeln('• Best Single Day Ever: ${steps["bestSingleDaySteps"]} steps');
      buf.writeln('• Lifetime Steps: ${steps["lifetimeSteps"]} steps (${steps["lifetimeDistanceKm"]} km)');
      final last7 = steps['last7DaysBreakdown'] as List? ?? [];
      if (last7.isNotEmpty) {
        buf.writeln('• Past 7 Days: ${last7.map((d) => "${d['date']}: ${d['steps']} steps (${d['achieved'] == true ? 'Goal Met' : 'Incomplete'})").join(", ")}');
      }
      buf.writeln();

      // 3. HABITS (Streaks + Consistency)
      buf.writeln('--- 🎯 HABITS & ROUTINES ---');
      buf.writeln('• Today\'s Completed Habits: ${habits["completedToday"]}/${habits["totalHabits"]} (${habits["todayCompletionRate"]}%)');
      buf.writeln('• Best Current Streak: ${habits["bestStreak"]} days');
      final habitList = habits['habits'] as List? ?? [];
      for (final h in habitList) {
        buf.writeln('  ${h["completedToday"] == true ? "✓" : "○"} ${h["title"]} — Streak: ${h["streak"]} days (${h["frequency"]})');
      }
      buf.writeln();

      // 4. TASKS & GOALS (Deadlines, Grace Period, Missed)
      buf.writeln('--- ✅ TASKS & GOALS ---');
      buf.writeln('• Summary: ${tasks["completed"]} completed, ${tasks["pending"]} pending, ${tasks["inGracePeriod"]} in 2h grace period, ${tasks["missed"]} missed (Total: ${tasks["total"]})');
      final upcomingTasks = tasks['upcomingTasks'] as List? ?? [];
      if (upcomingTasks.isNotEmpty) {
        buf.writeln('  Active Upcoming Tasks:');
        for (final t in upcomingTasks) {
          final grace = t['inGrace'] == true ? ' [⏳ IN 2-HOUR GRACE PERIOD]' : '';
          buf.writeln('    - ${t["title"]} (Due: ${t["dueDate"]}, Priority: P${t["priority"]})$grace');
        }
      }
      final missedTasks = tasks['missedTasks'] as List? ?? [];
      if (missedTasks.isNotEmpty) {
        buf.writeln('  Missed Tasks: ${missedTasks.map((t) => t["title"]).join(", ")}');
      }
      buf.writeln();

      // 5. FINANCE (Income, Expenses, Net Balance)
      buf.writeln('--- 💰 FINANCE ---');
      buf.writeln('• Balance: ₹${finance["totalBalance"]} | Total Income: ₹${finance["totalIncome"]} | Total Expenses: ₹${finance["totalExpense"]} | Savings Rate: ${finance["netSavingsRate"]}%');
      final txList = finance['recentTransactions'] as List? ?? [];
      if (txList.isNotEmpty) {
        buf.writeln('  Recent Transactions: ${txList.map((t) => "${t['title']}: ₹${t['amount']} (${t['category']}, ${t['date']})").join("; ")}');
      }
      buf.writeln();

      // 6. JOURNAL & MENTAL WELLNESS
      buf.writeln('--- 📖 JOURNAL & REFLECTIONS ---');
      buf.writeln('• Total Entries: ${journal["totalEntries"]}');
      final moods = journal['moodDistribution'] as Map? ?? {};
      if (moods.isNotEmpty) {
        buf.writeln('• Mood Distribution: ${moods.entries.map((e) => "${e.key}: ${e.value}").join(", ")}');
      }
      final recentJ = journal['recentEntries'] as List? ?? [];
      for (final e in recentJ) {
        buf.writeln('  [${e["date"]}] Mood: ${e["mood"]} — "${e["text"]}"');
      }
      buf.writeln();

      // 7. REMINDERS & TIMETABLE
      buf.writeln('--- ⏰ SCHEDULED REMINDERS ---');
      final upcomingR = reminders['upcoming'] as List? ?? [];
      if (upcomingR.isEmpty) {
        buf.writeln('None currently scheduled.');
      } else {
        for (final r in upcomingR) {
          buf.writeln('  • ${r["title"]} scheduled for ${r["dateTime"]} [${r["category"]}]');
        }
      }
      buf.writeln();

      final slots = timetable['slots'] as List? ?? [];
      if (slots.isNotEmpty) {
        buf.writeln('--- 📅 TIMETABLE & DAILY SCHEDULE ---');
        for (final s in slots) {
          buf.writeln('  • ${s["day"]}: ${s["startTime"]} - ${s["endTime"]} → ${s["title"]} (${s["category"]})');
        }
        buf.writeln();
      }

      buf.writeln('=== END OF REPOSITORY CONTEXT ===');
      return buf.toString();
    } catch (e, st) {
      debugPrint('[AppDataRepository] Error building AI context: $e\n$st');
      return 'Error loading app data context.';
    }
  }

  static String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }
}
