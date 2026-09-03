import 'package:flutter_test/flutter_test.dart';
import 'package:grow_personal_dev/models/todo.dart';

void main() {
  group('Task vs Goal Permanent Classification Tests', () {
    test('Deadline <= 7 days from creation is classified as Task', () {
      final now = DateTime(2026, 9, 1, 12, 0);

      // 3 days away
      final t1 = Todo(
        title: 'Submit Assignment',
        dueDate: now.add(const Duration(days: 3)),
        createdAt: now,
      );
      expect(t1.type, equals('task'));
      expect(t1.isTask, isTrue);
      expect(t1.isGoal, isFalse);

      // Exactly 7 days away
      final t2 = Todo(
        title: 'Finish Sprint',
        dueDate: now.add(const Duration(days: 7)),
        createdAt: now,
      );
      expect(t2.type, equals('task'));
      expect(t2.isTask, isTrue);
      expect(t2.isGoal, isFalse);

      // No due date
      final t3 = Todo(
        title: 'Someday Task',
        createdAt: now,
      );
      expect(t3.type, equals('task'));
      expect(t3.isTask, isTrue);
      expect(t3.isGoal, isFalse);
    });

    test('Deadline > 7 days from creation is classified as Goal', () {
      final now = DateTime(2026, 9, 1, 12, 0);

      // 8 days away
      final g1 = Todo(
        title: 'Prepare for Exam',
        dueDate: now.add(const Duration(days: 8)),
        createdAt: now,
      );
      expect(g1.type, equals('goal'));
      expect(g1.isGoal, isTrue);
      expect(g1.isTask, isFalse);

      // 30 days away
      final g2 = Todo(
        title: 'Run a Half Marathon',
        dueDate: now.add(const Duration(days: 30)),
        createdAt: now,
      );
      expect(g2.type, equals('goal'));
      expect(g2.isGoal, isTrue);
      expect(g2.isTask, isFalse);
    });

    test('Goal NEVER becomes a Task as deadline approaches (Permanent Classification)', () {
      final creationDate = DateTime(2026, 8, 1, 10, 0);
      final deadline = DateTime(2026, 9, 10, 10, 0); // 40 days initially -> Goal

      final goal = Todo(
        title: 'Complete Certification',
        dueDate: deadline,
        createdAt: creationDate,
      );

      expect(goal.type, equals('goal'));
      expect(goal.isGoal, isTrue);

      // Serialize to SQLite map
      final sqliteMap = goal.toSqliteMap();
      expect(sqliteMap['type'], equals('goal'));

      // Deserialize back from SQLite map (simulating opening app weeks later)
      final restored = Todo.fromSqlite(sqliteMap);
      expect(restored.type, equals('goal'));
      expect(restored.isGoal, isTrue);
      expect(restored.isTask, isFalse);
    });

    test('2-Hour Grace Period and Missed Status logic', () {
      final now = DateTime.now();

      // Due in future
      final upcoming = Todo(
        title: 'Upcoming',
        dueDate: now.add(const Duration(hours: 1)),
      );
      expect(upcoming.isMissed, isFalse);
      expect(upcoming.isInGracePeriod, isFalse);
      expect(upcoming.canComplete, isTrue);

      // 30 mins past due (In Grace Period)
      final inGrace = Todo(
        title: 'In Grace Window',
        dueDate: now.subtract(const Duration(minutes: 30)),
      );
      expect(inGrace.isInGracePeriod, isTrue);
      expect(inGrace.isMissed, isFalse);
      expect(inGrace.canComplete, isTrue);

      // 3 hours past due (Grace Period Expired -> Missed)
      final missed = Todo(
        title: 'Expired Task',
        dueDate: now.subtract(const Duration(hours: 3)),
      );
      expect(missed.isMissed, isTrue);
      expect(missed.isInGracePeriod, isFalse);
      expect(missed.canComplete, isFalse);
    });

    test('Priority levels are fully preserved (1..4)', () {
      for (final p in [1, 2, 3, 4]) {
        final t = Todo(title: 'Task P$p', priority: p);
        final map = t.toMap();
        final fromMap = Todo.fromMap(map);
        expect(fromMap.priority, equals(p));
      }
    });

    test('Legacy migration of existing stored tasks into goals using original creation date', () {
      // Simulating raw SQLite rows stored before the classification system
      final legacyRows = [
        // Task A: Created Sep 1, Deadline Sep 5 (diff = 4 <= 7) -> Stays Task
        {
          'id': 'task_a',
          'title': 'Task A',
          'created_at': '2026-09-01T00:00:00.000',
          'due_date': '2026-09-05T00:00:00.000',
          'type': 'task',
          'priority': 1,
          'completed': 0,
        },
        // Task B: Created Sep 1, Deadline Sep 20 (diff = 19 > 7) -> Migrates to Goal
        {
          'id': 'task_b',
          'title': 'Task B',
          'created_at': '2026-09-01T00:00:00.000',
          'due_date': '2026-09-20T00:00:00.000',
          'type': 'task',
          'priority': 2,
          'completed': 0,
        },
        // Task C: Created Sep 1, Deadline Sep 30 (diff = 29 > 7) -> Migrates to Goal
        {
          'id': 'task_c',
          'title': 'Task C',
          'created_at': '2026-09-01T00:00:00.000',
          'due_date': '2026-09-30T00:00:00.000',
          'type': 'task',
          'priority': 3,
          'completed': 1,
        },
        // Task D: Legacy row where created_at was null but updated_at had the creation timestamp
        {
          'id': 'task_d',
          'title': 'Task D with updated_at fallback',
          'created_at': null,
          'updated_at': '2026-09-01T00:00:00.000',
          'due_date': '2026-09-25T00:00:00.000',
          'type': 'task',
          'priority': 4,
          'completed': 0,
        },
        // Task E: No creation date at all -> Safe handling, do not guess, do not delete
        {
          'id': 'task_e',
          'title': 'Task E without date',
          'created_at': null,
          'updated_at': null,
          'due_date': '2026-09-20T00:00:00.000',
          'type': 'task',
          'priority': 4,
          'completed': 0,
        },
      ];

      final items = legacyRows.map((m) => Todo.fromSqlite(m)).toList();

      final taskA = items.firstWhere((t) => t.id == 'task_a');
      expect(taskA.type, equals('task'));
      expect(taskA.priority, equals(1));

      final taskB = items.firstWhere((t) => t.id == 'task_b');
      expect(taskB.type, equals('goal'));
      expect(taskB.isGoal, isTrue);
      expect(taskB.priority, equals(2));

      final taskC = items.firstWhere((t) => t.id == 'task_c');
      expect(taskC.type, equals('goal'));
      expect(taskC.isGoal, isTrue);
      expect(taskC.completed, isTrue);
      expect(taskC.priority, equals(3));

      final taskD = items.firstWhere((t) => t.id == 'task_d');
      expect(taskD.type, equals('goal'));
      expect(taskD.isGoal, isTrue);
      expect(taskD.createdAt, isNotNull);

      final taskE = items.firstWhere((t) => t.id == 'task_e');
      expect(taskE.type, equals('task'));
      expect(taskE.createdAt, isNull);
    });
  });
}
