import 'package:flutter_test/flutter_test.dart';
import 'package:grow_personal_dev/models/task_session.dart';
import 'package:grow_personal_dev/models/todo.dart';
import 'package:grow_personal_dev/providers/task_tracker_provider.dart';
import 'package:grow_personal_dev/services/task_analytics.dart';
import 'package:grow_personal_dev/utils/month_weeks.dart';

void main() {
  final task = Todo(
    id: 'task-1',
    uid: 'local_user',
    title: 'Physics revision',
    category: 'Study',
    createdAt: DateTime(2026, 10, 1),
    dueDate: DateTime(2026, 10, 3, 18),
  );
  final now = DateTime(2026, 10, 7, 12);

  int totalOn(List<TaskSession> all, DateTime day) =>
      TaskAnalytics.sessionsOn(all, day, now: now).fold(0, (s, x) => s + x.durationSeconds);

  group('Timer sessions belong only to the day they happened', () {
    test('Test 1: a 35-minute session on Oct 3 shows only on Oct 3', () {
      final start = DateTime(2026, 10, 3, 10, 15);
      final sessions = buildDailySessions(
        todo: task,
        segments: [TimerSegment(start, start.add(const Duration(minutes: 35)))],
        savedAt: start.add(const Duration(minutes: 35)),
      );

      expect(sessions, hasLength(1));
      expect(sessions.single.date, '2026-10-03');
      expect(sessions.single.startTime, start);
      expect(sessions.single.endTime, DateTime(2026, 10, 3, 10, 50));
      expect(sessions.single.status, TaskSession.statusCompleted);
      expect(totalOn(sessions, DateTime(2026, 10, 3)), 35 * 60);
      for (final day in [1, 2, 4, 5, 6, 7]) {
        expect(totalOn(sessions, DateTime(2026, 10, day)), 0, reason: 'Oct $day');
      }
    });

    test('Test 2: a second session on Oct 5 stays independent', () {
      final oct3 = buildDailySessions(
        todo: task,
        segments: [TimerSegment(DateTime(2026, 10, 3, 10, 15), DateTime(2026, 10, 3, 10, 50))],
        savedAt: DateTime(2026, 10, 3, 10, 50),
      );
      final oct5a = buildDailySessions(
        todo: task,
        segments: [TimerSegment(DateTime(2026, 10, 5, 9), DateTime(2026, 10, 5, 9, 20))],
        savedAt: DateTime(2026, 10, 5, 9, 20),
      );
      final oct5b = buildDailySessions(
        todo: task,
        segments: [TimerSegment(DateTime(2026, 10, 5, 15), DateTime(2026, 10, 5, 15, 15))],
        savedAt: DateTime(2026, 10, 5, 15, 15),
      );
      final all = [...oct3, ...oct5a, ...oct5b];

      expect(totalOn(all, DateTime(2026, 10, 3)), 35 * 60);
      expect(totalOn(all, DateTime(2026, 10, 4)), 0);
      expect(totalOn(all, DateTime(2026, 10, 5)), 35 * 60);
      expect(TaskAnalytics.sessionsOn(all, DateTime(2026, 10, 5), now: now), hasLength(2));
      expect(oct3.single.id, isNot(oct5a.single.id));
    });

    test('Paused on Oct 3 and ended on Oct 4 still counts on Oct 3', () {
      // Old behaviour dated the whole session to the day it was ended.
      final sessions = buildDailySessions(
        todo: task,
        segments: [TimerSegment(DateTime(2026, 10, 3, 10, 15), DateTime(2026, 10, 3, 10, 50))],
        savedAt: DateTime(2026, 10, 4, 8),
      );
      expect(sessions.single.date, '2026-10-03');
      expect(totalOn(sessions, DateTime(2026, 10, 4)), 0);
    });

    test('A timer running across midnight is split between the two days', () {
      final sessions = buildDailySessions(
        todo: task,
        segments: [TimerSegment(DateTime(2026, 10, 3, 23, 40), DateTime(2026, 10, 4, 0, 25))],
        savedAt: DateTime(2026, 10, 4, 0, 25),
      );
      expect(totalOn(sessions, DateTime(2026, 10, 3)), 20 * 60);
      expect(totalOn(sessions, DateTime(2026, 10, 4)), 25 * 60);
    });

    test('Sessions round-trip through the database map, including old rows', () {
      final s = buildDailySessions(
        todo: task,
        segments: [TimerSegment(DateTime(2026, 10, 3, 10, 15), DateTime(2026, 10, 3, 10, 50))],
        savedAt: DateTime(2026, 10, 3, 10, 50),
      ).single;
      final back = TaskSession.fromMap(s.toSqliteMap());
      expect(back.id, s.id);
      expect(back.date, '2026-10-03');
      expect(back.startTime, s.startTime);
      expect(back.endTime, s.endTime);
      expect(back.durationSeconds, 35 * 60);

      // A row saved before start/end columns existed.
      final legacy = TaskSession.fromMap({
        'id': 'old',
        'task_id': 'task-1',
        'task_title': 'Physics revision',
        'duration_seconds': 2100,
        'date': '2026-10-03',
        'timestamp': DateTime(2026, 10, 3, 10, 50).toIso8601String(),
      });
      expect(legacy.date, '2026-10-03');
      expect(legacy.startTime, DateTime(2026, 10, 3, 10, 15));
      expect(legacy.status, TaskSession.statusCompleted);
    });
  });

  group('Future dates are blocked', () {
    test('Test 3: next day from today is disabled and future dates clamp', () {
      expect(nextAnchor(AnalyticsPeriod.daily, now, now: now), isNull);
      expect(nextAnchor(AnalyticsPeriod.daily, DateTime(2026, 10, 6), now: now), DateTime(2026, 10, 7));
      expect(nextAnchor(AnalyticsPeriod.weekly, now, now: now), isNull);
      expect(nextAnchor(AnalyticsPeriod.monthly, now, now: now), isNull);
      expect(nextAnchor(AnalyticsPeriod.yearly, now, now: now), isNull);
      expect(clampToToday(DateTime(2026, 10, 8), now: now), DateTime(2026, 10, 7));

      final future = [
        TaskSession(taskId: 'x', taskTitle: 'x', durationSeconds: 60, date: '2026-10-08'),
      ];
      expect(TaskAnalytics.sessionsOn(future, DateTime(2026, 10, 8), now: now), isEmpty);
    });

    test('Reports asked for a future anchor show today instead', () {
      final r = TaskAnalytics(todos: const [], sessions: const [], now: now)
          .report(AnalyticsPeriod.daily, DateTime(2026, 10, 9));
      expect(r.range.start, DateTime(2026, 10, 7));
    });
  });

  group('Test 4: analytics come from stored task data', () {
    Todo t(String id, {required DateTime due, DateTime? completedAt, String type = 'task'}) => Todo(
          id: id,
          title: id,
          createdAt: due.subtract(const Duration(days: 1)),
          dueDate: due,
          completed: completedAt != null,
          completedAt: completedAt,
          type: type,
        );

    final todos = [
      // Today (Oct 7): 2 done, 1 missed (due 8am, grace over), 1 pending (due tonight).
      t('a', due: DateTime(2026, 10, 7, 18), completedAt: DateTime(2026, 10, 7, 9)),
      t('b', due: DateTime(2026, 10, 7, 20), completedAt: DateTime(2026, 10, 7, 10)),
      t('c', due: DateTime(2026, 10, 7, 8)),
      t('d', due: DateTime(2026, 10, 7, 22)),
      // Yesterday (Oct 6): 1 done, 1 missed.
      t('e', due: DateTime(2026, 10, 6, 18), completedAt: DateTime(2026, 10, 6, 17)),
      t('f', due: DateTime(2026, 10, 6, 9)),
      // Last week (Sep 28 - Oct 4): 1 done.
      t('g', due: DateTime(2026, 9, 30, 12), completedAt: DateTime(2026, 9, 30, 11)),
      // A goal: never part of task analytics.
      t('goal', due: DateTime(2026, 10, 7, 9), completedAt: DateTime(2026, 10, 7, 9), type: 'goal'),
    ];
    final sessions = [
      TaskSession(taskId: 'a', taskTitle: 'a', durationSeconds: 1800, date: '2026-10-07'),
      TaskSession(taskId: 'goal', taskTitle: 'goal', durationSeconds: 9999, date: '2026-10-07'),
    ];
    final analytics = TaskAnalytics(todos: todos, sessions: sessions, now: now);

    test('Daily: today vs yesterday', () {
      final r = analytics.report(AnalyticsPeriod.daily, now);
      expect(r.current.completed, 2);
      expect(r.current.missed, 1);
      expect(r.current.pending, 1);
      expect(r.current.completionRate, 50);
      expect(r.current.focusSeconds, 1800, reason: 'goal session excluded');
      expect(r.current.sessionCount, 1);
      expect(r.previous.focusSeconds, 0);
      expect(r.focusChange, 1800);
      expect(r.focusChangePercent, isNull, reason: 'no time yesterday, so no %');
      expect(r.previous.completed, 1);
      expect(r.previous.completionRate, 50);
      expect(r.completedChange, 1);
      expect(r.rateChange, 0);
      expect(r.chart, hasLength(7));
      expect(r.chart.last.counts.completed, 2);
    });

    test('Weekly: the month week Oct 1-7, vs the previous week Sep 29-30', () {
      final r = analytics.report(AnalyticsPeriod.weekly, now);
      expect(r.range.start, DateTime(2026, 10, 1));
      expect(r.range.end, DateTime(2026, 10, 8));
      expect(r.chart.map((b) => b.label),
          ['Thu\n1', 'Fri\n2', 'Sat\n3', 'Sun\n4', 'Mon\n5', 'Tue\n6', 'Wed\n7']);
      expect(r.chart.last.isCurrent, isTrue); // Oct 7
      expect(r.current.completed, 3);
      expect(r.current.missed, 2);
      // The week before Oct 1-7 is Sep 29-30: weeks never cross a month.
      expect(r.previous.completed, 1);
      expect(r.current.focusSeconds, 1800);
      expect(r.dailyAverageFocus, 1800 ~/ 7);
    });

    test('Weekly mid-month marks the rest of the week as future', () {
      final mid = TaskAnalytics(todos: todos, sessions: sessions, now: DateTime(2026, 10, 10, 12))
          .report(AnalyticsPeriod.weekly, DateTime(2026, 10, 10));
      expect(mid.range.start, DateTime(2026, 10, 8));
      expect(mid.chart, hasLength(7));
      expect(mid.chart[2].isCurrent, isTrue); // Oct 10
      expect(mid.chart[3].isFuture, isTrue);
      expect(mid.comparedDays, 3); // Oct 8-10 vs Oct 1-3
    });

    test('Top tasks by time, highest first, goals excluded', () {
      final top = analytics.topTasksByTime(rangeFor(AnalyticsPeriod.yearly, now));
      expect(top, hasLength(1));
      expect(top.single.title, 'a');
      expect(top.single.seconds, 1800);
    });

    test('Monthly and yearly buckets', () {
      final m = analytics.report(AnalyticsPeriod.monthly, now);
      expect(m.chart.map((b) => b.label), ['1–7', '8–14', '15–21', '22–28', '29–31']);
      expect(m.current.completed, 3);
      // Oct 1-7 is compared with Sep 1-7, so the Sep 30 task is not counted.
      expect(m.comparedDays, 7);
      expect(m.previous.completed, 0);

      final y = analytics.report(AnalyticsPeriod.yearly, now);
      expect(y.chart, hasLength(12));
      expect(y.chart[9].isCurrent, isTrue); // October
      expect(y.chart[10].isFuture, isTrue);
      expect(y.current.completed, 4);
    });

    test('No previous data gives no percentage change (never infinite)', () {
      final only = TaskAnalytics(todos: [todos.first], sessions: const [], now: now);
      final r = only.report(AnalyticsPeriod.daily, now);
      expect(r.previous.completionRate, isNull);
      expect(r.rateChange, isNull);
    });
  });

  group('Month weeks never cross into the next month', () {
    test('Weeks are 1-7, 8-14, 15-21, 22-28 and 29-end', () {
      expect(monthWeekOf(DateTime(2026, 10, 1)).start, DateTime(2026, 10, 1));
      expect(monthWeekOf(DateTime(2026, 10, 14)).last, DateTime(2026, 10, 14));
      final last = monthWeekOf(DateTime(2026, 10, 30));
      expect(last.start, DateTime(2026, 10, 29));
      expect(last.last, DateTime(2026, 10, 31));
      expect(last.length, 3);
      expect(monthWeekOf(DateTime(2026, 2, 28)).length, 7); // Feb 22-28, no 5th week
      expect(monthWeekOf(DateTime(2028, 2, 29)).length, 1); // leap day week
    });

    test('Previous and next weeks', () {
      final first = monthWeekOf(DateTime(2026, 10, 3));
      final prev = previousMonthWeek(first);
      expect(prev.start, DateTime(2026, 9, 29));
      expect(prev.last, DateTime(2026, 9, 30));
      expect(nextMonthWeek(prev, DateTime(2026, 10, 7))!.start, DateTime(2026, 10, 1));
      expect(nextMonthWeek(first, DateTime(2026, 10, 7)), isNull, reason: 'no future weeks');
    });
  });

  group('Completion time', () {
    test('copyWith stamps completedAt on completion and clears it on undo', () {
      final open = Todo(title: 'x');
      final done = open.copyWith(completed: true);
      expect(done.completedAt, isNotNull);
      final edited = done.copyWith(title: 'y');
      expect(edited.completedAt, done.completedAt);
      expect(done.copyWith(completed: false).completedAt, isNull);
      expect(Todo.fromSqlite(done.toSqliteMap()).completedAt, done.completedAt);
    });

    test('Goals are never timed', () {
      final goal = Todo(title: 'g', type: 'goal');
      final tracker = TaskTrackerProvider();
      tracker.startTracking(goal);
      expect(tracker.isTracking, isFalse);
      tracker.dispose();
    });
  });
}
