import 'package:flutter/material.dart';
import '../models/reminder.dart';
import '../models/todo.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

class ReminderProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<Reminder> _reminders = [];
  bool _isLoading = false;

  List<Reminder> get reminders => _reminders;

  /// Called after a task row was changed from the reminders side, so the
  /// in-memory task list can take the saved version (otherwise a later save of
  /// the stale task would write the old title/reminder/completion back).
  void Function(Todo task)? onTaskChanged;
  bool get isLoading => _isLoading;
  int get activeCount => _reminders.where((r) => !r.isCompleted).length;

  /// Reminders whose scheduled time is at or in the future (within last minute tolerance) — sorted chronologically.
  /// FIX H4: Use a 1-minute lookback so reminders at the current clock minute are included.
  /// The alarm watcher fires every 15 seconds; a strict isAfter(now) would miss reminders whose
  /// exact DateTime is a few milliseconds in the past by the time the tick fires.
  List<Reminder> get upcomingReminders => _reminders
      .where((r) =>
          !r.isDeleted &&
          !r.isCompleted &&
          r.dateTime
              .isAfter(DateTime.now().subtract(const Duration(minutes: 1))))
      .toList()
    ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

  /// All non-deleted reminders — sorted chronologically.
  List<Reminder> get allReminders =>
      _reminders.where((r) => !r.isDeleted).toList()
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
            description:
                t.description.isNotEmpty ? t.description : 'Task Reminder',
            category: t.category,
            dateTime: t.reminderDateTime!,
            isCompleted: t.completed,
          );
          await _db.insertReminder(taskReminder);
        } else {
          // BUG 11 FIX: If task has no reminder or is deleted, delete obsolete reminder record and cancel notification
          await _db.deleteReminder('task_${t.id}');
          await NotificationService.cancel(
              NotificationService.stableId('task_${t.id}'));
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

  /// Schedules a notification for every reminder still to come (e.g. after
  /// restoring a backup, whose reminders were only written to the database).
  Future<void> rescheduleUpcoming() async {
    final now = DateTime.now();
    for (final r in _reminders) {
      if (r.isDeleted || r.isCompleted || !r.dateTime.isAfter(now)) continue;
      await NotificationService.scheduleReminder(
        id: NotificationService.stableId(r.id),
        title: r.id.startsWith('task_')
            ? '🔔 Task Reminder: ${r.title}'
            : '🔔 Reminder: ${r.title}',
        dateTime: r.dateTime,
        body: r.description.isNotEmpty
            ? r.description
            : 'Time for your scheduled reminder!',
        reminderId: r.id,
      );
    }
  }

  Future<void> addReminder(Reminder r) async {
    _reminders.add(r);
    _reminders.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    notifyListeners();
    await _db.insertReminder(r);

    await NotificationService.scheduleReminder(
      id: NotificationService.stableId(r.id),
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
      id: NotificationService.stableId(updated.id),
      title: '🔔 Reminder: ${updated.title}',
      dateTime: updated.dateTime,
      body: updated.description.isNotEmpty
          ? updated.description
          : 'Rescheduled reminder notification',
      reminderId: updated.id,
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
          final saved = t.copyWith(
            title: r.title,
            description: r.description,
            category: r.category,
            reminderDateTime: r.dateTime,
            completed: r.isCompleted,
            updatedAt: DateTime.now(),
          );
          await _db.upsertTodo(saved);
          onTaskChanged?.call(saved);
        }
      }

      if (!r.isCompleted) {
        await NotificationService.scheduleReminder(
          id: NotificationService.stableId(r.id),
          title: r.id.startsWith('task_')
              ? '🔔 Task Reminder: ${r.title}'
              : '🔔 Reminder: ${r.title}',
          dateTime: r.dateTime,
          body: r.description.isNotEmpty
              ? r.description
              : 'Time for your scheduled reminder!',
          reminderId: r.id,
        );
      } else {
        await NotificationService.cancel(NotificationService.stableId(r.id));
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
    // BUG 10 FIX: Capture uid BEFORE removeWhere — if this is the only reminder,
    // _reminders will be empty after the remove and _reminders.first would throw.
    final targetReminder = _reminders.firstWhere(
      (r) => r.id == id,
      orElse: () => Reminder(
          id: id,
          uid: '',
          title: '',
          description: '',
          dateTime: DateTime.now()),
    );
    final uid = targetReminder.uid;

    _reminders.removeWhere((r) => r.id == id);
    notifyListeners();
    await NotificationService.cancel(NotificationService.stableId(id));
    await _db.deleteReminder(id);

    // If task reminder, clear reminderDateTime on Todo
    if (id.startsWith('task_')) {
      final taskId = id.substring(5);
      final tasks = await _db.getTodos(uid);
      final matches = tasks.where((t) => t.id == taskId);
      if (matches.isNotEmpty) {
        final t = matches.first;
        // copyWith(reminderDateTime: null) would keep the old value, and the
        // next load would then recreate the deleted reminder from the task.
        final saved = t.copyWith(clearReminder: true, updatedAt: DateTime.now());
        await _db.upsertTodo(saved);
        onTaskChanged?.call(saved);
      }
    }
  }
}
