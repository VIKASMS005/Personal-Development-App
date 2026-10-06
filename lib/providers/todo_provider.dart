import 'package:flutter/material.dart';
import '../models/todo.dart';
import '../models/task_session.dart';
import '../models/reminder.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/task_analytics.dart';

class TodoProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<Todo> _todos = [];
  List<TaskSession> _sessions = [];

  List<Todo> get todos => _todos;
  List<TaskSession> get sessions => _sessions;

  // ── Tasks vs Goals Split ──────────────────────────────────────────────────
  List<Todo> get tasks => _todos.where((t) => t.isTask).toList();
  List<Todo> get goals => _todos.where((t) => t.isGoal).toList();

  List<Todo> get scheduledTasks =>
      tasks.where((t) => !t.completed && !t.isMissed).toList();
  List<Todo> get completedTasks => tasks.where((t) => t.completed).toList();
  List<Todo> get missedTasks => tasks.where((t) => t.isMissed).toList();

  List<Todo> get activeGoals =>
      goals.where((t) => !t.completed && !t.isMissed).toList();
  List<Todo> get completedGoals => goals.where((t) => t.completed).toList();
  List<Todo> get missedGoals => goals.where((t) => t.isMissed).toList();

  int get completedCount => completedTasks.length;
  int get pendingCount => tasks.where((t) => !t.completed).length;
  List<Todo> get pendingTodos => tasks.where((t) => !t.completed).toList();

  /// Missed = due time has passed AND 2-hour grace period is also over.
  List<Todo> get missedTodos => tasks.where((t) => t.isMissed).toList();
  int get missedCount => missedTodos.length;

  void clear() {
    _todos = [];
    _sessions = [];
    notifyListeners();
  }

  Future<void> loadTodos(String uid) async {
    _todos = await _db.getTodos(uid);
    _sessions = await _db.getAllTaskSessions(uid);
    notifyListeners();
  }

  Future<void> addTodo(Todo todo) async {
    _todos.insert(0, todo);
    notifyListeners();
    await _db.upsertTodo(todo);

    if (todo.reminderDateTime != null) {
      final taskReminder = Reminder(
        id: 'task_${todo.id}',
        uid: todo.uid,
        title: todo.title,
        description:
            todo.description.isNotEmpty ? todo.description : 'Task Reminder',
        category: todo.category,
        dateTime: todo.reminderDateTime!,
        isCompleted: todo.completed,
      );
      await _db.insertReminder(taskReminder);

      await NotificationService.scheduleReminder(
        id: NotificationService.stableId('task_${todo.id}'),
        title: '🔔 Task Reminder: ${todo.title}',
        dateTime: todo.reminderDateTime!,
        body: todo.description.isNotEmpty
            ? todo.description
            : 'Time to complete your scheduled task!',
      );
    }
  }

  Future<void> updateTodo(Todo todo) async {
    final idx = _todos.indexWhere((t) => t.id == todo.id);
    if (idx != -1) {
      _todos[idx] = todo.copyWith(updatedAt: DateTime.now());
      notifyListeners();
      await _db.upsertTodo(_todos[idx]);

      if (todo.reminderDateTime != null && !todo.completed) {
        final taskReminder = Reminder(
          id: 'task_${todo.id}',
          uid: todo.uid,
          title: todo.title,
          description:
              todo.description.isNotEmpty ? todo.description : 'Task Reminder',
          category: todo.category,
          dateTime: todo.reminderDateTime!,
          isCompleted: todo.completed,
        );
        await _db.insertReminder(taskReminder);

        await NotificationService.scheduleReminder(
          id: NotificationService.stableId('task_${todo.id}'),
          title: '🔔 Task Reminder: ${todo.title}',
          dateTime: todo.reminderDateTime!,
          body: todo.description.isNotEmpty
              ? todo.description
              : 'Time to complete your scheduled task!',
        );
      } else {
        if (todo.reminderDateTime == null) {
          await _db.deleteReminder('task_${todo.id}');
        } else {
          final taskReminder = Reminder(
            id: 'task_${todo.id}',
            uid: todo.uid,
            title: todo.title,
            description: todo.description.isNotEmpty
                ? todo.description
                : 'Task Reminder',
            category: todo.category,
            dateTime: todo.reminderDateTime!,
            isCompleted: true,
          );
          await _db.insertReminder(taskReminder);
        }
        await NotificationService.cancel(
            NotificationService.stableId('task_${todo.id}'));
      }
    }
  }

  Future<void> toggleCompleted(Todo todo) async {
    // Enforce grace period — a task cannot be completed after its deadline + 2h.
    // Allow un-checking a completed task at any time.
    if (!todo.completed && !todo.canComplete) return;

    final updated = todo.copyWith(
      completed: !todo.completed,
      updatedAt: DateTime.now(),
    );
    final idx = _todos.indexWhere((t) => t.id == todo.id);
    if (idx != -1) {
      _todos[idx] = updated;
      notifyListeners();
      await _db.upsertTodo(updated);

      if (updated.reminderDateTime != null) {
        final taskReminder = Reminder(
          id: 'task_${updated.id}',
          uid: updated.uid,
          title: updated.title,
          description: updated.description.isNotEmpty
              ? updated.description
              : 'Task Reminder',
          category: updated.category,
          dateTime: updated.reminderDateTime!,
          isCompleted: updated.completed,
        );
        await _db.insertReminder(taskReminder);
      }

      if (updated.completed) {
        await NotificationService.cancel(
            NotificationService.stableId('task_${todo.id}'));
      } else if (updated.reminderDateTime != null &&
          updated.reminderDateTime!.isAfter(DateTime.now())) {
        await NotificationService.scheduleReminder(
          id: NotificationService.stableId('task_${todo.id}'),
          title: '🔔 Task Reminder: ${updated.title}',
          dateTime: updated.reminderDateTime!,
          body: updated.description.isNotEmpty
              ? updated.description
              : 'Time to complete your scheduled task!',
        );
      }
    }
  }

  Future<void> deleteTodo(String id) async {
    _todos.removeWhere((t) => t.id == id);
    notifyListeners();
    await NotificationService.cancel(NotificationService.stableId('task_$id'));
    await _db.deleteReminder('task_$id');
    await _db.softDeleteTodo(id);
  }

  /// Adds freshly saved timer sessions and their time to the task total.
  Future<void> recordSessions(String taskId, List<TaskSession> newSessions) async {
    if (newSessions.isEmpty) return;
    _sessions.insertAll(0, newSessions);
    final idx = _todos.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      final added = newSessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);
      _todos[idx] = _todos[idx].copyWith(
        timeSpentSeconds: _todos[idx].timeSpentSeconds + added,
        updatedAt: DateTime.now(),
      );
      await _db.upsertTodo(_todos[idx]);
    }
    notifyListeners();
  }

  // ==================== TASK ANALYTICS & TIMER HISTORY ====================

  /// Task analytics computed from the stored tasks and sessions.
  TaskAnalytics analytics({DateTime? now}) =>
      TaskAnalytics(todos: _todos, sessions: _sessions, now: now);

  /// Timer sessions that actually happened on [day] (none for future days).
  List<TaskSession> sessionsOn(DateTime day) =>
      TaskAnalytics.sessionsOn(_sessions, day);
}
