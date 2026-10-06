import '../models/todo.dart';

/// Pure computation engine for Task/Todo analytics.
/// No database access, no Flutter dependencies.
/// NOTE: [todos] should contain ALL todos (tasks + goals); this engine
/// internally filters to task-only where counts are shown to the user.
class TaskEngine {
  final List<Todo> todos;

  // Task-only list: excludes goals so pending/completed counts are task-scoped
  late final List<Todo> _tasks = todos.where((t) => t.isTask).toList();

  TaskEngine(this.todos);

  static String _dateStr(DateTime d) => d.toIso8601String().split('T')[0];

  static DateTime _startOfWeek(DateTime ref) {
    final monday = ref.subtract(Duration(days: ref.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  // ─── Basic Counts ──────────────────────────────────────────────────────────
  // FIX C3: All user-facing counts use _tasks (task-only), not todos (all items).

  int get totalCount => _tasks.length;
  int get completedCount => _tasks.where((t) => t.completed).length;
  int get pendingCount => _tasks.where((t) => !t.completed).length;

  double get completionPercentage {
    if (totalCount == 0) return 0.0;
    return completedCount / totalCount;
  }

  // ─── Time-Based ───────────────────────────────────────────────────────────

  List<Todo> get overdueIncomplete {
    final now = DateTime.now();
    return _tasks.where((t) {
      if (t.completed) return false;
      if (t.dueDate != null && t.dueDate!.isBefore(now)) return true;
      if (t.reminderDateTime != null && t.reminderDateTime!.isBefore(now)) {
        return true;
      }
      return false;
    }).toList();
  }

  int get overdueCount => overdueIncomplete.length;

  List<Todo> completedOn(DateTime date) {
    final ds = _dateStr(date);
    return _tasks
        .where((t) => t.completed && _dateStr(t.updatedAt) == ds)
        .toList();
  }

  int get completedTodayCount => completedOn(DateTime.now()).length;

  // ─── Weekly Trends ─────────────────────────────────────────────────────────

  int _completedInWeek(DateTime weekStart) {
    int count = 0;
    for (int i = 0; i < 7; i++) {
      final d = weekStart.add(Duration(days: i));
      count += completedOn(d).length;
    }
    return count;
  }

  int get completedThisWeek =>
      _completedInWeek(_startOfWeek(DateTime.now()));

  int get completedLastWeek =>
      _completedInWeek(_startOfWeek(DateTime.now()).subtract(const Duration(days: 7)));

  /// Percentage change in weekly completions vs last week.
  /// Returns null if last week had 0 completions (can't compute %).
  double? weeklyCompletionTrend() {
    final thisWeek = completedThisWeek;
    final lastWeek = completedLastWeek;
    if (lastWeek == 0) return null;
    return (thisWeek - lastWeek) / lastWeek;
  }

  // ─── Priority Breakdown ──────────────────────────────────────────────────

  List<Todo> get urgentImportantTasks =>
      _tasks.where((t) => t.priority == 1 && !t.completed).toList();
  List<Todo> get importantTasks =>
      _tasks.where((t) => t.priority == 2 && !t.completed).toList();
  List<Todo> get q1Tasks => urgentImportantTasks;
  List<Todo> get q2Tasks => importantTasks;
  List<Todo> get highPriorityPending =>
      _tasks.where((t) => (t.priority == 1 || t.priority == 2) && !t.completed).toList();

  // ─── Daily completion chart (last 7 days) ─────────────────────────────────

  /// Returns a list of 7 integers, index 0 = 6 days ago, index 6 = today.
  List<int> last7DaysCompletions() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return completedOn(d).length;
    });
  }
}
