import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/user_profile.dart';
import '../models/todo.dart';
import '../models/task_session.dart';
import '../models/habit.dart';
import '../models/journal_entry.dart';
import '../models/finance_transaction.dart';
import '../models/calendar_event.dart';
import '../models/timetable_slot.dart';
import '../models/chat_message.dart';
import '../models/reminder.dart';
import '../models/alarm_model.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  static Database? _database;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('grow_app_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onOpen: (db) async {
        // Ensure reminders table exists
        await db.execute('''
          CREATE TABLE IF NOT EXISTS reminders (
            id TEXT PRIMARY KEY,
            uid TEXT,
            title TEXT,
            description TEXT,
            date_time TEXT,
            category TEXT,
            is_completed INTEGER DEFAULT 0,
            updated_at TEXT,
            is_synced INTEGER DEFAULT 0,
            is_deleted INTEGER DEFAULT 0
          )
        ''');
        // Ensure alarms table exists
        await db.execute('''
          CREATE TABLE IF NOT EXISTS alarms (
            id TEXT PRIMARY KEY,
            uid TEXT,
            hour INTEGER,
            minute INTEGER,
            label TEXT,
            days_of_week TEXT,
            is_enabled INTEGER DEFAULT 1,
            created_at TEXT
          )
        ''');
        // Ensure task_sessions table exists
        await db.execute('''
          CREATE TABLE IF NOT EXISTS task_sessions (
            id TEXT PRIMARY KEY,
            uid TEXT,
            task_id TEXT,
            task_title TEXT,
            category TEXT,
            duration_seconds INTEGER DEFAULT 0,
            date TEXT,
            timestamp TEXT
          )
        ''');
        // Ensure reminder_date_time, time_spent_seconds, category, target_minutes exist on todos
        try {
          await db.execute('ALTER TABLE todos ADD COLUMN reminder_date_time TEXT');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE todos ADD COLUMN time_spent_seconds INTEGER DEFAULT 0');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE todos ADD COLUMN category TEXT DEFAULT "General"');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE todos ADD COLUMN target_minutes INTEGER DEFAULT 0');
        } catch (_) {}
        // Ensure phone_number, photo_path, focus_areas exist on user_profiles
        try {
          await db.execute('ALTER TABLE user_profiles ADD COLUMN phone_number TEXT');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE user_profiles ADD COLUMN photo_path TEXT');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE user_profiles ADD COLUMN focus_areas TEXT');
        } catch (_) {}
      },
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. User Profile Table
    await db.execute('''
      CREATE TABLE user_profiles (
        uid TEXT PRIMARY KEY,
        email TEXT,
        name TEXT,
        bio TEXT,
        phone_number TEXT,
        photo_path TEXT,
        focus_areas TEXT,
        updated_at TEXT,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    // 2. Todos Table
    await db.execute('''
      CREATE TABLE todos (
        id TEXT PRIMARY KEY,
        uid TEXT,
        title TEXT,
        description TEXT,
        due_date TEXT,
        reminder_date_time TEXT,
        priority INTEGER,
        completed INTEGER DEFAULT 0,
        updated_at TEXT,
        is_synced INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    // 3. Habits Table
    await db.execute('''
      CREATE TABLE habits (
        id TEXT PRIMARY KEY,
        uid TEXT,
        title TEXT,
        frequency TEXT,
        history_json TEXT,
        streak INTEGER DEFAULT 0,
        updated_at TEXT,
        is_synced INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    // 4. Journal Entries Table
    await db.execute('''
      CREATE TABLE journal_entries (
        id TEXT PRIMARY KEY,
        uid TEXT,
        text TEXT,
        mood TEXT,
        tags_json TEXT,
        created_at TEXT,
        updated_at TEXT,
        is_synced INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    // 5. Finance Transactions Table
    await db.execute('''
      CREATE TABLE finance_transactions (
        id TEXT PRIMARY KEY,
        uid TEXT,
        title TEXT,
        amount REAL,
        category TEXT,
        date TEXT,
        note TEXT,
        updated_at TEXT,
        is_synced INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    // 6. Calendar Events Table
    await db.execute('''
      CREATE TABLE calendar_events (
        id TEXT PRIMARY KEY,
        uid TEXT,
        title TEXT,
        description TEXT,
        date_time TEXT,
        category TEXT,
        updated_at TEXT,
        is_synced INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    // 7. Timetable Slots Table
    await db.execute('''
      CREATE TABLE timetable_slots (
        id TEXT PRIMARY KEY,
        uid TEXT,
        day_of_week TEXT,
        start_time TEXT,
        end_time TEXT,
        title TEXT,
        description TEXT,
        category TEXT,
        color_hex INTEGER,
        has_reminder INTEGER DEFAULT 1,
        is_completed INTEGER DEFAULT 0,
        updated_at TEXT,
        is_synced INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    // 8. Chat Messages Table
    await db.execute('''
      CREATE TABLE chat_messages (
        id TEXT PRIMARY KEY,
        uid TEXT,
        sender TEXT,
        text TEXT,
        timestamp TEXT,
        action_type TEXT,
        action_data TEXT,
        is_applied INTEGER DEFAULT 0
      )
    ''');

    // 9. Reminders Table
    await db.execute('''
      CREATE TABLE reminders (
        id TEXT PRIMARY KEY,
        uid TEXT,
        title TEXT,
        description TEXT,
        date_time TEXT,
        category TEXT,
        is_completed INTEGER DEFAULT 0,
        updated_at TEXT,
        is_synced INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0
      )
    ''');
  }

  // ==================== USER PROFILE ====================
  Future<UserProfile?> getProfile(String uid) async {
    final db = await database;
    final res = await db.query('user_profiles', where: 'uid = ?', whereArgs: [uid]);
    if (res.isNotEmpty) {
      final map = res.first;
      return UserProfile(
        uid: map['uid'] as String,
        email: (map['email'] ?? '') as String,
        name: (map['name'] ?? '') as String,
        bio: (map['bio'] ?? '') as String,
        phoneNumber: (map['phone_number'] ?? '') as String,
        photoPath: map['photo_path'] as String?,
        updatedAt: DateTime.tryParse((map['updated_at'] ?? '').toString()) ?? DateTime.now(),
        isSynced: map['is_synced'] == 1,
      );
    }
    return null;
  }

  Future<void> saveProfile(UserProfile profile) async {
    final db = await database;
    await db.insert(
      'user_profiles',
      profile.toSqliteMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ==================== TODOS ====================
  Future<List<Todo>> getTodos(String uid) async {
    final db = await database;
    final res = await db.query(
      'todos',
      where: 'uid = ? AND is_deleted = 0',
      whereArgs: [uid],
      orderBy: 'priority ASC, due_date ASC',
    );
    return res.map((m) => Todo.fromSqlite(m)).toList();
  }

  Future<void> upsertTodo(Todo todo) async {
    final db = await database;
    await db.insert('todos', todo.toSqliteMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> softDeleteTodo(String id) async {
    final db = await database;
    await db.update(
      'todos',
      {'is_deleted': 1, 'is_synced': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== HABITS ====================
  Future<List<Habit>> getHabits(String uid) async {
    final db = await database;
    final res = await db.query(
      'habits',
      where: 'uid = ? AND is_deleted = 0',
      whereArgs: [uid],
      orderBy: 'updated_at DESC',
    );
    return res.map((m) => Habit.fromSqlite(m)).toList();
  }

  Future<void> upsertHabit(Habit habit) async {
    final db = await database;
    await db.insert('habits', habit.toSqliteMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> softDeleteHabit(String id) async {
    final db = await database;
    await db.update(
      'habits',
      {'is_deleted': 1, 'is_synced': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== JOURNALS ====================
  Future<List<JournalEntry>> getJournals(String uid) async {
    final db = await database;
    final res = await db.query(
      'journal_entries',
      where: 'uid = ? AND is_deleted = 0',
      whereArgs: [uid],
      orderBy: 'created_at DESC',
    );
    return res.map((m) => JournalEntry.fromSqlite(m)).toList();
  }

  Future<void> upsertJournal(JournalEntry entry) async {
    final db = await database;
    await db.insert('journal_entries', entry.toSqliteMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> softDeleteJournal(String id) async {
    final db = await database;
    await db.update(
      'journal_entries',
      {'is_deleted': 1, 'is_synced': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== TRANSACTIONS ====================
  Future<List<FinanceTransaction>> getTransactions(String uid) async {
    final db = await database;
    final res = await db.query(
      'finance_transactions',
      where: 'uid = ? AND is_deleted = 0',
      whereArgs: [uid],
      orderBy: 'date DESC',
    );
    return res.map((m) => FinanceTransaction.fromSqlite(m)).toList();
  }

  Future<void> upsertTransaction(FinanceTransaction tx) async {
    final db = await database;
    await db.insert('finance_transactions', tx.toSqliteMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> softDeleteTransaction(String id) async {
    final db = await database;
    await db.update(
      'finance_transactions',
      {'is_deleted': 1, 'is_synced': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== CALENDAR EVENTS ====================
  Future<List<CalendarEvent>> getCalendarEvents(String uid) async {
    final db = await database;
    final res = await db.query(
      'calendar_events',
      where: 'uid = ? AND is_deleted = 0',
      whereArgs: [uid],
      orderBy: 'date_time ASC',
    );
    return res.map((m) => CalendarEvent.fromSqlite(m)).toList();
  }

  Future<void> upsertCalendarEvent(CalendarEvent event) async {
    final db = await database;
    await db.insert('calendar_events', event.toSqliteMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> softDeleteCalendarEvent(String id) async {
    final db = await database;
    await db.update(
      'calendar_events',
      {'is_deleted': 1, 'is_synced': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== TIMETABLE SLOTS ====================
  Future<List<TimetableSlot>> getTimetableSlots(String uid, {String? dayOfWeek}) async {
    final db = await database;
    String where = 'uid = ? AND is_deleted = 0';
    List<dynamic> whereArgs = [uid];
    if (dayOfWeek != null && dayOfWeek != 'All') {
      where += ' AND (day_of_week = ? OR day_of_week = "Daily")';
      whereArgs.add(dayOfWeek);
    }
    final res = await db.query(
      'timetable_slots',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'start_time ASC',
    );
    return res.map((m) => TimetableSlot.fromSqlite(m)).toList();
  }

  Future<void> upsertTimetableSlot(TimetableSlot slot) async {
    final db = await database;
    await db.insert('timetable_slots', slot.toSqliteMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> batchInsertTimetableSlots(List<TimetableSlot> slots) async {
    final db = await database;
    final batch = db.batch();
    for (final slot in slots) {
      batch.insert('timetable_slots', slot.toSqliteMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> softDeleteTimetableSlot(String id) async {
    final db = await database;
    await db.update(
      'timetable_slots',
      {'is_deleted': 1, 'is_synced': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== CHAT MESSAGES ====================
  Future<List<ChatMessage>> getChatMessages(String uid) async {
    final db = await database;
    final res = await db.query(
      'chat_messages',
      where: 'uid = ?',
      whereArgs: [uid],
      orderBy: 'timestamp ASC',
    );
    return res.map((m) => ChatMessage.fromSqlite(m)).toList();
  }

  Future<void> insertChatMessage(ChatMessage msg) async {
    final db = await database;
    await db.insert('chat_messages', msg.toSqliteMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> markChatActionApplied(String id) async {
    final db = await database;
    await db.update('chat_messages', {'is_applied': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearChatMessages(String uid) async {
    final db = await database;
    await db.delete('chat_messages', where: 'uid = ?', whereArgs: [uid]);
  }

  // ==================== SYNC HELPERS ====================
  Future<Map<String, List<Map<String, dynamic>>>> getUnsyncedRecords(String uid) async {
    final db = await database;
    final todos = await db.query('todos', where: 'uid = ? AND is_synced = 0', whereArgs: [uid]);
    final habits = await db.query('habits', where: 'uid = ? AND is_synced = 0', whereArgs: [uid]);
    final journals = await db.query('journal_entries', where: 'uid = ? AND is_synced = 0', whereArgs: [uid]);
    final transactions = await db.query('finance_transactions', where: 'uid = ? AND is_synced = 0', whereArgs: [uid]);
    final events = await db.query('calendar_events', where: 'uid = ? AND is_synced = 0', whereArgs: [uid]);
    final slots = await db.query('timetable_slots', where: 'uid = ? AND is_synced = 0', whereArgs: [uid]);
    final reminders = await db.query('reminders', where: 'uid = ? AND is_synced = 0', whereArgs: [uid]);
    final profile = await db.query('user_profiles', where: 'uid = ? AND is_synced = 0', whereArgs: [uid]);

    return {
      'todos': todos,
      'habits': habits,
      'journals': journals,
      'transactions': transactions,
      'calendar_events': events,
      'timetable_slots': slots,
      'reminders': reminders,
      'profile': profile,
    };
  }

  Future<void> markRecordSynced(String table, String id) async {
    final db = await database;
    await db.update(table, {'is_synced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markProfileSynced(String uid) async {
    final db = await database;
    await db.update('user_profiles', {'is_synced': 1}, where: 'uid = ?', whereArgs: [uid]);
  }

  Future<int> getTotalLocalRecordsCount(String uid) async {
    final db = await database;
    int count = 0;
    for (final table in ['todos', 'habits', 'journal_entries', 'finance_transactions', 'calendar_events', 'timetable_slots', 'reminders']) {
      final res = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table WHERE uid = ? AND is_deleted = 0', [uid]));
      count += (res ?? 0);
    }
    return count;
  }

  // ==================== REMINDERS ====================
  Future<void> insertReminder(Reminder r) async {
    final db = await database;
    await db.insert('reminders', r.toSqliteMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateReminder(Reminder r) async {
    final db = await database;
    await db.update('reminders', r.toSqliteMap(), where: 'id = ?', whereArgs: [r.id]);
  }

  Future<void> deleteReminder(String id) async {
    final db = await database;
    await db.update('reminders', {'is_deleted': 1, 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Reminder>> getReminders(String uid) async {
    final db = await database;
    final res = await db.query(
      'reminders',
      where: 'uid = ? AND is_deleted = 0',
      whereArgs: [uid],
      orderBy: 'date_time ASC',
    );
    return res.map((m) => Reminder.fromSqlite(m)).toList();
  }

  Future<List<Reminder>> getUnsyncedReminders(String uid) async {
    final db = await database;
    final res = await db.query(
      'reminders',
      where: 'uid = ? AND is_synced = 0',
      whereArgs: [uid],
    );
    return res.map((m) => Reminder.fromSqlite(m)).toList();
  }

  // ==================== ALARMS ====================
  Future<void> insertAlarm(AlarmModel alarm) async {
    final db = await database;
    await db.insert('alarms', alarm.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateAlarm(AlarmModel alarm) async {
    final db = await database;
    await db.update('alarms', alarm.toMap(), where: 'id = ?', whereArgs: [alarm.id]);
  }

  Future<void> deleteAlarm(String id) async {
    final db = await database;
    await db.delete('alarms', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<AlarmModel>> getAlarms(String uid) async {
    final db = await database;
    final res = await db.query(
      'alarms',
      where: 'uid = ?',
      whereArgs: [uid],
      orderBy: 'hour ASC, minute ASC',
    );
    return res.map((m) => AlarmModel.fromMap(m)).toList();
  }

  // ==================== TASK TIME SESSIONS & TRACKER ====================
  Future<void> insertTaskSession(TaskSession session) async {
    final db = await database;
    await db.insert('task_sessions', session.toSqliteMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<TaskSession>> getTaskSessionsForDay(String uid, String dateStr) async {
    final db = await database;
    final res = await db.query(
      'task_sessions',
      where: 'uid = ? AND date = ?',
      whereArgs: [uid, dateStr],
      orderBy: 'timestamp DESC',
    );
    return res.map((m) => TaskSession.fromMap(m)).toList();
  }

  Future<List<TaskSession>> getTaskSessionsForRange(String uid, String startDate, String endDate) async {
    final db = await database;
    final res = await db.query(
      'task_sessions',
      where: 'uid = ? AND date >= ? AND date <= ?',
      whereArgs: [uid, startDate, endDate],
      orderBy: 'date ASC, timestamp ASC',
    );
    return res.map((m) => TaskSession.fromMap(m)).toList();
  }

  Future<List<TaskSession>> getAllTaskSessions(String uid) async {
    final db = await database;
    final res = await db.query(
      'task_sessions',
      where: 'uid = ?',
      whereArgs: [uid],
      orderBy: 'timestamp DESC',
    );
    return res.map((m) => TaskSession.fromMap(m)).toList();
  }

  // ==================== COMPLETE LOCAL STORAGE PURGE ====================
  Future<void> clearLocalUserData(String uid) async {
    final db = await database;
    final tables = [
      'todos',
      'habits',
      'journal_entries',
      'finance_transactions',
      'calendar_events',
      'timetable_slots',
      'chat_messages',
      'reminders',
      'alarms',
      'task_sessions',
      'user_profiles',
    ];

    for (final table in tables) {
      try {
        await db.delete(table, where: 'uid = ?', whereArgs: [uid]);
      } catch (e) {
        debugPrint('clearLocalUserData error for table $table: $e');
      }
    }
  }
}
