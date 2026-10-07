import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_personal_dev/engine/task_engine.dart';
import 'package:grow_personal_dev/models/step_record.dart';
import 'package:grow_personal_dev/models/timetable_slot.dart';
import 'package:grow_personal_dev/models/todo.dart';
import 'package:grow_personal_dev/providers/task_tracker_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Home "tasks done today"', () {
    test('counts a task on the day it was completed, not the day it was last edited', () {
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1, 10);
      final task = Todo(
        title: 'Read',
        createdAt: yesterday,
        completed: true,
        completedAt: yesterday,
        updatedAt: now, // edited (or timed) today
      );
      final engine = TaskEngine([task]);
      expect(engine.completedTodayCount, 0);
      expect(engine.completedOn(yesterday).length, 1);
    });

    test('completed + pending + missed adds up to all tasks', () {
      final now = DateTime.now();
      final tasks = [
        Todo(title: 'done', completed: true, completedAt: now),
        Todo(title: 'open', dueDate: now.add(const Duration(days: 1))),
        Todo(title: 'missed', dueDate: now.subtract(const Duration(days: 2))),
        Todo(title: 'no date'),
      ];
      final e = TaskEngine(tasks);
      final missed = tasks.where((t) => t.isMissed).length;
      expect(missed, 1);
      expect(e.completedCount + e.pendingCount + missed, e.totalCount);
      expect(e.pendingCount, 2);
    });

    test('a reminder time passing does not make a task overdue', () {
      final now = DateTime.now();
      final t = Todo(
        title: 'call',
        dueDate: now.add(const Duration(days: 2)),
        reminderDateTime: now.subtract(const Duration(hours: 1)),
      );
      expect(TaskEngine([t]).overdueCount, 0);
    });
  });

  test('copyWith(clearReminder: true) removes the reminder; null keeps it', () {
    final t = Todo(title: 'x', reminderDateTime: DateTime(2026, 10, 8, 9));
    expect(t.copyWith(reminderDateTime: null).reminderDateTime, isNotNull);
    expect(t.copyWith(clearReminder: true).reminderDateTime, isNull);
  });

  test('An old timetable row with only the completed flag is not "done today"', () {
    final slot = TimetableSlot.fromSqlite({
      'id': 's1',
      'uid': 'local_user',
      'day_of_week': 'Daily',
      'start_time': '08:00',
      'end_time': '09:00',
      'title': 'Run',
      'is_completed': 1,
      'last_completed_date': null,
    });
    expect(slot.isCompleted, isFalse);
    expect(slot.lastCompletedDate, isNull);
  });

  test('Distance, calories and active minutes follow the step count', () {
    // A row written by older native code with a 0.75 m stride.
    final r = StepRecord.fromMap({
      'id': 'a',
      'uid': 'u',
      'date': '2026-10-06',
      'step_count': 10000,
      'distance_km': 7.5,
      'calories': 1.0,
      'active_minutes': 3,
    });
    expect(r.distanceKm, closeTo(7.62, 1e-9));
    expect(r.calories, closeTo(400, 1e-9));
    expect(r.activeMinutes, 100);
  });

  testWidgets('A running timer survives the app being closed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late BuildContext ctx;
    await tester.pumpWidget(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    }));
    final task = Todo(id: 't1', uid: 'local_user', title: 'Physics', createdAt: DateTime(2026, 10, 1));

    final first = TaskTrackerProvider();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await first.startTracking(ctx, task);
      first.pause();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    final pausedAt = first.pausedAt;
    first.dispose();

    // A fresh provider (as after a restart) restores the paused session.
    final second = TaskTrackerProvider();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(second.isTracking, isTrue);
    expect(second.isPaused, isTrue);
    expect(second.activeTodo?.id, 't1');
    expect(second.pausedAt, pausedAt);
    second.cancel();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    second.dispose();

    // Cancelling clears the saved state.
    final third = TaskTrackerProvider();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(third.isTracking, isFalse);
    third.dispose();
  });
}
