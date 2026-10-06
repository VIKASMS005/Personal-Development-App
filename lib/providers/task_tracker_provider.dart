import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/todo.dart';
import '../models/task_session.dart';
import '../services/database_service.dart';
import 'todo_provider.dart';

/// One uninterrupted stretch of a running timer (start/resume → pause/end).
class TimerSegment {
  final DateTime start;
  final DateTime end;
  const TimerSegment(this.start, this.end);
  int get seconds => end.difference(start).inSeconds;
}

/// Splits timed segments into one [TaskSession] per calendar day, so every
/// second is counted on the day it actually happened (a timer running across
/// midnight, or paused one day and ended the next, is split correctly).
List<TaskSession> buildDailySessions({
  required Todo todo,
  required List<TimerSegment> segments,
  required DateTime savedAt,
}) {
  final byDay = <String, List<TimerSegment>>{};
  for (final seg in segments) {
    var cursor = seg.start;
    while (cursor.isBefore(seg.end)) {
      final nextMidnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
      final pieceEnd = seg.end.isBefore(nextMidnight) ? seg.end : nextMidnight;
      byDay.putIfAbsent(TaskSession.formatDate(cursor), () => []).add(TimerSegment(cursor, pieceEnd));
      cursor = pieceEnd;
    }
  }

  final sessions = <TaskSession>[];
  for (final entry in byDay.entries) {
    final pieces = entry.value;
    final seconds = pieces.fold<int>(0, (sum, p) => sum + p.seconds);
    if (seconds <= 0) continue;
    sessions.add(TaskSession(
      uid: todo.uid,
      taskId: todo.id,
      taskTitle: todo.title,
      category: todo.category,
      durationSeconds: seconds,
      date: entry.key,
      startTime: pieces.first.start,
      endTime: pieces.last.end,
      status: TaskSession.statusCompleted,
      timestamp: savedAt,
    ));
  }
  return sessions;
}

/// Global persistent non-blocking task tracker provider.
/// Allows the user to track task time accurately across all screens
/// and in the background.
///
/// The running/paused timer lives only here. It becomes history (saved
/// [TaskSession]s with real timestamps) when the user ends it.
class TaskTrackerProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;

  /// Sessions shorter than this are treated as accidental taps.
  static const minSessionSeconds = 5;

  Todo? _activeTodo;
  bool _isTracking = false;
  bool _isPaused = false;

  /// Finished stretches of the current session.
  final List<TimerSegment> _segments = [];

  /// Start of the stretch that is running now (null while paused).
  DateTime? _runningSince;
  DateTime? _pausedAt;

  Timer? _tickerTimer;

  Todo? get activeTodo => _activeTodo;
  bool get isTracking => _isTracking;
  bool get isPaused => _isPaused;

  /// When the current session was first started.
  DateTime? get sessionStartedAt =>
      _segments.isNotEmpty ? _segments.first.start : _runningSince;

  /// When the current session was last paused (null while running).
  DateTime? get pausedAt => _isPaused ? _pausedAt : null;

  int get currentElapsedSeconds {
    if (!_isTracking) return 0;
    final done = _segments.fold<int>(0, (sum, s) => sum + s.seconds);
    if (_runningSince == null) return done;
    return done + DateTime.now().difference(_runningSince!).inSeconds;
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

  /// Starts timing [todo]. Goals are not timed, so they are ignored.
  void startTracking(Todo todo) {
    if (todo.isGoal) return;
    if (_isTracking) {
      // If already tracking another task, stop previous and start new
      cancel();
    }
    _activeTodo = todo;
    _isTracking = true;
    _isPaused = false;
    _segments.clear();
    _pausedAt = null;
    _runningSince = DateTime.now();

    _startTicker();
    notifyListeners();
  }

  void pause() {
    if (!_isTracking || _isPaused || _runningSince == null) return;
    final now = DateTime.now();
    _segments.add(TimerSegment(_runningSince!, now));
    _runningSince = null;
    _pausedAt = now;
    _isPaused = true;
    _tickerTimer?.cancel();
    notifyListeners();
  }

  void resume() {
    if (!_isTracking || !_isPaused) return;
    _isPaused = false;
    _pausedAt = null;
    _runningSince = DateTime.now();
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

  /// Ends the session and saves it as history, one record per day it ran on.
  Future<void> finish(BuildContext context) async {
    if (!_isTracking || _activeTodo == null) return;

    final now = DateTime.now();
    final segments = [
      ..._segments,
      if (_runningSince != null) TimerSegment(_runningSince!, now),
    ];
    final todo = _activeTodo!;
    final todoProvider = context.read<TodoProvider>();

    _reset();

    final total = segments.fold<int>(0, (sum, s) => sum + s.seconds);
    if (total <= minSessionSeconds) return;

    final sessions = buildDailySessions(todo: todo, segments: segments, savedAt: now);
    for (final session in sessions) {
      await _db.insertTaskSession(session);
    }
    await todoProvider.recordSessions(todo.id, sessions);
  }

  /// Discards the current session without saving anything.
  void cancel() => _reset();

  void _reset() {
    _tickerTimer?.cancel();
    _isTracking = false;
    _isPaused = false;
    _activeTodo = null;
    _segments.clear();
    _runningSince = null;
    _pausedAt = null;
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
