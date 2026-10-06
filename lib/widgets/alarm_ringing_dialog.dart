import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/alarm_model.dart';
import '../providers/app_providers.dart';
import '../services/notification_service.dart';
import 'ds/ds.dart';

class AlarmRingingDialog extends StatefulWidget {
  final AlarmModel alarm;
  final int snoozeCount;

  const AlarmRingingDialog({
    super.key,
    required this.alarm,
    this.snoozeCount = 0,
  });

  static Future<void> show(BuildContext context, AlarmModel alarm, {int snoozeCount = 0}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlarmRingingDialog(alarm: alarm, snoozeCount: snoozeCount),
    );
  }

  @override
  State<AlarmRingingDialog> createState() => _AlarmRingingDialogState();
}

class _AlarmRingingDialogState extends State<AlarmRingingDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  Timer? _autoOffTimer;
  int _secondsRinging = 0;
  static const int _maxRingDurationSeconds = 180; // 3 minutes per cycle

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    // Ring loudly
    NotificationService.playAlarmRingtone();

    // Auto-off after 3 minutes if not touched
    _autoOffTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      _secondsRinging++;
      if (_secondsRinging >= _maxRingDurationSeconds) {
        t.cancel();
        _dismissAndMarkMissed();
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _autoOffTimer?.cancel();
    NotificationService.stopRingtone();
    super.dispose();
  }

  void _turnOff() async {
    _autoOffTimer?.cancel();
    await NotificationService.stopRingtone();

    // Cancel all scheduled notifications for this alarm (base, days, snoozes, missed)
    final baseId = NotificationService.stableId(widget.alarm.id);
    await NotificationService.cancelAlarm(baseId);
    for (int day = 1; day <= 7; day++) {
      await NotificationService.cancelAlarm(NotificationService.stableId('${widget.alarm.id}_day$day'));
    }
    for (int s = 1; s <= 3; s++) {
      await NotificationService.cancelAlarm(NotificationService.stableId('snooze_${widget.alarm.id}_$s'));
    }

    if (mounted) {
      // Toggle alarm off in provider if it was a one-time alarm
      if (widget.alarm.daysOfWeek.isEmpty && widget.alarm.isEnabled) {
        context.read<AlarmProvider>().toggleAlarm(widget.alarm);
      }
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _snooze() async {
    if (widget.snoozeCount >= 3) return;

    _autoOffTimer?.cancel();
    await NotificationService.stopRingtone();

    final nextCount = widget.snoozeCount + 1;
    final snoozeTime = DateTime.now().add(const Duration(minutes: 5));
    final snoozeId = NotificationService.stableId('snooze_${widget.alarm.id}_$nextCount');

    // Schedule next snooze for 5 minutes later
    await NotificationService.scheduleAlarm(
      id: snoozeId,
      title: widget.alarm.label.isNotEmpty ? widget.alarm.label : 'Alarm',
      dateTime: snoozeTime,
      body: 'Snooze $nextCount of 3 ringing!',
      initialSnoozeCount: nextCount,
    );

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      final remaining = 3 - nextCount;
      AppSnack.show(
        context,
        'Snoozed for 5 minutes · $remaining snooze${remaining == 1 ? "" : "s"} left',
        duration: const Duration(seconds: 3),
      );
    }
  }

  void _dismissAndMarkMissed() async {
    await NotificationService.stopRingtone();

    // Cancel scheduled notifications for this alarm
    final baseId = NotificationService.stableId(widget.alarm.id);
    await NotificationService.cancelAlarm(baseId);
    for (int day = 1; day <= 7; day++) {
      await NotificationService.cancelAlarm(NotificationService.stableId('${widget.alarm.id}_day$day'));
    }
    for (int s = 1; s <= 3; s++) {
      await NotificationService.cancelAlarm(NotificationService.stableId('snooze_${widget.alarm.id}_$s'));
    }

    final timeStr =
        '${widget.alarm.hour.toString().padLeft(2, '0')}:${widget.alarm.minute.toString().padLeft(2, '0')}';

    await NotificationService.sendMissedAlarmNotification(
      id: baseId,
      title: widget.alarm.label.isNotEmpty ? widget.alarm.label : 'Alarm',
      timeStr: timeStr,
    );

    if (mounted) {
      if (widget.alarm.daysOfWeek.isEmpty && widget.alarm.isEnabled) {
        context.read<AlarmProvider>().toggleAlarm(widget.alarm);
      }
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final timeStr =
        '${widget.alarm.hour.toString().padLeft(2, '0')}:${widget.alarm.minute.toString().padLeft(2, '0')}';
    final noSnoozes = widget.snoozeCount >= 3;

    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: Tween<double>(begin: 0.95, end: 1.08).animate(
                  CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
                ),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                  child: Icon(Icons.alarm_on_rounded, size: 48, color: scheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Alarm', style: context.text.labelLarge?.copyWith(color: context.colors.textSecondary)),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                timeStr,
                style: context.text.displaySmall?.copyWith(fontSize: 52, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                widget.alarm.label.isNotEmpty ? widget.alarm.label : 'Wake up',
                textAlign: TextAlign.center,
                style: context.text.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              StatusBadge(
                label: noSnoozes
                    ? 'No snoozes left'
                    : '${3 - widget.snoozeCount} of 3 snoozes left',
                icon: Icons.snooze_rounded,
                tone: noSnoozes ? StatusTone.warning : StatusTone.neutral,
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSizes.buttonHeight + 4)),
                  icon: const Icon(Icons.alarm_off_rounded),
                  label: const Text('Turn off'),
                  onPressed: _turnOff,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSizes.buttonHeight)),
                  icon: const Icon(Icons.snooze_rounded, size: AppSizes.iconMd),
                  label: Text(noSnoozes ? 'No snoozes left' : 'Snooze 5 minutes'),
                  onPressed: noSnoozes ? null : _snooze,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
