import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/alarm_model.dart';
import '../providers/app_providers.dart';
import '../services/notification_service.dart';
import '../utils/app_colors.dart';

class AlarmRingingDialog extends StatefulWidget {
  final AlarmModel alarm;
  const AlarmRingingDialog({super.key, required this.alarm});

  static Future<void> show(BuildContext context, AlarmModel alarm) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlarmRingingDialog(alarm: alarm),
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
    if (mounted) {
      // Toggle alarm off in provider
      context.read<AlarmProvider>().toggleAlarm(widget.alarm);
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _snooze() async {
    _autoOffTimer?.cancel();
    await NotificationService.stopRingtone();
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏰ Alarm snoozed for 3 minutes'),
          backgroundColor: AppColors.alarm,
        ),
      );
    }
  }

  void _dismissAndMarkMissed() async {
    await NotificationService.stopRingtone();
    await NotificationService.showSimple(
      id: widget.alarm.id.hashCode.abs() % 2147483647,
      title: '⏰ Missed Alarm: ${widget.alarm.label}',
      body: 'Alarm for ${widget.alarm.hour.toString().padLeft(2, '0')}:${widget.alarm.minute.toString().padLeft(2, '0')} was missed.',
    );
    if (mounted) {
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
              const SizedBox(height: 24),
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
              const SizedBox(height: 28),

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
                  label: const Text(
                    'Snooze (3 min)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onPressed: _snooze,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
