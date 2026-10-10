import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../utils/month_weeks.dart';

enum HabitFrequency { daily, weekly }

class Habit {
  String id;
  String uid;
  String title;
  HabitFrequency frequency;
  Map<String, bool> history; // date -> done
  int streak;
  /// When the habit was added. Null for habits saved before this existed;
  /// days before it don't count as missed.
  DateTime? createdAt;
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
    this.createdAt,
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
    DateTime? createdAt,
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  static int calculateStreak(Map<String, bool> history, [DateTime? referenceDate]) {
    final ref = referenceDate ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);

    String toDateKey(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final todayKey = toDateKey(today);
    final yesterdayKey = toDateKey(DateTime(today.year, today.month, today.day - 1));

    DateTime cursor;
    if (history[todayKey] == true) {
      cursor = today;
    } else if (history[yesterdayKey] == true) {
      cursor = DateTime(today.year, today.month, today.day - 1);
    } else {
      return 0;
    }

    int streakCount = 0;
    while (true) {
      final key = toDateKey(cursor);
      if (history[key] == true) {
        streakCount++;
        // Calendar arithmetic: subtracting 24 h can skip a day across a DST change.
        cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
      } else {
        break;
      }
    }
    return streakCount;
  }

  /// Consecutive month-weeks (1–7, 8–14, ...) with at least one completion,
  /// ending with this week (or last week, if this week isn't done yet).
  static int calculateWeeklyStreak(Map<String, bool> history, [DateTime? referenceDate]) {
    final ref = referenceDate ?? DateTime.now();
    bool doneIn(MonthWeek w) => w.days.any((d) => history[_key(d)] == true);

    var week = monthWeekOf(ref);
    if (!doneIn(week)) {
      week = previousMonthWeek(week);
      if (!doneIn(week)) return 0;
    }
    var count = 0;
    while (doneIn(week)) {
      count++;
      week = previousMonthWeek(week);
    }
    return count;
  }

  /// Streak in this habit's own unit: days for daily habits, weeks for weekly ones.
  static int streakFor(HabitFrequency frequency, Map<String, bool> history, [DateTime? referenceDate]) =>
      frequency == HabitFrequency.weekly
          ? calculateWeeklyStreak(history, referenceDate)
          : calculateStreak(history, referenceDate);

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool get isWeekly => frequency == HabitFrequency.weekly;

  /// 'day' or 'week', the unit [streak] counts in.
  String get streakUnit => isWeekly ? 'week' : 'day';

  /// Done for the period containing [date]: that day for a daily habit, any
  /// day of that month-week for a weekly one.
  bool isDoneInPeriodOf(DateTime date) {
    if (!isWeekly) return history[_key(date)] == true;
    return monthWeekOf(date).days.any((d) => history[_key(d)] == true);
  }

  /// Done for the current period (today, or this week for a weekly habit).
  bool get isDoneThisPeriod => isDoneInPeriodOf(DateTime.now());

  bool get isCompletedToday {
    final today = DateTime.now().toIso8601String().split('T')[0];
    return history[today] == true;
  }

  bool isCompletedOn(DateTime date) {
    final d = date.toIso8601String().split('T')[0];
    return history[d] == true;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'uid': uid,
        'title': title,
        'frequency': frequency.name,
        'history': history,
        'streak': streak,
        'createdAt': createdAt?.toIso8601String(),
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
        'created_at': createdAt?.toIso8601String(),
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
      createdAt: DateTime.tryParse('${m['createdAt'] ?? ''}'),
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
      createdAt: DateTime.tryParse('${m['created_at'] ?? ''}'),
      updatedAt: m['updated_at'] != null
          ? DateTime.tryParse(m['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isSynced: m['is_synced'] == 1,
      isDeleted: m['is_deleted'] == 1,
    );
  }
}

