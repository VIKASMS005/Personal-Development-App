import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../utils/app_time_picker.dart';
import '../models/alarm_model.dart';
import '../models/reminder.dart';
import '../providers/app_providers.dart';
import '../services/notification_service.dart';
import '../widgets/ds/ds.dart';
import 'forms/reminder_form.dart';

class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key});

  static const remindersTab = 0;
  static const alarmsTab = 1;

  /// Lets other screens (e.g. Home's "Up next") open a specific tab.
  static final ValueNotifier<int?> requestedTab = ValueNotifier<int?>(null);

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedReminderFilter = 0; // 0=Upcoming, 1=Completed, 2=Missed, 3=All

  Duration _timerDuration = Duration.zero;
  Duration _initialTimerDuration = Duration.zero;
  Timer? _timer;
  bool _isTimerRunning = false;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _stopwatchTimer;
  final List<String> _laps = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() => setState(() {}));
    AlarmScreen.requestedTab.addListener(_onTabRequested);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.uid != null) {
        context.read<AlarmProvider>().loadAlarms(auth.uid!);
      }
      _onTabRequested();
    });
  }

  void _onTabRequested() {
    final tab = AlarmScreen.requestedTab.value;
    if (tab == null || !mounted) return;
    _tabController.animateTo(tab);
    if (tab == AlarmScreen.remindersTab) setState(() => _selectedReminderFilter = 0);
    AlarmScreen.requestedTab.value = null;
  }

  @override
  void dispose() {
    AlarmScreen.requestedTab.removeListener(_onTabRequested);
    _timer?.cancel();
    _stopwatchTimer?.cancel();
    NotificationService.stopRingtone();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final reminderProv = context.watch<ReminderProvider>();
    final alarmProv = context.watch<AlarmProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders & clock'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          tabs: const [
            Tab(text: 'Reminders'),
            Tab(text: 'Alarms'),
            Tab(text: 'Timer'),
            Tab(text: 'Stopwatch'),
          ],
        ),
      ),
      floatingActionButton: _buildFab(auth, reminderProv, alarmProv),
      body: TabBarView(
        controller: _tabController,
        children: [
          _reminderTab(auth, reminderProv),
          _alarmTab(auth, alarmProv),
          _timerTab(),
          _stopwatchTab(),
        ],
      ),
    );
  }

  Widget? _buildFab(AuthProvider auth, ReminderProvider reminderProv, AlarmProvider alarmProv) {
    if (_tabController.index == AlarmScreen.alarmsTab) {
      return FloatingActionButton.extended(
        icon: const Icon(Icons.alarm_add_rounded),
        label: const Text('Add alarm'),
        onPressed: () => _showAlarmDialog(context, auth, alarmProv),
      );
    } else if (_tabController.index == AlarmScreen.remindersTab) {
      return FloatingActionButton.extended(
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add reminder'),
        onPressed: () => _addReminder(auth, reminderProv),
      );
    }
    return null;
  }

  Future<void> _addReminder(AuthProvider auth, ReminderProvider reminderProv) async {
    final r = await ReminderForm.show(context);
    if (r != null && auth.uid != null) {
      r.uid = auth.uid!;
      await reminderProv.addReminder(r);
    }
  }

  // ==================== REMINDERS ====================
  Widget _reminderTab(AuthProvider auth, ReminderProvider reminderProv) {
    final now = DateTime.now();
    final all = reminderProv.allReminders;
    final upcoming = reminderProv.upcomingReminders;
    final completed = all.where((r) => r.isCompleted).toList().reversed.toList();
    final missed = all.where((r) => r.dateTime.isBefore(now) && !r.isCompleted).toList().reversed.toList();

    final lists = [upcoming, completed, missed, all];
    final displayList = lists[_selectedReminderFilter];

    return Column(
      children: [
        const SizedBox(height: AppSpacing.sm),
        ContentWidth(
          child: FilterBar(
            options: [
              FilterOption('Upcoming', count: upcoming.length),
              FilterOption('Completed', count: completed.length),
              FilterOption('Missed', count: missed.length),
              FilterOption('All', count: all.length),
            ],
            selectedIndex: _selectedReminderFilter,
            onSelected: (i) => setState(() => _selectedReminderFilter = i),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: AppMotion.medium,
            child: reminderProv.isLoading && all.isEmpty
                ? const LoadingList()
                : displayList.isEmpty
                    ? _reminderEmpty(auth, reminderProv)
                    : ContentWidth(
                        key: ValueKey('reminders-$_selectedReminderFilter'),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(
                              AppSpacing.screen, AppSpacing.xs, AppSpacing.screen, AppSpacing.fabClearance),
                          children: _groupedReminders(displayList, reminderProv),
                        ),
                      ),
          ),
        ),
      ],
    );
  }

  Widget _reminderEmpty(AuthProvider auth, ReminderProvider reminderProv) {
    const titles = ['No upcoming reminders', 'Nothing completed yet', 'No missed reminders', 'No reminders yet'];
    const subtitles = [
      'Schedule a reminder and you\'ll get a notification at the exact time.',
      'Reminders you complete will show up here.',
      'You haven\'t missed anything.',
      'Schedule a reminder and you\'ll get a notification at the exact time.',
    ];
    final i = _selectedReminderFilter;
    return EmptyState(
      key: ValueKey('reminders-empty-$i'),
      icon: i == 2 ? Icons.verified_outlined : Icons.notifications_none_rounded,
      title: titles[i],
      subtitle: subtitles[i],
      action: i == 0 || i == 3
          ? FilledButton.tonalIcon(
              icon: const Icon(Icons.add_rounded, size: AppSizes.iconMd),
              label: const Text('Add reminder'),
              onPressed: () => _addReminder(auth, reminderProv),
            )
          : null,
    );
  }

  /// Groups reminders under day headers ("Today", "Tomorrow", "Wed, 8 Oct").
  List<Widget> _groupedReminders(List<Reminder> items, ReminderProvider reminderProv) {
    final out = <Widget>[];
    String? lastHeader;
    final now = DateTime.now();
    for (final r in items) {
      String header;
      if (DateUtils.isSameDay(r.dateTime, now)) {
        header = 'Today';
      } else if (DateUtils.isSameDay(r.dateTime, now.add(const Duration(days: 1)))) {
        header = 'Tomorrow';
      } else if (DateUtils.isSameDay(r.dateTime, now.subtract(const Duration(days: 1)))) {
        header = 'Yesterday';
      } else {
        header = DateFormat(r.dateTime.year == now.year ? 'EEEE, d MMM' : 'd MMM yyyy').format(r.dateTime);
      }
      if (header != lastHeader) {
        out.add(Padding(
          padding: EdgeInsets.only(top: lastHeader == null ? AppSpacing.xs : AppSpacing.lg, bottom: AppSpacing.xs),
          child: Text(header, style: context.text.labelMedium?.copyWith(color: context.colors.textSecondary)),
        ));
        lastHeader = header;
      }
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: _ReminderCard(
          reminder: r,
          onReschedule: () => _reschedule(r, reminderProv),
          onEdit: () async {
            final updated = await ReminderForm.show(context, reminder: r);
            if (updated != null) {
              await reminderProv.updateReminder(updated);
            }
          },
          onDelete: () async {
            final ok = await ConfirmDialog.show(
              context,
              title: 'Delete reminder?',
              message: '"${r.title}" will be removed and its notification cancelled.',
              confirmLabel: 'Delete',
              destructive: true,
            );
            if (ok) await reminderProv.deleteReminder(r.id);
          },
        ),
      ));
    }
    return out;
  }

  Future<void> _reschedule(Reminder r, ReminderProvider reminderProv) async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate != null && mounted) {
      final pickedTime = await AppTimePicker.show(
        context,
        initialTime: TimeOfDay.now(),
        helpText: 'Reschedule time',
      );
      if (pickedTime != null) {
        final newDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        await reminderProv.rescheduleReminder(r, newDateTime);
        if (mounted) {
          AppSnack.show(context, 'Reminder rescheduled', tone: StatusTone.success);
        }
      }
    }
  }

  // ==================== ALARMS ====================
  Widget _alarmTab(AuthProvider auth, AlarmProvider alarmProv) {
    final alarms = alarmProv.alarms;

    if (alarms.isEmpty) {
      return EmptyState(
        icon: Icons.alarm_rounded,
        title: 'No alarms yet',
        subtitle: 'Add a wake-up or routine alarm. It rings with sound at the set time.',
        action: FilledButton.tonalIcon(
          icon: const Icon(Icons.alarm_add_rounded, size: AppSizes.iconMd),
          label: const Text('Add alarm'),
          onPressed: () => _showAlarmDialog(context, auth, alarmProv),
        ),
      );
    }

    return ContentWidth(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.md, AppSpacing.screen, AppSpacing.fabClearance),
        itemCount: alarms.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, i) {
          final alarm = alarms[i];
          final colors = context.colors;
          final fg = alarm.isEnabled ? colors.textPrimary : colors.textDisabled;
          return AppCard(
            onTap: () => _showAlarmDialog(context, auth, alarmProv, initial: alarm),
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xxs, AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(alarm.formattedTime, style: context.text.headlineMedium?.copyWith(color: fg)),
                      const SizedBox(height: 2),
                      Text(
                        '${alarm.label.isNotEmpty ? alarm.label : 'Alarm'} · ${alarm.daysSummary}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(color: alarm.isEnabled ? null : colors.textDisabled),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  label: alarm.isEnabled ? 'Alarm on' : 'Alarm off',
                  child: Switch(
                    value: alarm.isEnabled,
                    onChanged: (_) async {
                      await alarmProv.toggleAlarm(alarm);
                    },
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More actions',
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (val) async {
                    if (val == 'edit') {
                      _showAlarmDialog(context, auth, alarmProv, initial: alarm);
                    } else if (val == 'delete') {
                      final confirmed = await ConfirmDialog.show(
                        context,
                        title: 'Delete alarm?',
                        message: 'The ${alarm.formattedTime} alarm will be removed.',
                        confirmLabel: 'Delete',
                        destructive: true,
                      );
                      if (confirmed) {
                        await alarmProv.deleteAlarm(alarm.id);
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: colors.error))),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAlarmDialog(
    BuildContext context,
    AuthProvider auth,
    AlarmProvider alarmProv, {
    AlarmModel? initial,
  }) async {
    TimeOfDay selectedTime = initial?.timeOfDay ?? TimeOfDay.now();
    String label = initial?.label ?? 'Morning Wakeup';
    List<int> selectedDays = List<int>.from(initial?.daysOfWeek ?? []);

    final labelController = TextEditingController(text: label);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

            Future<void> save() async {
              final uid = auth.uid ?? 'local_user';
              final alarm = AlarmModel(
                id: initial?.id ?? const Uuid().v4(),
                uid: uid,
                hour: selectedTime.hour,
                minute: selectedTime.minute,
                label: labelController.text.trim().isNotEmpty ? labelController.text.trim() : 'Alarm',
                daysOfWeek: selectedDays,
                isEnabled: true,
              );

              if (initial == null) {
                await alarmProv.addAlarm(alarm);
              } else {
                await alarmProv.updateAlarm(alarm);
              }
              if (modalCtx.mounted) {
                Navigator.pop(modalCtx);
              }
            }

            return SheetScaffold(
              title: initial == null ? 'New alarm' : 'Edit alarm',
              footer: FilledButton(
                onPressed: save,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSizes.buttonHeight)),
                child: Text(initial == null ? 'Save alarm' : 'Save changes'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    button: true,
                    label: 'Alarm time ${AppTimePicker.format(modalCtx, selectedTime)}. Tap to change.',
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: AppRadius.lgAll,
                      onTap: () async {
                        final t = await AppTimePicker.show(
                          modalCtx,
                          initialTime: selectedTime,
                          helpText: 'Alarm time',
                        );
                        if (t != null) {
                          setModalState(() => selectedTime = t);
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: modalCtx.colors.surfaceMuted,
                          borderRadius: AppRadius.lgAll,
                        ),
                        child: Column(
                          children: [
                            Text(AppTimePicker.format(modalCtx, selectedTime), style: modalCtx.text.displaySmall),
                            const SizedBox(height: AppSpacing.xxs),
                            Text('Tap to change', style: modalCtx.text.labelSmall),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: labelController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Label',
                      hintText: 'e.g. Morning wake-up, workout',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const FieldLabel('Repeat'),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: List.generate(7, (idx) {
                      final dayNum = idx + 1;
                      final isSelected = selectedDays.contains(dayNum);
                      return FilterChip(
                        label: Text(dayLabels[idx]),
                        selected: isSelected,
                        labelStyle: modalCtx.text.labelMedium?.copyWith(
                          color: isSelected ? modalCtx.scheme.onPrimaryContainer : modalCtx.colors.textPrimary,
                        ),
                        onSelected: (val) {
                          setModalState(() {
                            if (val) {
                              selectedDays.add(dayNum);
                            } else {
                              selectedDays.remove(dayNum);
                            }
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      TextButton(
                        onPressed: () => setModalState(() => selectedDays = [1, 2, 3, 4, 5]),
                        child: const Text('Weekdays'),
                      ),
                      TextButton(
                        onPressed: () => setModalState(() => selectedDays = [1, 2, 3, 4, 5, 6, 7]),
                        child: const Text('Every day'),
                      ),
                      TextButton(
                        onPressed: () => setModalState(() => selectedDays.clear()),
                        child: const Text('Once'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ==================== TIMER ====================
  Widget _timerTab() {
    final progress = _initialTimerDuration.inSeconds > 0 ? _timerDuration.inSeconds / _initialTimerDuration.inSeconds : 0.0;
    final status = _isTimerRunning ? 'Running' : (_timerDuration > Duration.zero ? 'Paused' : 'Tap to set a time');

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Semantics(
              button: true,
              label: 'Timer ${_formatDuration(_timerDuration)}, $status',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: _showCustomTimerDialog,
                child: ProgressRing(
                  value: progress > 0 ? progress : (_timerDuration > Duration.zero ? 1 : 0),
                  size: 232,
                  strokeWidth: 10,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_formatDuration(_timerDuration), style: context.text.displaySmall),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        status,
                        style: context.text.labelSmall?.copyWith(
                          color: _isTimerRunning ? context.scheme.primary : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              alignment: WrapAlignment.center,
              children: [
                _durationChip('1 min', const Duration(minutes: 1)),
                _durationChip('5 min', const Duration(minutes: 5)),
                _durationChip('10 min', const Duration(minutes: 10)),
                _durationChip('25 min focus', const Duration(minutes: 25)),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(onPressed: _resetTimer, child: const Text('Reset')),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  icon: Icon(_isTimerRunning ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  label: Text(_isTimerRunning ? 'Pause' : 'Start'),
                  onPressed: _isTimerRunning ? _pauseTimer : _startTimer,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomTimerDialog() {
    int hours = _timerDuration.inHours;
    int minutes = _timerDuration.inMinutes % 60;
    int seconds = _timerDuration.inSeconds % 60;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          return SheetScaffold(
            title: 'Set timer',
            footer: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSizes.buttonHeight)),
              onPressed: () {
                final customDur = Duration(hours: hours, minutes: minutes, seconds: seconds);
                if (customDur > Duration.zero) {
                  _pauseTimer();
                  setState(() {
                    _timerDuration = customDur;
                    _initialTimerDuration = customDur;
                  });
                }
                Navigator.pop(modalCtx);
              },
              child: const Text('Set timer'),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildTimeColumn(
                      label: 'Hours',
                      value: hours,
                      max: 23,
                      onChanged: (val) => setModalState(() => hours = val),
                    ),
                    Text(':', style: modalCtx.text.headlineMedium),
                    _buildTimeColumn(
                      label: 'Minutes',
                      value: minutes,
                      max: 59,
                      onChanged: (val) => setModalState(() => minutes = val),
                    ),
                    Text(':', style: modalCtx.text.headlineMedium),
                    _buildTimeColumn(
                      label: 'Seconds',
                      value: seconds,
                      max: 59,
                      onChanged: (val) => setModalState(() => seconds = val),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  alignment: WrapAlignment.center,
                  children: [
                    ActionChip(
                      label: const Text('+1 min'),
                      onPressed: () => setModalState(() => minutes = (minutes + 1) % 60),
                    ),
                    ActionChip(
                      label: const Text('+5 min'),
                      onPressed: () => setModalState(() => minutes = (minutes + 5) % 60),
                    ),
                    ActionChip(
                      label: const Text('+10 min'),
                      onPressed: () => setModalState(() => minutes = (minutes + 10) % 60),
                    ),
                    ActionChip(
                      label: const Text('+30 min'),
                      onPressed: () => setModalState(() {
                        final total = minutes + 30;
                        hours = (hours + total ~/ 60) % 24;
                        minutes = total % 60;
                      }),
                    ),
                    ActionChip(
                      label: const Text('+1 hr'),
                      onPressed: () => setModalState(() => hours = (hours + 1) % 24),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimeColumn({
    required String label,
    required int value,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      children: [
        IconButton(
          tooltip: 'Increase $label',
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
          onPressed: () => onChanged((value + 1) % (max + 1)),
        ),
        Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: context.colors.surfaceMuted,
            borderRadius: AppRadius.mdAll,
          ),
          alignment: Alignment.center,
          child: Text(value.toString().padLeft(2, '0'), style: context.text.headlineMedium),
        ),
        IconButton(
          tooltip: 'Decrease $label',
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: () => onChanged((value - 1 + max + 1) % (max + 1)),
        ),
        Text(label, style: context.text.labelSmall),
      ],
    );
  }

  Widget _durationChip(String label, Duration duration) {
    final isSelected = _timerDuration == duration && _initialTimerDuration == duration;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      labelStyle: context.text.labelMedium?.copyWith(
        color: isSelected ? context.scheme.onPrimaryContainer : context.colors.textPrimary,
      ),
      onSelected: (val) {
        if (val) {
          _pauseTimer();
          setState(() {
            _timerDuration = duration;
            _initialTimerDuration = duration;
          });
        }
      },
    );
  }

  // ==================== STOPWATCH ====================
  Widget _stopwatchTab() {
    return ContentWidth(
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xxl),
          Semantics(
            liveRegion: false,
            label: 'Elapsed ${_formatStopwatch(_stopwatch.elapsed)}',
            child: Text(_formatStopwatch(_stopwatch.elapsed), style: context.text.displaySmall?.copyWith(fontSize: 56)),
          ),
          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: AppSpacing.screenPadding,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(onPressed: _resetStopwatch, child: const Text('Reset')),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(onPressed: _stopwatch.isRunning ? _recordLap : null, child: const Text('Lap')),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  icon: Icon(_stopwatch.isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  label: Text(_stopwatch.isRunning ? 'Pause' : 'Start'),
                  onPressed: _stopwatch.isRunning ? _stopStopwatch : _startStopwatch,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          Expanded(
            child: _laps.isEmpty
                ? Center(child: Text('Laps will appear here', style: context.text.bodySmall))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                    itemCount: _laps.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, i) {
                      final lapIndex = _laps.length - i;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        child: Row(
                          children: [
                            Expanded(child: Text('Lap $lapIndex', style: context.text.bodyMedium)),
                            Text(_laps[i], style: context.text.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _startTimer() {
    if (_timerDuration == Duration.zero) {
      _timerDuration = const Duration(minutes: 1);
      _initialTimerDuration = const Duration(minutes: 1);
    }
    _isTimerRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        if (_timerDuration.inSeconds > 0) {
          _timerDuration -= const Duration(seconds: 1);
        } else {
          t.cancel();
          _isTimerRunning = false;
          // Play loud Timer chime ringtone
          NotificationService.playTimerRingtone();
          NotificationService.showSimple(
            id: 2001,
            title: 'Timer Complete! 🔔',
            body: 'Your focus session is complete!',
            isTimer: true,
          );
          if (mounted) {
            _showTimerCompletionDialog();
          }
        }
      });
    });
  }

  void _showTimerCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.alarm_on_rounded, color: ctx.scheme.primary, size: 32),
        title: const Text('Time\'s up'),
        content: const Text('Your timer has finished.'),
        actions: [
          FilledButton(
            onPressed: () {
              NotificationService.stopRingtone();
              Navigator.pop(ctx);
            },
            child: const Text('Stop sound'),
          ),
        ],
      ),
    );
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() => _isTimerRunning = false);
  }

  void _resetTimer() {
    _timer?.cancel();
    NotificationService.stopRingtone();
    setState(() {
      _timerDuration = Duration.zero;
      _initialTimerDuration = Duration.zero;
      _isTimerRunning = false;
    });
  }

  void _startStopwatch() {
    _stopwatch.start();
    _stopwatchTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => setState(() {}));
  }

  void _stopStopwatch() {
    _stopwatch.stop();
    _stopwatchTimer?.cancel();
    setState(() {});
  }

  void _recordLap() {
    setState(() {
      _laps.insert(0, _formatStopwatch(_stopwatch.elapsed));
    });
  }

  void _resetStopwatch() {
    _stopwatch.reset();
    _stopwatchTimer?.cancel();
    setState(() => _laps.clear());
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    if (h > 0) {
      final hStr = h.toString().padLeft(2, '0');
      return '$hStr:$m:$s';
    }
    return '$m:$s';
  }

  String _formatStopwatch(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = ((d.inMilliseconds % 1000) ~/ 100).toString();
    return '$m:$s.$ms';
  }
}

class _ReminderCard extends StatelessWidget {
  final Reminder reminder;
  final VoidCallback onReschedule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ReminderCard({
    required this.reminder,
    required this.onReschedule,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final colors = context.colors;
    final isMissed = r.dateTime.isBefore(DateTime.now()) && !r.isCompleted;
    final isTask = r.id.startsWith('task_');
    final time = DateFormat('h:mm').format(r.dateTime);
    final period = DateFormat('a').format(r.dateTime);
    final soon = !isMissed && !r.isCompleted && r.dateTime.difference(DateTime.now()).inMinutes <= 60;

    return AppCard(
      borderColor: isMissed ? colors.error.withValues(alpha: 0.35) : null,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xxs, AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    time,
                    style: context.text.titleMedium?.copyWith(
                      color: isMissed ? colors.error : (r.isCompleted ? colors.textSecondary : colors.textPrimary),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(period, style: context.text.labelSmall),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 44, margin: const EdgeInsets.only(right: AppSpacing.sm, top: 2), color: colors.divider),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall?.copyWith(
                      decoration: r.isCompleted ? TextDecoration.lineThrough : null,
                      color: r.isCompleted ? colors.textSecondary : colors.textPrimary,
                    ),
                  ),
                  if (r.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(r.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xxs + 2,
                    runSpacing: AppSpacing.xxs + 2,
                    children: [
                      if (isMissed)
                        const StatusBadge(label: 'Missed', tone: StatusTone.error, icon: Icons.error_outline_rounded)
                      else if (r.isCompleted)
                        const StatusBadge(label: 'Completed', tone: StatusTone.success, icon: Icons.check_rounded)
                      else if (soon)
                        const StatusBadge(label: 'Coming up', tone: StatusTone.primary, icon: Icons.notifications_active_outlined),
                      StatusBadge(label: r.category, icon: categoryIcon(r.category), outlined: true),
                      if (isTask) const StatusBadge(label: 'From task', icon: Icons.task_alt_rounded, outlined: true),
                    ],
                  ),
                  if (isMissed) ...[
                    const SizedBox(height: AppSpacing.xs),
                    FilledButton.tonalIcon(
                      onPressed: onReschedule,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                        textStyle: context.text.labelMedium,
                      ),
                      icon: const Icon(Icons.update_rounded, size: AppSizes.iconSm),
                      label: const Text('Reschedule'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) {
              if (val == 'reschedule') onReschedule();
              if (val == 'edit') onEdit();
              if (val == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'reschedule', child: Text('Reschedule')),
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: colors.error))),
            ],
          ),
        ],
      ),
    );
  }
}
