import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../providers/app_providers.dart';
import '../services/sync_service.dart';
import '../services/notification_service.dart';
import '../utils/app_colors.dart';
import '../widgets/custom_bottom_nav.dart';
import '../widgets/weekly_expense_chart.dart';
import '../widgets/alarm_ringing_dialog.dart';
import 'todo_screen.dart';
import 'habit_screen.dart';
import 'journal_screen.dart';
import 'finance_screen.dart';
import 'alarm_screen.dart';
import 'profile_screen.dart';
import 'timetable_screen.dart';
import 'chatbot_screen.dart';
import 'forms/todo_form.dart';
import 'forms/habit_form.dart';
import 'forms/journal_form.dart';
import 'forms/finance_form.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  Timer? _alarmWatcherTimer;
  String? _lastRungAlarmId;
  int _lastRungMinute = -1;
  String? _lastRungReminderId;
  int _lastRungReminderMinute = -1;

  @override
  void initState() {
    super.initState();
    _requestNotificationPermission();

    SyncService.instance.onSyncCompleted = () {
      if (mounted) {
        final auth = context.read<AuthProvider>();
        final uid = auth.uid;
        if (uid != null) {
          _reloadProviders(uid, auth);
        }
      }
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllData();
      _startAlarmAndReminderWatcher();
    });
  }

  @override
  void dispose() {
    _alarmWatcherTimer?.cancel();
    SyncService.instance.onSyncCompleted = null;
    super.dispose();
  }

  void _startAlarmAndReminderWatcher() {
    _alarmWatcherTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      final now = DateTime.now();

      // 1. Check Alarms
      final alarmProv = context.read<AlarmProvider>();
      final alarms = alarmProv.alarms.where((a) => a.isEnabled);
      for (final alarm in alarms) {
        if (alarm.hour == now.hour && alarm.minute == now.minute && now.second <= 2) {
          final matchesDay =
              alarm.daysOfWeek.isEmpty || alarm.daysOfWeek.contains(now.weekday);
          if (matchesDay &&
              (_lastRungAlarmId != alarm.id || _lastRungMinute != now.minute)) {
            _lastRungAlarmId = alarm.id;
            _lastRungMinute = now.minute;
            AlarmRingingDialog.show(context, alarm);
            break;
          }
        }
      }

      // 2. Check Reminders
      final reminderProv = context.read<ReminderProvider>();
      final reminders = reminderProv.reminders.where((r) => !r.isCompleted);
      for (final reminder in reminders) {
        if (reminder.dateTime.year == now.year &&
            reminder.dateTime.month == now.month &&
            reminder.dateTime.day == now.day &&
            reminder.dateTime.hour == now.hour &&
            reminder.dateTime.minute == now.minute &&
            now.second <= 2) {
          if (_lastRungReminderId != reminder.id || _lastRungReminderMinute != now.minute) {
            _lastRungReminderId = reminder.id;
            _lastRungReminderMinute = now.minute;
            NotificationService.playReminderRingtone();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.notifications_active_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(child: Text('🔔 Reminder: ${reminder.title}')),
                  ],
                ),
                backgroundColor: AppColors.primary,
                duration: const Duration(seconds: 4),
              ),
            );
            break;
          }
        }
      }
    });
  }

  Future<void> _loadAllData() async {
    final auth = context.read<AuthProvider>();
    final uid = auth.uid;
    if (uid != null) {
      SyncService.instance.init(uid);
      _reloadProviders(uid, auth);

      // Restore and pull all user data from Firebase into SQLite
      try {
        await SyncService.instance.syncNow();
        if (mounted) {
          _reloadProviders(uid, auth);
        }
      } catch (e) {
        debugPrint('Cloud restore warning in _loadAllData: $e');
      }

      NotificationService.scheduleDailyInspiration();
    }
  }

  void _reloadProviders(String uid, AuthProvider auth) {
    if (!mounted) return;
    context.read<ProfileProvider>().loadProfile(uid, email: auth.user?.email, displayName: auth.user?.displayName);
    context.read<TodoProvider>().loadTodos(uid);
    context.read<HabitProvider>().loadHabits(uid);
    context.read<JournalProvider>().loadJournals(uid);
    context.read<FinanceProvider>().loadTransactions(uid);
    context.read<CalendarProvider>().loadEvents(uid);
    context.read<TimetableProvider>().loadSlots(uid);
    context.read<ChatbotProvider>().loadMessages(uid);
    context.read<ReminderProvider>().loadReminders(uid);
    context.read<AlarmProvider>().loadAlarms(uid);
  }

  Future<void> _requestNotificationPermission() async {
    await NotificationService.requestPermissions();
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good Morning';
    if (hour >= 12 && hour < 17) return 'Good Afternoon';
    if (hour >= 17 && hour < 22) return 'Good Evening';
    return 'Good Night';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildDashboard(context),
          const TimetableScreen(),
          const ChatbotScreen(),
          const AlarmScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: GrowBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
      ),
    );
  }

  Widget _buildDashboard(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final profile = context.watch<ProfileProvider>();
    final sync = context.watch<SyncService>();
    final todos = context.watch<TodoProvider>();
    final habits = context.watch<HabitProvider>();
    final journal = context.watch<JournalProvider>();
    final finance = context.watch<FinanceProvider>();

    final pendingTodos = todos.todos.where((t) => !t.completed).toList();
    final activeHabits = habits.habits;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            // Glowing Infinity Sprout Logo
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/app_logo.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppColors.primary,
                    child: const Icon(Icons.eco_rounded, size: 22, color: Colors.white),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_greeting()}, ${profile.displayName}!',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Grow Daily OS',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Live Cloud Sync Status Pill
          GestureDetector(
            onTap: () => sync.syncNow(),
            child: Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: sync.isSyncing
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : (sync.hasError
                        ? AppColors.error.withValues(alpha: 0.15)
                        : AppColors.success.withValues(alpha: 0.12)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    sync.isSyncing
                        ? Icons.sync_rounded
                        : (sync.hasError ? Icons.sync_problem_rounded : Icons.cloud_done_rounded),
                    size: 14,
                    color: sync.isSyncing
                        ? AppColors.primary
                        : (sync.hasError ? AppColors.error : AppColors.success),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    sync.isSyncing
                        ? 'Syncing'
                        : (sync.hasError ? 'Offline' : 'Synced'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: sync.isSyncing
                          ? AppColors.primary
                          : (sync.hasError ? AppColors.error : AppColors.success),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
            children: [
              // 1. Weekly Expenditure Bar Chart (Primary Requirement)
              WeeklyExpenseChart(
                transactions: finance.transactions,
                onTapDetails: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FinanceScreen()),
                  );
                },
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05),
              const SizedBox(height: 18),

              // Section Header: Core Focus Modules
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Daily Focus Modules',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '4 Core Areas',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ==================== MODULE 1: TASKS ====================
              _ModuleCard(
                title: 'Tasks & Matrix',
                subtitle: '${pendingTodos.length} pending · ${todos.todos.length - pendingTodos.length} done',
                badgeText: '${pendingTodos.length} Tasks',
                icon: Icons.task_alt_rounded,
                color: AppColors.tasks,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TodosScreen()),
                  );
                },
                onAdd: () async {
                  final t = await TodoForm.show(context);
                  if (t != null && auth.uid != null) {
                    t.uid = auth.uid!;
                    await todos.addTodo(t);
                  }
                },
                child: pendingTodos.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '🎉 All caught up! Tap + to schedule your next goal.',
                          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      )
                    : Column(
                        children: pendingTodos.take(2).map((t) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.circle_outlined,
                                  size: 14,
                                  color: AppColors.tasks,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    t.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (t.reminderDateTime != null)
                                  const Icon(Icons.notifications_active_rounded, size: 13, color: AppColors.alarm),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
              const SizedBox(height: 14),

              // ==================== MODULE 2: HABITS ====================
              _ModuleCard(
                title: 'Habits & Streaks',
                subtitle: '${activeHabits.length} daily habits active',
                badgeText: '${activeHabits.length} Habits',
                icon: Icons.local_fire_department_rounded,
                color: AppColors.habits,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HabitsScreen()),
                  );
                },
                onAdd: () async {
                  final h = await HabitForm.show(context);
                  if (h != null && auth.uid != null) {
                    h.uid = auth.uid!;
                    await habits.addHabit(h);
                  }
                },
                child: activeHabits.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '🔥 Start building atomic habits! Tap + to add.',
                          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: activeHabits.take(3).map((h) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.habits.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  h.title,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.habits,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${h.streak}🔥',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
              const SizedBox(height: 14),

              // ==================== MODULE 3: JOURNAL ====================
              _ModuleCard(
                title: 'Journal & Reflections',
                subtitle: '${journal.entries.length} reflections recorded',
                badgeText: '${journal.entries.length} Entries',
                icon: Icons.auto_stories_rounded,
                color: AppColors.journal,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const JournalScreen()),
                  );
                },
                onAdd: () async {
                  final j = await JournalForm.show(context);
                  if (j != null && auth.uid != null) {
                    j.uid = auth.uid!;
                    await journal.addJournal(j);
                  }
                },
                child: journal.entries.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '📖 Clear your mind with daily reflections and mood tracking.',
                          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                        ),
                      )
                    : Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.journal.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              journal.entries.first.mood,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              journal.entries.first.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                            ),
                          ),
                        ],
                      ),
              ).animate().fadeIn(duration: 400.ms, delay: 300.ms),
              const SizedBox(height: 14),

              // ==================== MODULE 4: FINANCE ====================
              _ModuleCard(
                title: 'Finance & Budget',
                subtitle: 'Total Balance: ₹${finance.totalBalance.toStringAsFixed(2)}',
                badgeText: '₹${finance.totalBalance.toStringAsFixed(0)}',
                icon: Icons.account_balance_wallet_rounded,
                color: AppColors.finance,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FinanceScreen()),
                  );
                },
                onAdd: () async {
                  final tx = await FinanceForm.show(context);
                  if (tx != null && auth.uid != null) {
                    tx.uid = auth.uid!;
                    await finance.addTransaction(tx);
                  }
                },
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.arrow_upward_rounded, size: 14, color: AppColors.success),
                            const SizedBox(width: 4),
                            Text(
                              '+₹${finance.totalIncome.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.success),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.arrow_downward_rounded, size: 14, color: AppColors.error),
                            const SizedBox(width: 4),
                            Text(
                              '-₹${finance.totalExpense.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.error),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 400.ms),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badgeText;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final Widget child;

  const _ModuleCard({
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.onAdd,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.add_circle_outline_rounded, color: color, size: 22),
                    onPressed: onAdd,
                    tooltip: 'Add new item',
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
