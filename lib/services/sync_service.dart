import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'database_service.dart';
import 'firestore_service.dart';
import '../models/user_profile.dart';
import '../models/todo.dart';
import '../models/habit.dart';
import '../models/journal_entry.dart';
import '../models/finance_transaction.dart';
import '../models/calendar_event.dart';
import '../models/timetable_slot.dart';
import '../models/reminder.dart';

enum SyncStatus { synced, syncing, offline, error }

class SyncService extends ChangeNotifier {
  static final SyncService instance = SyncService._internal();

  final DatabaseService _db = DatabaseService.instance;
  final FirestoreService _firestore = FirestoreService();
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<dynamic>? _connectivitySub;
  SyncStatus _status = SyncStatus.synced;
  DateTime? _lastSyncedAt;
  bool _isSyncing = false;
  Completer<void>? _activeSyncCompleter;
  VoidCallback? onSyncCompleted;
  String? _currentUid;

  SyncService._internal();

  SyncStatus get status => _status;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool get isSyncing => _isSyncing;
  bool get hasError => _status == SyncStatus.error || _status == SyncStatus.offline;
  bool get isOnline => _status == SyncStatus.synced || _status == SyncStatus.syncing;

  void init(String? uid) {
    _currentUid = uid;
    _connectivitySub?.cancel();

    _connectivitySub = _connectivity.onConnectivityChanged.listen((dynamic raw) {
      final isOnline = _isOnline(raw);
      if (isOnline) {
        syncNow();
      } else {
        _status = SyncStatus.offline;
        notifyListeners();
      }
    });

    // Check initial connectivity
    _connectivity.checkConnectivity().then((dynamic raw) {
      if (_isOnline(raw)) {
        syncNow();
      } else {
        _status = SyncStatus.offline;
        notifyListeners();
      }
    });
  }

  void updateUid(String? uid) {
    _currentUid = uid;
    if (uid != null) {
      syncNow();
    }
  }

  bool _isOnline(dynamic raw) {
    try {
      if (raw is ConnectivityResult) {
        return raw != ConnectivityResult.none;
      }
      if (raw is List && raw.isNotEmpty && raw.first is ConnectivityResult) {
        return raw.first != ConnectivityResult.none;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<void> syncNow() async {
    final uid = _currentUid;
    if (uid == null || uid.isEmpty) {
      _status = SyncStatus.synced;
      notifyListeners();
      return;
    }

    if (_isSyncing) {
      if (_activeSyncCompleter != null && !_activeSyncCompleter!.isCompleted) {
        await _activeSyncCompleter!.future;
      }
      return;
    }

    _isSyncing = true;
    _activeSyncCompleter = Completer<void>();
    _status = SyncStatus.syncing;
    notifyListeners();

    try {
      // 1. PUSH UNSYNCED LOCAL CHANGES TO FIRESTORE
      final unsynced = await _db.getUnsyncedRecords(uid);

      // Push Profile
      for (final pMap in unsynced['profile'] ?? []) {
        final p = UserProfile.fromMap(pMap);
        await _firestore.upsertProfile(p);
        await _db.markProfileSynced(uid);
      }

      // Push Todos
      for (final tMap in unsynced['todos'] ?? []) {
        final t = Todo.fromSqlite(tMap);
        if (t.isDeleted) {
          await _firestore.deleteTodo(uid, t.id);
        } else {
          await _firestore.upsertTodo(uid, t);
        }
        await _db.markRecordSynced('todos', t.id);
      }

      // Push Habits
      for (final hMap in unsynced['habits'] ?? []) {
        final h = Habit.fromSqlite(hMap);
        if (h.isDeleted) {
          await _firestore.deleteHabit(uid, h.id);
        } else {
          await _firestore.upsertHabit(uid, h);
        }
        await _db.markRecordSynced('habits', h.id);
      }

      // Push Journals
      for (final jMap in unsynced['journals'] ?? []) {
        final j = JournalEntry.fromSqlite(jMap);
        if (j.isDeleted) {
          await _firestore.deleteJournal(uid, j.id);
        } else {
          await _firestore.upsertJournal(uid, j);
        }
        await _db.markRecordSynced('journal_entries', j.id);
      }

      // Push Transactions
      for (final txMap in unsynced['transactions'] ?? []) {
        final tx = FinanceTransaction.fromSqlite(txMap);
        if (tx.isDeleted) {
          await _firestore.deleteTransaction(uid, tx.id);
        } else {
          await _firestore.upsertTransaction(uid, tx);
        }
        await _db.markRecordSynced('finance_transactions', tx.id);
      }

      // Push Calendar Events
      for (final eMap in unsynced['calendar_events'] ?? []) {
        final e = CalendarEvent.fromSqlite(eMap);
        if (e.isDeleted) {
          await _firestore.deleteCalendarEvent(uid, e.id);
        } else {
          await _firestore.upsertCalendarEvent(uid, e);
        }
        await _db.markRecordSynced('calendar_events', e.id);
      }

      // Push Timetable Slots
      for (final sMap in unsynced['timetable_slots'] ?? []) {
        final s = TimetableSlot.fromSqlite(sMap);
        if (s.isDeleted) {
          await _firestore.deleteTimetableSlot(uid, s.id);
        } else {
          await _firestore.upsertTimetableSlot(uid, s);
        }
        await _db.markRecordSynced('timetable_slots', s.id);
      }

      // Push Reminders
      for (final rMap in unsynced['reminders'] ?? []) {
        final r = Reminder.fromSqlite(rMap);
        if (r.isDeleted) {
          await _firestore.deleteReminder(uid, r.id);
        } else {
          await _firestore.upsertReminder(uid, r);
        }
        await _db.markRecordSynced('reminders', r.id);
      }

      // Push Alarms
      final localAlarms = await _db.getAlarms(uid);
      for (final a in localAlarms) {
        await _firestore.upsertAlarm(uid, a);
      }

      // Push Task Sessions
      final localSessions = await _db.getAllTaskSessions(uid);
      for (final s in localSessions) {
        await _firestore.upsertTaskSession(uid, s);
      }

      // 2. PULL REMOTE CHANGES FROM FIRESTORE TO LOCAL SQLITE (CONFLICT-AWARE)
      // Pull remote todos
      try {
        final remoteTodos = await _firestore.fetchAllTodos(uid);
        final localTodos = await _db.getTodos(uid);
        final localMap = {for (var t in localTodos) t.id: t};

        for (final rt in remoteTodos) {
          if (!rt.isDeleted) {
            final local = localMap[rt.id];
            if (local == null || local.isSynced || !local.updatedAt.isAfter(rt.updatedAt)) {
              await _db.upsertTodo(rt.copyWith(isSynced: true));
            }
          }
        }
      } catch (e) {
        debugPrint('SyncService pull todos warning: $e');
      }

      // Pull remote habits
      try {
        final remoteHabits = await _firestore.fetchAllHabits(uid);
        final localHabits = await _db.getHabits(uid);
        final localMap = {for (var h in localHabits) h.id: h};

        for (final rh in remoteHabits) {
          if (!rh.isDeleted) {
            final local = localMap[rh.id];
            if (local == null || local.isSynced || !local.updatedAt.isAfter(rh.updatedAt)) {
              await _db.upsertHabit(rh.copyWith(isSynced: true));
            }
          }
        }
      } catch (e) {
        debugPrint('SyncService pull habits warning: $e');
      }

      // Pull remote journals
      try {
        final remoteJournals = await _firestore.fetchAllJournals(uid);
        final localJournals = await _db.getJournals(uid);
        final localMap = {for (var j in localJournals) j.id: j};

        for (final rj in remoteJournals) {
          if (!rj.isDeleted) {
            final local = localMap[rj.id];
            if (local == null || local.isSynced || !local.updatedAt.isAfter(rj.updatedAt)) {
              await _db.upsertJournal(rj.copyWith(isSynced: true));
            }
          }
        }
      } catch (e) {
        debugPrint('SyncService pull journals warning: $e');
      }

      // Pull remote transactions
      try {
        final remoteTxs = await _firestore.fetchAllTransactions(uid);
        final localTxs = await _db.getTransactions(uid);
        final localMap = {for (var t in localTxs) t.id: t};

        for (final rtx in remoteTxs) {
          if (!rtx.isDeleted) {
            final local = localMap[rtx.id];
            if (local == null || local.isSynced || !local.updatedAt.isAfter(rtx.updatedAt)) {
              await _db.upsertTransaction(rtx.copyWith(isSynced: true));
            }
          }
        }
      } catch (e) {
        debugPrint('SyncService pull transactions warning: $e');
      }

      // Pull remote calendar events
      try {
        final remoteEvents = await _firestore.fetchAllCalendarEvents(uid);
        final localEvents = await _db.getCalendarEvents(uid);
        final localMap = {for (var e in localEvents) e.id: e};

        for (final re in remoteEvents) {
          if (!re.isDeleted) {
            final local = localMap[re.id];
            if (local == null || local.isSynced || !local.updatedAt.isAfter(re.updatedAt)) {
              await _db.upsertCalendarEvent(re.copyWith(isSynced: true));
            }
          }
        }
      } catch (e) {
        debugPrint('SyncService pull calendar events warning: $e');
      }

      // Pull remote timetable slots
      try {
        final remoteSlots = await _firestore.fetchAllTimetableSlots(uid);
        final localSlots = await _db.getTimetableSlots(uid);
        final localMap = {for (var s in localSlots) s.id: s};

        for (final rs in remoteSlots) {
          if (!rs.isDeleted) {
            final local = localMap[rs.id];
            if (local == null || local.isSynced || !local.updatedAt.isAfter(rs.updatedAt)) {
              await _db.upsertTimetableSlot(rs.copyWith(isSynced: true));
            }
          }
        }
      } catch (e) {
        debugPrint('SyncService pull timetable slots warning: $e');
      }

      // Pull remote reminders
      try {
        final remoteReminders = await _firestore.fetchAllReminders(uid);
        final localReminders = await _db.getReminders(uid);
        final localMap = {for (var r in localReminders) r.id: r};

        for (final rr in remoteReminders) {
          if (!rr.isDeleted) {
            final local = localMap[rr.id];
            if (local == null || local.isSynced || !local.updatedAt.isAfter(rr.updatedAt)) {
              await _db.insertReminder(rr.copyWith(isSynced: true));
            }
          }
        }
      } catch (e) {
        debugPrint('SyncService pull reminders warning: $e');
      }

      // Pull remote alarms
      try {
        final remoteAlarms = await _firestore.fetchAllAlarms(uid);
        for (final ra in remoteAlarms) {
          await _db.insertAlarm(ra);
        }
      } catch (e) {
        debugPrint('SyncService pull alarms warning: $e');
      }

      // Pull remote task sessions
      try {
        final remoteSessions = await _firestore.fetchAllTaskSessions(uid);
        for (final rs in remoteSessions) {
          await _db.insertTaskSession(rs);
        }
      } catch (e) {
        debugPrint('SyncService pull task sessions warning: $e');
      }

      // Pull remote chat messages
      try {
        final remoteChats = await _firestore.fetchAllChatMessages(uid);
        for (final rc in remoteChats) {
          await _db.insertChatMessage(rc);
        }
      } catch (e) {
        debugPrint('SyncService pull chat messages warning: $e');
      }

      // Pull remote profile
      try {
        final remoteProfile = await _firestore.fetchProfile(uid);
        if (remoteProfile != null) {
          await _db.saveProfile(remoteProfile.copyWith(isSynced: true));
        }
      } catch (e) {
        debugPrint('SyncService pull profile warning: $e');
      }

      _lastSyncedAt = DateTime.now();
      _status = SyncStatus.synced;
    } catch (e, st) {
      debugPrint('SyncService sync error: $e\n$st');
      _status = SyncStatus.error;
    } finally {
      _isSyncing = false;
      if (_activeSyncCompleter != null && !_activeSyncCompleter!.isCompleted) {
        _activeSyncCompleter!.complete();
      }
      notifyListeners();
      onSyncCompleted?.call();
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }
}
