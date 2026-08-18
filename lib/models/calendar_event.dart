import 'package:uuid/uuid.dart';

class CalendarEvent {
  String id;
  String uid;
  String title;
  String description;
  DateTime dateTime;
  String category;
  DateTime updatedAt;
  bool isSynced;
  bool isDeleted;

  CalendarEvent({
    String? id,
    this.uid = '',
    required this.title,
    this.description = '',
    required this.dateTime,
    this.category = 'General',
    DateTime? updatedAt,
    this.isSynced = false,
    this.isDeleted = false,
  })  : id = id ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now();

  CalendarEvent copyWith({
    String? id,
    String? uid,
    String? title,
    String? description,
    DateTime? dateTime,
    String? category,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      title: title ?? this.title,
      description: description ?? this.description,
      dateTime: dateTime ?? this.dateTime,
      category: category ?? this.category,
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
        'updated_at': updatedAt.toIso8601String(),
        'is_synced': isSynced ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
      };

  factory CalendarEvent.fromMap(Map<String, dynamic> m) => CalendarEvent(
        id: m['id'] as String?,
        uid: (m['uid'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        dateTime: m['dateTime'] != null
            ? DateTime.tryParse(m['dateTime'].toString()) ?? DateTime.now()
            : DateTime.now(),
        category: (m['category'] ?? 'General') as String,
        updatedAt: m['updatedAt'] != null
            ? DateTime.tryParse(m['updatedAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        isSynced: (m['isSynced'] == true || m['isSynced'] == 1 || m['isSynced'] == 'true'),
        isDeleted: (m['isDeleted'] == true || m['isDeleted'] == 1 || m['isDeleted'] == 'true'),
      );

  factory CalendarEvent.fromSqlite(Map<String, dynamic> m) => CalendarEvent(
        id: m['id'] as String?,
        uid: (m['uid'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        dateTime: m['date_time'] != null
            ? DateTime.tryParse(m['date_time'].toString()) ?? DateTime.now()
            : DateTime.now(),
        category: (m['category'] ?? 'General') as String,
        updatedAt: m['updated_at'] != null
            ? DateTime.tryParse(m['updated_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        isSynced: m['is_synced'] == 1,
        isDeleted: m['is_deleted'] == 1,
      );
}
