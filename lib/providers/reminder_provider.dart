import 'package:flutter/material.dart';
import '../models/reminder.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

class ReminderProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<Reminder> _reminders = [];
  bool _isLoading = false;

  List<Reminder> get reminders => _reminders;
  bool get isLoading => _isLoading;
  int get activeCount => _reminders.where((r) => !r.isCompleted).length;

  /// Reminders whose scheduled time is in the future — sorted chronologically.
  List<Reminder> get upcomingReminders => _reminders
      .where((r) => !r.isDeleted && r.dateTime.isAfter(DateTime.now()))
      .toList()
    ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

  /// All non-deleted reminders — sorted chronologically.
  List<Reminder> get allReminders => _reminders
      .where((r) => !r.isDeleted)
      .toList()
    ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

  void clear() {
    _reminders = [];
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadReminders(String uid) async {
    _isLoading = true;
    notifyListeners();
    try {
      // Reconcile and ensure all task reminders are present in reminders table
      final tasks = await _db.getTodos(uid);
      for (final t in tasks) {
        if (t.reminderDateTime != null && !t.isDeleted) {
          final taskReminder = Reminder(
            id: 'task_${t.id}',
            uid: t.uid,
            title: t.title,
            description: t.description.isNotEmpty ? t.description : 'Task Reminder',
            category: t.category,
            dateTime: t.reminderDateTime!,
            isCompleted: t.completed,
          );
          await _db.insertReminder(taskReminder);
        }
      }

      _reminders = await _db.getReminders(uid);
      _reminders.sort((a, b) => a.dateTime.compareTo(b.dateTime));

      // Wire up the auto-complete callback for reminder notifications
      NotificationService.onReminderTapped = (reminderId) {
        final idx = _reminders.indexWhere((r) => r.id == reminderId);
        if (idx != -1 && !_reminders[idx].isCompleted) {
          toggleCompleted(_reminders[idx]);
        }
      };
    } catch (e) {
      debugPrint('Error loading reminders: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addReminder(Reminder r) async {
    _reminders.add(r);
    _reminders.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    notifyListeners();
    await _db.insertReminder(r);

    await NotificationService.scheduleReminder(
      id: r.id.hashCode.abs() % 2147483647,
      title: '🔔 Reminder: ${r.title}',
      dateTime: r.dateTime,
      body: r.description.isNotEmpty
          ? r.description
          : 'Time for your scheduled reminder!',
      reminderId: r.id,
    );
  }

  Future<void> rescheduleReminder(Reminder r, DateTime newTime) async {
    final updated = r.copyWith(
      dateTime: newTime,
      isCompleted: false,
      updatedAt: DateTime.now(),
    );
    await updateReminder(updated);
    await NotificationService.scheduleReminder(
      id: updated.id.hashCode.abs() % 2147483647,
      title: '🔔 Reminder: ${updated.title}',
      dateTime: updated.dateTime,
      body: updated.description.isNotEmpty
          ? updated.description
          : 'Rescheduled reminder notification',
    );
  }

  Future<void> updateReminder(Reminder r) async {
    final idx = _reminders.indexWhere((item) => item.id == r.id);
    if (idx != -1) {
      _reminders[idx] = r.copyWith(updatedAt: DateTime.now());
      _reminders.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      notifyListeners();
      await _db.updateReminder(_reminders[idx]);

      // Sync back to Todo if this was a task reminder
      if (r.id.startsWith('task_')) {
        final taskId = r.id.substring(5);
        final taskList = await _db.getTodos(r.uid);
        final matches = taskList.where((t) => t.id == taskId);
        if (matches.isNotEmpty) {
          final t = matches.first;
          await _db.upsertTodo(t.copyWith(
            title: r.title,
            description: r.description,
            category: r.category,
            reminderDateTime: r.dateTime,
            completed: r.isCompleted,
            updatedAt: DateTime.now(),
          ));
        }
      }

      if (!r.isCompleted) {
        await NotificationService.scheduleReminder(
          id: r.id.hashCode.abs() % 2147483647,
          title: r.id.startsWith('task_') ? '🔔 Task Reminder: ${r.title}' : '🔔 Reminder: ${r.title}',
          dateTime: r.dateTime,
          body: r.description.isNotEmpty ? r.description : 'Time for your scheduled reminder!',
        );
      } else {
        await NotificationService.cancel(r.id.hashCode.abs() % 2147483647);
      }
    }
  }

  Future<void> toggleCompleted(Reminder r) async {
    final updated = r.copyWith(
      isCompleted: !r.isCompleted,
      updatedAt: DateTime.now(),
    );
    await updateReminder(updated);
  }

  Future<void> deleteReminder(String id) async {
    _reminders.removeWhere((r) => r.id == id);
    notifyListeners();
    await NotificationService.cancel(id.hashCode.abs() % 2147483647);
    await _db.deleteReminder(id);

    // If task reminder, clear reminderDateTime on Todo
    if (id.startsWith('task_')) {
      final taskId = id.substring(5);
      final tasks = await _db.getTodos(_reminders.isNotEmpty ? _reminders.first.uid : '');
      final matches = tasks.where((t) => t.id == taskId);
      if (matches.isNotEmpty) {
        final t = matches.first;
        await _db.upsertTodo(t.copyWith(
          reminderDateTime: null,
          updatedAt: DateTime.now(),
        ));
      }
    }
  }
}
