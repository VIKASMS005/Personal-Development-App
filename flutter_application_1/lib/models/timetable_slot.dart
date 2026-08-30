import 'package:uuid/uuid.dart';

class TimetableSlot {
  String id;
  String uid;
  String dayOfWeek; // 'Daily', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  String startTime; // e.g. '08:00' or '08:00 AM'
  String endTime; // e.g. '09:00' or '09:00 AM'
  String title;
  String description;
  String category; // 'Study', 'Work', 'Health', 'Workout', 'Leisure', 'Sleep', 'Personal', 'Other'
  int colorHex;
  bool hasReminder;
  bool isCompleted;
  DateTime updatedAt;
  bool isSynced;
  bool isDeleted;

  TimetableSlot({
    String? id,
    this.uid = '',
    this.dayOfWeek = 'Daily',
    required this.startTime,
    required this.endTime,
    required this.title,
    this.description = '',
    this.category = 'Study',
    this.colorHex = 0xFF059669,
    this.hasReminder = true,
    this.isCompleted = false,
    DateTime? updatedAt,
    this.isSynced = false,
    this.isDeleted = false,
  })  : id = id ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now();

  TimetableSlot copyWith({
    String? id,
    String? uid,
    String? dayOfWeek,
    String? startTime,
    String? endTime,
    String? title,
    String? description,
    String? category,
    int? colorHex,
    bool? hasReminder,
    bool? isCompleted,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return TimetableSlot(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      colorHex: colorHex ?? this.colorHex,
      hasReminder: hasReminder ?? this.hasReminder,
      isCompleted: isCompleted ?? this.isCompleted,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'uid': uid,
        'dayOfWeek': dayOfWeek,
        'startTime': startTime,
        'endTime': endTime,
        'title': title,
        'description': description,
        'category': category,
        'colorHex': colorHex,
        'hasReminder': hasReminder,
        'isCompleted': isCompleted,
        'updatedAt': updatedAt.toIso8601String(),
        'isDeleted': isDeleted,
      };

  Map<String, dynamic> toSqliteMap() => {
        'id': id,
        'uid': uid,
        'day_of_week': dayOfWeek,
        'start_time': startTime,
        'end_time': endTime,
        'title': title,
        'description': description,
        'category': category,
        'color_hex': colorHex,
        'has_reminder': hasReminder ? 1 : 0,
        'is_completed': isCompleted ? 1 : 0,
        'updated_at': updatedAt.toIso8601String(),
        'is_synced': isSynced ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
      };

  factory TimetableSlot.fromMap(Map<String, dynamic> m) => TimetableSlot(
        id: m['id'] as String?,
        uid: (m['uid'] ?? '') as String,
        dayOfWeek: (m['dayOfWeek'] ?? 'Daily') as String,
        startTime: (m['startTime'] ?? '08:00') as String,
        endTime: (m['endTime'] ?? '09:00') as String,
        title: (m['title'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        category: (m['category'] ?? 'Study') as String,
        colorHex: (m['colorHex'] is num)
            ? (m['colorHex'] as num).toInt()
            : int.tryParse('${m['colorHex']}') ?? 0xFF059669,
        hasReminder: (m['hasReminder'] == true || m['hasReminder'] == 1 || m['hasReminder'] == 'true'),
        isCompleted: (m['isCompleted'] == true || m['isCompleted'] == 1 || m['isCompleted'] == 'true'),
        updatedAt: m['updatedAt'] != null
            ? DateTime.tryParse(m['updatedAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        isSynced: (m['isSynced'] == true || m['isSynced'] == 1 || m['isSynced'] == 'true'),
        isDeleted: (m['isDeleted'] == true || m['isDeleted'] == 1 || m['isDeleted'] == 'true'),
      );

  factory TimetableSlot.fromSqlite(Map<String, dynamic> m) => TimetableSlot(
        id: m['id'] as String?,
        uid: (m['uid'] ?? '') as String,
        dayOfWeek: (m['day_of_week'] ?? 'Daily') as String,
        startTime: (m['start_time'] ?? '08:00') as String,
        endTime: (m['end_time'] ?? '09:00') as String,
        title: (m['title'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        category: (m['category'] ?? 'Study') as String,
        colorHex: (m['color_hex'] is num)
            ? (m['color_hex'] as num).toInt()
            : int.tryParse('${m['color_hex']}') ?? 0xFF059669,
        hasReminder: (m['has_reminder'] == 1 || m['has_reminder'] == true),
        isCompleted: (m['is_completed'] == 1 || m['is_completed'] == true),
        updatedAt: m['updated_at'] != null
            ? DateTime.tryParse(m['updated_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        isSynced: m['is_synced'] == 1,
        isDeleted: m['is_deleted'] == 1,
      );
}
