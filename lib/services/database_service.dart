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

import '../models/step_record.dart';
import '../models/screen_time_record.dart';

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
        // Ensure reminder_date_time, time_spent_seconds, category, target_minutes, type, created_at exist on todos
        try {
          await db
              .execute('ALTER TABLE todos ADD COLUMN reminder_date_time TEXT');
        } catch (_) {}
        try {
          await db.execute(
              'ALTER TABLE todos ADD COLUMN time_spent_seconds INTEGER DEFAULT 0');
        } catch (_) {}
        try {
          await db.execute(
              'ALTER TABLE todos ADD COLUMN category TEXT DEFAULT "General"');
        } catch (_) {}
        try {
          await db.execute(
              'ALTER TABLE todos ADD COLUMN target_minutes INTEGER DEFAULT 0');
        } catch (_) {}
        try {
          await db
              .execute('ALTER TABLE todos ADD COLUMN type TEXT DEFAULT "task"');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE todos ADD COLUMN created_at TEXT');
        } catch (_) {}
        try {
          await db.execute(
              'ALTER TABLE todos ADD COLUMN classification_locked INTEGER DEFAULT 0');
        } catch (_) {}
        // Backfill created_at from updated_at for pre-existing records where created_at is NULL
        try {
          await db.execute(
              'UPDATE todos SET created_at = updated_at WHERE created_at IS NULL AND updated_at IS NOT NULL');
        } catch (_) {}
        // ── CRITICAL: recover any records saved with uid='' (bug from form saves that dropped uid) ──
        // These records are invisible on reload because queries filter WHERE uid='local_user'.
        // Re-assign them to 'local_user' so they appear correctly after app restart.
        try {
          await db.execute(
              "UPDATE todos SET uid = 'local_user' WHERE uid = '' OR uid IS NULL");
        } catch (_) {}
        try {
          await db.execute(
              "UPDATE journal_entries SET uid = 'local_user' WHERE uid = '' OR uid IS NULL");
        } catch (_) {}
        try {
          await db.execute(
              "UPDATE habits SET uid = 'local_user' WHERE uid = '' OR uid IS NULL");
        } catch (_) {}
        try {
          await db.execute(
              "UPDATE finance_transactions SET uid = 'local_user' WHERE uid = '' OR uid IS NULL");
        } catch (_) {}
        try {
          await db.execute(
              "UPDATE calendar_events SET uid = 'local_user' WHERE uid = '' OR uid IS NULL");
        } catch (_) {}
        try {
          await db.execute(
              "UPDATE timetable_slots SET uid = 'local_user' WHERE uid = '' OR uid IS NULL");
        } catch (_) {}
        // Ensure phone_number, photo_path, focus_areas exist on user_profiles
        try {
          await db.execute(
              'ALTER TABLE user_profiles ADD COLUMN phone_number TEXT');
        } catch (_) {}
        try {
          await db.execute(
              "ALTER TABLE journal_entries ADD COLUMN title TEXT DEFAULT ''");
        } catch (_) {}
        try {
          await db.execute(
              "ALTER TABLE timetable_slots ADD COLUMN last_completed_date TEXT DEFAULT NULL");
        } catch (_) {}
        // Ensure step_records table exists
        await db.execute('''
          CREATE TABLE IF NOT EXISTS step_records (
            id TEXT PRIMARY KEY,
            uid TEXT,
            date TEXT,
            step_count INTEGER DEFAULT 0,
            goal INTEGER DEFAULT 6000,
            calories REAL DEFAULT 0.0,
            distance_km REAL DEFAULT 0.0,
            active_minutes INTEGER DEFAULT 0,
            updated_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS screen_time_records (
            uid TEXT,
            date TEXT,
            total_seconds INTEGER DEFAULT 0,
            app_usages_json TEXT,
            updated_at TEXT,
            PRIMARY KEY (uid, date)
          )
        ''');

        // Deduplicate any pre-existing step records for the same calendar date
        await _consolidateStepRecords(db);
        // Note: _repairMisassignedStepRecords has been removed (FIX C4) — it incorrectly
        // moved today's steps to yesterday whenever yesterday had 0 steps, causing data loss.

        // Ensure unique index on (uid, date) to permanently prevent duplicate date rows
        try {
          await db.execute('''
            CREATE UNIQUE INDEX IF NOT EXISTS idx_step_records_uid_date 
            ON step_records (uid, date)
          ''');
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
        description TEXT DEFAULT '',
        category TEXT DEFAULT 'General',
        due_date TEXT,
        reminder_date_time TEXT,
        priority INTEGER DEFAULT 4,
        time_spent_seconds INTEGER DEFAULT 0,
        target_minutes INTEGER DEFAULT 0,
        completed INTEGER DEFAULT 0,
        type TEXT DEFAULT 'task',
        classification_locked INTEGER DEFAULT 1,
        created_at TEXT,
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

    // 10. Step Records Table
    await db.execute('''
      CREATE TABLE step_records (
        id TEXT PRIMARY KEY,
        uid TEXT,
        date TEXT,
        step_count INTEGER DEFAULT 0,
        goal INTEGER DEFAULT 6000,
        calories REAL DEFAULT 0.0,
        distance_km REAL DEFAULT 0.0,
        active_minutes INTEGER DEFAULT 0,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE screen_time_records (
        uid TEXT,
        date TEXT,
        total_seconds INTEGER DEFAULT 0,
        app_usages_json TEXT,
        updated_at TEXT,
        PRIMARY KEY (uid, date)
      )
    ''');
  }

  // ==================== USER PROFILE ====================
  Future<UserProfile?> getProfile(String uid) async {
    final db = await database;
    final res =
        await db.query('user_profiles', where: 'uid = ?', whereArgs: [uid]);
    if (res.isNotEmpty) {
      final map = res.first;
      return UserProfile(
        uid: map['uid'] as String,
        email: (map['email'] ?? '') as String,
        name: (map['name'] ?? '') as String,
        bio: (map['bio'] ?? '') as String,
        phoneNumber: (map['phone_number'] ?? '') as String,
        photoPath: map['photo_path'] as String?,
        updatedAt: DateTime.tryParse((map['updated_at'] ?? '').toString()) ??
            DateTime.now(),
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

    // Ensure legacy records have created_at backfilled from updated_at if created_at is null
    try {
      await db.execute(
          'UPDATE todos SET created_at = updated_at WHERE created_at IS NULL AND updated_at IS NOT NULL');
    } catch (_) {}

    final res = await db.query(
      'todos',
      where: 'uid = ? AND is_deleted = 0',
      whereArgs: [uid],
      orderBy: 'priority ASC, due_date ASC',
    );
    final todos = res.map((m) => Todo.fromSqlite(m)).toList();

    final toMigrate = <Todo>[];
    for (final item in todos) {
      final rawMatch =
          res.firstWhere((m) => m['id'] == item.id, orElse: () => {});
      if (rawMatch['classification_locked'] != 1) {
        toMigrate.add(item);
      }
    }

    if (toMigrate.isNotEmpty) {
      final batch = db.batch();
      for (final item in toMigrate) {
        batch.update(
          'todos',
          {
            'type': item.type,
            'classification_locked': 1,
            if (item.createdAt != null)
              'created_at': item.createdAt!.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [item.id],
        );
      }
      await batch.commit(noResult: true);
    }

    return todos;
  }

  Future<void> upsertTodo(Todo todo) async {
    final db = await database;
    await db.insert('todos', todo.toSqliteMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> softDeleteTodo(String id) async {
    final db = await database;
    await db.update(
      'todos',
      {
        'is_deleted': 1,
        'is_synced': 0,
        'updated_at': DateTime.now().toIso8601String()
      },
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
    await db.insert('habits', habit.toSqliteMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> softDeleteHabit(String id) async {
    final db = await database;
    await db.update(
      'habits',
      {
        'is_deleted': 1,
        'is_synced': 0,
        'updated_at': DateTime.now().toIso8601String()
      },
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
    await db.insert('journal_entries', entry.toSqliteMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> softDeleteJournal(String id) async {
    final db = await database;
    await db.update(
      'journal_entries',
      {
        'is_deleted': 1,
        'is_synced': 0,
        'updated_at': DateTime.now().toIso8601String()
      },
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
    await db.insert('finance_transactions', tx.toSqliteMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> softDeleteTransaction(String id) async {
    final db = await database;
    await db.update(
      'finance_transactions',
      {
        'is_deleted': 1,
        'is_synced': 0,
        'updated_at': DateTime.now().toIso8601String()
      },
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
    await db.insert('calendar_events', event.toSqliteMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> softDeleteCalendarEvent(String id) async {
    final db = await database;
    await db.update(
      'calendar_events',
      {
        'is_deleted': 1,
        'is_synced': 0,
        'updated_at': DateTime.now().toIso8601String()
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== TIMETABLE SLOTS ====================
  Future<List<TimetableSlot>> getTimetableSlots(String uid,
      {String? dayOfWeek}) async {
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
    await db.insert('timetable_slots', slot.toSqliteMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> batchInsertTimetableSlots(List<TimetableSlot> slots) async {
    final db = await database;
    final batch = db.batch();
    for (final slot in slots) {
      batch.insert('timetable_slots', slot.toSqliteMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> softDeleteTimetableSlot(String id) async {
    final db = await database;
    await db.update(
      'timetable_slots',
      {
        'is_deleted': 1,
        'is_synced': 0,
        'updated_at': DateTime.now().toIso8601String()
      },
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
    await db.insert('chat_messages', msg.toSqliteMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> markChatActionApplied(String id) async {
    final db = await database;
    await db.update('chat_messages', {'is_applied': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearChatMessages(String uid) async {
    final db = await database;
    await db.delete('chat_messages', where: 'uid = ?', whereArgs: [uid]);
  }

  // ==================== SYNC HELPERS ====================
  Future<Map<String, List<Map<String, dynamic>>>> getUnsyncedRecords(
      String uid) async {
    final db = await database;
    final todos = await db
        .query('todos', where: 'uid = ? AND is_synced = 0', whereArgs: [uid]);
    final habits = await db
        .query('habits', where: 'uid = ? AND is_synced = 0', whereArgs: [uid]);
    final journals = await db.query('journal_entries',
        where: 'uid = ? AND is_synced = 0', whereArgs: [uid]);
    final transactions = await db.query('finance_transactions',
        where: 'uid = ? AND is_synced = 0', whereArgs: [uid]);
    final events = await db.query('calendar_events',
        where: 'uid = ? AND is_synced = 0', whereArgs: [uid]);
    final slots = await db.query('timetable_slots',
        where: 'uid = ? AND is_synced = 0', whereArgs: [uid]);
    final reminders = await db.query('reminders',
        where: 'uid = ? AND is_synced = 0', whereArgs: [uid]);
    final profile = await db.query('user_profiles',
        where: 'uid = ? AND is_synced = 0', whereArgs: [uid]);

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
    await db.update('user_profiles', {'is_synced': 1},
        where: 'uid = ?', whereArgs: [uid]);
  }

  Future<int> getTotalLocalRecordsCount(String uid) async {
    final db = await database;
    int count = 0;
    for (final table in [
      'todos',
      'habits',
      'journal_entries',
      'finance_transactions',
      'calendar_events',
      'timetable_slots',
      'reminders'
    ]) {
      final res = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM $table WHERE uid = ? AND is_deleted = 0',
          [uid]));
      count += (res ?? 0);
    }
    return count;
  }

  // ==================== REMINDERS ====================
  Future<void> insertReminder(Reminder r) async {
    final db = await database;
    await db.insert('reminders', r.toSqliteMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateReminder(Reminder r) async {
    final db = await database;
    await db.update('reminders', r.toSqliteMap(),
        where: 'id = ?', whereArgs: [r.id]);
  }

  Future<void> deleteReminder(String id) async {
    final db = await database;
    await db.update('reminders', {'is_deleted': 1, 'is_synced': 0},
        where: 'id = ?', whereArgs: [id]);
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
    await db.insert('alarms', alarm.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateAlarm(AlarmModel alarm) async {
    final db = await database;
    await db.update('alarms', alarm.toMap(),
        where: 'id = ?', whereArgs: [alarm.id]);
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
    await db.insert('task_sessions', session.toSqliteMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<TaskSession>> getTaskSessionsForDay(
      String uid, String dateStr) async {
    final db = await database;
    final res = await db.query(
      'task_sessions',
      where: 'uid = ? AND date = ?',
      whereArgs: [uid, dateStr],
      orderBy: 'timestamp DESC',
    );
    return res.map((m) => TaskSession.fromMap(m)).toList();
  }

  Future<List<TaskSession>> getTaskSessionsForRange(
      String uid, String startDate, String endDate) async {
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

  // ==================== STEP RECORDS ====================

  /// Consolidates any duplicate rows for the same (uid, date) into one canonical row.
  /// FIX H3: Uses MAX(step_count) instead of SUM to avoid double-counting daily totals.
  /// Both duplicate rows represent the SAME day's total, not additive increments.
  static Future<void> _consolidateStepRecords(Database db) async {
    try {
      final dupes = await db.rawQuery('''
        SELECT uid, date, COUNT(*) as cnt 
        FROM step_records 
        GROUP BY uid, date 
        HAVING cnt > 1
      ''');

      for (final row in dupes) {
        final uid = row['uid'] as String?;
        final date = row['date'] as String?;
        if (date == null) continue;

        final records = await db.query(
          'step_records',
          where: uid != null ? 'uid = ? AND date = ?' : 'date = ?',
          whereArgs: uid != null ? [uid, date] : [date],
          orderBy:
              'updated_at DESC', // Most recently updated first — most authoritative
        );

        if (records.length <= 1) continue;

        // FIX H3: For daily step totals, use MAX not SUM.
        // Each row already represents the day's cumulative total — summing would double-count.
        int maxSteps = 0;
        double maxCalories = 0.0;
        double maxDistance = 0.0;
        int maxActiveMins = 0;
        int maxGoal = 6000;
        final keeperId =
            records.first['id'] as String; // Most recently updated row

        for (final r in records) {
          final s = (r['step_count'] as num?)?.toInt() ?? 0;
          if (s > maxSteps) {
            maxSteps = s;
            maxCalories = (r['calories'] as num?)?.toDouble() ?? 0.0;
            maxDistance = (r['distance_km'] as num?)?.toDouble() ?? 0.0;
            maxActiveMins = (r['active_minutes'] as num?)?.toInt() ?? 0;
          }
          final g = (r['goal'] as num?)?.toInt() ?? 6000;
          if (g > maxGoal) maxGoal = g;
        }

        await db.delete(
          'step_records',
          where: uid != null ? 'uid = ? AND date = ?' : 'date = ?',
          whereArgs: uid != null ? [uid, date] : [date],
        );

        await db.insert('step_records', {
          'id': keeperId,
          'uid': uid ?? '',
          'date': date,
          'step_count': maxSteps,
          'goal': maxGoal,
          'calories': maxCalories,
          'distance_km': maxDistance,
          'active_minutes': maxActiveMins,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('[DatabaseService] _consolidateStepRecords error: $e');
    }
  }

  // FIX C4: _repairMisassignedStepRecords has been REMOVED.
  // The old logic moved today's steps to yesterday whenever yesterday was empty,
  // which caused data loss for legitimate first-day-of-use step data. The correct
  // approach is to let the native StepDbHelper and Dart _processRawSteps handle
  // date rollover correctly using baseline arithmetic, not after-the-fact DB repairs.

  Future<void> upsertStepRecord(StepRecord record) async {
    final db = await database;
    // Query by canonical (uid, date) to strictly enforce one entry per calendar date
    final existing = await db.query(
      'step_records',
      where: 'uid = ? AND date = ?',
      whereArgs: [record.uid, record.date],
    );
    if (existing.isNotEmpty) {
      final existingId = existing.first['id'] as String;
      final map = record.toMap();
      map['id'] = existingId;
      await db.update(
        'step_records',
        map,
        where: 'id = ?',
        whereArgs: [existingId],
      );
    } else {
      await db.insert(
        'step_records',
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<StepRecord?> getStepRecord(String uid, String date) async {
    final db = await database;
    final res = await db.query(
      'step_records',
      where: 'uid = ? AND date = ?',
      whereArgs: [uid, date],
    );
    if (res.isEmpty) return null;
    if (res.length == 1) return StepRecord.fromMap(res.first);

    // If multiple rows exist for the same (uid, date), they are duplicates of the
    // same cumulative daily total — NOT independent incremental records.
    // Use MAX step_count (most steps ever seen today), not SUM (would double-count).
    // Use the row with the highest step_count as the canonical record.
    StepRecord best = StepRecord.fromMap(res.first);
    for (final m in res.skip(1)) {
      final r = StepRecord.fromMap(m);
      if (r.stepCount > best.stepCount) best = r;
    }
    return best;
  }

  Future<List<StepRecord>> getStepRecordsForRange(
      String uid, String startDate, String endDate) async {
    final db = await database;
    final res = await db.query(
      'step_records',
      where: 'uid = ? AND date >= ? AND date <= ?',
      whereArgs: [uid, startDate, endDate],
      orderBy: 'date ASC',
    );
    final Map<String, StepRecord> uniqueMap = {};
    for (final m in res) {
      final record = StepRecord.fromMap(m);
      if (uniqueMap.containsKey(record.date)) {
        final existing = uniqueMap[record.date]!;
        // Use MAX — both rows are cumulative daily totals, not incremental counts.
        if (record.stepCount > existing.stepCount) {
          uniqueMap[record.date] = record;
        }
      } else {
        uniqueMap[record.date] = record;
      }
    }
    return uniqueMap.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<List<StepRecord>> getAllStepRecords(String uid) async {
    final db = await database;
    final res = await db.query(
      'step_records',
      where: 'uid = ?',
      whereArgs: [uid],
      orderBy: 'date DESC',
    );
    // Group and aggregate by date so callers never receive duplicate dates.
    // Use MAX step_count — duplicate rows are the same cumulative daily total, not increments.
    final Map<String, StepRecord> uniqueMap = {};
    for (final m in res) {
      final record = StepRecord.fromMap(m);
      if (uniqueMap.containsKey(record.date)) {
        final existing = uniqueMap[record.date]!;
        if (record.stepCount > existing.stepCount) {
          uniqueMap[record.date] = record;
        }
      } else {
        uniqueMap[record.date] = record;
      }
    }
    return uniqueMap.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> upsertScreenTimeSummary(
      String uid, DailyScreenTimeSummary summary) async {
    final db = await database;
    await db.insert(
      'screen_time_records',
      summary.toMap(uid),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DailyScreenTimeSummary?> getScreenTimeSummary(
      String uid, String date) async {
    final db = await database;
    final rows = await db.query(
      'screen_time_records',
      where: 'uid = ? AND date = ?',
      whereArgs: [uid, date],
      limit: 1,
    );
    return rows.isEmpty ? null : DailyScreenTimeSummary.fromMap(rows.first);
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
      'step_records',
      'screen_time_records',
    ];

    for (final table in tables) {
      try {
        await db.delete(table, where: 'uid = ?', whereArgs: [uid]);
      } catch (e) {
        debugPrint('clearLocalUserData error for table $table: $e');
      }
    }
  }

  // ==================== DATA EXPORT / IMPORT ====================

  /// Exports all user data from every table into a single JSON-serializable map.
  /// Used by DataExportService to write the backup file.
  Future<Map<String, dynamic>> exportAllData(String uid) async {
    final db = await database;

    final todos = await db.query('todos', where: 'uid = ?', whereArgs: [uid]);
    final habits = await db.query('habits', where: 'uid = ?', whereArgs: [uid]);
    final journals =
        await db.query('journal_entries', where: 'uid = ?', whereArgs: [uid]);
    final transactions = await db
        .query('finance_transactions', where: 'uid = ?', whereArgs: [uid]);
    final events =
        await db.query('calendar_events', where: 'uid = ?', whereArgs: [uid]);
    final slots =
        await db.query('timetable_slots', where: 'uid = ?', whereArgs: [uid]);
    final reminders =
        await db.query('reminders', where: 'uid = ?', whereArgs: [uid]);
    final alarms = await db.query('alarms', where: 'uid = ?', whereArgs: [uid]);
    final sessions =
        await db.query('task_sessions', where: 'uid = ?', whereArgs: [uid]);
    final steps =
        await db.query('step_records', where: 'uid = ?', whereArgs: [uid]);
    final screenTime = await db.query('screen_time_records', where: 'uid = ?', whereArgs: [uid]);
    final profile =
        await db.query('user_profiles', where: 'uid = ?', whereArgs: [uid]);

    return {
      'export_version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'uid': uid,
      'todos': todos,
      'habits': habits,
      'journal_entries': journals,
      'finance_transactions': transactions,
      'calendar_events': events,
      'timetable_slots': slots,
      'reminders': reminders,
      'alarms': alarms,
      'task_sessions': sessions,
      'step_records': steps,
      'screen_time_records': screenTime,
      'user_profiles': profile,
    };
  }

  /// Imports and restores all user data from a parsed JSON backup map.
  /// Uses REPLACE conflict algorithm so existing records are overwritten.
  Future<void> importAllData(
    Map<String, dynamic> data, {
    required String uid,
  }) async {
    final db = await database;
    final batch = db.batch();

    const columns = <String, Set<String>>{
      'todos': {
        'id',
        'title',
        'description',
        'category',
        'due_date',
        'reminder_date_time',
        'priority',
        'time_spent_seconds',
        'target_minutes',
        'completed',
        'type',
        'created_at',
        'classification_locked',
        'updated_at',
        'is_synced',
        'is_deleted'
      },
      'habits': {
        'id',
        'title',
        'frequency',
        'history_json',
        'streak',
        'updated_at',
        'is_synced',
        'is_deleted'
      },
      'journal_entries': {
        'id',
        'text',
        'title',
        'mood',
        'tags_json',
        'created_at',
        'updated_at',
        'is_synced',
        'is_deleted'
      },
      'finance_transactions': {
        'id',
        'title',
        'amount',
        'category',
        'date',
        'note',
        'updated_at',
        'is_synced',
        'is_deleted'
      },
      'calendar_events': {
        'id',
        'title',
        'description',
        'date_time',
        'category',
        'updated_at',
        'is_synced',
        'is_deleted'
      },
      'timetable_slots': {
        'id',
        'day_of_week',
        'start_time',
        'end_time',
        'title',
        'description',
        'category',
        'color_hex',
        'has_reminder',
        'is_completed',
        'updated_at',
        'is_synced',
        'is_deleted',
        'last_completed_date'
      },
      'reminders': {
        'id',
        'title',
        'description',
        'date_time',
        'category',
        'is_completed',
        'updated_at',
        'is_synced',
        'is_deleted'
      },
      'alarms': {
        'id',
        'hour',
        'minute',
        'label',
        'days_of_week',
        'is_enabled',
        'created_at'
      },
      'task_sessions': {
        'id',
        'task_id',
        'task_title',
        'category',
        'duration_seconds',
        'date',
        'timestamp'
      },
      'step_records': {
        'id',
        'date',
        'step_count',
        'goal',
        'calories',
        'distance_km',
        'active_minutes',
        'updated_at'
      },
      'screen_time_records': {
        'date',
        'total_seconds',
        'app_usages_json',
        'updated_at',
      },
      'user_profiles': {
        'uid',
        'email',
        'name',
        'bio',
        'phone_number',
        'photo_path',
        'focus_areas',
        'updated_at',
        'is_synced'
      },
    };

    void batchInsert(String table, dynamic rows) {
      if (rows is List) {
        for (final row in rows) {
          if (row is Map<String, dynamic>) {
            final allowed = columns[table];
            if (allowed == null) continue;
            final sanitized = <String, dynamic>{
              for (final entry in row.entries)
                if (allowed.contains(entry.key)) entry.key: entry.value,
            };
            if (table == 'user_profiles') {
              sanitized['uid'] = uid;
            } else {
              sanitized['uid'] = uid;
            }
            final hasIdentity = table == 'user_profiles'
              ? sanitized['uid'] != null
              : table == 'screen_time_records'
                ? sanitized['uid'] != null && sanitized['date'] is String
                : sanitized['id'] is String &&
                    (sanitized['id'] as String).isNotEmpty;
            if (!hasIdentity) continue;
            batch.insert(table, sanitized,
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }
    }

    batchInsert('todos', data['todos']);
    batchInsert('habits', data['habits']);
    batchInsert('journal_entries', data['journal_entries']);
    batchInsert('finance_transactions', data['finance_transactions']);
    batchInsert('calendar_events', data['calendar_events']);
    batchInsert('timetable_slots', data['timetable_slots']);
    batchInsert('reminders', data['reminders']);
    batchInsert('alarms', data['alarms']);
    batchInsert('task_sessions', data['task_sessions']);
    batchInsert('step_records', data['step_records']);
    batchInsert('screen_time_records', data['screen_time_records']);
    batchInsert('user_profiles', data['user_profiles']);

    await batch.commit(noResult: true);
  }
}
