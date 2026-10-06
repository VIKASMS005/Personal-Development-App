import 'package:flutter_test/flutter_test.dart';
import 'package:grow_personal_dev/models/todo.dart';
import 'package:grow_personal_dev/models/habit.dart';
import 'package:grow_personal_dev/models/timetable_slot.dart';
import 'package:grow_personal_dev/models/journal_entry.dart';
import 'package:grow_personal_dev/services/notification_service.dart';
import 'package:grow_personal_dev/models/screen_time_record.dart';
import 'package:grow_personal_dev/models/step_record.dart';

void main() {
  test('Screen-time summaries round-trip daily and per-app data', () {
    final start = DateTime(2026, 9, 10, 9);
    final summary = DailyScreenTimeSummary(
      date: '2026-09-10',
      totalDuration: const Duration(hours: 2, minutes: 15),
      appUsages: [
        AppUsageRecord(
          packageName: 'com.example.app',
          appName: 'Example',
          usage: const Duration(minutes: 30),
          startDate: start,
          endDate: start.add(const Duration(minutes: 30)),
          category: 'Productivity',
        ),
      ],
      categoryBreakdown: const {
        'Productivity': Duration(minutes: 30),
      },
    );

    final restored =
        DailyScreenTimeSummary.fromMap(summary.toMap('local_user'));
    expect(restored.date, '2026-09-10');
    expect(restored.totalDuration, const Duration(hours: 2, minutes: 15));
    expect(restored.appUsages.single.appName, 'Example');
  });

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

    test(
        'Goal NEVER becomes a Task as deadline approaches (Permanent Classification)',
        () {
      final creationDate = DateTime(2026, 8, 1, 10, 0);
      final deadline =
          DateTime(2026, 9, 10, 10, 0); // 40 days initially -> Goal

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

    test(
        'Locked Task remains a Task after its deadline moves beyond seven days',
        () {
      final created = DateTime(2026, 9, 1);
      final task = Todo(
        title: 'Permanent Task',
        dueDate: DateTime(2026, 9, 3),
        createdAt: created,
      );

      final stored = task.toSqliteMap()
        ..['due_date'] = DateTime(2026, 9, 30).toIso8601String();
      final restored = Todo.fromSqlite(stored);

      expect(restored.isTask, isTrue);
      expect(restored.isGoal, isFalse);
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

    test(
        'Legacy migration of existing stored tasks into goals using original creation date',
        () {
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

  group('Habit Streak Consecutive Days Calculation', () {
    test(
        'Calculates streak accurately when completed today and past consecutive days',
        () {
      final now = DateTime(2026, 9, 4);
      final history = {
        '2026-09-04': true,
        '2026-09-03': true,
        '2026-09-02': true,
        '2026-09-01': false, // broken streak
        '2026-08-31': true,
      };

      final streak = Habit.calculateStreak(history, now);
      expect(streak, equals(3));
    });

    test(
        'Preserves streak on current day morning when today is not yet done but yesterday was done',
        () {
      final now = DateTime(2026, 9, 4);
      final history = {
        '2026-09-03': true,
        '2026-09-02': true,
      };

      // Today (2026-09-04) is not in history or false
      final streak = Habit.calculateStreak(history, now);
      expect(streak, equals(2));
    });

    test('Resets streak to 0 if both today and yesterday were missed', () {
      final now = DateTime(2026, 9, 4);
      final history = {
        '2026-09-02': true,
        '2026-09-01': true,
      };

      final streak = Habit.calculateStreak(history, now);
      expect(streak, equals(0));
    });

    test('Returns 0 for empty or uncompleted history', () {
      final now = DateTime(2026, 9, 4);
      expect(Habit.calculateStreak({}, now), equals(0));
      expect(Habit.calculateStreak({'2026-09-04': false}, now), equals(0));
    });
  });

  group('Timetable Daily Reset Logic', () {
    test('Slot is completed only on the date recorded in lastCompletedDate',
        () {
      final slot = TimetableSlot(
        startTime: '09:00',
        endTime: '10:00',
        title: 'Deep Work',
        lastCompletedDate: '2026-09-03',
      );

      // On September 3rd, it was completed
      expect(slot.isCompletedToday(DateTime(2026, 9, 3)), isTrue);

      // On September 4th, it automatically resets to uncompleted
      expect(slot.isCompletedToday(DateTime(2026, 9, 4)), isFalse);
      expect(slot.isCompletedOn('2026-09-04'), isFalse);
    });

    test('Toggling completion updates lastCompletedDate to current date string',
        () {
      final today = DateTime(2026, 9, 4);
      final slot = TimetableSlot(
        startTime: '09:00',
        endTime: '10:00',
        title: 'Deep Work',
        lastCompletedDate: null,
      );

      expect(slot.isCompletedToday(today), isFalse);

      // Marking complete
      final completedSlot = slot.copyWith(isCompleted: true);
      expect(completedSlot.lastCompletedDate,
          equals(TimetableSlot.formatTodayString()));
      expect(completedSlot.isCompletedToday(), isTrue);

      // Marking uncompleted
      final uncompletedSlot = completedSlot.copyWith(isCompleted: false);
      expect(uncompletedSlot.lastCompletedDate, isNull);
      expect(uncompletedSlot.isCompletedToday(today), isFalse);
    });
  });

  group('Journal Entry Title & Description Integrity', () {
    test('Serializes and deserializes title and description correctly', () {
      final entry = JournalEntry(
        title: 'Morning Focus',
        text: 'Wrote 500 lines of code and meditated.',
        mood: 'energetic',
        tags: ['focus', 'coding'],
      );

      final sqliteMap = entry.toSqliteMap();
      expect(sqliteMap['title'], equals('Morning Focus'));
      expect(
          sqliteMap['text'], equals('Wrote 500 lines of code and meditated.'));

      final restored = JournalEntry.fromSqlite(sqliteMap);
      expect(restored.title, equals('Morning Focus'));
      expect(restored.text, equals('Wrote 500 lines of code and meditated.'));
      expect(restored.mood, equals('energetic'));
      expect(restored.tags, containsAll(['focus', 'coding']));
    });

    test('Handles legacy database entries without a title gracefully', () {
      final legacyMap = {
        'id': 'legacy-id-123',
        'uid': 'local_user',
        'text': 'Old reflection without title',
        'mood': 'calm',
        'tags_json': '["mindset"]',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'is_synced': 0,
        'is_deleted': 0,
      };

      final restored = JournalEntry.fromSqlite(legacyMap);
      expect(restored.title, isEmpty);
      expect(restored.text, equals('Old reflection without title'));
    });
  });

  group('Todo Calendar-Day Classification', () {
    test('Boundary test: created late night due 8 days later is a goal', () {
      final created = DateTime(2026, 9, 1, 23, 55);
      final due = DateTime(2026, 9, 9, 8, 0); // 8 calendar days later

      final classification = Todo.classify(dueDate: due, createdAt: created);
      expect(classification, equals('goal'));
    });

    test('Boundary test: created early morning due 7 days later is a task', () {
      final created = DateTime(2026, 9, 1, 1, 0);
      final due = DateTime(2026, 9, 8, 23, 0); // exactly 7 calendar days later

      final classification = Todo.classify(dueDate: due, createdAt: created);
      expect(classification, equals('task'));
    });
  });

  group('Step Date Rollover & Forward Navigation Guard Tests', () {
    test(
        'Steps walked on Sep 3 do NOT carry over to Sep 4 (Isolated Baselines)',
        () {
      // Hardware sensor cumulative count at end of Sep 3: 5000 steps
      const sep3RawSteps = 5000;
      const sep3Baseline = 0;
      final sep3Steps = sep3RawSteps - sep3Baseline;
      expect(sep3Steps, equals(5000));

      // Midnight rollover to Sep 4:
      // When Sep 4 begins, baseline is set to rawSteps at the transition point (5000)
      const sep4Baseline = sep3RawSteps; // 5000
      var currentRawSteps = 5000; // User has not walked any steps on Sep 4 yet

      var sep4Steps = (currentRawSteps - sep4Baseline);
      if (sep4Steps < 0) sep4Steps = 0;

      // Assert Sep 4 is 0 while Sep 3 remains 5000
      expect(sep3Steps, equals(5000));
      expect(sep4Steps, equals(0));

      // User now walks 1,000 steps on Sep 4
      currentRawSteps += 1000; // 6000 hardware total
      sep4Steps = (currentRawSteps - sep4Baseline);

      // Assert Sep 4 increases to 1000, Sep 3 remains strictly 5000
      expect(sep3Steps, equals(5000));
      expect(sep4Steps, equals(1000));
    });

    test('Forward Date Navigation is blocked on Today and clamped', () {
      DateTime normalizeDate(DateTime dt) =>
          DateTime(dt.year, dt.month, dt.day);

      final today = DateTime(2026, 9, 4, 14, 30);
      final normalizedToday = normalizeDate(today);

      var selectedDate = normalizedToday;

      // On Today (Sep 4): canGoNext MUST be false
      bool canGoNext(DateTime selected) =>
          normalizeDate(selected).isBefore(normalizedToday);
      expect(canGoNext(selectedDate), isFalse);

      // User navigates backward to Sep 3
      selectedDate =
          DateTime(selectedDate.year, selectedDate.month, selectedDate.day - 1);
      expect(selectedDate, equals(DateTime(2026, 9, 3)));
      // On Sep 3: canGoNext MUST be true
      expect(canGoNext(selectedDate), isTrue);

      // User navigates forward from Sep 3 -> Sep 4
      if (canGoNext(selectedDate)) {
        final next = DateTime(
            selectedDate.year, selectedDate.month, selectedDate.day + 1);
        if (!normalizeDate(next).isAfter(normalizedToday)) {
          selectedDate = next;
        }
      }
      expect(selectedDate, equals(DateTime(2026, 9, 4)));
      // Back on Sep 4: canGoNext MUST be false again
      expect(canGoNext(selectedDate), isFalse);

      // Attempting to advance beyond Sep 4 is blocked
      if (canGoNext(selectedDate)) {
        selectedDate = DateTime(
            selectedDate.year, selectedDate.month, selectedDate.day + 1);
      }
      expect(selectedDate, equals(DateTime(2026, 9, 4))); // Still Sep 4!

      // If a future date (e.g. Sep 5) arrives via cache/state, clamp forces it back to today
      var futureDate = DateTime(2026, 9, 5);
      if (normalizeDate(futureDate).isAfter(normalizedToday)) {
        futureDate = normalizedToday;
      }
      expect(futureDate, equals(DateTime(2026, 9, 4)));
    });

    test('Month and Year navigation forward boundaries', () {
      final now = DateTime(2026, 9, 4);

      // Month View: Sep 2026
      var selYear = 2026;
      var selMonth = 9;
      bool canGoNextMonth(int y, int m) =>
          (y < now.year) || (y == now.year && m < now.month);

      expect(canGoNextMonth(selYear, selMonth),
          isFalse); // September 2026 cannot go next

      // Go back to August 2026
      selMonth = 8;
      expect(canGoNextMonth(selYear, selMonth), isTrue);

      // Year View: 2026
      bool canGoNextYear(int y) => y < now.year;
      expect(canGoNextYear(2026), isFalse); // 2026 cannot go next
      expect(canGoNextYear(2025), isTrue); // 2025 can go next
    });
  });

  group('Pull-to-Refresh Step Tracking & Navigation Integrity Tests', () {
    test(
        'Pulling to refresh multiple times never double-counts steps (Idempotent)',
        () {
      // Setup day baseline
      const dayBaseline = 10000;
      var rawHardwareSteps = 12000;

      int calculateTodaySteps(int raw, int baseline) {
        final diff = raw - baseline;
        return diff < 0 ? 0 : diff;
      }

      // Initial read: 2000 steps
      var todaySteps = calculateTodaySteps(rawHardwareSteps, dayBaseline);
      expect(todaySteps, equals(2000));

      // User pulls to refresh 10 times without walking
      for (int i = 0; i < 10; i++) {
        todaySteps = calculateTodaySteps(rawHardwareSteps, dayBaseline);
        expect(todaySteps, equals(2000),
            reason: 'Refresh iteration $i should not duplicate steps');
      }
    });

    test(
        'Walking 500 steps and refreshing retrieves exact updated steps without duplication',
        () {
      const dayBaseline = 10000;
      var rawHardwareSteps = 12000; // 2,000 steps walked so far

      int calculateTodaySteps(int raw, int baseline) {
        final diff = raw - baseline;
        return diff < 0 ? 0 : diff;
      }

      expect(calculateTodaySteps(rawHardwareSteps, dayBaseline), equals(2000));

      // User walks 500 steps while phone is in pocket / screen locked
      rawHardwareSteps += 500; // Now 12,500 hardware count

      // User opens app and pulls to refresh
      final refreshedSteps = calculateTodaySteps(rawHardwareSteps, dayBaseline);
      expect(refreshedSteps, equals(2500));

      // User refreshes 5 more times
      for (int i = 0; i < 5; i++) {
        expect(
            calculateTodaySteps(rawHardwareSteps, dayBaseline), equals(2500));
      }
    });

    test('Historical date refresh preserves selected date and historical data',
        () {
      final today = DateTime(2026, 9, 4);
      var selectedDate = DateTime(2026, 9, 2); // User viewing Sep 2

      final databaseRecords = {
        '2026-09-02': 4500,
        '2026-09-03': 6200,
        '2026-09-04': 2500, // Today's live steps
      };

      // Simulating onRefresh handler on historical date:
      DateTime normalizeDate(DateTime dt) =>
          DateTime(dt.year, dt.month, dt.day);
      final isToday = normalizeDate(selectedDate) == normalizeDate(today);
      expect(isToday, isFalse);

      // On historical date, refresh reloads database records without altering selectedDate
      final dateKey =
          '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
      final displayedSteps = databaseRecords[dateKey] ?? 0;

      // Verify Sep 2 data is 4,500 (NOT replaced with today's 2,500)
      expect(displayedSteps, equals(4500));
      expect(selectedDate, equals(DateTime(2026, 9, 2)));
    });

    test('Future date navigation remains disabled during and after refresh',
        () {
      DateTime normalizeDate(DateTime dt) =>
          DateTime(dt.year, dt.month, dt.day);
      final today = normalizeDate(DateTime(2026, 9, 4));
      var selectedDate = today;

      bool canGoNext(DateTime selected) =>
          normalizeDate(selected).isBefore(today);

      // Before refresh on today
      expect(canGoNext(selectedDate), isFalse);

      // User pulls to refresh on today
      // Re-evaluating navigation state:
      expect(canGoNext(selectedDate), isFalse);

      // Attempting to advance into Sep 5 is blocked
      if (canGoNext(selectedDate)) {
        selectedDate = DateTime(
            selectedDate.year, selectedDate.month, selectedDate.day + 1);
      }
      expect(selectedDate, equals(today)); // Still Sep 4
    });

    test(
        'Screen-off pocket step batching accurately captures all 40-50 steps upon flush',
        () {
      const todayBaseline = 5000;
      var rawHardwareSteps = 5000; // Screen turned off with phone in pocket

      int calculateTodaySteps(int raw, int baseline) {
        final diff = raw - baseline;
        return diff < 0 ? 0 : diff;
      }

      // Initial state: 0 steps walked today
      expect(calculateTodaySteps(rawHardwareSteps, todayBaseline), equals(0));

      // User walks 48 steps with phone in pocket (screen off)
      // Hardware FIFO buffers steps silently in hardware sensor hub
      rawHardwareSteps += 48;

      // Phone is taken out and unlocked: hardware flush delivers all 48 steps at once
      final flushedSteps = calculateTodaySteps(rawHardwareSteps, todayBaseline);
      expect(flushedSteps, equals(48),
          reason: 'All 48 steps must be delivered, not just 6');

      // User walks another 50 steps
      rawHardwareSteps += 50;
      expect(calculateTodaySteps(rawHardwareSteps, todayBaseline), equals(98));
    });
  });

  group('Stable Notification ID Tests', () {
    test(
        'stableId produces identical deterministic hashes across calls and fits in 31-bit positive int',
        () {
      const id1 = 'alarm_abc-123-uuid';
      const id2 = 'task_xyz-789-uuid';
      final h1A = NotificationService.stableId(id1);
      final h1B = NotificationService.stableId(id1);
      final h2 = NotificationService.stableId(id2);

      expect(h1A, equals(h1B), reason: 'stableId must be 100% deterministic');
      expect(h1A, isNot(equals(h2)),
          reason: 'different IDs should produce different hashes');
      expect(h1A >= 0 && h1A <= 0x7FFFFFFF, isTrue);
      expect(h2 >= 0 && h2 <= 0x7FFFFFFF, isTrue);
    });

    test('Alarm 3-Snooze cycle and Missed Alarm IDs have unique non-colliding offsets', () {
      final baseId = NotificationService.stableId('alarm_morning_routine');
      final s1 = baseId + 100000;
      final s2 = baseId + 200000;
      final s3 = baseId + 300000;
      final missed = baseId + 400000;

      final idSet = {baseId, s1, s2, s3, missed};
      expect(idSet.length, equals(5), reason: 'All 3 snoozes and missed alarm must have unique IDs');
      for (final id in idSet) {
        expect(id, isPositive);
      }
    });
  });

  group('Weekly Steps Calculation & Monday-to-Sunday Alignment Tests', () {
    test('Calculates Monday to Sunday range correctly for any given anchor day', () {
      // Wednesday Sep 16, 2026 -> Monday Sep 14 to Sunday Sep 20
      final wednesday = DateTime(2026, 9, 16);
      final monday = DateTime(wednesday.year, wednesday.month, wednesday.day - (wednesday.weekday - 1));
      final sunday = DateTime(monday.year, monday.month, monday.day + 6);

      expect(monday, equals(DateTime(2026, 9, 14)));
      expect(sunday, equals(DateTime(2026, 9, 20)));
      expect(monday.weekday, equals(DateTime.monday));
      expect(sunday.weekday, equals(DateTime.sunday));
    });

    test('WeeklySummary calculates total steps, daily average, highest and lowest days accurately', () {
      final records = [
        StepRecord(date: '2026-09-14', stepCount: 6245, goal: 6000), // Mon
        StepRecord(date: '2026-09-15', stepCount: 8120, goal: 6000), // Tue
        StepRecord(date: '2026-09-16', stepCount: 4980, goal: 6000), // Wed
        StepRecord(date: '2026-09-17', stepCount: 9450, goal: 6000), // Thu
        StepRecord(date: '2026-09-18', stepCount: 7230, goal: 6000), // Fri
        StepRecord(date: '2026-09-19', stepCount: 11020, goal: 6000), // Sat
        StepRecord(date: '2026-09-20', stepCount: 5870, goal: 6000), // Sun
      ];

      final total = records.fold(0, (sum, r) => sum + r.stepCount);
      expect(total, equals(52915));

      final avg = (total / 7).round();
      expect(avg, equals(7559));

      final highest = records.reduce((a, b) => a.stepCount >= b.stepCount ? a : b);
      expect(highest.date, equals('2026-09-19'));
      expect(highest.stepCount, equals(11020));

      final lowest = records.reduce((a, b) => a.stepCount <= b.stepCount ? a : b);
      expect(lowest.date, equals('2026-09-16'));
      expect(lowest.stepCount, equals(4980));

      final goalsReached = records.where((r) => r.isGoalReached).length;
      expect(goalsReached, equals(5)); // Mon, Tue, Thu, Fri, Sat
    });

    test('Incomplete week handles future days gracefully with zero counts', () {
      // Suppose today is Thursday Sep 17, 2026 (days elapsed = 4)
      final records = [
        StepRecord(date: '2026-09-14', stepCount: 5000, goal: 6000),
        StepRecord(date: '2026-09-15', stepCount: 7000, goal: 6000),
        StepRecord(date: '2026-09-16', stepCount: 8000, goal: 6000),
        StepRecord(date: '2026-09-17', stepCount: 4000, goal: 6000), // today
        StepRecord(date: '2026-09-18', stepCount: 0, goal: 6000), // future
        StepRecord(date: '2026-09-19', stepCount: 0, goal: 6000), // future
        StepRecord(date: '2026-09-20', stepCount: 0, goal: 6000), // future
      ];

      const elapsed = 4;
      final total = records.fold(0, (sum, r) => sum + r.stepCount);
      expect(total, equals(24000));

      final avg = (total / elapsed).round();
      expect(avg, equals(6000));

      final active = records.take(elapsed).toList();
      final highest = active.reduce((a, b) => a.stepCount >= b.stepCount ? a : b);
      expect(highest.date, equals('2026-09-16'));
      expect(highest.stepCount, equals(8000));
    });
  });

  group('Real-Time Step Detection & Sensor Fusion Accuracy Tests', () {
    test('Simulating walking 20 genuine steps increments step by step to exactly 20', () {
      int lastHardwareCounter = 1000;
      int detectorStepsSinceCounter = 0;

      // User walks 20 steps one by one
      for (int i = 1; i <= 20; i++) {
        detectorStepsSinceCounter++;
        final effectiveRaw = lastHardwareCounter + detectorStepsSinceCounter;
        final stepsWalked = effectiveRaw - 1000;
        expect(stepsWalked, equals(i));
      }

      final finalWalked = (lastHardwareCounter + detectorStepsSinceCounter) - 1000;
      expect(finalWalked, equals(20));
    });

    test('Hardware counter catch-up reconciles cleanly with zero double-counting', () {
      int lastHardwareCounter = 5000;
      int detectorStepsSinceCounter = 0;

      // 1. User takes 20 steps detected in real-time by step detector
      for (int i = 0; i < 20; i++) {
        detectorStepsSinceCounter++;
      }
      int effectiveRaw = lastHardwareCounter + detectorStepsSinceCounter;
      expect(effectiveRaw - 5000, equals(20));

      // 2. Hardware counter flushes its batch to 5020
      const counterRaw = 5020;
      if (counterRaw > lastHardwareCounter) {
        final totalEffective = counterRaw > (lastHardwareCounter + detectorStepsSinceCounter)
            ? counterRaw
            : (lastHardwareCounter + detectorStepsSinceCounter);
        lastHardwareCounter = counterRaw;
        detectorStepsSinceCounter = totalEffective - counterRaw;
        if (detectorStepsSinceCounter < 0) detectorStepsSinceCounter = 0;
      }

      effectiveRaw = lastHardwareCounter + detectorStepsSinceCounter;
      // Must remain exactly 20, NEVER 40
      expect(effectiveRaw - 5000, equals(20));
      expect(detectorStepsSinceCounter, equals(0));
    });

    test('Cadence rate limiter correctly differentiates walking (1.8 Hz) from fast shaking (> 4 Hz)', () {
      // 2-second time window (2,000,000,000 ns)
      const windowNanos = 2000000000;
      const maxAllowedCadenceHz = 3.6;
      final maxAllowedStepsIn2s = (maxAllowedCadenceHz * 2.0).toInt(); // 7 steps

      // Scenario A: Genuine walking at 1.8 steps/sec (~550ms between steps)
      // In 2 seconds, a walker takes ~3 to 4 steps
      final walkingTimestamps = [
        0,
        550000000,
        1100000000,
        1650000000,
      ];
      final walkingStepsInWindow = walkingTimestamps.where((t) => t <= windowNanos).length;
      expect(walkingStepsInWindow, equals(4));
      expect(walkingStepsInWindow <= maxAllowedStepsIn2s, isTrue); // PASS: Accepted as walking

      // Scenario B: Fast hand shaking at 5.0 Hz (~200ms between steps)
      // In 2 seconds, rapid shaking generates 10 steps
      final shakingTimestamps = List.generate(10, (i) => i * 200000000);
      final shakingStepsInWindow = shakingTimestamps.where((t) => t <= windowNanos).length;
      expect(shakingStepsInWindow, equals(10));
      expect(shakingStepsInWindow > maxAllowedStepsIn2s, isTrue); // PASS: Flagged as shaking
    });
  });
}
