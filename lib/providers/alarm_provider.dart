import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alarm_model.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

class AlarmProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<AlarmModel> _alarms = [];
  bool _isLoading = false;

  /// When each enabled one-time alarm is due to ring (alarm id → time), so a
  /// one-time alarm that rang while the app was closed can be switched off.
  static const _fireTimesKey = 'grow_one_time_alarm_fire_at_v1';
  Map<String, DateTime> _oneTimeFireAt = {};

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
      await _loadFireTimes();
      await expirePassedOneTimeAlarms();
    } catch (e) {
      debugPrint('Error loading alarms: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadFireTimes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_fireTimesKey);
      final map = raw == null ? const {} : jsonDecode(raw) as Map;
      _oneTimeFireAt = {
        for (final e in map.entries)
          if (DateTime.tryParse('${e.value}') != null)
            '${e.key}': DateTime.parse('${e.value}'),
      };
    } catch (_) {
      _oneTimeFireAt = {};
    }
  }

  Future<void> _saveFireTimes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fireTimesKey,
          jsonEncode(_oneTimeFireAt.map((k, v) => MapEntry(k, v.toIso8601String()))));
    } catch (_) {}
  }

  /// Switches off enabled one-time alarms whose ring time has passed (they
  /// rang while the app was closed or in the background). Their pending
  /// snoozes and "missed" notice are left alone. Returns true if any changed.
  Future<bool> expirePassedOneTimeAlarms() async {
    final now = DateTime.now();
    var changed = false;
    var learned = false;
    for (var i = 0; i < _alarms.length; i++) {
      final a = _alarms[i];
      if (!a.isEnabled || a.daysOfWeek.isNotEmpty) continue;
      final fireAt = _oneTimeFireAt[a.id];
      if (fireAt == null) {
        // Saved by an older build with no ring time on record: treat it as
        // still due at its next ring rather than guessing it already rang.
        _oneTimeFireAt[a.id] = _firstRingAfter(a, now);
        learned = true;
        continue;
      }
      // Still ringing during its own minute; switch off once that minute is over.
      if (now.isBefore(fireAt.add(const Duration(minutes: 1)))) continue;
      final off = a.copyWith(isEnabled: false);
      _alarms[i] = off;
      _oneTimeFireAt.remove(a.id);
      await _db.updateAlarm(off);
      changed = true;
    }
    if (changed || learned) await _saveFireTimes();
    if (changed) notifyListeners();
    return changed;
  }

  static DateTime _firstRingAfter(AlarmModel a, DateTime from) {
    var t = DateTime(from.year, from.month, from.day, a.hour, a.minute);
    if (t.isBefore(from)) t = DateTime(from.year, from.month, from.day + 1, a.hour, a.minute);
    return t;
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
    if (_oneTimeFireAt.remove(id) != null) await _saveFireTimes();
    await _db.deleteAlarm(id);
  }

  void _scheduleAlarmNotifications(AlarmModel alarm) {
    final now = DateTime.now();
    if (alarm.daysOfWeek.isEmpty) {
      // One-time alarm. Calendar arithmetic, so a DST change can't shift the day.
      final alarmDt = _firstRingAfter(alarm, now);
      _oneTimeFireAt[alarm.id] = alarmDt;
      _saveFireTimes();
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
    if (_oneTimeFireAt.remove(alarmId) != null) _saveFireTimes();
    NotificationService.cancelAlarm(NotificationService.stableId(alarmId));
    for (int day = 1; day <= 7; day++) {
      final notifId = NotificationService.stableId('${alarmId}_day$day');
      NotificationService.cancelAlarm(notifId);
    }
  }
}
