import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_providers.dart';
import '../repositories/app_data_repository.dart';
import '../services/notification_service.dart';
import '../services/step_tracker_service.dart';
import '../utils/app_colors.dart';
import '../widgets/weekly_expense_chart.dart';
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
import 'steps_screen.dart';
import 'screen_time_screen.dart';
import '../widgets/global_task_tracker_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  Timer? _alarmWatcherTimer;
  String? _lastRungAlarmId;
  int _lastRungMinute = -1;
  String? _lastRungReminderId;
  int _lastRungReminderMinute = -1;

  final PageController _analyticsPageController = PageController();
  int _activeAnalyticsSlide = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestNotificationPermission();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllData();
      _startAlarmAndReminderWatcher();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-read hardware step sensor and refresh screen time when app returns to foreground
      final auth = context.read<AuthProvider>();
      final uid = auth.uid ?? 'local_user';
      StepTrackerService.instance.reinit();
      context.read<StepProvider>().loadStepData(uid);
      context.read<ScreenTimeProvider>().loadScreenTime(isResume: true);
      _rebuildEngine();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarmWatcherTimer?.cancel();
    _analyticsPageController.dispose();
    super.dispose();
  }

  bool _isShowingAlarmDialog = false;

  void _showAlarmRingingDialog(String alarmLabel) {
    if (_isShowingAlarmDialog || !mounted) return;
    _isShowingAlarmDialog = true;
    NotificationService.playAlarmRingtone();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Text('⏰ ', style: TextStyle(fontSize: 26)),
              Expanded(
                child: Text(
                  alarmLabel.isNotEmpty ? alarmLabel : 'Alarm Ringing',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
            ],
          ),
          content: const Text(
            'Time for your scheduled routine! Wake up and attack the day.',
            style: TextStyle(fontSize: 14),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.snooze_rounded),
              label: const Text('Snooze (+5m)'),
              onPressed: () {
                NotificationService.stopRingtone();
                _isShowingAlarmDialog = false;
                Navigator.pop(dialogCtx);
              },
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.alarm_off_rounded),
              label: const Text('Dismiss'),
              onPressed: () {
                NotificationService.stopRingtone();
                _isShowingAlarmDialog = false;
                Navigator.pop(dialogCtx);
              },
            ),
          ],
        ),
      ),
    ).then((_) {
      NotificationService.stopRingtone();
      _isShowingAlarmDialog = false;
    });
  }

  void _startAlarmAndReminderWatcher() {
    _alarmWatcherTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final now = DateTime.now();
      final currentMinute = now.hour * 60 + now.minute;

      if (!mounted) return;

      // 1. Check Alarms
      final alarms = context.read<AlarmProvider>().alarms.where((a) => a.isEnabled).toList();
      for (final alarm in alarms) {
        if (alarm.hour == now.hour && alarm.minute == now.minute) {
          if (_lastRungAlarmId != alarm.id || _lastRungMinute != currentMinute) {
            _lastRungAlarmId = alarm.id;
            _lastRungMinute = currentMinute;
            _showAlarmRingingDialog(alarm.label);
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
          if (_lastRungReminderId != rem.id || _lastRungReminderMinute != currentMinute) {
            _lastRungReminderId = rem.id;
            _lastRungReminderMinute = currentMinute;
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
    if (hour >= 5 && hour < 12) return 'Good Morning';
    if (hour >= 12 && hour < 17) return 'Good Afternoon';
    if (hour >= 17 && hour < 22) return 'Good Evening';
    return 'Good Night';
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
      bottomNavigationBar: NavigationBar(
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
            icon: Icon(Icons.table_chart_outlined),
            selectedIcon: Icon(Icons.table_chart_rounded),
            label: 'Timetable',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology_rounded),
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
    );
  }

  // ===========================================================================
  // DASHBOARD BUILDER (Sliding Analytics Carousel + 2x2 Focus Modules Grid)
  // ===========================================================================
  Widget _buildDashboard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();
    final profile = context.watch<ProfileProvider>();
    final todos = context.watch<TodoProvider>();
    final habits = context.watch<HabitProvider>();
    final journal = context.watch<JournalProvider>();
    final finance = context.watch<FinanceProvider>();
    final engineProv = context.watch<EngineProvider>();
    final stepProv = context.watch<StepProvider>();
    final screenProv = context.watch<ScreenTimeProvider>();

    final pendingTodos = todos.todos.where((t) => !t.completed).toList();
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

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            // App Logo
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
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: RefreshIndicator(
            color: AppColors.primary,
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
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              children: [
              // ─── 1. Sliding Analytics Carousel (One Card at a Time) ───────
              SizedBox(
                height: 250,
                child: PageView(
                  controller: _analyticsPageController,
                  onPageChanged: (index) {
                    setState(() => _activeAnalyticsSlide = index);
                  },
                  children: [
                    // Slide 0: Today's Progress + Engine Insights
                    _TodayProgressCard(
                      engineProv: engineProv,
                      onAskAI: () => setState(() => _currentIndex = 2),
                    ),

                    // Slide 1: Weekly Expenditure Bar Chart
                    WeeklyExpenseChart(
                      transactions: finance.transactions,
                      onTapDetails: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const FinanceScreen()),
                        );
                      },
                    ),

                    // Slide 2: Precision Steps Counter
                    _buildStepsCarouselCard(theme, isDark, stepProv),

                    // Slide 3: Device Screen Time (All Apps)
                    _buildScreenTimeCarouselCard(theme, isDark, screenProv),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ─── 2. Dot Pagination Indicators ─────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (idx) {
                  final isActive = _activeAnalyticsSlide == idx;
                  return GestureDetector(
                    onTap: () {
                      _analyticsPageController.animateToPage(
                        idx,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.primary
                            : theme.colorScheme.onSurface.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),

              // ─── 3. Section Header: Core Focus Modules ────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Daily Focus Modules',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ─── 4. 2x3 Focus Modules Grid ─────────────────────────────────
              Row(
                children: [
                  // Module 1: Tasks and Goals
                  Expanded(
                    child: _CompactModuleTile(
                      title: 'Tasks and Goals',
                      subtitle: '${pendingTodos.length} scheduled',
                      icon: Icons.task_alt_rounded,
                      color: AppColors.tasks,
                      badgeText: '${pendingTodos.length}',
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
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Module 2: Habits & Routine
                  Expanded(
                    child: _CompactModuleTile(
                      title: 'Habits & Routine',
                      subtitle: '$habitsDoneToday/${activeHabits.length} done',
                      icon: Icons.repeat_rounded,
                      color: AppColors.habits,
                      badgeText: '${activeHabits.length}',
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
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Module 3: Daily Journal
                  Expanded(
                    child: _CompactModuleTile(
                      title: 'Daily Journal',
                      subtitle: '${journal.entries.length} reflections',
                      icon: Icons.edit_note_rounded,
                      color: AppColors.journal,
                      badgeText: '${journal.entries.length}',
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
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Module 4: Finance & Budget
                  Expanded(
                    child: _CompactModuleTile(
                      title: 'Finance & Budget',
                      subtitle: NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(finance.totalExpense),
                      icon: Icons.account_balance_wallet_rounded,
                      color: AppColors.finance,
                      badgeText: finance.transactions.isNotEmpty ? 'Active' : '0',
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
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Module 5: Steps & Activity
                  Expanded(
                    child: _CompactModuleTile(
                      title: 'Steps & Activity',
                      subtitle: '${NumberFormat('#,###').format(stepProv.todaySteps)} / ${NumberFormat('#,###').format(stepProv.dailyGoal)}',
                      icon: Icons.directions_walk_rounded,
                      color: AppColors.primary,
                      badgeText: '${((stepProv.todaySteps / (stepProv.dailyGoal > 0 ? stepProv.dailyGoal : 1)) * 100).toInt()}%',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const StepsScreen()),
                        );
                      },
                      onAdd: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const StepsScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Module 6: Device Screen Time
                  Expanded(
                    child: _CompactModuleTile(
                      title: 'Screen Time',
                      subtitle: screenProv.todayFormattedTotal,
                      icon: Icons.phone_android_rounded,
                      color: const Color(0xFF6366F1),
                      badgeText: 'All Apps',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ScreenTimeScreen()),
                        );
                      },
                      onAdd: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ScreenTimeScreen()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  }

  // ─── Step Counter Sliding Card ─────────────────────────────────────────────

  Widget _buildStepsCarouselCard(ThemeData theme, bool isDark, StepProvider stepProv) {
    final record = stepProv.todayRecord;
    final steps = record?.stepCount ?? stepProv.todaySteps;
    final goal = record?.goal ?? stepProv.dailyGoal;
    final progress = goal > 0 ? (steps / goal).clamp(0.0, 1.0) : 0.0;
    final cal = record?.calories ?? 0.0;
    final km = record?.distanceKm ?? 0.0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const StepsScreen()));
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.directions_walk_rounded, color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Step Counter & Activity',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${(progress * 100).toInt()}% Goal',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 8,
                          strokeCap: StrokeCap.round,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                        const Icon(Icons.bolt_rounded, color: AppColors.primary, size: 28),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          NumberFormat('#,###').format(steps),
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                        ),
                        Text(
                          'of ${NumberFormat('#,###').format(goal)} daily goal',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              '🔥 ${cal.toStringAsFixed(0)} kcal',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '📍 ${km.toStringAsFixed(1)} km',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tap to view 12-month analytics',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Screen Time Sliding Card ──────────────────────────────────────────────

  Widget _buildScreenTimeCarouselCard(ThemeData theme, bool isDark, ScreenTimeProvider screenProv) {
    final total = screenProv.todaySummary?.totalDuration ?? Duration.zero;
    final topApps = (screenProv.todaySummary?.appUsages ?? []).take(2).toList();
    final h = total.inHours;
    final m = total.inMinutes % 60;
    final timeStr = h > 0 ? '${h}h ${m}m' : '${m}m';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ScreenTimeScreen()));
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.phone_android_rounded, color: Color(0xFF6366F1), size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Device Screen Time',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'All Apps',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF6366F1)),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        timeStr,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                      ),
                      Text(
                        'Total screen on time today',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (topApps.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: topApps.map((a) {
                        final mins = a.usage.inMinutes;
                        final aStr = mins >= 60 ? '${mins ~/ 60}h ${mins % 60}m' : '${mins}m';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                a.appName,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                aStr,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF6366F1)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  else
                    Text(
                      'No app usage recorded',
                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                    ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tap for app-by-app & yearly trends',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFF6366F1)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Compact Module Tile for 2x2 Grid ────────────────────────────────────────

class _CompactModuleTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String badgeText;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  const _CompactModuleTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.badgeText,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  IconButton(
                    icon: Icon(Icons.add_circle_outline_rounded, color: color, size: 20),
                    onPressed: onAdd,
                    tooltip: 'Quick Add',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Today's Progress + Insight Card ─────────────────────────────────────────

class _TodayProgressCard extends StatelessWidget {
  final EngineProvider engineProv;
  final VoidCallback onAskAI;

  const _TodayProgressCard({
    required this.engineProv,
    required this.onAskAI,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final progress = engineProv.todayProgress;
    final insights = engineProv.insights;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1A2E1A), const Color(0xFF0D1F0D)]
              : [AppColors.primary.withValues(alpha: 0.07), AppColors.primary.withValues(alpha: 0.03)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.bar_chart_rounded, color: AppColors.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Today\'s Progress',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              if (progress?.bestStreak != null && progress!.bestStreak > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '🔥 ${progress.bestStreak}d streak',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.orange),
                  ),
                ),
            ],
          ),

          // Stats Row
          if (progress != null)
            Row(
              children: [
                _StatChip(
                  icon: '⚡',
                  label: 'Habits',
                  value: '${progress.habitsCompleted}/${progress.habitsTotal}',
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  icon: '📋',
                  label: 'Tasks',
                  value: '${progress.tasksCompletedToday} done',
                  color: AppColors.tasks,
                ),
              ],
            ),

          // Top insight
          if (insights.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(insights.first.icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    insights.first.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      height: 1.3,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),

          // Ask Grow AI button
          SizedBox(
            width: double.infinity,
            height: 38,
            child: FilledButton.icon(
              onPressed: onAskAI,
              icon: const Icon(Icons.auto_awesome_rounded, size: 15),
              label: const Text('Ask Grow AI', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 9,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
