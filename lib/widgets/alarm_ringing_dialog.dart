import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/alarm_model.dart';
import '../providers/app_providers.dart';
import '../services/notification_service.dart';
import '../utils/app_colors.dart';

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

  /// Stops what is still queued for this ring: the automatic snoozes, the
  /// missed notice and any manual snooze. A repeating alarm keeps its weekly
  /// schedule; a one-time alarm is switched off.
  Future<void> _cancelPendingRings() async {
    final id = widget.alarm.id;
    await NotificationService.cancelAlarmFollowUps(NotificationService.stableId(id));
    for (int day = 1; day <= 7; day++) {
      await NotificationService.cancelAlarmFollowUps(
          NotificationService.stableId('${id}_day$day'));
    }
    for (int s = 1; s <= 3; s++) {
      await NotificationService.cancelAlarm(NotificationService.stableId('snooze_${id}_$s'));
    }
  }

  void _switchOffIfOneTime() {
    if (widget.alarm.daysOfWeek.isEmpty && widget.alarm.isEnabled) {
      context.read<AlarmProvider>().toggleAlarm(widget.alarm);
    }
  }

  void _turnOff() async {
    _autoOffTimer?.cancel();
    await NotificationService.stopRingtone();
    await _cancelPendingRings();

    if (mounted) {
      _switchOffIfOneTime();
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _snooze() async {
    if (widget.snoozeCount >= 3) return;

    _autoOffTimer?.cancel();
    await NotificationService.stopRingtone();

    // The manual snooze replaces the automatic ones, so it rings only once.
    await _cancelPendingRings();

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
      alarmKey: widget.alarm.id,
    );

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).clearSnackBars();
      final remaining = 3 - nextCount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⏰ Alarm snoozed for 5 minutes ($remaining snooze${remaining == 1 ? "" : "s"} remaining)'),
          backgroundColor: AppColors.alarm,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _dismissAndMarkMissed() async {
    await NotificationService.stopRingtone();
    await _cancelPendingRings();

    final timeStr =
        '${widget.alarm.hour.toString().padLeft(2, '0')}:${widget.alarm.minute.toString().padLeft(2, '0')}';

    await NotificationService.sendMissedAlarmNotification(
      id: NotificationService.stableId(widget.alarm.id),
      title: widget.alarm.label.isNotEmpty ? widget.alarm.label : 'Alarm',
      timeStr: timeStr,
    );

    if (mounted) {
      _switchOffIfOneTime();
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr =
        '${widget.alarm.hour.toString().padLeft(2, '0')}:${widget.alarm.minute.toString().padLeft(2, '0')}';

    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing Alarm Bell Icon
              ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1.2).animate(
                  CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
                ),
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppColors.alarm.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.alarm.withValues(alpha: 0.3),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.alarm_on_rounded,
                    size: 56,
                    color: AppColors.alarm,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '⏰ ALARM RINGING',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppColors.alarm,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                timeStr,
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.alarm.label.isNotEmpty ? widget.alarm.label : 'Wake Up Routine',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),

              // Snooze count chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: widget.snoozeCount >= 3
                      ? AppColors.error.withValues(alpha: 0.12)
                      : (widget.snoozeCount > 0
                          ? Colors.orange.withValues(alpha: 0.12)
                          : AppColors.primary.withValues(alpha: 0.12)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.snoozeCount >= 3
                      ? 'No snoozes remaining (3/3 used)'
                      : (widget.snoozeCount == 0
                          ? '3 Snoozes Available (5 min each)'
                          : 'Snooze ${widget.snoozeCount} of 3 used (${3 - widget.snoozeCount} left)'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: widget.snoozeCount >= 3
                        ? AppColors.error
                        : (widget.snoozeCount > 0 ? Colors.orange[800] : AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Turn Off Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.alarm,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.alarm_off_rounded, size: 22),
                  label: const Text(
                    'TURN OFF ALARM',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5),
                  ),
                  onPressed: _turnOff,
                ),
              ),
              const SizedBox(height: 12),

              // Snooze Button
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.snooze_rounded, size: 18),
                  label: Text(
                    widget.snoozeCount >= 3
                        ? 'No Snoozes Remaining'
                        : 'Snooze (+5m) • ${3 - widget.snoozeCount} left',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onPressed: widget.snoozeCount >= 3 ? null : _snooze,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
