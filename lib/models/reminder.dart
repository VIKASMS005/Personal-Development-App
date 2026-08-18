import 'package:uuid/uuid.dart';

class Reminder {
  String id;
  String uid;
  String title;
  String description;
  DateTime dateTime;
  String category; // 'Personal', 'Work', 'Study', 'Health', 'Urgent'
  bool isCompleted;
  DateTime updatedAt;
  bool isSynced;
  bool isDeleted;

  Reminder({
    String? id,
    this.uid = '',
    required this.title,
    this.description = '',
    required this.dateTime,
    this.category = 'Personal',
    this.isCompleted = false,
    DateTime? updatedAt,
    this.isSynced = false,
    this.isDeleted = false,
  })  : id = id ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now();

  Reminder copyWith({
    String? id,
    String? uid,
    String? title,
    String? description,
    DateTime? dateTime,
    String? category,
    bool? isCompleted,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return Reminder(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      title: title ?? this.title,
      description: description ?? this.description,
      dateTime: dateTime ?? this.dateTime,
      category: category ?? this.category,
      isCompleted: isCompleted ?? this.isCompleted,
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
        'dateTime': dateTime.toIso8601String(),
        'category': category,
        'isCompleted': isCompleted,
        'updatedAt': updatedAt.toIso8601String(),
        'isDeleted': isDeleted,
      };

  Map<String, dynamic> toSqliteMap() => {
        'id': id,
        'uid': uid,
        'title': title,
        'description': description,
        'date_time': dateTime.toIso8601String(),
        'category': category,
        'is_completed': isCompleted ? 1 : 0,
        'updated_at': updatedAt.toIso8601String(),
        'is_synced': isSynced ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
      };

  factory Reminder.fromMap(Map<String, dynamic> m) => Reminder(
        id: m['id'] as String?,
        uid: (m['uid'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        dateTime: m['dateTime'] != null
            ? DateTime.tryParse(m['dateTime'].toString()) ?? DateTime.now()
            : DateTime.now(),
        category: (m['category'] ?? 'Personal') as String,
        isCompleted: (m['isCompleted'] == true || m['isCompleted'] == 1 || m['isCompleted'] == 'true'),
        updatedAt: m['updatedAt'] != null
            ? DateTime.tryParse(m['updatedAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        isSynced: (m['isSynced'] == true || m['isSynced'] == 1 || m['isSynced'] == 'true'),
        isDeleted: (m['isDeleted'] == true || m['isDeleted'] == 1 || m['isDeleted'] == 'true'),
      );

  factory Reminder.fromSqlite(Map<String, dynamic> m) => Reminder(
        id: m['id'] as String?,
        uid: (m['uid'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        dateTime: m['date_time'] != null
            ? DateTime.tryParse(m['date_time'].toString()) ?? DateTime.now()
            : DateTime.now(),
        category: (m['category'] ?? 'Personal') as String,
        isCompleted: (m['is_completed'] == 1 || m['is_completed'] == true),
        updatedAt: m['updated_at'] != null
            ? DateTime.tryParse(m['updated_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        isSynced: m['is_synced'] == 1,
        isDeleted: m['is_deleted'] == 1,
      );
}
