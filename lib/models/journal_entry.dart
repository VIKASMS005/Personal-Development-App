import 'dart:convert';
import 'package:uuid/uuid.dart';

class JournalEntry {
  String id;
  String uid;
  String text;
  String mood; // 'happy', 'calm', 'neutral', 'sad', 'stressed', 'energetic'
  List<String> tags;
  DateTime createdAt;
  DateTime updatedAt;
  bool isSynced;
  bool isDeleted;

  JournalEntry({
    String? id,
    this.uid = '',
    required this.text,
    this.mood = 'calm',
    this.tags = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isSynced = false,
    this.isDeleted = false,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  JournalEntry copyWith({
    String? id,
    String? uid,
    String? text,
    String? mood,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
  }) {

    return JournalEntry(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      text: text ?? this.text,
      mood: mood ?? this.mood,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'uid': uid,
        'text': text,
        'mood': mood,
        'tags': tags,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isDeleted': isDeleted,
      };

  Map<String, dynamic> toSqliteMap() => {
        'id': id,
        'uid': uid,
        'text': text,
        'mood': mood,
        'tags_json': jsonEncode(tags),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'is_synced': isSynced ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
      };

  factory JournalEntry.fromMap(Map<String, dynamic> m) {
    List<String> parsedTags = [];
    if (m['tags'] != null) {
      if (m['tags'] is List) {
        parsedTags = (m['tags'] as List).map((e) => e.toString()).toList();
      } else if (m['tags'] is String) {
        try {
          final decoded = jsonDecode(m['tags']);
          if (decoded is List) {
            parsedTags = decoded.map((e) => e.toString()).toList();
          }
        } catch (_) {}
      }
    }
    return JournalEntry(
      id: m['id'] as String?,
      uid: (m['uid'] ?? '') as String,
      text: (m['text'] ?? '') as String,
      mood: (m['mood'] ?? 'calm') as String,
      tags: parsedTags,
      createdAt: m['createdAt'] != null
          ? DateTime.tryParse(m['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: m['updatedAt'] != null
          ? DateTime.tryParse(m['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isSynced: (m['isSynced'] == true || m['isSynced'] == 1 || m['isSynced'] == 'true'),
      isDeleted: (m['isDeleted'] == true || m['isDeleted'] == 1 || m['isDeleted'] == 'true'),
    );
  }

  factory JournalEntry.fromSqlite(Map<String, dynamic> m) {
    List<String> parsedTags = [];
    if (m['tags_json'] != null && m['tags_json'] is String) {
      try {
        final decoded = jsonDecode(m['tags_json']);
        if (decoded is List) {
          parsedTags = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    return JournalEntry(
      id: m['id'] as String?,
      uid: (m['uid'] ?? '') as String,
      text: (m['text'] ?? '') as String,
      mood: (m['mood'] ?? 'calm') as String,
      tags: parsedTags,
      createdAt: m['created_at'] != null
          ? DateTime.tryParse(m['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: m['updated_at'] != null
          ? DateTime.tryParse(m['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isSynced: m['is_synced'] == 1,
      isDeleted: m['is_deleted'] == 1,
    );
  }
}
