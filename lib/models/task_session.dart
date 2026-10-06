import 'package:uuid/uuid.dart';

/// One finished block of timed work on a task.
///
/// A session always belongs to exactly one calendar day ([date]). If a timer
/// runs across midnight, the tracker saves one session per day, so a day's
/// total is simply the sum of its own sessions.
class TaskSession {
  static const statusCompleted = 'completed';

  String id;
  String uid;
  String taskId;
  String taskTitle;
  String category;
  int durationSeconds;
  String date; // YYYY-MM-DD of [startTime], local time
  DateTime startTime;
  DateTime endTime;
  String status;

  /// When the session was saved. Kept for ordering and older backups.
  DateTime timestamp;

  TaskSession({
    String? id,
    this.uid = '',
    required this.taskId,
    required this.taskTitle,
    this.category = 'General',
    required this.durationSeconds,
    String? date,
    DateTime? startTime,
    DateTime? endTime,
    this.status = statusCompleted,
    DateTime? timestamp,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? endTime ?? DateTime.now(),
        endTime = endTime ?? timestamp ?? DateTime.now(),
        startTime = startTime ??
            (endTime ?? timestamp ?? DateTime.now())
                .subtract(Duration(seconds: durationSeconds)),
        date = date ??
            formatDate(startTime ??
                (endTime ?? timestamp ?? DateTime.now())
                    .subtract(Duration(seconds: durationSeconds)));

  static String formatDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'uid': uid,
        'taskId': taskId,
        'taskTitle': taskTitle,
        'category': category,
        'durationSeconds': durationSeconds,
        'date': date,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'status': status,
        'timestamp': timestamp.toIso8601String(),
      };

  Map<String, dynamic> toSqliteMap() => {
        'id': id,
        'uid': uid,
        'task_id': taskId,
        'task_title': taskTitle,
        'category': category,
        'duration_seconds': durationSeconds,
        'date': date,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'status': status,
        'timestamp': timestamp.toIso8601String(),
      };

  static DateTime? _parse(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  factory TaskSession.fromMap(Map<String, dynamic> m) {
    final duration = (m['durationSeconds'] is num)
        ? (m['durationSeconds'] as num).toInt()
        : (m['duration_seconds'] is num)
            ? (m['duration_seconds'] as num).toInt()
            : int.tryParse('${m['durationSeconds'] ?? m['duration_seconds']}') ?? 0;
    final timestamp = _parse(m['timestamp']);
    // Sessions saved before start/end were stored only had the save time,
    // which was the moment the timer was finished.
    final end = _parse(m['endTime'] ?? m['end_time']) ?? timestamp;
    final start = _parse(m['startTime'] ?? m['start_time']) ??
        end?.subtract(Duration(seconds: duration));
    return TaskSession(
      id: m['id'] as String?,
      uid: (m['uid'] ?? '') as String,
      taskId: (m['taskId'] ?? m['task_id'] ?? '') as String,
      taskTitle: (m['taskTitle'] ?? m['task_title'] ?? '') as String,
      category: (m['category'] ?? 'General') as String,
      durationSeconds: duration,
      date: m['date'] as String?,
      startTime: start,
      endTime: end,
      status: (m['status'] ?? statusCompleted) as String,
      timestamp: timestamp,
    );
  }
}
