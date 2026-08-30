import 'package:uuid/uuid.dart';

class TaskSession {
  String id;
  String uid;
  String taskId;
  String taskTitle;
  String category;
  int durationSeconds;
  String date; // YYYY-MM-DD
  DateTime timestamp;

  TaskSession({
    String? id,
    this.uid = '',
    required this.taskId,
    required this.taskTitle,
    this.category = 'General',
    required this.durationSeconds,
    String? date,
    DateTime? timestamp,
  })  : id = id ?? const Uuid().v4(),
        date = date ?? _formatDate(timestamp ?? DateTime.now()),
        timestamp = timestamp ?? DateTime.now();

  static String _formatDate(DateTime dt) {
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
        'timestamp': timestamp.toIso8601String(),
      };

  factory TaskSession.fromMap(Map<String, dynamic> m) => TaskSession(
        id: m['id'] as String?,
        uid: (m['uid'] ?? '') as String,
        taskId: (m['taskId'] ?? m['task_id'] ?? '') as String,
        taskTitle: (m['taskTitle'] ?? m['task_title'] ?? '') as String,
        category: (m['category'] ?? 'General') as String,
        durationSeconds: (m['durationSeconds'] is num)
            ? (m['durationSeconds'] as num).toInt()
            : (m['duration_seconds'] is num)
                ? (m['duration_seconds'] as num).toInt()
                : int.tryParse('${m['durationSeconds'] ?? m['duration_seconds']}') ?? 0,
        date: m['date'] as String?,
        timestamp: m['timestamp'] != null
            ? DateTime.tryParse(m['timestamp'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );
}
