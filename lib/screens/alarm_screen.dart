import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../utils/app_colors.dart';
import '../utils/app_time_picker.dart';
import '../models/alarm_model.dart';
import '../models/reminder.dart';
import '../providers/app_providers.dart';
import '../services/notification_service.dart';
import 'forms/reminder_form.dart';

class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedReminderFilter = 0; // 0=All, 1=Missed, 2=Upcoming, 3=Completed

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.uid != null) {
        context.read<AlarmProvider>().loadAlarms(auth.uid!);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopwatchTimer?.cancel();
    NotificationService.stopRingtone();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final reminderProv = context.watch<ReminderProvider>();
    final alarmProv = context.watch<AlarmProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clock & Reminders'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [
            Tab(icon: Icon(Icons.alarm_rounded, size: 20), text: 'Alarms'),
            Tab(icon: Icon(Icons.timer_outlined, size: 20), text: 'Timer'),
            Tab(icon: Icon(Icons.timer_rounded, size: 20), text: 'Stopwatch'),
            Tab(icon: Icon(Icons.notifications_active_rounded, size: 20), text: 'Reminders'),
          ],
        ),
      ),
      floatingActionButton: _buildFab(auth, reminderProv, alarmProv),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 750),
          child: TabBarView(
            controller: _tabController,
            children: [
              _alarmTab(theme, auth, alarmProv),
              _timerTab(theme),
              _stopwatchTab(theme),
              _reminderTab(theme, auth, reminderProv),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildFab(AuthProvider auth, ReminderProvider reminderProv, AlarmProvider alarmProv) {
    if (_tabController.index == 0) {
      return FloatingActionButton(
        backgroundColor: AppColors.alarm,
        foregroundColor: Colors.white,
        tooltip: 'Add New Alarm',
        child: const Icon(Icons.alarm_add_rounded),
        onPressed: () => _showAlarmDialog(context, auth, alarmProv),
      );
    } else if (_tabController.index == 3) {
      return FloatingActionButton(
        backgroundColor: AppColors.alarm,
        foregroundColor: Colors.white,
        tooltip: 'Add New Reminder',
        child: const Icon(Icons.add_alert_rounded),
        onPressed: () async {
          final r = await ReminderForm.show(context);
          if (r != null && auth.uid != null) {
            r.uid = auth.uid!;
            await reminderProv.addReminder(r);
          }
        },
      );
    }
    return null;
  }

  // ==================== 1. ALARMS TAB ====================
  Widget _alarmTab(ThemeData theme, AuthProvider auth, AlarmProvider alarmProv) {
    final alarms = alarmProv.alarms;

    if (alarms.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.alarm.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.alarm_outlined, size: 52, color: AppColors.alarm),
              ),
              const SizedBox(height: 16),
              Text(
                'No Alarms Set',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Tap the button below to add your morning wakeups and daily routine alarms with sound.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.alarm_add_rounded),
                label: const Text('Add Alarm'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.alarm,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _showAlarmDialog(context, auth, alarmProv),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: alarms.length,
      itemBuilder: (context, i) {
        final alarm = alarms[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _showAlarmDialog(context, auth, alarmProv, initial: alarm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    // Clock Icon
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (alarm.isEnabled ? AppColors.alarm : theme.dividerColor)
                            .withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.alarm_rounded,
                        color: alarm.isEnabled
                            ? AppColors.alarm
                            : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Time and Label
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alarm.formattedTime,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: alarm.isEnabled
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                alarm.label.isNotEmpty ? alarm.label : 'Alarm',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: alarm.isEnabled
                                      ? AppColors.alarm
                                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                              Text(
                                '• ${alarm.daysSummary}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Trailing Actions: Switch & Options Menu
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale: 0.85,
                          child: Switch(
                            value: alarm.isEnabled,
                            activeTrackColor: AppColors.alarm.withValues(alpha: 0.5),
                            onChanged: (_) async {
                              await alarmProv.toggleAlarm(alarm);
                            },
                          ),
                        ),
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert_rounded, size: 18),
                          onSelected: (val) async {
                            if (val == 'edit') {
                              _showAlarmDialog(context, auth, alarmProv, initial: alarm);
                            } else if (val == 'delete') {
                              await alarmProv.deleteAlarm(alarm.id);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, size: 16),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                                  SizedBox(width: 8),
                                  Text('Delete', style: TextStyle(color: AppColors.error)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ).animate().fadeIn(delay: (i * 50).ms);
      },
    );
  }

  // ==================== ALARM CREATE / EDIT DIALOG ====================
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
      backgroundColor: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final theme = Theme.of(modalCtx);
            const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.dividerColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          initial == null ? 'New Alarm' : 'Edit Alarm',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Large Time Selector Button
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        final t = await AppTimePicker.show(
                          modalCtx,
                          initialTime: selectedTime,
                          helpText: 'Set Alarm Time (AM / PM)',
                        );
                        if (t != null) {
                          setModalState(() => selectedTime = t);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.alarm.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.alarm.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.access_time_rounded, color: AppColors.alarm, size: 28),
                            const SizedBox(width: 12),
                            Text(
                              AppTimePicker.format(modalCtx, selectedTime),
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Label Field
                    TextField(
                      controller: labelController,
                      decoration: InputDecoration(
                        labelText: 'Alarm Label',
                        hintText: 'e.g. Morning Wakeup, Workout, Medicine',
                        prefixIcon: const Icon(Icons.label_outline_rounded),
                        filled: true,
                        fillColor: theme.colorScheme.surface,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Repeat Days Chips
                    Text(
                      'Repeat on Days',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(7, (idx) {
                        final dayNum = idx + 1;
                        final isSelected = selectedDays.contains(dayNum);
                        return FilterChip(
                          label: Text(dayLabels[idx]),
                          selected: isSelected,
                          selectedColor: AppColors.alarm,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : theme.colorScheme.onSurface,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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
                    const SizedBox(height: 12),

                    // Quick presets
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('Weekdays'),
                          onPressed: () {
                            setModalState(() => selectedDays = [1, 2, 3, 4, 5]);
                          },
                        ),
                        ActionChip(
                          label: const Text('Everyday'),
                          onPressed: () {
                            setModalState(() => selectedDays = [1, 2, 3, 4, 5, 6, 7]);
                          },
                        ),
                        ActionChip(
                          label: const Text('Once'),
                          onPressed: () {
                            setModalState(() => selectedDays.clear());
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.alarm,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(initial == null ? 'Save Alarm' : 'Update Alarm', style: const TextStyle(fontWeight: FontWeight.w700)),
                        onPressed: () async {
                          final uid = auth.uid ?? 'local_user';
                          final alarm = AlarmModel(
                            id: initial?.id ?? const Uuid().v4(),
                            uid: uid,
                            hour: selectedTime.hour,
                            minute: selectedTime.minute,
                            label: labelController.text.trim().isNotEmpty
                                ? labelController.text.trim()
                                : 'Alarm',
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
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==================== 2. TIMER TAB ====================
  Widget _timerTab(ThemeData theme) {
    final progress = _initialTimerDuration.inSeconds > 0
        ? _timerDuration.inSeconds / _initialTimerDuration.inSeconds
        : 0.0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Circular Visual Timer with High-Contrast Bold Text
            GestureDetector(
              onTap: _showCustomTimerDialog,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: CircularProgressIndicator(
                      value: progress > 0 ? progress : 1.0,
                      strokeWidth: 12,
                      backgroundColor: theme.dividerColor.withValues(alpha: 0.2),
                      color: AppColors.primary,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatDuration(_timerDuration),
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isTimerRunning
                            ? 'Running'
                            : (_timerDuration > Duration.zero ? 'Paused' : 'Tap to set custom time'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _isTimerRunning
                              ? AppColors.primary
                              : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                _durationChip('1 min', const Duration(minutes: 1)),
                _durationChip('5 min', const Duration(minutes: 5)),
                _durationChip('10 min', const Duration(minutes: 10)),
                _durationChip('🍅 25 min (Pomodoro)', const Duration(minutes: 25)),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  icon: Icon(_isTimerRunning ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  label: Text(_isTimerRunning ? 'Pause' : 'Start', style: const TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: _isTimerRunning ? _pauseTimer : _startTimer,
                ),
                const SizedBox(width: 14),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  onPressed: _resetTimer,
                  child: const Text('Reset'),
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
      backgroundColor: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          final theme = Theme.of(modalCtx);
          return Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              16,
              24,
              MediaQuery.of(modalCtx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Set Custom Timer',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(modalCtx),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Hours, Minutes, Seconds Stepper Grid
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildTimeColumn(
                      label: 'Hours',
                      value: hours,
                      max: 23,
                      onChanged: (val) => setModalState(() => hours = val),
                      theme: theme,
                    ),
                    Text(':', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    _buildTimeColumn(
                      label: 'Minutes',
                      value: minutes,
                      max: 59,
                      onChanged: (val) => setModalState(() => minutes = val),
                      theme: theme,
                    ),
                    Text(':', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    _buildTimeColumn(
                      label: 'Seconds',
                      value: seconds,
                      max: 59,
                      onChanged: (val) => setModalState(() => seconds = val),
                      theme: theme,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Quick Add Chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('+1m'),
                      onPressed: () => setModalState(() => minutes = (minutes + 1) % 60),
                    ),
                    ActionChip(
                      label: const Text('+5m'),
                      onPressed: () => setModalState(() => minutes = (minutes + 5) % 60),
                    ),
                    ActionChip(
                      label: const Text('+10m'),
                      onPressed: () => setModalState(() => minutes = (minutes + 10) % 60),
                    ),
                    ActionChip(
                      label: const Text('+30m'),
                      onPressed: () => setModalState(() {
                        final total = minutes + 30;
                        hours = (hours + total ~/ 60) % 24;
                        minutes = total % 60;
                      }),
                    ),
                    ActionChip(
                      label: const Text('+1h'),
                      onPressed: () => setModalState(() => hours = (hours + 1) % 24),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
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
                    child: const Text('Set Timer Duration', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
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
    required ThemeData theme,
  }) {
    return Column(
      children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 28),
          onPressed: () => onChanged((value + 1) % (max + 1)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
              color: AppColors.primary,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
          onPressed: () => onChanged((value - 1 + max + 1) % (max + 1)),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _durationChip(String label, Duration duration) {
    final isSelected = _timerDuration == duration;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
        fontSize: 12,
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

  // ==================== 3. STOPWATCH TAB (HIGH CONTRAST) ====================
  Widget _stopwatchTab(ThemeData theme) {
    return Column(
      children: [
        const SizedBox(height: 36),
        // High-Contrast Glowing Stopwatch Display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _stopwatch.isRunning ? AppColors.secondary : theme.dividerColor,
              width: 2,
            ),
          ),
          child: Text(
            _formatStopwatch(_stopwatch.elapsed),
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _stopwatch.isRunning ? AppColors.error : AppColors.secondary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              icon: Icon(_stopwatch.isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded),
              label: Text(_stopwatch.isRunning ? 'Pause' : 'Start', style: const TextStyle(fontWeight: FontWeight.w700)),
              onPressed: _stopwatch.isRunning ? _stopStopwatch : _startStopwatch,
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              icon: const Icon(Icons.flag_rounded, size: 18),
              label: const Text('Lap'),
              onPressed: _stopwatch.isRunning ? _recordLap : null,
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onPressed: _resetStopwatch,
              child: const Text('Reset'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(),
        Expanded(
          child: _laps.isEmpty
              ? Center(
                  child: Text(
                    'No laps recorded',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  itemCount: _laps.length,
                  itemBuilder: (context, i) {
                    final lapIndex = _laps.length - i;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Lap $lapIndex',
                              style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
                            ),
                            Text(
                              _laps[i],
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ==================== 4. REMINDERS TAB ====================
  Widget _reminderTab(ThemeData theme, AuthProvider auth, ReminderProvider reminderProv) {
    final allReminders = reminderProv.reminders;

    final filterLabels = [
      'All',
      '⏰ Missed (${reminderProv.missedCount})',
      '📅 Upcoming',
      '✓ Completed',
    ];

    List<Reminder> displayList;
    if (_selectedReminderFilter == 1) {
      displayList = reminderProv.missedReminders;
    } else if (_selectedReminderFilter == 2) {
      displayList = reminderProv.upcomingReminders;
    } else if (_selectedReminderFilter == 3) {
      displayList = reminderProv.completedReminders;
    } else {
      displayList = allReminders;
    }

    return Column(
      children: [
        // Filter Chips Bar
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filterLabels.length,
            itemBuilder: (context, i) {
              final isSelected = _selectedReminderFilter == i;
              final isMissedChip = i == 1;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(filterLabels[i]),
                  selected: isSelected,
                  selectedColor: isMissedChip ? AppColors.error : AppColors.alarm,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : (isMissedChip && reminderProv.missedCount > 0 ? AppColors.error : null),
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _selectedReminderFilter = i);
                  },
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),

        Expanded(
          child: displayList.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: (_selectedReminderFilter == 1 ? AppColors.success : AppColors.alarm).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _selectedReminderFilter == 1 ? Icons.check_circle_outline_rounded : Icons.notifications_active_outlined,
                            size: 48,
                            color: _selectedReminderFilter == 1 ? AppColors.success : AppColors.alarm,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _selectedReminderFilter == 1
                              ? 'No Missed Reminders'
                              : (_selectedReminderFilter == 2 ? 'No Upcoming Reminders' : 'No Reminders Found'),
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _selectedReminderFilter == 1
                              ? 'Awesome! You are completely on track with all your schedule notifications.'
                              : 'Schedule custom reminders, alerts, and notifications with exact calendar dates and times.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                        ),
                        if (_selectedReminderFilter != 1) ...[
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add_alert_rounded),
                            label: const Text('Add Reminder'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.alarm,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              final r = await ReminderForm.show(context);
                              if (r != null && auth.uid != null) {
                                r.uid = auth.uid!;
                                await reminderProv.addReminder(r);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  itemCount: displayList.length,
                  itemBuilder: (context, i) {
                    final r = displayList[i];
                    final isPast = r.dateTime.isBefore(DateTime.now()) && !r.isCompleted;
                    final isTask = r.id.startsWith('task_');

                    Color catColor = AppColors.alarm;
                    IconData catIcon = Icons.notifications_active_rounded;
                    if (r.category == 'Work') {
                      catColor = AppColors.secondary;
                      catIcon = Icons.work_rounded;
                    } else if (r.category == 'Study') {
                      catColor = AppColors.timetable;
                      catIcon = Icons.school_rounded;
                    } else if (r.category == 'Health' || r.category == 'Fitness' || r.category == 'Workout') {
                      catColor = AppColors.habits;
                      catIcon = Icons.fitness_center_rounded;
                    } else if (r.category == 'Coding') {
                      catColor = AppColors.primary;
                      catIcon = Icons.code_rounded;
                    } else if (r.category == 'Reading') {
                      catColor = AppColors.journal;
                      catIcon = Icons.auto_stories_rounded;
                    } else if (r.category == 'Urgent') {
                      catColor = AppColors.error;
                      catIcon = Icons.warning_amber_rounded;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: isPast
                              ? const BorderSide(color: AppColors.error, width: 1.2)
                              : BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (isPast ? AppColors.error : catColor).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isPast ? Icons.alarm_off_rounded : catIcon,
                              color: isPast ? AppColors.error : catColor,
                              size: 22,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  r.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    decoration: r.isCompleted ? TextDecoration.lineThrough : null,
                                    color: r.isCompleted ? theme.colorScheme.onSurface.withValues(alpha: 0.45) : null,
                                  ),
                                ),
                              ),
                              if (isPast) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                                  ),
                                  child: const Text(
                                    'Missed',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.error,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              if (isTask) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.tasks.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppColors.tasks.withValues(alpha: 0.4), width: 0.8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.task_alt_rounded, size: 10, color: AppColors.tasks),
                                      SizedBox(width: 3),
                                      Text(
                                        'Task',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.tasks,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (r.description.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  r.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time_rounded,
                                    size: 13,
                                    color: isPast ? AppColors.error : AppColors.alarm,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    DateFormat('EEE, MMM d • hh:mm a').format(r.dateTime),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isPast ? AppColors.error : theme.colorScheme.onSurface.withValues(alpha: 0.65),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '• ${r.category}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: catColor,
                                    ),
                                  ),
                                ],
                              ),
                              if (isPast) ...[
                                const SizedBox(height: 6),
                                InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () async {
                                    final now = DateTime.now();
                                    final pickedDate = await showDatePicker(
                                      context: context,
                                      initialDate: now,
                                      firstDate: now,
                                      lastDate: now.add(const Duration(days: 365)),
                                    );
                                    if (pickedDate != null && context.mounted) {
                                      final pickedTime = await AppTimePicker.show(
                                        context,
                                        initialTime: TimeOfDay.now(),
                                        helpText: 'Reschedule Time (AM / PM)',
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
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Reminder rescheduled successfully! 🔔'),
                                              backgroundColor: AppColors.success,
                                            ),
                                          );
                                        }
                                      }
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.update_rounded, size: 13, color: AppColors.primary),
                                        SizedBox(width: 4),
                                        Text(
                                          'Reschedule Reminder',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: r.isCompleted,
                                activeColor: AppColors.success,
                                onChanged: (_) => reminderProv.toggleCompleted(r),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert_rounded, size: 18),
                                onSelected: (val) async {
                                  if (val == 'reschedule') {
                                    final now = DateTime.now();
                                    final pickedDate = await showDatePicker(
                                      context: context,
                                      initialDate: now,
                                      firstDate: now,
                                      lastDate: now.add(const Duration(days: 365)),
                                    );
                                    if (pickedDate != null && context.mounted) {
                                      final pickedTime = await AppTimePicker.show(
                                        context,
                                        initialTime: TimeOfDay.now(),
                                        helpText: 'Reschedule Time (AM / PM)',
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
                                      }
                                    }
                                  } else if (val == 'edit') {
                                    final updated = await ReminderForm.show(context, reminder: r);
                                    if (updated != null) {
                                      await reminderProv.updateReminder(updated);
                                    }
                                  } else if (val == 'delete') {
                                    await reminderProv.deleteReminder(r.id);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'reschedule',
                                    child: Row(
                                      children: [
                                        Icon(Icons.update_rounded, size: 16, color: AppColors.primary),
                                        SizedBox(width: 8),
                                        Text('Reschedule'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_outlined, size: 16),
                                        SizedBox(width: 8),
                                        Text('Edit'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                                        SizedBox(width: 8),
                                        Text('Delete', style: TextStyle(color: AppColors.error)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ).animate().fadeIn(delay: (i * 40).ms);
                  },
                ),
        ),
      ],
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
        title: const Row(
          children: [
            Icon(Icons.alarm_on_rounded, color: AppColors.primary, size: 28),
            SizedBox(width: 10),
            Text('Timer Finished!'),
          ],
        ),
        content: const Text('Your focus timer has reached 00:00! Ringtone is playing.'),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () {
              NotificationService.stopRingtone();
              Navigator.pop(ctx);
            },
            child: const Text('Stop Ringtone'),
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
