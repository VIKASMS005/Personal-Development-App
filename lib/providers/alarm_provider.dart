import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/alarm_model.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

class AlarmProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<AlarmModel> _alarms = [];
  bool _isLoading = false;

  List<AlarmModel> get alarms => List.unmodifiable(_alarms);
  bool get isLoading => _isLoading;

  void clear() {
    _alarms = [];
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadAlarms(String uid) async {
    _isLoading = true;
    notifyListeners();
    try {
      _alarms = await _db.getAlarms(uid);
    } catch (e) {
      debugPrint('Error loading alarms: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Re-schedules every enabled alarm (e.g. after restoring a backup).
  void rescheduleAll() {
    for (final a in _alarms) {
      _cancelAlarmNotifications(a.id);
      if (a.isEnabled) _scheduleAlarmNotifications(a);
    }
  }

  Future<void> addAlarm(AlarmModel alarm) async {
    _alarms.add(alarm);
    _alarms.sort(
        (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    notifyListeners();
    await _db.insertAlarm(alarm);
    if (alarm.isEnabled) {
      _scheduleAlarmNotifications(alarm);
    }
  }

  Future<void> updateAlarm(AlarmModel alarm) async {
    final idx = _alarms.indexWhere((a) => a.id == alarm.id);
    if (idx != -1) {
      _alarms[idx] = alarm;
      _alarms.sort(
          (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
      notifyListeners();
      await _db.updateAlarm(alarm);
      _cancelAlarmNotifications(alarm.id);
      if (alarm.isEnabled) {
        _scheduleAlarmNotifications(alarm);
      }
    }
  }

  Future<void> toggleAlarm(AlarmModel alarm) async {
    final updated = alarm.copyWith(isEnabled: !alarm.isEnabled);
    await updateAlarm(updated);
  }

  Future<void> deleteAlarm(String id) async {
    _alarms.removeWhere((a) => a.id == id);
    notifyListeners();
    _cancelAlarmNotifications(id);
    await _db.deleteAlarm(id);
  }

  void _scheduleAlarmNotifications(AlarmModel alarm) {
    final now = DateTime.now();
    if (alarm.daysOfWeek.isEmpty) {
      // One-time alarm
      var alarmDt =
          DateTime(now.year, now.month, now.day, alarm.hour, alarm.minute);
      if (alarmDt.isBefore(now)) {
        alarmDt = alarmDt.add(const Duration(days: 1));
      }
      NotificationService.scheduleAlarm(
        id: NotificationService.stableId(alarm.id),
        title: alarm.label.isNotEmpty ? alarm.label : 'Alarm ⏰',
        dateTime: alarmDt,
        body:
            'Time for ${alarm.label.isNotEmpty ? alarm.label : "your routine"}!',
      );
    } else {
      // Recurring days of week (1=Mon..7=Sun)
      for (final day in alarm.daysOfWeek) {
        int daysUntil = (day - now.weekday + 7) % 7;
        var alarmDt = DateTime(
            now.year, now.month, now.day + daysUntil, alarm.hour, alarm.minute);
        if (daysUntil == 0 && alarmDt.isBefore(now)) {
          alarmDt = alarmDt.add(const Duration(days: 7));
        }
        // Use stableId XOR day so each day gets a unique but reproducible ID
        final notifId = NotificationService.stableId('${alarm.id}_day$day');
        NotificationService.scheduleAlarm(
          id: notifId,
          title: alarm.label.isNotEmpty ? alarm.label : 'Alarm ⏰',
          dateTime: alarmDt,
          body:
              'Time for ${alarm.label.isNotEmpty ? alarm.label : "your routine"}!',
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
    }
  }

  void _cancelAlarmNotifications(String alarmId) {
    NotificationService.cancelAlarm(NotificationService.stableId(alarmId));
    for (int day = 1; day <= 7; day++) {
      final notifId = NotificationService.stableId('${alarmId}_day$day');
      NotificationService.cancelAlarm(notifId);
    }
  }
}
