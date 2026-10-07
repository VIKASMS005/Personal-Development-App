import 'package:uuid/uuid.dart';

class Todo {
  String id;
  String uid;
  String title;
  String description;
  String
      category; // 'Study', 'Work', 'Workout', 'Coding', 'Reading', 'Personal', 'General', 'Other'
  DateTime? dueDate;
  DateTime? reminderDateTime;
  int priority; // 1..4 (1=Urgent, 2=Important, 3=Medium, 4=Low)
  int timeSpentSeconds; // Total tracked focus/study time in seconds
  int targetMinutes; // Optional goal duration in minutes
  bool completed;

  /// When the item was marked complete; null while it is not completed.
  DateTime? completedAt;
  String
      type; // Permanent classification: 'task' (<= 7 days at creation) or 'goal' (> 7 days at creation)
  DateTime? createdAt;
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
    this.completedAt,
    String? type,
    this.createdAt,
    DateTime? updatedAt,
    this.isSynced = false,
    this.isDeleted = false,
  })  : id = id ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now(),
        type = type ?? classify(dueDate: dueDate, createdAt: createdAt);

  // ─── Classification Helper ───────────────────────────────────────────────

  /// Determine classification ONCE at creation time:
  /// • Deadline <= 7 days from creation -> 'task'
  /// • Deadline > 7 days from creation -> 'goal'
  /// If no valid creation date exists, do not guess -> default 'task'
  /// Once set, this classification NEVER changes automatically.
  static String classify(
      {required DateTime? dueDate, required DateTime? createdAt}) {
    if (dueDate == null || createdAt == null) return 'task';
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final createdDay = DateTime(createdAt.year, createdAt.month, createdAt.day);
    final diffDays = dueDay.difference(createdDay).inDays;
    return diffDays > 7 ? 'goal' : 'task';
  }

  bool get isGoal => type == 'goal';
  bool get isTask => type != 'goal';

  // ─── Due-time & Grace-period Helpers ──────────────────────────────────────

  /// 2-hour grace period after due time. After this, the task/goal is permanently missed.
  static const Duration gracePeriod = Duration(hours: 2);

  /// The absolute deadline = dueDate + 2-hour grace.
  DateTime? get absoluteDeadline => dueDate?.add(gracePeriod);

  /// True only if NOW is AFTER dueDate + 2 hours AND the item is not completed.
  /// Items without a dueDate are never considered missed.
  bool get isMissed {
    if (completed) return false;
    if (dueDate == null) return false;
    return DateTime.now().isAfter(dueDate!.add(gracePeriod));
  }

  /// True when NOW is between dueDate and dueDate + 2 hours (grace window).
  bool get isInGracePeriod {
    if (completed) return false;
    if (dueDate == null) return false;
    final now = DateTime.now();
    return now.isAfter(dueDate!) && now.isBefore(dueDate!.add(gracePeriod));
  }

  /// True when the item can still be marked complete (before or within grace period).
  bool get canComplete {
    if (completed) return true; // already done — always allow un-check
    return !isMissed; // still within grace window or no due date
  }

  // ─────────────────────────────────────────────────────────────────────────

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
    DateTime? completedAt,
    String? type,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
    // `reminderDateTime: null` means "keep"; pass this to remove the reminder.
    bool clearReminder = false,
  }) {
    // Completing stamps the completion time; un-completing clears it.
    final nextCompleted = completed ?? this.completed;
    final DateTime? nextCompletedAt;
    if (!nextCompleted) {
      nextCompletedAt = null;
    } else if (completedAt != null) {
      nextCompletedAt = completedAt;
    } else if (this.completed) {
      nextCompletedAt = this.completedAt;
    } else {
      nextCompletedAt = DateTime.now();
    }
    return Todo(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      dueDate: dueDate ?? this.dueDate,
      reminderDateTime:
          clearReminder ? null : (reminderDateTime ?? this.reminderDateTime),
      priority: priority ?? this.priority,
      timeSpentSeconds: timeSpentSeconds ?? this.timeSpentSeconds,
      targetMinutes: targetMinutes ?? this.targetMinutes,
      completed: nextCompleted,
      completedAt: nextCompletedAt,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
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
        'completedAt': completedAt?.toIso8601String(),
        'type': type,
        'classification_locked': 1,
        'createdAt': createdAt?.toIso8601String(),
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
        'completed_at': completedAt?.toIso8601String(),
        'type': type,
        'classification_locked': 1,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'is_synced': isSynced ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
      };

  factory Todo.fromMap(Map<String, dynamic> m) {
    final createdRaw = m['createdAt']?.toString() ??
        m['created_at']?.toString() ??
        m['updatedAt']?.toString() ??
        m['updated_at']?.toString();
    final parsedCreated = (createdRaw != null && createdRaw.isNotEmpty)
        ? DateTime.tryParse(createdRaw)
        : null;
    final dueRaw = (m['dueDate'] ?? m['due_date'])?.toString();
    final parsedDue = (dueRaw != null && dueRaw.isNotEmpty)
        ? DateTime.tryParse(dueRaw)
        : null;

    final existingType = m['type']?.toString();
    String parsedType;
    final classificationLocked = m['classification_locked'];
    if (classificationLocked == 1 || classificationLocked == true) {
      parsedType = existingType == 'goal' ? 'goal' : 'task';
    } else if (existingType == 'goal') {
      parsedType = 'goal';
    } else if (parsedDue != null &&
        parsedCreated != null &&
        parsedDue.difference(parsedCreated).inDays > 7) {
      parsedType = 'goal';
    } else {
      parsedType = existingType ?? 'task';
    }

    return Todo(
      id: m['id'] as String?,
      uid: (m['uid'] ?? '') as String,
      title: (m['title'] ?? '') as String,
      description: (m['description'] ?? '') as String,
      category: (m['category'] ?? 'General') as String,
      dueDate: parsedDue,
      reminderDateTime:
          (m['reminderDateTime'] ?? m['reminder_date_time']) != null
              ? DateTime.tryParse(
                  (m['reminderDateTime'] ?? m['reminder_date_time']).toString())
              : null,
      priority: (m['priority'] is num)
          ? (m['priority'] as num).toInt()
          : int.tryParse('${m['priority']}') ?? 4,
      timeSpentSeconds: (m['timeSpentSeconds'] is num)
          ? (m['timeSpentSeconds'] as num).toInt()
          : (m['time_spent_seconds'] is num)
              ? (m['time_spent_seconds'] as num).toInt()
              : int.tryParse(
                      '${m['timeSpentSeconds'] ?? m['time_spent_seconds']}') ??
                  0,
      targetMinutes: (m['targetMinutes'] is num)
          ? (m['targetMinutes'] as num).toInt()
          : (m['target_minutes'] is num)
              ? (m['target_minutes'] as num).toInt()
              : int.tryParse('${m['targetMinutes'] ?? m['target_minutes']}') ??
                  0,
      completed: (m['completed'] == true ||
          m['completed'] == 1 ||
          m['completed'] == 'true'),
      completedAt: (m['completedAt'] ?? m['completed_at']) != null
          ? DateTime.tryParse((m['completedAt'] ?? m['completed_at']).toString())
          : null,
      type: parsedType,
      createdAt: parsedCreated,
      updatedAt: (m['updatedAt'] ?? m['updated_at']) != null
          ? DateTime.tryParse((m['updatedAt'] ?? m['updated_at']).toString()) ??
              DateTime.now()
          : DateTime.now(),
      isSynced: (m['isSynced'] == true ||
          m['isSynced'] == 1 ||
          m['isSynced'] == 'true' ||
          m['is_synced'] == 1 ||
          m['is_synced'] == true),
      isDeleted: (m['isDeleted'] == true ||
          m['isDeleted'] == 1 ||
          m['isDeleted'] == 'true' ||
          m['is_deleted'] == 1 ||
          m['is_deleted'] == true),
    );
  }

  factory Todo.fromSqlite(Map<String, dynamic> m) {
    final createdRaw =
        m['created_at']?.toString() ?? m['updated_at']?.toString();
    final parsedCreated = (createdRaw != null && createdRaw.isNotEmpty)
        ? DateTime.tryParse(createdRaw)
        : null;
    final dueRaw = m['due_date']?.toString();
    final parsedDue = (dueRaw != null && dueRaw.isNotEmpty)
        ? DateTime.tryParse(dueRaw)
        : null;

    final existingType = m['type']?.toString();
    String parsedType;
    final classificationLocked = m['classification_locked'];
    if (classificationLocked == 1 || classificationLocked == true) {
      parsedType = existingType == 'goal' ? 'goal' : 'task';
    } else if (existingType == 'goal') {
      parsedType = 'goal';
    } else if (parsedDue != null &&
        parsedCreated != null &&
        parsedDue.difference(parsedCreated).inDays > 7) {
      parsedType = 'goal';
    } else {
      parsedType = existingType ?? 'task';
    }

    return Todo(
      id: m['id'] as String?,
      uid: (m['uid'] ?? '') as String,
      title: (m['title'] ?? '') as String,
      description: (m['description'] ?? '') as String,
      category: (m['category'] ?? 'General') as String,
      dueDate: parsedDue,
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
      completedAt: m['completed_at'] != null
          ? DateTime.tryParse(m['completed_at'].toString())
          : null,
      type: parsedType,
      createdAt: parsedCreated,
      updatedAt: m['updated_at'] != null
          ? DateTime.tryParse(m['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isSynced: m['is_synced'] == 1,
      isDeleted: m['is_deleted'] == 1,
    );
  }
}
