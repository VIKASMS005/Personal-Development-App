import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_personal_dev/models/todo.dart';
import 'package:grow_personal_dev/providers/task_tracker_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grow_personal_dev/engine/habit_engine.dart';
import 'package:grow_personal_dev/models/habit.dart';
import 'package:grow_personal_dev/services/notification_service.dart';

String _key(DateTime d) => d.toIso8601String().split('T')[0];

void main() {
  group('Alarm notification ids and payloads', () {
    test('follow-up ids always fit a 32-bit Android id', () {
      for (final id in [0, 12345, 0x7FFFFFFF - 1, 0x7FFFFFFF - 150000]) {
        for (var k = 1; k <= 4; k++) {
          final f = NotificationService.followUpId(id, k);
          expect(f, inInclusiveRange(0, 0x7FFFFFFE));
        }
      }
      // Ids that don't overflow keep their old values.
      expect(NotificationService.followUpId(1000, 2), 201000);
    });

    test('payload carries the alarm id and keeps colons in the title', () {
      expect(NotificationService.alarmPayload('abc-1', 'Gym: legs', 2),
          'alarmv2:2:abc-1:Gym: legs');
    });
  });

  group('Habits added recently', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    test('a habit created today is not at risk and has no missed days', () {
      final h = Habit(title: 'Read', createdAt: now);
      final engine = HabitEngine([h]);
      expect(engine.habitsAtRisk(), isEmpty);
      expect(engine.missedDays(h, lookbackDays: 7), 1); // only today
    });

    test('an older habit with no record is still at risk', () {
      final h = Habit(title: 'Read', createdAt: today.subtract(const Duration(days: 10)));
      expect(HabitEngine([h]).habitsAtRisk(), [h]);
      final legacy = Habit(title: 'Old'); // created before the field existed
      expect(HabitEngine([legacy]).habitsAtRisk(), [legacy]);
    });

    test('last week\'s rate ignores habits that did not exist then', () {
      final fresh = Habit(title: 'New', createdAt: now);
      final old = Habit(
        title: 'Old',
        createdAt: DateTime(2020),
        history: {
          for (var i = 1; i <= 40; i++)
            _key(DateTime(today.year, today.month, today.day - i)): true,
        },
      );
      expect(HabitEngine([fresh, old]).overallPreviousWeekRate(), 1.0);
    });

    test('created date survives a database round trip', () {
      final h = Habit(title: 'Walk', createdAt: DateTime(2026, 10, 1, 9));
      final back = Habit.fromSqlite(h.toSqliteMap());
      expect(back.createdAt, DateTime(2026, 10, 1, 9));
      expect(Habit.fromSqlite({...h.toSqliteMap(), 'created_at': null}).createdAt, isNull);
    });
  });

  test('longest streak counts calendar days', () {
    final h = Habit(title: 'X', history: {
      '2026-03-27': true,
      '2026-03-28': true,
      '2026-03-29': true, // a DST change day in many zones
      '2026-03-30': true,
      '2026-04-02': true,
    });
    expect(HabitEngine([h]).longestStreak(h), 4);
  });

  // Presses made on the timer notification are replayed at the moment they
  // happened, so a pause pressed while the app was closed counts exactly.
  testWidgets('notification Pause and Resume are applied at their times', (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'grow_active_task_timer_v1': jsonEncode({
        'todo': Todo(title: 'Study').toMap(),
        'segments': [],
        'runningSince': now.subtract(const Duration(minutes: 10)).toIso8601String(),
        'pausedAt': null,
      }),
    });
    final tracker = TaskTrackerProvider();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(tracker.isTracking, isTrue);

    tracker.applyNotificationEvent('pause', now.subtract(const Duration(minutes: 6)));
    expect(tracker.isPaused, isTrue);
    expect(tracker.currentElapsedSeconds, 240);

    tracker.applyNotificationEvent('pause', now); // already paused: ignored
    expect(tracker.currentElapsedSeconds, 240);

    tracker.applyNotificationEvent('resume', now.subtract(const Duration(minutes: 1)));
    expect(tracker.isPaused, isFalse);
    expect(tracker.currentElapsedSeconds, inInclusiveRange(300, 301));
    tracker.dispose();
  });
}
