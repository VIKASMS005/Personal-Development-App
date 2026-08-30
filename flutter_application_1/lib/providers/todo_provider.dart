import 'package:flutter/material.dart';
import '../models/todo.dart';
import '../models/task_session.dart';
import '../models/reminder.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';

class TodoProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<Todo> _todos = [];
  List<TaskSession> _sessions = [];

  List<Todo> get todos => _todos;
  List<TaskSession> get sessions => _sessions;
  int get completedCount => _todos.where((t) => t.completed).length;
  int get pendingCount => _todos.where((t) => !t.completed).length;
  List<Todo> get pendingTodos => _todos.where((t) => !t.completed).toList();
  /// Missed = due time has passed AND 2-hour grace period is also over.
  List<Todo> get missedTodos => _todos.where((t) => t.isMissed).toList();
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
        description: todo.description.isNotEmpty ? todo.description : 'Task Reminder',
        category: todo.category,
        dateTime: todo.reminderDateTime!,
        isCompleted: todo.completed,
      );
      await _db.insertReminder(taskReminder);

      await NotificationService.scheduleReminder(
        id: ('task_${todo.id}').hashCode.abs() % 2147483647,
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
          description: todo.description.isNotEmpty ? todo.description : 'Task Reminder',
          category: todo.category,
          dateTime: todo.reminderDateTime!,
          isCompleted: todo.completed,
        );
        await _db.insertReminder(taskReminder);

        await NotificationService.scheduleReminder(
          id: ('task_${todo.id}').hashCode.abs() % 2147483647,
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
            description: todo.description.isNotEmpty ? todo.description : 'Task Reminder',
            category: todo.category,
            dateTime: todo.reminderDateTime!,
            isCompleted: true,
          );
          await _db.insertReminder(taskReminder);
        }
        await NotificationService.cancel(('task_${todo.id}').hashCode.abs() % 2147483647);
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
          description: updated.description.isNotEmpty ? updated.description : 'Task Reminder',
          category: updated.category,
          dateTime: updated.reminderDateTime!,
          isCompleted: updated.completed,
        );
        await _db.insertReminder(taskReminder);
      }

      if (updated.completed) {
        await NotificationService.cancel(('task_${todo.id}').hashCode.abs() % 2147483647);
      } else if (updated.reminderDateTime != null && updated.reminderDateTime!.isAfter(DateTime.now())) {
        await NotificationService.scheduleReminder(
          id: ('task_${todo.id}').hashCode.abs() % 2147483647,
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
    await NotificationService.cancel(('task_$id').hashCode.abs() % 2147483647);
    await _db.deleteReminder('task_$id');
    await _db.softDeleteTodo(id);
  }

  Future<void> logTaskTime(String taskId, int durationSeconds) async {
    final idx = _todos.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      final task = _todos[idx];
      final newTime = task.timeSpentSeconds + durationSeconds;
      final updated = task.copyWith(
        timeSpentSeconds: newTime,
        updatedAt: DateTime.now(),
      );
      _todos[idx] = updated;

      final session = TaskSession(
        uid: task.uid,
        taskId: task.id,
        taskTitle: task.title,
        category: task.category.isNotEmpty ? task.category : 'General',
        durationSeconds: durationSeconds,
        timestamp: DateTime.now(),
      );
      _sessions.insert(0, session);
      notifyListeners();

      await _db.upsertTodo(updated);
      await _db.insertTaskSession(session);
    }
  }

  // ==================== DAILY REPORTS & ANALYTICS ====================
  static String _formatDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> getDailyReport(DateTime date) {
    final dateStr = _formatDate(date);
    final daySessions = _sessions.where((s) => s.date == dateStr).toList();
    final totalFocusSeconds =
        daySessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);

    // Group focus time by category
    final Map<String, int> categoryTime = {};
    for (final s in daySessions) {
      final cat = s.category.isNotEmpty ? s.category : 'General';
      categoryTime[cat] = (categoryTime[cat] ?? 0) + s.durationSeconds;
    }

    // Completed vs Incomplete Tasks
    final completedTasks = _todos.where((t) {
      if (!t.completed) return false;
      final updatedDateStr = _formatDate(t.updatedAt);
      return updatedDateStr == dateStr ||
          daySessions.any((s) => s.taskId == t.id);
    }).toList();

    final pendingTasks = _todos.where((t) => !t.completed).toList();

    final totalRelevant = completedTasks.length + pendingTasks.length;
    final completionRate = totalRelevant > 0
        ? ((completedTasks.length / totalRelevant) * 100).round()
        : 0;

    return {
      'date': date,
      'dateStr': dateStr,
      'totalSeconds': totalFocusSeconds,
      'totalMinutes': (totalFocusSeconds / 60).round(),
      'completedTasks': completedTasks,
      'pendingTasks': pendingTasks,
      'daySessions': daySessions,
      'categoryTime': categoryTime,
      'completionRate': completionRate,
    };
  }

  Map<String, dynamic> getImprovementComparison() {
    final now = DateTime.now();
    final todayStr = _formatDate(now);
    final yesterdayStr = _formatDate(now.subtract(const Duration(days: 1)));

    // 1. Day-to-Day (Today vs Yesterday)
    final todaySeconds = _sessions
        .where((s) => s.date == todayStr)
        .fold<int>(0, (sum, s) => sum + s.durationSeconds);
    final yesterdaySeconds = _sessions
        .where((s) => s.date == yesterdayStr)
        .fold<int>(0, (sum, s) => sum + s.durationSeconds);

    final todayCompleted = _todos
        .where((t) => t.completed && _formatDate(t.updatedAt) == todayStr)
        .length;
    final yesterdayCompleted = _todos
        .where((t) => t.completed && _formatDate(t.updatedAt) == yesterdayStr)
        .length;

    int dayTimeChangePct = 0;
    if (yesterdaySeconds > 0) {
      dayTimeChangePct =
          (((todaySeconds - yesterdaySeconds) / yesterdaySeconds) * 100)
              .round();
    } else if (todaySeconds > 0) {
      dayTimeChangePct = 100;
    }

    // 2. Week-to-Week (Past 7 Days vs Prior 7 Days)
    final past7Days =
        List.generate(7, (i) => _formatDate(now.subtract(Duration(days: i))));
    final prior7Days = List.generate(
        7, (i) => _formatDate(now.subtract(Duration(days: 7 + i))));

    final currentWeekSeconds = _sessions
        .where((s) => past7Days.contains(s.date))
        .fold<int>(0, (sum, s) => sum + s.durationSeconds);
    final priorWeekSeconds = _sessions
        .where((s) => prior7Days.contains(s.date))
        .fold<int>(0, (sum, s) => sum + s.durationSeconds);

    final currentWeekCompleted = _todos
        .where(
            (t) => t.completed && past7Days.contains(_formatDate(t.updatedAt)))
        .length;
    final priorWeekCompleted = _todos
        .where(
            (t) => t.completed && prior7Days.contains(_formatDate(t.updatedAt)))
        .length;

    int weekTimeChangePct = 0;
    if (priorWeekSeconds > 0) {
      weekTimeChangePct =
          (((currentWeekSeconds - priorWeekSeconds) / priorWeekSeconds) * 100)
              .round();
    } else if (currentWeekSeconds > 0) {
      weekTimeChangePct = 100;
    }

    // 3. Month-to-Month (This Month vs Previous Month)
    final thisMonthSessions = _sessions.where(
        (s) => s.timestamp.year == now.year && s.timestamp.month == now.month);
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevMonthYear = now.month == 1 ? now.year - 1 : now.year;
    final prevMonthSessions = _sessions.where((s) =>
        s.timestamp.year == prevMonthYear && s.timestamp.month == prevMonth);

    final thisMonthSeconds =
        thisMonthSessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);
    final prevMonthSeconds =
        prevMonthSessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);

    final thisMonthCompleted = _todos
        .where((t) =>
            t.completed &&
            t.updatedAt.year == now.year &&
            t.updatedAt.month == now.month)
        .length;
    final prevMonthCompleted = _todos
        .where((t) =>
            t.completed &&
            t.updatedAt.year == prevMonthYear &&
            t.updatedAt.month == prevMonth)
        .length;

    int monthTimeChangePct = 0;
    if (prevMonthSeconds > 0) {
      monthTimeChangePct =
          (((thisMonthSeconds - prevMonthSeconds) / prevMonthSeconds) * 100)
              .round();
    } else if (thisMonthSeconds > 0) {
      monthTimeChangePct = 100;
    }

    return {
      // Day-to-Day
      'todayMinutes': (todaySeconds / 60).round(),
      'yesterdayMinutes': (yesterdaySeconds / 60).round(),
      'todayCompleted': todayCompleted,
      'yesterdayCompleted': yesterdayCompleted,
      'dayTimeChangePct': dayTimeChangePct,

      // Week-to-Week
      'currentWeekHours': (currentWeekSeconds / 3600).toStringAsFixed(1),
      'priorWeekHours': (priorWeekSeconds / 3600).toStringAsFixed(1),
      'currentWeekDailyAvgMinutes': ((currentWeekSeconds / 60) / 7).round(),
      'currentWeekCompleted': currentWeekCompleted,
      'priorWeekCompleted': priorWeekCompleted,
      'weekTimeChangePct': weekTimeChangePct,

      // Month-to-Month
      'thisMonthHours': (thisMonthSeconds / 3600).toStringAsFixed(1),
      'prevMonthHours': (prevMonthSeconds / 3600).toStringAsFixed(1),
      'thisMonthCompleted': thisMonthCompleted,
      'prevMonthCompleted': prevMonthCompleted,
      'monthTimeChangePct': monthTimeChangePct,
    };
  }
}
