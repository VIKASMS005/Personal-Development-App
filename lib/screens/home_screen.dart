import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_providers.dart';
import '../repositories/app_data_repository.dart';
import '../services/notification_service.dart';
import '../services/step_tracker_service.dart';
import '../models/todo.dart';
import '../widgets/ds/ds.dart';
import '../widgets/todo_widgets.dart';
import 'todo_screen.dart';
import 'habit_screen.dart';
import 'journal_screen.dart';
import 'finance_screen.dart';
import 'timetable_screen.dart';
import 'chatbot_screen.dart';
import 'alarm_screen.dart';
import 'profile_screen.dart';
import 'forms/todo_form.dart';
import 'forms/habit_form.dart';
import 'forms/journal_form.dart';
import 'forms/finance_form.dart';
import 'forms/reminder_form.dart';
import 'task_report_screen.dart';
import 'steps_screen.dart';
import 'screen_time_screen.dart';
import '../widgets/global_task_tracker_bar.dart';
import '../widgets/alarm_ringing_dialog.dart';
import '../models/alarm_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  Timer? _alarmWatcherTimer;

  // BUG 4 FIX: Use Sets keyed by (minute) so multiple alarms at the same
  // clock-minute are each rung exactly once and never spam-repeated.
  final Set<String> _rungAlarmIdsThisMinute = {};
  final Set<String> _rungReminderIdsThisMinute = {};
  int _lastWatchedMinute = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestNotificationPermission();

    NotificationService.onAlarmTriggered = (alarmId, title, snoozeCount) {
      if (!mounted) return;
      final alarms = context.read<AlarmProvider>().alarms;
      final alarm = alarms.firstWhere(
        (a) => a.id == alarmId || NotificationService.stableId(a.id).toString() == alarmId,
        orElse: () => AlarmModel(
          id: alarmId,
          uid: context.read<AuthProvider>().uid ?? 'local_user',
          hour: DateTime.now().hour,
          minute: DateTime.now().minute,
          label: title,
        ),
      );
      _showAlarmRingingDialog(alarm, snoozeCount: snoozeCount);
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllData();
      _startAlarmAndReminderWatcher();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // FIX H1: On resume, only re-init the hardware sensor listener (not the full
      // loadStepData which would create duplicate polling timers and re-register the
      // method call handler). refreshStepData is lightweight — no tracker re-init.
      final auth = context.read<AuthProvider>();
      final uid = auth.uid ?? 'local_user';
      StepTrackerService.instance.reinit();
      context.read<StepProvider>().refreshStepData(uid);
      context.read<ScreenTimeProvider>().loadScreenTime(isResume: true);
      _rebuildEngine();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarmWatcherTimer?.cancel();
    NotificationService.onAlarmTriggered = null;
    super.dispose();
  }

  bool _isShowingAlarmDialog = false;

  void _showAlarmRingingDialog(AlarmModel alarm, {int snoozeCount = 0}) {
    if (_isShowingAlarmDialog || !mounted) return;
    // BUG 13 FIX: Do not pop up dialog if app is transitioning to background/detached
    if (WidgetsBinding.instance.lifecycleState != null &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _isShowingAlarmDialog = true;

    AlarmRingingDialog.show(context, alarm, snoozeCount: snoozeCount).then((_) {
      _isShowingAlarmDialog = false;
    });
  }

  void _startAlarmAndReminderWatcher() {
    _alarmWatcherTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final now = DateTime.now();
      final currentMinute = now.hour * 60 + now.minute;

      if (!mounted) return;

      // BUG 4 FIX: When the clock minute changes, clear the rung-IDs Sets so
      // alarms at the new minute can fire. Within the same minute, each ID is
      // only allowed to ring once no matter how many 15-second ticks pass.
      if (currentMinute != _lastWatchedMinute) {
        _rungAlarmIdsThisMinute.clear();
        _rungReminderIdsThisMinute.clear();
        _lastWatchedMinute = currentMinute;
      }

      // 1. Check Alarms
      final alarms = context.read<AlarmProvider>().alarms.where((a) => a.isEnabled).toList();
      for (final alarm in alarms) {
        if (alarm.hour == now.hour && alarm.minute == now.minute) {
          // BUG 5 FIX: Only ring on the correct day of the week.
          // daysOfWeek uses ISO weekday (1=Mon..7=Sun). Empty list = every day.
          if (alarm.daysOfWeek.isNotEmpty && !alarm.daysOfWeek.contains(now.weekday)) {
            continue;
          }
          if (!_rungAlarmIdsThisMinute.contains(alarm.id)) {
            _rungAlarmIdsThisMinute.add(alarm.id);
            _showAlarmRingingDialog(alarm, snoozeCount: 0);
            break;
          }
        }
      }

      // 2. Check Reminders
      final reminders = context.read<ReminderProvider>().upcomingReminders;
      for (final rem in reminders) {
        final rDate = rem.dateTime;
        if (rDate.year == now.year &&
            rDate.month == now.month &&
            rDate.day == now.day &&
            rDate.hour == now.hour &&
            rDate.minute == now.minute) {
          if (!_rungReminderIdsThisMinute.contains(rem.id)) {
            _rungReminderIdsThisMinute.add(rem.id);
            NotificationService.playReminderRingtone();
            break;
          }
        }
      }
    });
  }

  Future<void> _loadAllData() async {
    final auth = context.read<AuthProvider>();
    final uid = auth.uid ?? 'local_user';

    await _reloadProviders(uid);

    NotificationService.scheduleDailyInspiration();
  }

  Future<void> _reloadProviders(String uid) async {
    if (!mounted) return;
    // Await all providers so the engine always rebuilds with fresh data
    await Future.wait([
      context.read<ProfileProvider>().loadProfile(uid),
      context.read<TodoProvider>().loadTodos(uid),
      context.read<HabitProvider>().loadHabits(uid),
      context.read<JournalProvider>().loadJournals(uid),
      context.read<FinanceProvider>().loadTransactions(uid),
      context.read<CalendarProvider>().loadEvents(uid),
      context.read<TimetableProvider>().loadSlots(uid),
      context.read<ChatbotProvider>().loadMessages(uid),
      context.read<ReminderProvider>().loadReminders(uid),
      context.read<AlarmProvider>().loadAlarms(uid),
      context.read<StepProvider>().loadStepData(uid),
    ]);
    if (!mounted) return;
    context.read<ScreenTimeProvider>().loadScreenTime();
    // Rebuild the Personal Development Engine with fresh data
    _rebuildEngine();
  }

  void _rebuildEngine() {
    if (!mounted) return;
    final habits = context.read<HabitProvider>().habits;
    final todos = context.read<TodoProvider>().todos;
    final journals = context.read<JournalProvider>().entries;
    final finance = context.read<FinanceProvider>();
    final timetable = context.read<TimetableProvider>().slots;
    final reminders = context.read<ReminderProvider>().reminders;
    final profile = context.read<ProfileProvider>().profile;
    final stepProv = context.read<StepProvider>();
    final screenProv = context.read<ScreenTimeProvider>();

    AppDataRepository.instance.init(
      steps: stepProv,
      screenTime: screenProv,
      habits: context.read<HabitProvider>(),
      todos: context.read<TodoProvider>(),
      finance: finance,
      journal: context.read<JournalProvider>(),
      reminders: context.read<ReminderProvider>(),
      profile: context.read<ProfileProvider>(),
      timetable: context.read<TimetableProvider>(),
    );

    context.read<EngineProvider>().rebuild(
          habits: habits,
          todos: todos,
          journals: journals,
          transactions: finance.transactions,
          timetableSlots: timetable,
          reminders: reminders,
          userName: profile?.name ?? '',
          todaySteps: stepProv.todaySteps,
          stepGoal: stepProv.stepGoal,
          todayCalories: stepProv.todayCalories,
          todayDistanceKm: stepProv.todayDistanceKm,
          todayActiveMinutes: stepProv.todayActiveMinutes,
          todayScreenTime: screenProv.todayFormattedTotal,
          totalFinanceBalance: finance.totalBalance,
        );
  }

  Future<void> _requestNotificationPermission() async {
    await NotificationService.requestPermissions();
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    if (hour >= 17 && hour < 22) return 'Good evening';
    return 'Good night';
  }

  void _openTab(int index) {
    setState(() => _currentIndex = index);
  }

  void _push(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                _buildDashboard(context),
                const TimetableScreen(),
                const ChatbotScreen(),
                const AlarmScreen(),
                const ProfileScreen(),
              ],
            ),
          ),
          const GlobalTaskTrackerBar(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.colors.divider)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) {
            setState(() => _currentIndex = idx);
            if (idx == 0) {
              final auth = context.read<AuthProvider>();
              final uid = auth.uid ?? 'local_user';
              _reloadProviders(uid);
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_view_day_outlined),
              selectedIcon: Icon(Icons.calendar_view_day_rounded),
              label: 'Timetable',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined),
              selectedIcon: Icon(Icons.auto_awesome_rounded),
              label: 'AI Coach',
            ),
            NavigationDestination(
              icon: Icon(Icons.alarm_outlined),
              selectedIcon: Icon(Icons.alarm_rounded),
              label: 'Clock',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // DASHBOARD: Today → Quick actions → Up next → Goals → Activity → Tools
  // ===========================================================================
  Widget _buildDashboard(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = context.watch<ProfileProvider>();
    final todos = context.watch<TodoProvider>();
    final habits = context.watch<HabitProvider>();
    final journal = context.watch<JournalProvider>();
    final finance = context.watch<FinanceProvider>();
    final engineProv = context.watch<EngineProvider>();
    final stepProv = context.watch<StepProvider>();
    final screenProv = context.watch<ScreenTimeProvider>();
    final reminderProv = context.watch<ReminderProvider>();

    // FIX C1: Use scheduledTasks (tasks only, not goals) for the task badge count.
    // todos.todos includes both Tasks and Goals — using it would inflate the count.
    final pendingTodos = todos.scheduledTasks; // tasks only, not completed, not missed
    final activeHabits = habits.habits;
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final habitsDoneToday = activeHabits.where((h) => h.history[todayStr] == true).length;

    // Rebuild engine when provider data changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final timetable = context.read<TimetableProvider>().slots;
      final reminders = context.read<ReminderProvider>().reminders;
      context.read<EngineProvider>().rebuild(
            habits: habits.habits,
            todos: todos.todos,
            journals: journal.entries,
            transactions: finance.transactions,
            timetableSlots: timetable,
            reminders: reminders,
            userName: profile.profile?.name ?? '',
            todaySteps: stepProv.todaySteps,
            stepGoal: stepProv.stepGoal,
            todayCalories: stepProv.todayCalories,
            todayDistanceKm: stepProv.todayDistanceKm,
            todayActiveMinutes: stepProv.todayActiveMinutes,
            todayScreenTime: screenProv.todayFormattedTotal,
            totalFinanceBalance: finance.totalBalance,
          );
    });

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    bool isToday(DateTime? d) => d != null && DateUtils.isSameDay(d, today);

    final upNext = [...pendingTodos]..sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return a.priority.compareTo(b.priority);
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
    final dueTodayPending = pendingTodos.where((t) => isToday(t.dueDate)).length;
    final remindersToday = reminderProv.upcomingReminders.where((r) => isToday(r.dateTime)).toList();
    final goals = [...todos.activeGoals]..sort((a, b) {
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
    final tasksDoneToday = engineProv.todayProgress?.tasksCompletedToday ??
        todos.completedTasks.where((t) => isToday(t.updatedAt)).length;

    Future<void> addTask() async {
      final t = await TodoForm.show(context);
      if (t != null && auth.uid != null) {
        t.uid = auth.uid!;
        await todos.addTodo(t);
      }
    }

    Future<void> addReminder() async {
      final r = await ReminderForm.show(context);
      if (r != null && auth.uid != null) {
        r.uid = auth.uid!;
        await reminderProv.addReminder(r);
      }
    }

    Future<void> addHabit() async {
      final h = await HabitForm.show(context);
      if (h != null && auth.uid != null) {
        h.uid = auth.uid!;
        await habits.addHabit(h);
      }
    }

    Future<void> addJournal() async {
      final j = await JournalForm.show(context);
      if (j != null && auth.uid != null) {
        j.uid = auth.uid!;
        await journal.addJournal(j);
      }
    }

    Future<void> addExpense() async {
      final tx = await FinanceForm.show(context);
      if (tx != null && auth.uid != null) {
        tx.uid = auth.uid!;
        await finance.addTransaction(tx);
      }
    }

    final weekStart = today.subtract(const Duration(days: 6));
    final weekSpend = finance.transactions
        .where((tx) => tx.amount < 0 && !tx.date.isBefore(weekStart))
        .fold<double>(0, (sum, tx) => sum + tx.amount.abs());
    final money = NumberFormat.compactCurrency(symbol: '₹', decimalDigits: 0);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: PageListView(
          clearFab: false,
          onRefresh: () async {
            try {
              final auth = context.read<AuthProvider>();
              final uid = auth.uid ?? 'local_user';
              await StepTrackerService.instance.refreshSteps(uid: uid);
              await _reloadProviders(uid);
            } catch (e) {
              debugPrint('[HomeScreen] Refresh error: $e');
            }
          },
          children: [
            _DashboardHeader(
              greeting: _greeting(),
              name: profile.displayName,
              date: DateFormat('EEEE, d MMMM').format(now),
              onProfile: () => _openTab(4),
            ),
            const SizedBox(height: AppSpacing.md),

            // ─── Today ──────────────────────────────────────────────────────
            _TodayCard(
              tasksDone: tasksDoneToday,
              tasksDueToday: dueTodayPending,
              tasksScheduled: pendingTodos.length,
              habitsDone: habitsDoneToday,
              habitsTotal: activeHabits.length,
              remindersToday: remindersToday.length,
              goalsActive: todos.activeGoals.length,
              insight: engineProv.insights.isNotEmpty ? engineProv.insights.first.text : null,
              onAskAI: () => _openTab(2),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ─── Quick actions ─────────────────────────────────────────────
            _QuickActions(actions: [
              _QuickAction(Icons.add_task_rounded, 'Task', addTask),
              _QuickAction(Icons.notifications_none_rounded, 'Reminder', addReminder),
              _QuickAction(Icons.repeat_rounded, 'Habit', addHabit),
              _QuickAction(Icons.edit_note_rounded, 'Journal', addJournal),
              _QuickAction(Icons.receipt_long_outlined, 'Expense', addExpense),
            ]),
            const SectionGap(),

            // ─── Up next ───────────────────────────────────────────────────
            SectionHeader(
              title: 'Up next',
              actionLabel: 'All tasks',
              onAction: () => _push(const TodosScreen()),
            ),
            if (upNext.isEmpty && remindersToday.isEmpty)
              AppCard(
                child: EmptyState(
                  compact: true,
                  icon: Icons.task_alt_rounded,
                  title: 'Nothing scheduled',
                  subtitle: 'Add a task or reminder to plan your day.',
                  action: FilledButton.tonalIcon(
                    onPressed: addTask,
                    icon: const Icon(Icons.add_rounded, size: AppSizes.iconMd),
                    label: const Text('Add task'),
                  ),
                ),
              )
            else
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                child: Column(
                  children: [
                    for (final t in upNext.take(3))
                      _UpNextTask(
                        todo: t,
                        onToggle: t.canComplete ? () => todos.toggleCompleted(t) : null,
                        onTap: () => _push(const TodosScreen()),
                      ),
                    if (upNext.isNotEmpty && remindersToday.isNotEmpty)
                      const Divider(indent: AppSpacing.md, endIndent: AppSpacing.md),
                    for (final r in remindersToday.take(2))
                      _UpNextReminder(
                        title: r.title,
                        time: DateFormat('h:mm a').format(r.dateTime),
                        onTap: () {
                          AlarmScreen.requestedTab.value = AlarmScreen.remindersTab;
                          _openTab(3);
                        },
                      ),
                  ],
                ),
              ),

            // ─── Goals ─────────────────────────────────────────────────────
            if (goals.isNotEmpty) ...[
              const SectionGap(),
              SectionHeader(
                title: 'Goals',
                actionLabel: 'All goals',
                onAction: () => _push(const TodosScreen(initialGoals: true)),
              ),
              for (final g in goals.take(2)) ...[
                GoalProgressCard(goal: g, onTap: () => _push(const TodosScreen(initialGoals: true))),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
            const SectionGap(),

            // ─── Activity ──────────────────────────────────────────────────
            const SectionHeader(title: 'Activity'),
            _StepsSummaryCard(
              steps: stepProv.todayRecord?.stepCount ?? stepProv.todaySteps,
              goal: stepProv.todayRecord?.goal ?? stepProv.dailyGoal,
              calories: stepProv.todayRecord?.calories ?? 0,
              distanceKm: stepProv.todayRecord?.distanceKm ?? 0,
              onTap: () => _push(const StepsScreen()),
            ),
            const SizedBox(height: AppSpacing.sm),
            StatRow(children: [
              StatCard(
                icon: Icons.phone_android_rounded,
                label: 'Screen time today',
                value: screenProv.todayFormattedTotal,
                onTap: () => _push(const ScreenTimeScreen()),
              ),
              StatCard(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Spent in last 7 days',
                value: money.format(weekSpend),
                onTap: () => _push(const FinanceScreen()),
              ),
            ]),
            const SectionGap(),

            // ─── All tools ─────────────────────────────────────────────────
            const SectionHeader(title: 'Your tools'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _ToolRow(
                    icon: Icons.task_alt_rounded,
                    title: 'Tasks & goals',
                    detail: '${pendingTodos.length} scheduled',
                    onTap: () => _push(const TodosScreen()),
                  ),
                  _ToolRow(
                    icon: Icons.repeat_rounded,
                    title: 'Habits',
                    detail: '$habitsDoneToday of ${activeHabits.length} done today',
                    onTap: () => _push(const HabitsScreen()),
                  ),
                  _ToolRow(
                    icon: Icons.edit_note_rounded,
                    title: 'Journal',
                    detail: '${journal.entries.length} ${journal.entries.length == 1 ? 'entry' : 'entries'}',
                    onTap: () => _push(const JournalScreen()),
                  ),
                  _ToolRow(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Finance',
                    detail: '${finance.transactions.length} ${finance.transactions.length == 1 ? 'entry' : 'entries'}',
                    onTap: () => _push(const FinanceScreen()),
                  ),
                  _ToolRow(
                    icon: Icons.directions_walk_rounded,
                    title: 'Steps & activity',
                    detail: '${NumberFormat('#,###').format(stepProv.todaySteps)} steps today',
                    onTap: () => _push(const StepsScreen()),
                  ),
                  _ToolRow(
                    icon: Icons.insights_rounded,
                    title: 'Reports',
                    detail: 'Focus time and completion',
                    onTap: () => _push(const TaskReportScreen()),
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Dashboard pieces ────────────────────────────────────────────────────────

class _DashboardHeader extends StatelessWidget {
  final String greeting;
  final String name;
  final String date;
  final VoidCallback onProfile;

  const _DashboardHeader({
    required this.greeting,
    required this.name,
    required this.date,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>().profile;
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'G';
    final photo = profile?.photoPath;
    final hasPhoto = photo != null && photo.isNotEmpty && File(photo).existsSync();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date, style: context.text.labelSmall),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '$greeting, $name',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.headlineSmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Semantics(
            button: true,
            label: 'Open profile',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onProfile,
              child: CircleAvatar(
                radius: 22,
                backgroundColor: context.scheme.primaryContainer,
                backgroundImage: hasPhoto ? FileImage(File(photo)) : null,
                child: hasPhoto
                    ? null
                    : Text(initial, style: context.text.titleSmall?.copyWith(color: context.scheme.onPrimaryContainer)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  final int tasksDone;
  final int tasksDueToday;
  final int tasksScheduled;
  final int habitsDone;
  final int habitsTotal;
  final int remindersToday;
  final int goalsActive;
  final String? insight;
  final VoidCallback onAskAI;

  const _TodayCard({
    required this.tasksDone,
    required this.tasksDueToday,
    required this.tasksScheduled,
    required this.habitsDone,
    required this.habitsTotal,
    required this.remindersToday,
    required this.goalsActive,
    required this.insight,
    required this.onAskAI,
  });

  @override
  Widget build(BuildContext context) {
    final planned = tasksDone + tasksDueToday + habitsTotal;
    final done = tasksDone + habitsDone;
    final progress = planned == 0 ? 0.0 : done / planned;
    final percent = (progress * 100).round();

    return AppCard(
      emphasized: true,
      padding: const EdgeInsets.all(AppSpacing.md + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProgressRing(
                value: progress,
                size: 72,
                strokeWidth: 8,
                child: Text('$percent%', style: context.text.titleSmall),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Today\'s progress', style: context.text.titleMedium),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      planned == 0
                          ? 'Nothing planned yet for today.'
                          : '$done of $planned planned items done',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          MetricStrip(metrics: [
            Metric(value: '$tasksDone', label: 'Tasks done'),
            Metric(value: '$habitsDone/$habitsTotal', label: 'Habits'),
            Metric(value: '$remindersToday', label: 'Reminders'),
            Metric(value: '$goalsActive', label: 'Goals'),
          ]),
          if (insight != null) ...[
            const SizedBox(height: AppSpacing.md),
            Divider(color: context.scheme.primary.withValues(alpha: 0.15)),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded, size: AppSizes.iconMd, color: context.scheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    insight!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(color: context.colors.textPrimary),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAskAI,
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs)),
              icon: const Icon(Icons.auto_awesome_rounded, size: AppSizes.iconSm),
              label: const Text('Ask Grow AI'),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction(this.icon, this.label, this.onTap);
}

class _QuickActions extends StatelessWidget {
  final List<_QuickAction> actions;
  const _QuickActions({required this.actions});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: actions
          .map((a) => Expanded(
                child: Semantics(
                  button: true,
                  label: 'Add ${a.label.toLowerCase()}',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: a.onTap,
                    borderRadius: AppRadius.mdAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: Column(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: context.scheme.surface,
                              borderRadius: AppRadius.lgAll,
                              border: Border.all(color: context.colors.border),
                            ),
                            child: Icon(a.icon, color: context.scheme.primary, size: AppSizes.iconLg),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            a.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelSmall?.copyWith(color: context.colors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _UpNextTask extends StatelessWidget {
  final Todo todo;
  final VoidCallback? onToggle;
  final VoidCallback onTap;

  const _UpNextTask({required this.todo, required this.onToggle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final due = todo.dueDate;
    String? when;
    if (due != null) {
      final now = DateTime.now();
      final hasTime = due.hour != 0 || due.minute != 0;
      if (DateUtils.isSameDay(due, now)) {
        when = hasTime ? 'Today, ${DateFormat('h:mm a').format(due)}' : 'Today';
      } else if (DateUtils.isSameDay(due, now.add(const Duration(days: 1)))) {
        when = hasTime ? 'Tomorrow, ${DateFormat('h:mm a').format(due)}' : 'Tomorrow';
      } else {
        when = DateFormat('EEE, d MMM').format(due);
      }
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xxs, AppSpacing.xxs, AppSpacing.md, AppSpacing.xxs),
        child: Row(
          children: [
            Checkbox(value: todo.completed, onChanged: onToggle == null ? null : (_) => onToggle!()),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(todo.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                  if (when != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      when,
                      style: context.text.labelSmall?.copyWith(
                        color: todo.isInGracePeriod ? context.colors.warning : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            PriorityBadge(priority: todo.priority, compact: true),
          ],
        ),
      ),
    );
  }
}

class _UpNextReminder extends StatelessWidget {
  final String title;
  final String time;
  final VoidCallback onTap;

  const _UpNextReminder({required this.title, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(Icons.notifications_none_rounded, size: AppSizes.iconMd, color: context.colors.textSecondary),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium)),
            const SizedBox(width: AppSpacing.xs),
            Text(time, style: context.text.labelMedium?.copyWith(color: context.colors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _StepsSummaryCard extends StatelessWidget {
  final int steps;
  final int goal;
  final double calories;
  final double distanceKm;
  final VoidCallback onTap;

  const _StepsSummaryCard({
    required this.steps,
    required this.goal,
    required this.calories,
    required this.distanceKm,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final progress = goal > 0 ? (steps / goal).clamp(0.0, 1.0) : 0.0;
    final nf = NumberFormat('#,###');
    return AppCard(
      onTap: onTap,
      semanticLabel: 'Steps today: ${nf.format(steps)} of ${nf.format(goal)}',
      child: Row(
        children: [
          ProgressRing(
            value: progress,
            size: 64,
            strokeWidth: 7,
            child: Icon(Icons.directions_walk_rounded, color: context.scheme.primary, size: AppSizes.iconLg),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Steps today', style: context.text.labelSmall),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: nf.format(steps), style: context.text.headlineMedium),
                    TextSpan(text: '  / ${nf.format(goal)}', style: context.text.bodySmall),
                  ])),
                ),
                const SizedBox(height: 2),
                Text(
                  '${calories.toStringAsFixed(0)} kcal · ${distanceKm.toStringAsFixed(1)} km',
                  style: context.text.labelSmall,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: context.colors.textSecondary),
        ],
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final bool showDivider;

  const _ToolRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          shape: const RoundedRectangleBorder(),
          leading: IconBadge(icon: icon, size: 36),
          title: Text(title),
          subtitle: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Icon(Icons.chevron_right_rounded, color: context.colors.textSecondary),
        ),
        if (showDivider) const Divider(indent: 68),
      ],
    );
  }
}
