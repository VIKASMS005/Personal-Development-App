import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';
import '../models/todo.dart';
import '../models/habit.dart';
import '../models/journal_entry.dart';
import '../models/finance_transaction.dart';
import '../models/calendar_event.dart';
import '../models/timetable_slot.dart';
import '../models/reminder.dart';
import '../models/alarm_model.dart';
import '../models/task_session.dart';
import '../models/chat_message.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _coll(String uid, String name) =>
      _db.collection('users').doc(uid).collection(name);

  Future<void> _ensureUserDoc(String uid) async {
    try {
      await _db.collection('users').doc(uid).set({
        'uid': uid,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // Profile
  Future<void> upsertProfile(UserProfile p) async {
    await _ensureUserDoc(p.uid);
    await _db.collection('users').doc(p.uid).set(p.toMap(), SetOptions(merge: true));
  }

  Future<UserProfile?> fetchProfile(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return UserProfile.fromMap(doc.data()!);
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    }
    return null;
  }

  // Todos
  Future<void> upsertTodo(String uid, Todo t) async {
    await _ensureUserDoc(uid);
    await _coll(uid, 'todos').doc(t.id).set(t.toMap(), SetOptions(merge: true));
  }

  Future<List<Todo>> fetchAllTodos(String uid) async {
    try {
      final snap = await _coll(uid, 'todos').get();
      final list = <Todo>[];
      for (final d in snap.docs) {
        try {
          final data = d.data();
          data['id'] = data['id'] ?? d.id;
          list.add(Todo.fromMap(data));
        } catch (e) {
          debugPrint('Error parsing remote todo ${d.id}: $e');
        }
      }
      return list;
    } catch (e) {
      debugPrint('Error fetching todos: $e');
      return [];
    }
  }

  Future<void> deleteTodo(String uid, String id) async {
    try {
      await _coll(uid, 'todos').doc(id).delete();
    } catch (_) {}
  }

  // Habits
  Future<void> upsertHabit(String uid, Habit h) async {
    await _ensureUserDoc(uid);
    await _coll(uid, 'habits').doc(h.id).set(h.toMap(), SetOptions(merge: true));
  }

  Future<List<Habit>> fetchAllHabits(String uid) async {
    try {
      final snap = await _coll(uid, 'habits').get();
      final list = <Habit>[];
      for (final d in snap.docs) {
        try {
          final data = d.data();
          data['id'] = data['id'] ?? d.id;
          list.add(Habit.fromMap(data));
        } catch (e) {
          debugPrint('Error parsing remote habit ${d.id}: $e');
        }
      }
      return list;
    } catch (e) {
      debugPrint('Error fetching habits: $e');
      return [];
    }
  }

  Future<void> deleteHabit(String uid, String id) async {
    try {
      await _coll(uid, 'habits').doc(id).delete();
    } catch (_) {}
  }

  // Journals
  Future<void> upsertJournal(String uid, JournalEntry j) async {
    await _ensureUserDoc(uid);
    await _coll(uid, 'journals').doc(j.id).set(j.toMap(), SetOptions(merge: true));
  }

  Future<List<JournalEntry>> fetchAllJournals(String uid) async {
    try {
      final snap = await _coll(uid, 'journals').get();
      final list = <JournalEntry>[];
      for (final d in snap.docs) {
        try {
          final data = d.data();
          data['id'] = data['id'] ?? d.id;
          list.add(JournalEntry.fromMap(data));
        } catch (e) {
          debugPrint('Error parsing remote journal ${d.id}: $e');
        }
      }
      return list;
    } catch (e) {
      debugPrint('Error fetching journals: $e');
      return [];
    }
  }

  Future<void> deleteJournal(String uid, String id) async {
    try {
      await _coll(uid, 'journals').doc(id).delete();
    } catch (_) {}
  }

  // Transactions
  Future<void> upsertTransaction(String uid, FinanceTransaction tx) async {
    await _ensureUserDoc(uid);
    await _coll(uid, 'transactions').doc(tx.id).set(tx.toMap(), SetOptions(merge: true));
  }

  Future<List<FinanceTransaction>> fetchAllTransactions(String uid) async {
    try {
      final snap = await _coll(uid, 'transactions').get();
      final list = <FinanceTransaction>[];
      for (final d in snap.docs) {
        try {
          final data = d.data();
          data['id'] = data['id'] ?? d.id;
          list.add(FinanceTransaction.fromMap(data));
        } catch (e) {
          debugPrint('Error parsing remote transaction ${d.id}: $e');
        }
      }
      return list;
    } catch (e) {
      debugPrint('Error fetching transactions: $e');
      return [];
    }
  }

  Future<void> deleteTransaction(String uid, String id) async {
    try {
      await _coll(uid, 'transactions').doc(id).delete();
    } catch (_) {}
  }

  // Calendar Events
  Future<void> upsertCalendarEvent(String uid, CalendarEvent event) async {
    await _ensureUserDoc(uid);
    await _coll(uid, 'calendar_events').doc(event.id).set(event.toMap(), SetOptions(merge: true));
  }

  Future<List<CalendarEvent>> fetchAllCalendarEvents(String uid) async {
    try {
      final snap = await _coll(uid, 'calendar_events').get();
      final list = <CalendarEvent>[];
      for (final d in snap.docs) {
        try {
          final data = d.data();
          data['id'] = data['id'] ?? d.id;
          list.add(CalendarEvent.fromMap(data));
        } catch (e) {
          debugPrint('Error parsing remote calendar event ${d.id}: $e');
        }
      }
      return list;
    } catch (e) {
      debugPrint('Error fetching calendar events: $e');
      return [];
    }
  }

  Future<void> deleteCalendarEvent(String uid, String id) async {
    try {
      await _coll(uid, 'calendar_events').doc(id).delete();
    } catch (_) {}
  }

  // Timetable Slots
  Future<void> upsertTimetableSlot(String uid, TimetableSlot slot) async {
    await _ensureUserDoc(uid);
    await _coll(uid, 'timetable_slots').doc(slot.id).set(slot.toMap(), SetOptions(merge: true));
  }

  Future<List<TimetableSlot>> fetchAllTimetableSlots(String uid) async {
    try {
      final snap = await _coll(uid, 'timetable_slots').get();
      final list = <TimetableSlot>[];
      for (final d in snap.docs) {
        try {
          final data = d.data();
          data['id'] = data['id'] ?? d.id;
          list.add(TimetableSlot.fromMap(data));
        } catch (e) {
          debugPrint('Error parsing remote timetable slot ${d.id}: $e');
        }
      }
      return list;
    } catch (e) {
      debugPrint('Error fetching timetable slots: $e');
      return [];
    }
  }

  Future<void> deleteTimetableSlot(String uid, String id) async {
    try {
      await _coll(uid, 'timetable_slots').doc(id).delete();
    } catch (_) {}
  }

  // Reminders
  Future<void> upsertReminder(String uid, Reminder r) async {
    await _ensureUserDoc(uid);
    await _coll(uid, 'reminders').doc(r.id).set(r.toMap(), SetOptions(merge: true));
  }

  Future<List<Reminder>> fetchAllReminders(String uid) async {
    try {
      final snap = await _coll(uid, 'reminders').get();
      final list = <Reminder>[];
      for (final d in snap.docs) {
        try {
          final data = d.data();
          data['id'] = data['id'] ?? d.id;
          list.add(Reminder.fromMap(data));
        } catch (e) {
          debugPrint('Error parsing remote reminder ${d.id}: $e');
        }
      }
      return list;
    } catch (e) {
      debugPrint('Error fetching reminders: $e');
      return [];
    }
  }

  Future<void> deleteReminder(String uid, String id) async {
    try {
      await _coll(uid, 'reminders').doc(id).delete();
    } catch (_) {}
  }

  // Alarms
  Future<void> upsertAlarm(String uid, AlarmModel alarm) async {
    await _ensureUserDoc(uid);
    await _coll(uid, 'alarms').doc(alarm.id).set(alarm.toMap(), SetOptions(merge: true));
  }

  Future<List<AlarmModel>> fetchAllAlarms(String uid) async {
    try {
      final snap = await _coll(uid, 'alarms').get();
      final list = <AlarmModel>[];
      for (final d in snap.docs) {
        try {
          final data = d.data();
          data['id'] = data['id'] ?? d.id;
          list.add(AlarmModel.fromMap(data));
        } catch (e) {
          debugPrint('Error parsing remote alarm ${d.id}: $e');
        }
      }
      return list;
    } catch (e) {
      debugPrint('Error fetching alarms: $e');
      return [];
    }
  }

  Future<void> deleteAlarm(String uid, String id) async {
    try {
      await _coll(uid, 'alarms').doc(id).delete();
    } catch (_) {}
  }

  // Task Sessions (Time Tracker)
  Future<void> upsertTaskSession(String uid, TaskSession session) async {
    await _ensureUserDoc(uid);
    await _coll(uid, 'task_sessions').doc(session.id).set(session.toMap(), SetOptions(merge: true));
  }

  Future<List<TaskSession>> fetchAllTaskSessions(String uid) async {
    try {
      final snap = await _coll(uid, 'task_sessions').get();
      final list = <TaskSession>[];
      for (final d in snap.docs) {
        try {
          final data = d.data();
          data['id'] = data['id'] ?? d.id;
          list.add(TaskSession.fromMap(data));
        } catch (e) {
          debugPrint('Error parsing remote session ${d.id}: $e');
        }
      }
      return list;
    } catch (e) {
      debugPrint('Error fetching sessions: $e');
      return [];
    }
  }

  Future<void> deleteTaskSession(String uid, String id) async {
    try {
      await _coll(uid, 'task_sessions').doc(id).delete();
    } catch (_) {}
  }

  // Chat Messages
  Future<void> upsertChatMessage(String uid, ChatMessage msg) async {
    await _ensureUserDoc(uid);
    await _coll(uid, 'chat_messages').doc(msg.id).set(msg.toMap(), SetOptions(merge: true));
  }

  Future<List<ChatMessage>> fetchAllChatMessages(String uid) async {
    try {
      final snap = await _coll(uid, 'chat_messages').get();
      final list = <ChatMessage>[];
      for (final d in snap.docs) {
        try {
          final data = d.data();
          data['id'] = data['id'] ?? d.id;
          list.add(ChatMessage.fromMap(data));
        } catch (e) {
          debugPrint('Error parsing remote chat message ${d.id}: $e');
        }
      }
      return list;
    } catch (e) {
      debugPrint('Error fetching chat messages: $e');
      return [];
    }
  }

  Future<void> deleteChatMessage(String uid, String id) async {
    try {
      await _coll(uid, 'chat_messages').doc(id).delete();
    } catch (_) {}
  }

  // ==================== COMPLETE CLOUD DATA PURGE ====================
  Future<void> deleteAllUserData(String uid) async {
    final subcollections = [
      'todos',
      'habits',
      'journals',
      'transactions',
      'calendar_events',
      'timetable_slots',
      'reminders',
      'alarms',
      'task_sessions',
      'chat_messages',
    ];

    for (final col in subcollections) {
      try {
        final snap = await _coll(uid, col).get();
        for (final doc in snap.docs) {
          await doc.reference.delete();
        }
      } catch (e) {
        // Continue deleting remaining collections even if one fails
      }
    }

    // Delete user profile document
    try {
      await _db.collection('users').doc(uid).delete();
    } catch (_) {}
  }
}
