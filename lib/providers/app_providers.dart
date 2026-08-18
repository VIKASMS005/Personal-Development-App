import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/firestore_service.dart';
import '../services/sync_service.dart';
import '../services/ai_chatbot_service.dart';
import '../services/notification_service.dart';

// ==================== 1. AUTH PROVIDER ====================
class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  User? _user;
  bool _isLoading = true;

  AuthProvider() {
    _init();
  }

  User? get user => _user;
  String? get uid => _user?.uid;
  bool get isAuthenticated => _user != null;
  bool get isLoading => _isLoading;

  void _init() {
    _authService.authStateChanges().listen((u) {
      _user = u;
      _isLoading = false;
      SyncService.instance.updateUid(u?.uid);
      notifyListeners();
    });
  }

  Future<void> signInWithEmail(String email, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      _user = await _authService.signInWithEmail(email, password);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      _user = await _authService.signUpWithEmail(email, password);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signInWithGoogle() async {
    _isLoading = true;
    notifyListeners();
    try {
      _user = await _authService.signInWithGoogle();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await _authService.sendPasswordResetEmail(email);
  }

  Future<void> deleteAccount({BuildContext? context}) async {
    final uid = _user?.uid;
    if (uid != null) {
      // 1. Permanently delete all user data from Firebase Firestore
      try {
        await FirestoreService().deleteAllUserData(uid);
      } catch (e) {
        debugPrint('Error deleting Firestore user data: $e');
      }

      // 2. Cancel all active notifications and alarms
      await NotificationService.cancelAll();

      // 3. Clear all local storage records for this user from SQLite
      await DatabaseService.instance.clearLocalUserData(uid);

      // 4. Delete Firebase Auth user account
      await _authService.deleteAccount();
    }
    _user = null;
    SyncService.instance.updateUid(null);
    if (context != null && context.mounted) {
      _clearAllProviders(context);
    }
    notifyListeners();
  }

  Future<void> signOut({BuildContext? context}) async {
    final uid = _user?.uid;
    if (uid != null) {
      // 1. Sync pending local changes to Firestore before logout so cloud has latest data
      try {
        await SyncService.instance.syncNow();
      } catch (e) {
        debugPrint('Error syncing before logout: $e');
      }

      // 2. Cancel all active notifications and alarms
      await NotificationService.cancelAll();

      // 3. Clear all local storage records for this user from SQLite
      await DatabaseService.instance.clearLocalUserData(uid);
    }

    await _authService.signOut();
    _user = null;
    SyncService.instance.updateUid(null);
    if (context != null && context.mounted) {
      _clearAllProviders(context);
    }
    notifyListeners();
  }

  void _clearAllProviders(BuildContext context) {
    try {
      context.read<ProfileProvider>().clear();
      context.read<TodoProvider>().clear();
      context.read<HabitProvider>().clear();
      context.read<JournalProvider>().clear();
      context.read<FinanceProvider>().clear();
      context.read<CalendarProvider>().clear();
      context.read<TimetableProvider>().clear();
      context.read<ChatbotProvider>().clear();
      context.read<ReminderProvider>().clear();
      context.read<AlarmProvider>().clear();
    } catch (_) {}
  }
}

// ==================== 2. THEME PROVIDER ====================
class ThemeProvider extends ChangeNotifier {
  static const _key = 'theme_mode_pref';
  ThemeMode _themeMode = ThemeMode.light;

  ThemeProvider() {
    _load();
  }

  ThemeMode get themeMode => _themeMode;

  bool isDark(BuildContext context) {
    if (_themeMode == ThemeMode.system) {
      return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_key);
    if (val == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (val == 'light') {
      _themeMode = ThemeMode.light;
    } else {
      _themeMode = ThemeMode.light;
    }
    notifyListeners();
  }

  void toggleTheme(BuildContext context) async {
    final currentIsDark = isDark(context);
    _themeMode = currentIsDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, _themeMode == ThemeMode.dark ? 'dark' : 'light');
  }

  void setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode == ThemeMode.dark ? 'dark' : 'light');
  }
}

// ==================== 3. PROFILE PROVIDER ====================
class ProfileProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  UserProfile? _profile;

  UserProfile? get profile => _profile;
  String get displayName => _profile?.name.isNotEmpty == true
      ? _profile!.name
      : (_profile?.email.isNotEmpty == true
          ? _profile!.email.split('@').first
          : 'Champion');

  Future<void> loadProfile(String uid,
      {String? email, String? displayName}) async {
    var p = await _db.getProfile(uid);
    if (p == null) {
      p = UserProfile(
        uid: uid,
        email: email ?? '',
        name: displayName ?? '',
      );
      await _db.saveProfile(p);
    }
    _profile = p;
    notifyListeners();
  }

  Future<void> updateProfile({
    required String name,
    required String bio,
    required String phone,
    String? photoPath,
  }) async {
    if (_profile == null) return;
    final updated = _profile!.copyWith(
      name: name,
      bio: bio,
      phoneNumber: phone,
      photoPath: photoPath ?? _profile!.photoPath,
      updatedAt: DateTime.now(),
      isSynced: false,
    );
    _profile = updated;
    await _db.saveProfile(updated);
    notifyListeners();
    SyncService.instance.syncNow();
  }

  Future<void> updatePhoto(String photoPath) async {
    if (_profile == null) return;
    final updated = _profile!.copyWith(
        photoPath: photoPath, isSynced: false, updatedAt: DateTime.now());
    _profile = updated;
    await _db.saveProfile(updated);
    notifyListeners();
    SyncService.instance.syncNow();
  }

  void clear() {
    _profile = null;
    notifyListeners();
  }
}

class TodoProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<Todo> _todos = [];
  List<TaskSession> _sessions = [];

  List<Todo> get todos => _todos;
  List<TaskSession> get sessions => _sessions;
  int get completedCount => _todos.where((t) => t.completed).length;
  int get pendingCount => _todos.where((t) => !t.completed).length;
  List<Todo> get pendingTodos => _todos.where((t) => !t.completed).toList();
  List<Todo> get missedTodos => _todos.where((t) {
        if (t.completed) return false;
        final now = DateTime.now();
        if (t.dueDate != null && t.dueDate!.isBefore(now)) return true;
        if (t.reminderDateTime != null && t.reminderDateTime!.isBefore(now)) return true;
        return false;
      }).toList();
  int get missedCount => missedTodos.length;

  void clear() {
    _todos = [];
    _sessions = [];
    notifyListeners();
  }

  Future<void> loadTodos(String uid) async {
    _todos = await _db.getTodos(uid);
    _sessions = await _db.getAllTaskSessions(uid);
    notifyListeners();
  }

  Future<void> addTodo(Todo todo) async {
    _todos.insert(0, todo);
    notifyListeners();
    await _db.upsertTodo(todo);

    if (todo.reminderDateTime != null) {
      final taskReminder = Reminder(
        id: 'task_${todo.id}',
        uid: todo.uid,
        title: todo.title,
        description: todo.description.isNotEmpty ? todo.description : 'Task Reminder',
        category: todo.category,
        dateTime: todo.reminderDateTime!,
        isCompleted: todo.completed,
      );
      await _db.insertReminder(taskReminder);

      await NotificationService.scheduleReminder(
        id: ('task_${todo.id}').hashCode.abs() % 2147483647,
        title: '🔔 Task Reminder: ${todo.title}',
        dateTime: todo.reminderDateTime!,
        body: todo.description.isNotEmpty
            ? todo.description
            : 'Time to complete your scheduled task!',
      );
    }
    SyncService.instance.syncNow();
  }

  Future<void> updateTodo(Todo todo) async {
    final idx = _todos.indexWhere((t) => t.id == todo.id);
    if (idx != -1) {
      _todos[idx] = todo.copyWith(updatedAt: DateTime.now(), isSynced: false);
      notifyListeners();
      await _db.upsertTodo(_todos[idx]);

      if (todo.reminderDateTime != null && !todo.completed) {
        final taskReminder = Reminder(
          id: 'task_${todo.id}',
          uid: todo.uid,
          title: todo.title,
          description: todo.description.isNotEmpty ? todo.description : 'Task Reminder',
          category: todo.category,
          dateTime: todo.reminderDateTime!,
          isCompleted: todo.completed,
        );
        await _db.insertReminder(taskReminder);

        await NotificationService.scheduleReminder(
          id: ('task_${todo.id}').hashCode.abs() % 2147483647,
          title: '🔔 Task Reminder: ${todo.title}',
          dateTime: todo.reminderDateTime!,
          body: todo.description.isNotEmpty
              ? todo.description
              : 'Time to complete your scheduled task!',
        );
      } else {
        if (todo.reminderDateTime == null) {
          await _db.deleteReminder('task_${todo.id}');
        } else {
          final taskReminder = Reminder(
            id: 'task_${todo.id}',
            uid: todo.uid,
            title: todo.title,
            description: todo.description.isNotEmpty ? todo.description : 'Task Reminder',
            category: todo.category,
            dateTime: todo.reminderDateTime!,
            isCompleted: true,
          );
          await _db.insertReminder(taskReminder);
        }
        await NotificationService.cancel(('task_${todo.id}').hashCode.abs() % 2147483647);
      }
      SyncService.instance.syncNow();
    }
  }

  Future<void> toggleCompleted(Todo todo) async {
    final updated = todo.copyWith(
      completed: !todo.completed,
      updatedAt: DateTime.now(),
      isSynced: false,
    );
    final idx = _todos.indexWhere((t) => t.id == todo.id);
    if (idx != -1) {
      _todos[idx] = updated;
      notifyListeners();
      await _db.upsertTodo(updated);

      if (updated.reminderDateTime != null) {
        final taskReminder = Reminder(
          id: 'task_${updated.id}',
          uid: updated.uid,
          title: updated.title,
          description: updated.description.isNotEmpty ? updated.description : 'Task Reminder',
          category: updated.category,
          dateTime: updated.reminderDateTime!,
          isCompleted: updated.completed,
        );
        await _db.insertReminder(taskReminder);
      }

      if (updated.completed) {
        await NotificationService.cancel(('task_${todo.id}').hashCode.abs() % 2147483647);
      } else if (updated.reminderDateTime != null && updated.reminderDateTime!.isAfter(DateTime.now())) {
        await NotificationService.scheduleReminder(
          id: ('task_${todo.id}').hashCode.abs() % 2147483647,
          title: '🔔 Task Reminder: ${updated.title}',
          dateTime: updated.reminderDateTime!,
          body: updated.description.isNotEmpty
              ? updated.description
              : 'Time to complete your scheduled task!',
        );
      }
      SyncService.instance.syncNow();
    }
  }

  Future<void> deleteTodo(String id) async {
    _todos.removeWhere((t) => t.id == id);
    notifyListeners();
    await NotificationService.cancel(('task_$id').hashCode.abs() % 2147483647);
    await _db.deleteReminder('task_$id');
    await _db.softDeleteTodo(id);
    SyncService.instance.syncNow();
  }

  Future<void> logTaskTime(String taskId, int durationSeconds) async {
    final idx = _todos.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      final task = _todos[idx];
      final newTime = task.timeSpentSeconds + durationSeconds;
      final updated = task.copyWith(
        timeSpentSeconds: newTime,
        updatedAt: DateTime.now(),
        isSynced: false,
      );
      _todos[idx] = updated;

      final session = TaskSession(
        uid: task.uid,
        taskId: task.id,
        taskTitle: task.title,
        category: task.category.isNotEmpty ? task.category : 'General',
        durationSeconds: durationSeconds,
        timestamp: DateTime.now(),
      );
      _sessions.insert(0, session);
      notifyListeners();

      await _db.upsertTodo(updated);
      await _db.insertTaskSession(session);
      SyncService.instance.syncNow();
    }
  }

  // ==================== DAILY REPORTS & ANALYTICS ====================
  static String _formatDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> getDailyReport(DateTime date) {
    final dateStr = _formatDate(date);
    final daySessions = _sessions.where((s) => s.date == dateStr).toList();
    final totalFocusSeconds =
        daySessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);

    // Group focus time by category
    final Map<String, int> categoryTime = {};
    for (final s in daySessions) {
      final cat = s.category.isNotEmpty ? s.category : 'General';
      categoryTime[cat] = (categoryTime[cat] ?? 0) + s.durationSeconds;
    }

    // Completed vs Incomplete Tasks
    final completedTasks = _todos.where((t) {
      if (!t.completed) return false;
      final updatedDateStr = _formatDate(t.updatedAt);
      return updatedDateStr == dateStr ||
          daySessions.any((s) => s.taskId == t.id);
    }).toList();

    final pendingTasks = _todos.where((t) => !t.completed).toList();

    final totalRelevant = completedTasks.length + pendingTasks.length;
    final completionRate = totalRelevant > 0
        ? ((completedTasks.length / totalRelevant) * 100).round()
        : 0;

    return {
      'date': date,
      'dateStr': dateStr,
      'totalSeconds': totalFocusSeconds,
      'totalMinutes': (totalFocusSeconds / 60).round(),
      'completedTasks': completedTasks,
      'pendingTasks': pendingTasks,
      'daySessions': daySessions,
      'categoryTime': categoryTime,
      'completionRate': completionRate,
    };
  }

  Map<String, dynamic> getImprovementComparison() {
    final now = DateTime.now();
    final todayStr = _formatDate(now);
    final yesterdayStr = _formatDate(now.subtract(const Duration(days: 1)));

    // 1. Day-to-Day (Today vs Yesterday)
    final todaySeconds = _sessions
        .where((s) => s.date == todayStr)
        .fold<int>(0, (sum, s) => sum + s.durationSeconds);
    final yesterdaySeconds = _sessions
        .where((s) => s.date == yesterdayStr)
        .fold<int>(0, (sum, s) => sum + s.durationSeconds);

    final todayCompleted = _todos
        .where((t) => t.completed && _formatDate(t.updatedAt) == todayStr)
        .length;
    final yesterdayCompleted = _todos
        .where((t) => t.completed && _formatDate(t.updatedAt) == yesterdayStr)
        .length;

    int dayTimeChangePct = 0;
    if (yesterdaySeconds > 0) {
      dayTimeChangePct =
          (((todaySeconds - yesterdaySeconds) / yesterdaySeconds) * 100)
              .round();
    } else if (todaySeconds > 0) {
      dayTimeChangePct = 100;
    }

    // 2. Week-to-Week (Past 7 Days vs Prior 7 Days)
    final past7Days =
        List.generate(7, (i) => _formatDate(now.subtract(Duration(days: i))));
    final prior7Days = List.generate(
        7, (i) => _formatDate(now.subtract(Duration(days: 7 + i))));

    final currentWeekSeconds = _sessions
        .where((s) => past7Days.contains(s.date))
        .fold<int>(0, (sum, s) => sum + s.durationSeconds);
    final priorWeekSeconds = _sessions
        .where((s) => prior7Days.contains(s.date))
        .fold<int>(0, (sum, s) => sum + s.durationSeconds);

    final currentWeekCompleted = _todos
        .where(
            (t) => t.completed && past7Days.contains(_formatDate(t.updatedAt)))
        .length;
    final priorWeekCompleted = _todos
        .where(
            (t) => t.completed && prior7Days.contains(_formatDate(t.updatedAt)))
        .length;

    int weekTimeChangePct = 0;
    if (priorWeekSeconds > 0) {
      weekTimeChangePct =
          (((currentWeekSeconds - priorWeekSeconds) / priorWeekSeconds) * 100)
              .round();
    } else if (currentWeekSeconds > 0) {
      weekTimeChangePct = 100;
    }

    // 3. Month-to-Month (This Month vs Previous Month)
    final thisMonthSessions = _sessions.where(
        (s) => s.timestamp.year == now.year && s.timestamp.month == now.month);
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevMonthYear = now.month == 1 ? now.year - 1 : now.year;
    final prevMonthSessions = _sessions.where((s) =>
        s.timestamp.year == prevMonthYear && s.timestamp.month == prevMonth);

    final thisMonthSeconds =
        thisMonthSessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);
    final prevMonthSeconds =
        prevMonthSessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);

    final thisMonthCompleted = _todos
        .where((t) =>
            t.completed &&
            t.updatedAt.year == now.year &&
            t.updatedAt.month == now.month)
        .length;
    final prevMonthCompleted = _todos
        .where((t) =>
            t.completed &&
            t.updatedAt.year == prevMonthYear &&
            t.updatedAt.month == prevMonth)
        .length;

    int monthTimeChangePct = 0;
    if (prevMonthSeconds > 0) {
      monthTimeChangePct =
          (((thisMonthSeconds - prevMonthSeconds) / prevMonthSeconds) * 100)
              .round();
    } else if (thisMonthSeconds > 0) {
      monthTimeChangePct = 100;
    }

    return {
      // Day-to-Day
      'todayMinutes': (todaySeconds / 60).round(),
      'yesterdayMinutes': (yesterdaySeconds / 60).round(),
      'todayCompleted': todayCompleted,
      'yesterdayCompleted': yesterdayCompleted,
      'dayTimeChangePct': dayTimeChangePct,

      // Week-to-Week
      'currentWeekHours': (currentWeekSeconds / 3600).toStringAsFixed(1),
      'priorWeekHours': (priorWeekSeconds / 3600).toStringAsFixed(1),
      'currentWeekDailyAvgMinutes': ((currentWeekSeconds / 60) / 7).round(),
      'currentWeekCompleted': currentWeekCompleted,
      'priorWeekCompleted': priorWeekCompleted,
      'weekTimeChangePct': weekTimeChangePct,

      // Month-to-Month
      'thisMonthHours': (thisMonthSeconds / 3600).toStringAsFixed(1),
      'prevMonthHours': (prevMonthSeconds / 3600).toStringAsFixed(1),
      'thisMonthCompleted': thisMonthCompleted,
      'prevMonthCompleted': prevMonthCompleted,
      'monthTimeChangePct': monthTimeChangePct,
    };
  }
}

// ==================== 5. HABIT PROVIDER ====================
class HabitProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<Habit> _habits = [];

  List<Habit> get habits => _habits;
  int get activeCount => _habits.length;

  void clear() {
    _habits = [];
    notifyListeners();
  }

  Future<void> loadHabits(String uid) async {
    _habits = await _db.getHabits(uid);
    notifyListeners();
    for (final h in _habits) {
      if (h.streak > 0) {
        final todayStr = DateTime.now().toIso8601String().split('T')[0];
        if (h.history[todayStr] != true) {
          NotificationService.scheduleHabitStreakWarning(
            id: h.id.hashCode,
            habitTitle: h.title,
          );
        }
      }
    }
  }

  Future<void> addHabit(Habit habit) async {
    _habits.insert(0, habit);
    notifyListeners();
    await _db.upsertHabit(habit);
    NotificationService.scheduleHabitStreakWarning(
      id: habit.id.hashCode,
      habitTitle: habit.title,
    );
    SyncService.instance.syncNow();
  }

  Future<void> updateHabit(Habit habit) async {
    final idx = _habits.indexWhere((h) => h.id == habit.id);
    if (idx != -1) {
      _habits[idx] = habit.copyWith(updatedAt: DateTime.now(), isSynced: false);
      notifyListeners();
      await _db.upsertHabit(_habits[idx]);
      SyncService.instance.syncNow();
    }
  }

  Future<void> toggleDay(Habit habit, String dateStr) async {
    final history = Map<String, bool>.from(habit.history);
    final wasDone = history[dateStr] ?? false;
    history[dateStr] = !wasDone;

    int newStreak = habit.streak;
    if (!wasDone) {
      newStreak++;
      // If completed today, cancel warning
      await NotificationService.cancel(habit.id.hashCode);
    } else {
      if (newStreak > 0) newStreak--;
      // Reschedule warning if uncompleted today
      await NotificationService.scheduleHabitStreakWarning(
        id: habit.id.hashCode,
        habitTitle: habit.title,
      );
    }

    final updated = habit.copyWith(
      history: history,
      streak: newStreak,
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    final idx = _habits.indexWhere((h) => h.id == habit.id);
    if (idx != -1) {
      _habits[idx] = updated;
      notifyListeners();
      await _db.upsertHabit(updated);
      SyncService.instance.syncNow();
    }
  }

  Future<void> deleteHabit(String id) async {
    _habits.removeWhere((h) => h.id == id);
    notifyListeners();
    await NotificationService.cancel(id.hashCode);
    await _db.softDeleteHabit(id);
    SyncService.instance.syncNow();
  }
}

// ==================== 6. JOURNAL PROVIDER ====================
class JournalProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<JournalEntry> _entries = [];

  List<JournalEntry> get entries => _entries;

  void clear() {
    _entries = [];
    notifyListeners();
  }

  Future<void> loadJournals(String uid) async {
    _entries = await _db.getJournals(uid);
    notifyListeners();
  }

  Future<void> addJournal(JournalEntry entry) async {
    _entries.insert(0, entry);
    notifyListeners();
    await _db.upsertJournal(entry);
    SyncService.instance.syncNow();
  }

  Future<void> updateJournal(JournalEntry entry) async {
    final idx = _entries.indexWhere((j) => j.id == entry.id);
    if (idx != -1) {
      _entries[idx] =
          entry.copyWith(updatedAt: DateTime.now(), isSynced: false);
      notifyListeners();
      await _db.upsertJournal(_entries[idx]);
      SyncService.instance.syncNow();
    }
  }

  Future<void> deleteJournal(String id) async {
    _entries.removeWhere((j) => j.id == id);
    notifyListeners();
    await _db.softDeleteJournal(id);
    SyncService.instance.syncNow();
  }
}

// ==================== 7. FINANCE PROVIDER ====================
class FinanceProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<FinanceTransaction> _transactions = [];

  List<FinanceTransaction> get transactions => _transactions;

  double get totalBalance =>
      _transactions.fold(0.0, (sum, t) => sum + t.amount);
  double get totalIncome => _transactions
      .where((t) => t.amount > 0)
      .fold(0.0, (sum, t) => sum + t.amount);
  double get totalExpense => _transactions
      .where((t) => t.amount < 0)
      .fold(0.0, (sum, t) => sum + t.amount.abs());

  void clear() {
    _transactions = [];
    notifyListeners();
  }

  Future<void> loadTransactions(String uid) async {
    _transactions = await _db.getTransactions(uid);
    notifyListeners();
  }

  Future<void> addTransaction(FinanceTransaction tx) async {
    _transactions.insert(0, tx);
    notifyListeners();
    await _db.upsertTransaction(tx);
    SyncService.instance.syncNow();
  }

  Future<void> updateTransaction(FinanceTransaction tx) async {
    final idx = _transactions.indexWhere((t) => t.id == tx.id);
    if (idx != -1) {
      _transactions[idx] =
          tx.copyWith(updatedAt: DateTime.now(), isSynced: false);
      notifyListeners();
      await _db.upsertTransaction(_transactions[idx]);
      SyncService.instance.syncNow();
    }
  }

  Future<void> deleteTransaction(String id) async {
    _transactions.removeWhere((t) => t.id == id);
    notifyListeners();
    await _db.softDeleteTransaction(id);
    SyncService.instance.syncNow();
  }
}

// ==================== 8. CALENDAR PROVIDER ====================
class CalendarProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<CalendarEvent> _events = [];

  List<CalendarEvent> get events => _events;

  void clear() {
    _events = [];
    notifyListeners();
  }

  Future<void> loadEvents(String uid) async {
    _events = await _db.getCalendarEvents(uid);
    notifyListeners();
  }

  List<CalendarEvent> getEventsForDay(DateTime day) {
    return _events.where((e) {
      return e.dateTime.year == day.year &&
          e.dateTime.month == day.month &&
          e.dateTime.day == day.day;
    }).toList();
  }

  Future<void> addEvent(CalendarEvent event) async {
    _events.add(event);
    notifyListeners();
    await _db.upsertCalendarEvent(event);
    SyncService.instance.syncNow();
  }

  Future<void> deleteEvent(String id) async {
    _events.removeWhere((e) => e.id == id);
    notifyListeners();
    await _db.softDeleteCalendarEvent(id);
    SyncService.instance.syncNow();
  }
}

// ==================== 9. TIMETABLE PROVIDER ====================
class TimetableProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<TimetableSlot> _slots = [];
  String _selectedDay = 'All';

  List<TimetableSlot> get slots => _slots;
  String get selectedDay => _selectedDay;

  void clear() {
    _slots = [];
    notifyListeners();
  }

  static int parseTimeToMinutes(String timeStr) {
    try {
      final clean = timeStr.trim().toUpperCase();
      final isPM = clean.contains('PM');
      final isAM = clean.contains('AM');
      final numPart = clean.replaceAll(RegExp(r'[^\d:]'), '').trim();
      final parts = numPart.split(':');
      if (parts.length >= 2) {
        int hour = int.tryParse(parts[0]) ?? 0;
        final minute = int.tryParse(parts[1]) ?? 0;
        if (isPM && hour < 12) hour += 12;
        if (isAM && hour == 12) hour = 0;
        return hour * 60 + minute;
      }
    } catch (_) {}
    return 0;
  }

  void _sortSlots() {
    _slots.sort((a, b) => parseTimeToMinutes(a.startTime)
        .compareTo(parseTimeToMinutes(b.startTime)));
  }

  void setSelectedDay(String day) {
    _selectedDay = day;
    notifyListeners();
  }

  Future<void> loadSlots(String uid) async {
    _slots = await _db.getTimetableSlots(uid);
    _sortSlots();
    notifyListeners();
  }

  List<TimetableSlot> getFilteredSlots(String day) {
    List<TimetableSlot> list;
    if (day == 'All' || day == 'Daily') {
      list = List.from(_slots);
    } else {
      list = _slots
          .where((s) => s.dayOfWeek == day || s.dayOfWeek == 'Daily')
          .toList();
    }
    list.sort((a, b) => parseTimeToMinutes(a.startTime)
        .compareTo(parseTimeToMinutes(b.startTime)));
    return list;
  }

  Future<void> addSlot(TimetableSlot slot) async {
    _slots.add(slot);
    _sortSlots();
    notifyListeners();
    await _db.upsertTimetableSlot(slot);
    SyncService.instance.syncNow();
  }

  Future<void> addMultipleSlots(List<TimetableSlot> newSlots) async {
    _slots.addAll(newSlots);
    _sortSlots();
    notifyListeners();
    await _db.batchInsertTimetableSlots(newSlots);
    SyncService.instance.syncNow();
  }

  Future<void> updateSlot(TimetableSlot slot) async {
    final idx = _slots.indexWhere((s) => s.id == slot.id);
    if (idx != -1) {
      _slots[idx] = slot.copyWith(updatedAt: DateTime.now(), isSynced: false);
      _sortSlots();
      notifyListeners();
      await _db.upsertTimetableSlot(_slots[idx]);
      SyncService.instance.syncNow();
    }
  }

  Future<void> toggleCompleted(TimetableSlot slot) async {
    final updated = slot.copyWith(
      isCompleted: !slot.isCompleted,
      updatedAt: DateTime.now(),
      isSynced: false,
    );
    final idx = _slots.indexWhere((s) => s.id == slot.id);
    if (idx != -1) {
      _slots[idx] = updated;
      notifyListeners();
      await _db.upsertTimetableSlot(updated);
      SyncService.instance.syncNow();
    }
  }

  Future<void> deleteSlot(String id) async {
    _slots.removeWhere((s) => s.id == id);
    notifyListeners();
    await _db.softDeleteTimetableSlot(id);
    SyncService.instance.syncNow();
  }
}

// ==================== 10. CHATBOT PROVIDER ====================
class ChatbotProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  final AiChatbotService _aiService = AiChatbotService.instance;

  List<ChatMessage> _messages = [];
  bool _isThinking = false;

  List<ChatMessage> get messages => _messages;
  bool get isThinking => _isThinking;

  void clear() {
    _messages = [];
    _isThinking = false;
    notifyListeners();
  }

  Future<void> loadMessages(String uid) async {
    _messages = await _db.getChatMessages(uid);
    if (_messages.isEmpty) {
      final welcome = ChatMessage(
        uid: uid,
        sender: 'bot',
        text:
            '👋 Hi there! I am **GrowBot**, your personal AI companion.\n\n'
            'You can ask me **anything you want** — from study strategies, coding solutions, science, philosophy, and writing, to planning your day and creating custom timetables!\n\nHow can I help you grow today?',
      );
      _messages.add(welcome);
      await _db.insertChatMessage(welcome);
    }
    notifyListeners();
  }

  Future<void> sendMessage({
    required String uid,
    required String userText,
    String userName = 'Friend',
    int habitCount = 0,
    int pendingTaskCount = 0,
    List<String> habitTitles = const [],
    List<String> taskTitles = const [],
  }) async {
    if (userText.trim().isEmpty) return;

    final userMsg = ChatMessage(
      uid: uid,
      sender: 'user',
      text: userText.trim(),
    );
    _messages.add(userMsg);

    // Create a live placeholder for token-by-token streaming
    final botPlaceholder = ChatMessage(
      uid: uid,
      sender: 'bot',
      text: '',
    );
    _messages.add(botPlaceholder);
    _isThinking = true;
    notifyListeners();

    await _db.insertChatMessage(userMsg);

    // Prior history excluding the user turn and placeholder
    final priorHistory = _messages.where((m) => m.id != userMsg.id && m.id != botPlaceholder.id).toList();

    // Stream tokens in real time
    final finalReply = await _aiService.streamMessage(
      uid: uid,
      userText: userText,
      userName: userName,
      habitCount: habitCount,
      pendingTaskCount: pendingTaskCount,
      habitTitles: habitTitles,
      taskTitles: taskTitles,
      history: priorHistory,
      onTokenChunk: (chunk, accumulatedText) {
        final idx = _messages.indexWhere((m) => m.id == botPlaceholder.id);
        if (idx != -1) {
          _messages[idx] = _messages[idx].copyWith(text: accumulatedText);
          notifyListeners();
        }
      },
    );

    final finalIdx = _messages.indexWhere((m) => m.id == botPlaceholder.id);
    if (finalIdx != -1) {
      _messages[finalIdx] = finalReply.copyWith(id: botPlaceholder.id);
    }
    _isThinking = false;
    notifyListeners();

    await _db.insertChatMessage(_messages[finalIdx]);
  }

  Future<void> applyTimetableAction(
      ChatMessage msg, TimetableProvider timetableProvider) async {
    if (msg.actionData == null || msg.isApplied) return;
    try {
      final List<dynamic> raw = jsonDecode(msg.actionData!);
      final slots = raw
          .map((m) => TimetableSlot.fromMap(Map<String, dynamic>.from(m)))
          .toList();
      await timetableProvider.addMultipleSlots(slots);
      await _db.markChatActionApplied(msg.id);

      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx != -1) {
        _messages[idx] = msg.copyWith(isApplied: true);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error applying timetable from chatbot: $e');
    }
  }

  Future<void> applyTaskAction(
      ChatMessage msg, TodoProvider todoProvider) async {
    if (msg.actionData == null || msg.isApplied) return;
    try {
      final Map<String, dynamic> data = jsonDecode(msg.actionData!);
      final todo = Todo(
        uid: msg.uid,
        title: (data['title'] ?? 'New Task').toString(),
        description: (data['description'] ?? '').toString(),
        category: (data['category'] ?? 'General').toString(),
        priority: (data['priority'] is int)
            ? data['priority'] as int
            : int.tryParse('${data['priority']}') ?? 2,
        reminderDateTime: (data['reminderDateTime'] != null)
            ? DateTime.tryParse('${data['reminderDateTime']}')
            : null,
      );
      await todoProvider.addTodo(todo);
      await _db.markChatActionApplied(msg.id);

      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx != -1) {
        _messages[idx] = msg.copyWith(isApplied: true);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error applying task from chatbot: $e');
    }
  }

  Future<void> applyHabitAction(
      ChatMessage msg, HabitProvider habitProvider) async {
    if (msg.actionData == null || msg.isApplied) return;
    try {
      final Map<String, dynamic> data = jsonDecode(msg.actionData!);
      final freqStr = (data['frequency'] ?? 'daily').toString().toLowerCase();
      final frequency = freqStr.contains('week')
          ? HabitFrequency.weekly
          : HabitFrequency.daily;
      final habit = Habit(
        uid: msg.uid,
        title: (data['title'] ?? 'New Habit').toString(),
        frequency: frequency,
      );
      await habitProvider.addHabit(habit);
      await _db.markChatActionApplied(msg.id);

      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx != -1) {
        _messages[idx] = msg.copyWith(isApplied: true);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error applying habit from chatbot: $e');
    }
  }

  Future<void> applyReminderAction(
      ChatMessage msg, ReminderProvider reminderProvider) async {
    if (msg.actionData == null || msg.isApplied) return;
    try {
      final Map<String, dynamic> data = jsonDecode(msg.actionData!);
      DateTime reminderTime = DateTime.now().add(const Duration(hours: 2));
      if (data['time'] != null) {
        final timeStr = data['time'].toString().toLowerCase();
        final now = DateTime.now();
        int hour = 17;
        int minute = 0;
        final timeMatch =
            RegExp(r'(\d{1,2}):?(\d{2})?\s*(am|pm)?').firstMatch(timeStr);
        if (timeMatch != null) {
          hour = int.tryParse(timeMatch.group(1) ?? '17') ?? 17;
          minute = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
          final isPm = (timeMatch.group(3) ?? '').toLowerCase() == 'pm';
          if (isPm && hour < 12) hour += 12;
          if (!isPm && timeMatch.group(3) == 'am' && hour == 12) hour = 0;
        }
        reminderTime = DateTime(now.year, now.month, now.day, hour, minute);
        if (reminderTime.isBefore(now)) {
          reminderTime = reminderTime.add(const Duration(days: 1));
        }
      }

      final reminder = Reminder(
        uid: msg.uid,
        title: (data['title'] ?? 'New Reminder').toString(),
        description:
            (data['description'] ?? 'Created by GrowBot').toString(),
        category: (data['category'] ?? 'General').toString(),
        dateTime: reminderTime,
      );
      await reminderProvider.addReminder(reminder);
      await _db.markChatActionApplied(msg.id);

      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx != -1) {
        _messages[idx] = msg.copyWith(isApplied: true);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error applying reminder from chatbot: $e');
    }
  }

  Future<void> clearHistory(String uid) async {
    _messages.clear();
    notifyListeners();
    await _db.clearChatMessages(uid);
    await loadMessages(uid);
  }
}

// ==================== 11. REMINDER PROVIDER ====================
class ReminderProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<Reminder> _reminders = [];
  bool _isLoading = false;

  List<Reminder> get reminders => _reminders;
  bool get isLoading => _isLoading;
  int get activeCount => _reminders.where((r) => !r.isCompleted).length;

  List<Reminder> get missedReminders =>
      _reminders.where((r) => !r.isCompleted && r.dateTime.isBefore(DateTime.now())).toList();

  List<Reminder> get upcomingReminders =>
      _reminders.where((r) => !r.isCompleted && !r.dateTime.isBefore(DateTime.now())).toList();

  List<Reminder> get completedReminders =>
      _reminders.where((r) => r.isCompleted).toList();

  int get missedCount => missedReminders.length;

  void clear() {
    _reminders = [];
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadReminders(String uid) async {
    _isLoading = true;
    notifyListeners();
    try {
      // Reconcile and ensure all task reminders are present in reminders table
      final tasks = await _db.getTodos(uid);
      for (final t in tasks) {
        if (t.reminderDateTime != null && !t.isDeleted) {
          final taskReminder = Reminder(
            id: 'task_${t.id}',
            uid: t.uid,
            title: t.title,
            description: t.description.isNotEmpty ? t.description : 'Task Reminder',
            category: t.category,
            dateTime: t.reminderDateTime!,
            isCompleted: t.completed,
          );
          await _db.insertReminder(taskReminder);
        }
      }

      _reminders = await _db.getReminders(uid);
      _reminders.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    } catch (e) {
      debugPrint('Error loading reminders: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addReminder(Reminder r) async {
    _reminders.add(r);
    _reminders.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    notifyListeners();
    await _db.insertReminder(r);

    await NotificationService.scheduleReminder(
      id: r.id.hashCode.abs() % 2147483647,
      title: '🔔 Reminder: ${r.title}',
      dateTime: r.dateTime,
      body: r.description.isNotEmpty
          ? r.description
          : 'Time for your scheduled reminder!',
    );
    SyncService.instance.syncNow();
  }

  Future<void> rescheduleReminder(Reminder r, DateTime newTime) async {
    final updated = r.copyWith(
      dateTime: newTime,
      isCompleted: false,
      updatedAt: DateTime.now(),
      isSynced: false,
    );
    await updateReminder(updated);
    await NotificationService.scheduleReminder(
      id: updated.id.hashCode.abs() % 2147483647,
      title: '🔔 Reminder: ${updated.title}',
      dateTime: updated.dateTime,
      body: updated.description.isNotEmpty
          ? updated.description
          : 'Rescheduled reminder notification',
    );
  }

  Future<void> updateReminder(Reminder r) async {
    final idx = _reminders.indexWhere((item) => item.id == r.id);
    if (idx != -1) {
      _reminders[idx] = r.copyWith(updatedAt: DateTime.now(), isSynced: false);
      _reminders.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      notifyListeners();
      await _db.updateReminder(_reminders[idx]);

      // Sync back to Todo if this was a task reminder
      if (r.id.startsWith('task_')) {
        final taskId = r.id.substring(5);
        final taskList = await _db.getTodos(r.uid);
        final matches = taskList.where((t) => t.id == taskId);
        if (matches.isNotEmpty) {
          final t = matches.first;
          await _db.upsertTodo(t.copyWith(
            title: r.title,
            description: r.description,
            category: r.category,
            reminderDateTime: r.dateTime,
            completed: r.isCompleted,
            updatedAt: DateTime.now(),
            isSynced: false,
          ));
        }
      }

      if (!r.isCompleted) {
        await NotificationService.scheduleReminder(
          id: r.id.hashCode.abs() % 2147483647,
          title: r.id.startsWith('task_') ? '🔔 Task Reminder: ${r.title}' : '🔔 Reminder: ${r.title}',
          dateTime: r.dateTime,
          body: r.description.isNotEmpty ? r.description : 'Time for your scheduled reminder!',
        );
      } else {
        await NotificationService.cancel(r.id.hashCode.abs() % 2147483647);
      }
      SyncService.instance.syncNow();
    }
  }

  Future<void> toggleCompleted(Reminder r) async {
    final updated = r.copyWith(
      isCompleted: !r.isCompleted,
      updatedAt: DateTime.now(),
      isSynced: false,
    );
    await updateReminder(updated);
  }

  Future<void> deleteReminder(String id) async {
    _reminders.removeWhere((r) => r.id == id);
    notifyListeners();
    await NotificationService.cancel(id.hashCode.abs() % 2147483647);
    await _db.deleteReminder(id);

    // If task reminder, clear reminderDateTime on Todo
    if (id.startsWith('task_')) {
      final taskId = id.substring(5);
      final tasks = await _db.getTodos(_reminders.isNotEmpty ? _reminders.first.uid : '');
      final matches = tasks.where((t) => t.id == taskId);
      if (matches.isNotEmpty) {
        final t = matches.first;
        await _db.upsertTodo(t.copyWith(
          reminderDateTime: null,
          updatedAt: DateTime.now(),
          isSynced: false,
        ));
      }
    }
    SyncService.instance.syncNow();
  }
}

// ==================== 12. ALARM PROVIDER ====================
class AlarmProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  List<AlarmModel> _alarms = [];
  bool _isLoading = false;

  List<AlarmModel> get alarms => List.unmodifiable(_alarms);
  bool get isLoading => _isLoading;

  void clear() {
    _alarms = [];
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadAlarms(String uid) async {
    _isLoading = true;
    notifyListeners();
    try {
      _alarms = await _db.getAlarms(uid);
    } catch (e) {
      debugPrint('Error loading alarms: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addAlarm(AlarmModel alarm) async {
    _alarms.add(alarm);
    _alarms.sort(
        (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    notifyListeners();
    await _db.insertAlarm(alarm);
    if (alarm.isEnabled) {
      _scheduleAlarmNotifications(alarm);
    }
  }

  Future<void> updateAlarm(AlarmModel alarm) async {
    final idx = _alarms.indexWhere((a) => a.id == alarm.id);
    if (idx != -1) {
      _alarms[idx] = alarm;
      _alarms.sort(
          (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
      notifyListeners();
      await _db.updateAlarm(alarm);
      _cancelAlarmNotifications(alarm.id);
      if (alarm.isEnabled) {
        _scheduleAlarmNotifications(alarm);
      }
    }
  }

  Future<void> toggleAlarm(AlarmModel alarm) async {
    final updated = alarm.copyWith(isEnabled: !alarm.isEnabled);
    await updateAlarm(updated);
  }

  Future<void> deleteAlarm(String id) async {
    _alarms.removeWhere((a) => a.id == id);
    notifyListeners();
    _cancelAlarmNotifications(id);
    await _db.deleteAlarm(id);
  }

  void _scheduleAlarmNotifications(AlarmModel alarm) {
    final now = DateTime.now();
    if (alarm.daysOfWeek.isEmpty) {
      // One-time alarm
      var alarmDt =
          DateTime(now.year, now.month, now.day, alarm.hour, alarm.minute);
      if (alarmDt.isBefore(now)) {
        alarmDt = alarmDt.add(const Duration(days: 1));
      }
      NotificationService.scheduleAlarm(
        id: alarm.id.hashCode.abs() % 2147483647,
        title: alarm.label.isNotEmpty ? alarm.label : 'Alarm ⏰',
        dateTime: alarmDt,
        body:
            'Time for ${alarm.label.isNotEmpty ? alarm.label : "your routine"}!',
      );
    } else {
      // Recurring days of week (1=Mon..7=Sun)
      for (final day in alarm.daysOfWeek) {
        int daysUntil = (day - now.weekday + 7) % 7;
        var alarmDt = DateTime(
            now.year, now.month, now.day + daysUntil, alarm.hour, alarm.minute);
        if (daysUntil == 0 && alarmDt.isBefore(now)) {
          alarmDt = alarmDt.add(const Duration(days: 7));
        }
        final notifId = (alarm.id.hashCode ^ day).abs() % 2147483647;
        NotificationService.scheduleAlarm(
          id: notifId,
          title: alarm.label.isNotEmpty ? alarm.label : 'Alarm ⏰',
          dateTime: alarmDt,
          body:
              'Time for ${alarm.label.isNotEmpty ? alarm.label : "your routine"}!',
        );
      }
    }
  }

  void _cancelAlarmNotifications(String alarmId) {
    NotificationService.cancelAlarm(alarmId.hashCode.abs() % 2147483647);
    for (int day = 1; day <= 7; day++) {
      final notifId = (alarmId.hashCode ^ day).abs() % 2147483647;
      NotificationService.cancelAlarm(notifId);
    }
  }
}
