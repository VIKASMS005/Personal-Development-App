import 'dart:convert';
import 'package:uuid/uuid.dart';

enum HabitFrequency { daily, weekly }

class Habit {
  String id;
  String uid;
  String title;
  HabitFrequency frequency;
  Map<String, bool> history; // date -> done
  int streak;
  DateTime updatedAt;
  bool isSynced;
  bool isDeleted;

  Habit({
    String? id,
    this.uid = '',
    required this.title,
    this.frequency = HabitFrequency.daily,
    Map<String, bool>? history,
    this.streak = 0,
    DateTime? updatedAt,
    this.isSynced = false,
    this.isDeleted = false,
  })  : id = id ?? const Uuid().v4(),
        history = history ?? {},
        updatedAt = updatedAt ?? DateTime.now();

  Habit copyWith({
    String? id,
    String? uid,
    String? title,
    HabitFrequency? frequency,
    Map<String, bool>? history,
    int? streak,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return Habit(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      title: title ?? this.title,
      frequency: frequency ?? this.frequency,
      history: history ?? Map.from(this.history),
      streak: streak ?? this.streak,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'uid': uid,
        'title': title,
        'frequency': frequency.name,
        'history': history,
        'streak': streak,
        'updatedAt': updatedAt.toIso8601String(),
        'isDeleted': isDeleted,
      };

  Map<String, dynamic> toSqliteMap() => {
        'id': id,
        'uid': uid,
        'title': title,
        'frequency': frequency.name,
        'history_json': jsonEncode(history),
        'streak': streak,
        'updated_at': updatedAt.toIso8601String(),
        'is_synced': isSynced ? 1 : 0,
        'is_deleted': isDeleted ? 1 : 0,
      };

  factory Habit.fromMap(Map<String, dynamic> m) {
    Map<String, bool> parsedHistory = {};
    if (m['history'] != null) {
      if (m['history'] is Map) {
        m['history'].forEach((k, v) {
          parsedHistory[k.toString()] = (v == true || v == 1 || v == 'true');
        });
      } else if (m['history'] is String) {
        try {
          final decoded = jsonDecode(m['history']);
          if (decoded is Map) {
            decoded.forEach((k, v) {
              parsedHistory[k.toString()] = (v == true || v == 1 || v == 'true');
            });
          }
        } catch (_) {}
      }
    }
    return Habit(
      id: m['id'] as String?,
      uid: (m['uid'] ?? '') as String,
      title: (m['title'] ?? '') as String,
      frequency: (m['frequency'] ?? 'daily').toString().toLowerCase() == 'weekly'
          ? HabitFrequency.weekly
          : HabitFrequency.daily,
      history: parsedHistory,
      streak: (m['streak'] is num)
          ? (m['streak'] as num).toInt()
          : int.tryParse('${m['streak']}') ?? 0,
      updatedAt: m['updatedAt'] != null
          ? DateTime.tryParse(m['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isSynced: (m['isSynced'] == true || m['isSynced'] == 1 || m['isSynced'] == 'true'),
      isDeleted: (m['isDeleted'] == true || m['isDeleted'] == 1 || m['isDeleted'] == 'true'),
    );
  }

  factory Habit.fromSqlite(Map<String, dynamic> m) {
    Map<String, bool> parsedHistory = {};
    if (m['history_json'] != null && m['history_json'] is String) {
      try {
        final decoded = jsonDecode(m['history_json']);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            parsedHistory[k.toString()] = (v == true || v == 1 || v == 'true');
          });
        }
      } catch (_) {}
    }
    return Habit(
      id: m['id'] as String?,
      uid: (m['uid'] ?? '') as String,
      title: (m['title'] ?? '') as String,
      frequency: (m['frequency'] ?? 'daily').toString().toLowerCase() == 'weekly'
          ? HabitFrequency.weekly
          : HabitFrequency.daily,
      history: parsedHistory,
      streak: (m['streak'] is num)
          ? (m['streak'] as num).toInt()
          : int.tryParse('${m['streak']}') ?? 0,
      updatedAt: m['updated_at'] != null
          ? DateTime.tryParse(m['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isSynced: m['is_synced'] == 1,
      isDeleted: m['is_deleted'] == 1,
    );
  }
}

