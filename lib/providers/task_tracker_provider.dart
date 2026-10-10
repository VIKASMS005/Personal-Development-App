import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
/// The running/paused timer lives here and is mirrored to SharedPreferences,
/// so it survives the app being closed or killed. It becomes history (saved
/// [TaskSession]s with real timestamps) when the user ends it.
class TaskTrackerProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;

  static const _prefsKey = 'grow_active_task_timer_v1';
  static const _channel = MethodChannel('com.grow.app/settings');

  /// Set by the home screen once tasks are loaded; needed to save sessions
  /// for presses made on the timer notification.
  TodoProvider? _todoProvider;
  Timer? _notificationPoll;
  bool _applyingNotification = false;

  TaskTrackerProvider() {
    _restore();
  }

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
  /// A timer already running on another task is ended and saved first, so
  /// switching tasks never throws away tracked time.
  Future<void> startTracking(BuildContext context, Todo todo) async {
    if (todo.isGoal) return;
    if (_isTracking) {
      await finish(context);
    }
    _activeTodo = todo;
    _isTracking = true;
    _isPaused = false;
    _segments.clear();
    _pausedAt = null;
    _runningSince = DateTime.now();

    _startTicker();
    _persist();
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
    _persist();
    notifyListeners();
  }

  void resume() {
    if (!_isTracking || !_isPaused) return;
    _isPaused = false;
    _pausedAt = null;
    _runningSince = DateTime.now();
    _startTicker();
    _persist();
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
  /// Returns false when nothing was saved (too short, or the task is gone).
  Future<bool> finish(BuildContext context) =>
      _finishAt(DateTime.now(), context.read<TodoProvider>());

  Future<bool> _finishAt(DateTime now, TodoProvider todoProvider) async {
    if (!_isTracking || _activeTodo == null) return false;

    final segments = [
      ..._segments,
      if (_runningSince != null && now.isAfter(_runningSince!))
        TimerSegment(_runningSince!, now),
    ];
    // Use the task as it is now (it may have been renamed while the timer ran).
    final active = _activeTodo!;
    final matches = todoProvider.todos.where((t) => t.id == active.id);

    _reset();

    final total = segments.fold<int>(0, (sum, s) => sum + s.seconds);
    if (total <= minSessionSeconds || matches.isEmpty) return false;
    final todo = matches.first;

    final sessions = buildDailySessions(todo: todo, segments: segments, savedAt: now);
    for (final session in sessions) {
      await _db.insertTaskSession(session);
    }
    await todoProvider.recordSessions(todo.id, sessions);
    return true;
  }

  /// Discards the current session without saving anything.
  void cancel() => _reset();

  /// Stops (without saving) if [todoId] is the task being timed.
  void cancelIfTracking(String todoId) {
    if (_isTracking && _activeTodo?.id == todoId) cancel();
  }

  void _reset() {
    _tickerTimer?.cancel();
    _isTracking = false;
    _isPaused = false;
    _activeTodo = null;
    _segments.clear();
    _runningSince = null;
    _pausedAt = null;
    _persist();
    notifyListeners();
  }

  // ── Persistence ─────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todo = _activeTodo;
      if (!_isTracking || todo == null) {
        await prefs.remove(_prefsKey);
        return;
      }
      await prefs.setString(
          _prefsKey,
          jsonEncode({
            'todo': todo.toMap(),
            'segments': [
              for (final s in _segments)
                [s.start.toIso8601String(), s.end.toIso8601String()]
            ],
            'runningSince': _runningSince?.toIso8601String(),
            'pausedAt': _pausedAt?.toIso8601String(),
          }));
    } catch (e) {
      debugPrint('[TaskTracker] could not save timer state: $e');
    }
    await _syncNotification();
  }

  // ── Timer notification (Android) ────────────────────────────────────────────

  /// Mirrors the timer into the notification, or removes it when it ended.
  Future<void> _syncNotification() async {
    if (!Platform.isAndroid) return;
    try {
      final todo = _activeTodo;
      if (!_isTracking || todo == null) {
        await _channel.invokeMethod('stopTaskTimer');
        return;
      }
      final doneMs = _segments.fold<int>(
          0, (sum, s) => sum + s.end.difference(s.start).inMilliseconds);
      await _channel.invokeMethod('syncTaskTimer', {
        'title': todo.title,
        'doneMs': doneMs,
        'runningSinceMs': _runningSince?.millisecondsSinceEpoch ?? 0,
      });
    } catch (e) {
      debugPrint('[TaskTracker] could not update the timer notification: $e');
    }
  }

  /// Starts applying presses made on the notification (now, every couple of
  /// seconds while the app is open, and on [syncFromNotification]).
  void attach(TodoProvider todoProvider) {
    _todoProvider = todoProvider;
    _notificationPoll?.cancel();
    _notificationPoll = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isTracking) syncFromNotification();
    });
    syncFromNotification(resync: true);
  }

  /// Replays Pause/Resume/End pressed on the notification, at the moments
  /// they were pressed (even while the app was closed). With [resync] (app
  /// opened or brought back) the notification is re-shown from the app's
  /// state even when nothing was pressed, e.g. after an update.
  Future<void> syncFromNotification({bool resync = false}) async {
    final todoProvider = _todoProvider;
    if (!Platform.isAndroid || todoProvider == null || _applyingNotification) return;
    _applyingNotification = true;
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('drainTaskTimerEvents') ?? const [];
      final events = [
        for (final e in raw)
          if (e is Map)
            (
              action: '${e['action']}',
              at: DateTime.fromMillisecondsSinceEpoch((e['atMs'] as num).toInt()),
            )
      ]..sort((a, b) => a.at.compareTo(b.at));
      for (final e in events) {
        applyNotificationEvent(e.action, e.at);
        if (e.action == 'end') await _finishAt(e.at, todoProvider);
      }
      if (events.isNotEmpty) {
        await _persist();
        notifyListeners();
      } else if (resync) {
        await _syncNotification();
      }
    } catch (e) {
      debugPrint('[TaskTracker] could not read timer notification presses: $e');
    } finally {
      _applyingNotification = false;
    }
  }

  /// Applies a Pause or Resume pressed at [at] (End is saved by the caller).
  @visibleForTesting
  void applyNotificationEvent(String action, DateTime at) {
    if (!_isTracking) return;
    if (action == 'pause' && _runningSince != null) {
      if (at.isAfter(_runningSince!)) _segments.add(TimerSegment(_runningSince!, at));
      _runningSince = null;
      _pausedAt = at;
      _isPaused = true;
      _tickerTimer?.cancel();
    } else if (action == 'resume' && _isPaused) {
      _isPaused = false;
      _pausedAt = null;
      _runningSince = at;
      _startTicker();
    }
  }

  /// Brings back a timer that was running or paused when the app was closed.
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || _isTracking) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final todo = Todo.fromMap(Map<String, dynamic>.from(m['todo'] as Map));
      final segments = <TimerSegment>[];
      for (final s in (m['segments'] as List? ?? const [])) {
        final start = DateTime.tryParse('${s[0]}');
        final end = DateTime.tryParse('${s[1]}');
        if (start != null && end != null && end.isAfter(start)) {
          segments.add(TimerSegment(start, end));
        }
      }
      final runningSince = DateTime.tryParse('${m['runningSince']}');
      if (segments.isEmpty && runningSince == null) {
        await prefs.remove(_prefsKey);
        return;
      }
      _activeTodo = todo;
      _isTracking = true;
      _segments
        ..clear()
        ..addAll(segments);
      _runningSince = runningSince;
      _isPaused = runningSince == null;
      _pausedAt = _isPaused ? DateTime.tryParse('${m['pausedAt']}') : null;
      if (!_isPaused) _startTicker();
      notifyListeners();
    } catch (e) {
      debugPrint('[TaskTracker] could not restore timer state: $e');
    }
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
    _notificationPoll?.cancel();
    super.dispose();
  }
}
