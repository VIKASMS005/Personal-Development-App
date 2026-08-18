import 'package:uuid/uuid.dart';

class Todo {
  String id;
  String uid;
  String title;
  String description;
  String category; // 'Study', 'Work', 'Workout', 'Coding', 'Reading', 'Personal', 'General', 'Other'
  DateTime? dueDate;
  DateTime? reminderDateTime;
  int priority; // 1..4 (Eisenhower mapping: 1=Urgent&Important, 2=Important, 3=Urgent, 4=Low)
  int timeSpentSeconds; // Total tracked focus/study time in seconds
  int targetMinutes; // Optional goal duration in minutes
  bool completed;
  DateTime updatedAt;
  bool isSynced;
  bool isDeleted;

  Todo({
    String? id,
    this.uid = '',
    required this.title,
    this.description = '',
    this.category = 'General',
    this.dueDate,
    this.reminderDateTime,
    this.priority = 4,
    this.timeSpentSeconds = 0,
    this.targetMinutes = 0,
    this.completed = false,
    DateTime? updatedAt,
    this.isSynced = false,
    this.isDeleted = false,
  })  : id = id ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now();

  Todo copyWith({
    String? id,
    String? uid,
    String? title,
    String? description,
    String? category,
    DateTime? dueDate,
    DateTime? reminderDateTime,
    int? priority,
    int? timeSpentSeconds,
    int? targetMinutes,
    bool? completed,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return Todo(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      dueDate: dueDate ?? this.dueDate,
      reminderDateTime: reminderDateTime ?? this.reminderDateTime,
      priority: priority ?? this.priority,
      timeSpentSeconds: timeSpentSeconds ?? this.timeSpentSeconds,
      targetMinutes: targetMinutes ?? this.targetMinutes,
      completed: completed ?? this.completed,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'uid': uid,
        'title': title,
        'description': description,
        'category': category,
        'dueDate': dueDate?.toIso8601String(),
        'reminderDateTime': reminderDateTime?.toIso8601String(),
        'priority': priority,
        'timeSpentSeconds': timeSpentSeconds,
        'targetMinutes': targetMinutes,
        'completed': completed,
        'updatedAt': updatedAt.toIso8601String(),
        'isDeleted': isDeleted,
      };

  Map<String, dynamic> toSqliteMap() => {
        'id': id,
        'uid': uid,
        'title': title,
        'description': description,
        'category': category,
        'due_date': dueDate?.toIso8601String(),
        'reminder_date_time': reminderDateTime?.toIso8601String(),
        'priority': priority,
        'time_spent_seconds': timeSpentSeconds,
        'target_minutes': targetMinutes,
        'completed': completed ? 1 : 0,
        'updated_at': updatedAt.toIso8601String(),
        'is_synced': isSynced ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
      };

  factory Todo.fromMap(Map<String, dynamic> m) => Todo(
        id: m['id'] as String?,
        uid: (m['uid'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        category: (m['category'] ?? 'General') as String,
        dueDate: (m['dueDate'] ?? m['due_date']) != null
            ? DateTime.tryParse((m['dueDate'] ?? m['due_date']).toString())
            : null,
        reminderDateTime: (m['reminderDateTime'] ?? m['reminder_date_time']) != null
            ? DateTime.tryParse((m['reminderDateTime'] ?? m['reminder_date_time']).toString())
            : null,
        priority: (m['priority'] is num)
            ? (m['priority'] as num).toInt()
            : int.tryParse('${m['priority']}') ?? 4,
        timeSpentSeconds: (m['timeSpentSeconds'] ?? m['time_spent_seconds'] is num)
            ? ((m['timeSpentSeconds'] ?? m['time_spent_seconds']) as num).toInt()
            : int.tryParse('${m['timeSpentSeconds'] ?? m['time_spent_seconds']}') ?? 0,
        targetMinutes: (m['targetMinutes'] ?? m['target_minutes'] is num)
            ? ((m['targetMinutes'] ?? m['target_minutes']) as num).toInt()
            : int.tryParse('${m['targetMinutes'] ?? m['target_minutes']}') ?? 0,
        completed: (m['completed'] == true || m['completed'] == 1 || m['completed'] == 'true'),
        updatedAt: (m['updatedAt'] ?? m['updated_at']) != null
            ? DateTime.tryParse((m['updatedAt'] ?? m['updated_at']).toString()) ?? DateTime.now()
            : DateTime.now(),
        isSynced: (m['isSynced'] == true || m['isSynced'] == 1 || m['isSynced'] == 'true' || m['is_synced'] == 1 || m['is_synced'] == true),
        isDeleted: (m['isDeleted'] == true || m['isDeleted'] == 1 || m['isDeleted'] == 'true' || m['is_deleted'] == 1 || m['is_deleted'] == true),
      );

  factory Todo.fromSqlite(Map<String, dynamic> m) => Todo(
        id: m['id'] as String?,
        uid: (m['uid'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        category: (m['category'] ?? 'General') as String,
        dueDate:
            m['due_date'] != null ? DateTime.tryParse(m['due_date'].toString()) : null,
        reminderDateTime: m['reminder_date_time'] != null
            ? DateTime.tryParse(m['reminder_date_time'].toString())
            : null,
        priority: (m['priority'] is num)
            ? (m['priority'] as num).toInt()
            : int.tryParse('${m['priority']}') ?? 4,
        timeSpentSeconds: (m['time_spent_seconds'] is num)
            ? (m['time_spent_seconds'] as num).toInt()
            : int.tryParse('${m['time_spent_seconds']}') ?? 0,
        targetMinutes: (m['target_minutes'] is num)
            ? (m['target_minutes'] as num).toInt()
            : int.tryParse('${m['target_minutes']}') ?? 0,
        completed: (m['completed'] == 1 || m['completed'] == true),
        updatedAt: m['updated_at'] != null
            ? DateTime.tryParse(m['updated_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        isSynced: m['is_synced'] == 1,
        isDeleted: m['is_deleted'] == 1,
      );
}
