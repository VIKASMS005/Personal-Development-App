import 'package:flutter_test/flutter_test.dart';
import 'package:grow_personal_dev/models/habit.dart';
import 'package:grow_personal_dev/models/task_session.dart';
import 'package:grow_personal_dev/models/todo.dart';
import 'package:grow_personal_dev/services/task_analytics.dart';

void main() {
  group('Weekly habits are scored per week', () {
    // Weeks stay inside their month: Oct 1-7, Oct 8-14, ...
    final now = DateTime(2026, 10, 10, 12); // in the week Oct 8-14

    test('streak counts weeks with at least one completion', () {
      final history = {
        '2026-09-23': true, // Sep 22-28
        '2026-09-29': true, // Sep 29-30
        '2026-10-03': true, // Oct 1-7
        '2026-10-09': true, // Oct 8-14 (this week)
      };
      expect(Habit.calculateWeeklyStreak(history, now), 4);
    });

    test('this week not done yet keeps the streak from last week', () {
      final history = {'2026-10-02': true, '2026-09-30': true};
      expect(Habit.calculateWeeklyStreak(history, now), 2);
    });

    test('a missed week breaks the streak', () {
      final history = {'2026-09-20': true, '2026-10-09': true}; // Sep 29-30 and Oct 1-7 missed
      expect(Habit.calculateWeeklyStreak(history, now), 1);
      expect(Habit.calculateWeeklyStreak({'2026-09-20': true}, now), 0);
    });

    test('done any day of the week counts as done for the week', () {
      final h = Habit(title: 'Long run', frequency: HabitFrequency.weekly, history: {'2026-10-08': true});
      expect(h.isDoneInPeriodOf(DateTime(2026, 10, 14)), isTrue);
      expect(h.isDoneInPeriodOf(DateTime(2026, 10, 7)), isFalse);
      final daily = Habit(title: 'Read', history: {'2026-10-08': true});
      expect(daily.isDoneInPeriodOf(DateTime(2026, 10, 9)), isFalse);
    });

    test('streakFor picks the unit from the frequency', () {
      final history = {'2026-10-09': true, '2026-10-10': true};
      expect(Habit.streakFor(HabitFrequency.daily, history, now), 2);
      expect(Habit.streakFor(HabitFrequency.weekly, history, now), 1);
    });
  });

  group('Task analytics leave out deleted tasks', () {
    final now = DateTime(2026, 10, 7, 12);
    final kept = Todo(id: 'kept', title: 'kept', createdAt: DateTime(2026, 10, 1));
    final deleted = Todo(id: 'gone', title: 'gone', createdAt: DateTime(2026, 10, 1), isDeleted: true);
    final sessions = [
      TaskSession(taskId: 'kept', taskTitle: 'kept', durationSeconds: 600, date: '2026-10-07'),
      TaskSession(taskId: 'gone', taskTitle: 'gone', durationSeconds: 900, date: '2026-10-07'),
      TaskSession(taskId: 'removed-from-list', taskTitle: 'x', durationSeconds: 300, date: '2026-10-07'),
    ];
    final analytics = TaskAnalytics(todos: [kept, deleted], sessions: sessions, now: now);

    test('focus time and top tasks only count tasks that still exist', () {
      expect(analytics.report(AnalyticsPeriod.daily, now).current.focusSeconds, 600);
      final top = analytics.topTasksByTime(rangeFor(AnalyticsPeriod.yearly, now));
      expect(top.map((t) => t.title), ['kept']);
    });

    test('the day timeline does too', () {
      expect(analytics.sessionsOnDay(now).map((s) => s.taskId), ['kept']);
    });
  });
}
