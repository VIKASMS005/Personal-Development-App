import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/todo.dart';
import '../models/task_session.dart';
import '../services/database_service.dart';
import 'todo_provider.dart';

/// Global persistent non-blocking task tracker provider.
/// Allows the user to track task time accurately across all screens
/// and in the background.
class TaskTrackerProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;

  Todo? _activeTodo;
  bool _isTracking = false;
  bool _isPaused = false;

  DateTime? _sessionStartTime;
  int _accumulatedSecondsBeforePause = 0;

  Timer? _tickerTimer;

  Todo? get activeTodo => _activeTodo;
  bool get isTracking => _isTracking;
  bool get isPaused => _isPaused;

  int get currentElapsedSeconds {
    if (!_isTracking || _sessionStartTime == null) return 0;
    if (_isPaused) {
      return _accumulatedSecondsBeforePause;
    }
    final currentRunningSeconds =
        DateTime.now().difference(_sessionStartTime!).inSeconds;
    return _accumulatedSecondsBeforePause + currentRunningSeconds;
  }

  String get formattedTime {
    final sec = currentElapsedSeconds;
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void startTracking(Todo todo) {
    if (_isTracking) {
      // If already tracking another task, stop previous and start new
      cancel();
    }
    _activeTodo = todo;
    _isTracking = true;
    _isPaused = false;
    _accumulatedSecondsBeforePause = 0;
    _sessionStartTime = DateTime.now();

    _startTicker();
    notifyListeners();
  }

  void pause() {
    if (!_isTracking || _isPaused) return;
    _isPaused = true;
    _accumulatedSecondsBeforePause +=
        DateTime.now().difference(_sessionStartTime!).inSeconds;
    _sessionStartTime = null;
    _tickerTimer?.cancel();
    notifyListeners();
  }

  void resume() {
    if (!_isTracking || !_isPaused) return;
    _isPaused = false;
    _sessionStartTime = DateTime.now();
    _startTicker();
    notifyListeners();
  }

  void togglePauseResume() {
    if (_isPaused) {
      resume();
    } else {
      pause();
    }
  }

  Future<void> finish(BuildContext context) async {
    if (!_isTracking || _activeTodo == null) return;

    final elapsed = currentElapsedSeconds;
    final todo = _activeTodo!;

    _tickerTimer?.cancel();
    _isTracking = false;
    _isPaused = false;
    _activeTodo = null;
    _sessionStartTime = null;
    _accumulatedSecondsBeforePause = 0;
    notifyListeners();

    if (elapsed > 5) {
      // Record task session in SQLite
      final now = DateTime.now();
      final dateStr = now.toIso8601String().split('T')[0];
      final session = TaskSession(
        uid: todo.uid,
        taskId: todo.id,
        taskTitle: todo.title,
        category: todo.category,
        durationSeconds: elapsed,
        date: dateStr,
        timestamp: now,
      );
      await _db.insertTaskSession(session);

      // Update total time spent on the todo
      final updatedTodo = todo.copyWith(
        timeSpentSeconds: todo.timeSpentSeconds + elapsed,
        updatedAt: now,
      );

      if (context.mounted) {
        await context.read<TodoProvider>().updateTodo(updatedTodo);
      }
    }
  }

  void cancel() {
    _tickerTimer?.cancel();
    _isTracking = false;
    _isPaused = false;
    _activeTodo = null;
    _sessionStartTime = null;
    _accumulatedSecondsBeforePause = 0;
    notifyListeners();
  }

  void _startTicker() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    super.dispose();
  }
}
