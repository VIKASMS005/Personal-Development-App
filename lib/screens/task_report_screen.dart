import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_providers.dart';
import '../models/todo.dart';
import '../models/task_session.dart';
import '../widgets/ds/ds.dart';

String _formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) {
    return '${h}h ${m}m';
  }
  return '${m}m';
}

String _hours(double minutes) {
  if (minutes >= 60) return '${(minutes / 60).toStringAsFixed(minutes >= 600 ? 0 : 1)}h';
  return '${minutes.round()}m';
}

String _dateKey(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

/// Presentation-only roll-up of existing sessions and todos for a date range.
/// Uses the same rules as TodoProvider's reports: focus time comes from
/// sessions by date, and a task counts as completed on the day it was last updated.
class _PeriodStats {
  final int focusSeconds;
  final int sessionCount;
  final int tasksCompleted;
  final int goalsCompleted;
  final Map<String, int> categorySeconds;
  final Set<String> activeDays;

  _PeriodStats({
    required this.focusSeconds,
    required this.sessionCount,
    required this.tasksCompleted,
    required this.goalsCompleted,
    required this.categorySeconds,
    required this.activeDays,
  });

  factory _PeriodStats.of(List<TaskSession> sessions, List<Todo> todos, bool Function(String dateKey) inRange) {
    var seconds = 0, count = 0;
    final cats = <String, int>{};
    final days = <String>{};
    for (final s in sessions) {
      if (!inRange(s.date)) continue;
      seconds += s.durationSeconds;
      count++;
      days.add(s.date);
      final c = s.category.isNotEmpty ? s.category : 'General';
      cats[c] = (cats[c] ?? 0) + s.durationSeconds;
    }
    var tasks = 0, goals = 0;
    for (final t in todos) {
      if (!t.completed || !inRange(_dateKey(t.updatedAt))) continue;
      if (t.isGoal) {
        goals++;
      } else {
        tasks++;
      }
    }
    return _PeriodStats(
      focusSeconds: seconds,
      sessionCount: count,
      tasksCompleted: tasks,
      goalsCompleted: goals,
      categorySeconds: cats,
      activeDays: days,
    );
  }
}

class TaskReportScreen extends StatefulWidget {
  const TaskReportScreen({super.key});

  @override
  State<TaskReportScreen> createState() => _TaskReportScreenState();
}

class _TaskReportScreenState extends State<TaskReportScreen> {
  int _period = 0; // 0=Day, 1=Week, 2=Month, 3=Year, 4=All time
  DateTime _selectedDate = DateTime.now();

  void _previousDay() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
    });
  }

  void _nextDay() {
    setState(() {
      _selectedDate = _selectedDate.add(const Duration(days: 1));
    });
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final todoProv = context.watch<TodoProvider>();

    final List<Widget> content = switch (_period) {
      0 => _buildDay(todoProv),
      1 => _buildWeek(todoProv),
      2 => _buildMonth(todoProv),
      3 => _buildYear(todoProv),
      _ => _buildAllTime(todoProv),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: PageListView(
        clearFab: false,
        children: [
          AppSegmented<int>(
            segments: const {0: 'Day', 1: 'Week', 2: 'Month', 3: 'Year', 4: 'All'},
            selected: _period,
            onChanged: (v) => setState(() => _period = v),
          ),
          const SizedBox(height: AppSpacing.md),
          AnimatedSwitcher(
            duration: AppMotion.medium,
            child: Column(
              key: ValueKey(_period),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: content,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Day ───────────────────────────────────────────────────────────────────

  List<Widget> _buildDay(TodoProvider todoProv) {
    final report = todoProv.getDailyReport(_selectedDate);
    final totalSeconds = report['totalSeconds'] as int;
    final completedTasks = report['completedTasks'] as List<Todo>;
    final pendingTasks = report['pendingTasks'] as List<Todo>;
    final categoryTime = report['categoryTime'] as Map<String, int>;
    final completionRate = report['completionRate'] as int;
    final daySessions = report['daySessions'] as List<TaskSession>;
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());

    return [
      DateNavigator(
        label: isToday ? 'Today, ${DateFormat('MMM d').format(_selectedDate)}' : DateFormat('EEE, MMM d, yyyy').format(_selectedDate),
        onPrevious: _previousDay,
        onNext: _nextDay,
        onTapLabel: _pickDate,
      ),
      const SizedBox(height: AppSpacing.sm),
      StatRow(children: [
        StatCard(
          label: 'Focus time',
          value: _formatDuration(totalSeconds),
          caption: '${daySessions.length} ${daySessions.length == 1 ? 'session' : 'sessions'}',
          icon: Icons.timer_outlined,
        ),
        StatCard(
          label: 'Completion',
          value: '$completionRate%',
          caption: '${completedTasks.length} done · ${pendingTasks.length} open',
          icon: Icons.task_alt_rounded,
          tone: completionRate >= 70 ? StatusTone.success : StatusTone.warning,
        ),
      ]),
      if (isToday) ...[
        const SectionGap(),
        _comparisonCard(todoProv, 0),
      ],
      if (categoryTime.isNotEmpty) ...[
        const SectionGap(),
        _categoryCard(categoryTime, totalSeconds),
      ],
      const SectionGap(),
      SectionHeader(title: 'Completed', subtitle: '${completedTasks.length} on this day'),
      if (completedTasks.isEmpty)
        const EmptyState(
          compact: true,
          icon: Icons.task_alt_rounded,
          title: 'Nothing completed',
          subtitle: 'Tasks you finish on this day will show here.',
        )
      else
        _taskList(completedTasks, isDone: true),
      const SectionGap(),
      SectionHeader(title: 'Still open', subtitle: '${pendingTasks.length} across all dates'),
      if (pendingTasks.isEmpty)
        const EmptyState(
          compact: true,
          icon: Icons.celebration_outlined,
          title: 'All caught up',
          subtitle: 'There are no open tasks or goals.',
        )
      else
        _taskList(pendingTasks, isDone: false),
    ];
  }

  // ─── Week (last 7 days, same window as the improvement comparison) ───────

  List<Widget> _buildWeek(TodoProvider todoProv) {
    final now = DateTime.now();
    final days = List.generate(7, (i) => DateTime(now.year, now.month, now.day - 6 + i));
    final keys = days.map(_dateKey).toSet();
    final stats = _PeriodStats.of(todoProv.sessions, todoProv.todos, keys.contains);
    final perDay = days.map((d) {
      final k = _dateKey(d);
      return todoProv.sessions.where((s) => s.date == k).fold<int>(0, (a, s) => a + s.durationSeconds) / 60.0;
    }).toList();

    return [
      _summaryCard(
        label: 'Last 7 days',
        stats: stats,
        caption: 'Avg ${_hours(stats.focusSeconds / 60 / 7)} a day',
      ),
      const SectionGap(),
      _chartCard(
        title: 'Focus time per day',
        values: perDay,
        labels: days.map((d) => DateFormat('E').format(d).substring(0, 1)).toList(),
        highlight: 6,
        semantics: 'Focus minutes per day for the last 7 days',
      ),
      const SectionGap(),
      _comparisonCard(todoProv, 1),
      if (stats.categorySeconds.isNotEmpty) ...[
        const SectionGap(),
        _categoryCard(stats.categorySeconds, stats.focusSeconds),
      ],
    ];
  }

  // ─── Month (this calendar month) ─────────────────────────────────────────

  List<Widget> _buildMonth(TodoProvider todoProv) {
    final now = DateTime.now();
    final prefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final stats = _PeriodStats.of(todoProv.sessions, todoProv.todos, (k) => k.startsWith(prefix));
    final perDay = List<double>.filled(daysInMonth, 0);
    for (final s in todoProv.sessions) {
      if (!s.date.startsWith(prefix)) continue;
      final d = int.tryParse(s.date.substring(8)) ?? 0;
      if (d >= 1 && d <= daysInMonth) perDay[d - 1] += s.durationSeconds / 60.0;
    }

    return [
      _summaryCard(
        label: DateFormat('MMMM yyyy').format(now),
        stats: stats,
        caption: '${stats.activeDays.length} of ${now.day} days with focus time',
      ),
      const SectionGap(),
      _chartCard(
        title: 'Focus time per day',
        values: perDay,
        labels: List.generate(daysInMonth, (i) => (i == 0 || (i + 1) % 5 == 0) ? '${i + 1}' : ''),
        highlight: now.day - 1,
        disabled: {for (var i = now.day; i < daysInMonth; i++) i},
        semantics: 'Focus minutes per day this month',
      ),
      const SectionGap(),
      _comparisonCard(todoProv, 2),
      if (stats.categorySeconds.isNotEmpty) ...[
        const SectionGap(),
        _categoryCard(stats.categorySeconds, stats.focusSeconds),
      ],
    ];
  }

  // ─── Year (this calendar year) ───────────────────────────────────────────

  List<Widget> _buildYear(TodoProvider todoProv) {
    final now = DateTime.now();
    final prefix = '${now.year}-';
    final stats = _PeriodStats.of(todoProv.sessions, todoProv.todos, (k) => k.startsWith(prefix));
    final perMonth = List<double>.filled(12, 0);
    for (final s in todoProv.sessions) {
      if (!s.date.startsWith(prefix)) continue;
      final m = int.tryParse(s.date.substring(5, 7)) ?? 0;
      if (m >= 1 && m <= 12) perMonth[m - 1] += s.durationSeconds / 60.0;
    }
    final completedPerMonth = List<int>.filled(12, 0);
    for (final t in todoProv.todos) {
      if (t.completed && t.updatedAt.year == now.year) completedPerMonth[t.updatedAt.month - 1]++;
    }
    var best = -1;
    for (var i = 0; i < 12; i++) {
      if (perMonth[i] > 0 && (best < 0 || perMonth[i] > perMonth[best])) best = i;
    }

    return [
      _summaryCard(
        label: 'Year ${now.year}',
        stats: stats,
        caption: best >= 0
            ? 'Most focused month: ${DateFormat('MMMM').format(DateTime(now.year, best + 1))}'
            : '${stats.activeDays.length} days with focus time',
      ),
      const SectionGap(),
      _chartCard(
        title: 'Focus time per month',
        values: perMonth,
        labels: List.generate(12, (m) => DateFormat('MMMMM').format(DateTime(now.year, m + 1))),
        highlight: now.month - 1,
        disabled: {for (var m = now.month; m < 12; m++) m},
        semantics: 'Focus minutes per month in ${now.year}',
      ),
      const SectionGap(),
      _chartCard(
        title: 'Tasks and goals completed per month',
        values: completedPerMonth.map((v) => v.toDouble()).toList(),
        labels: List.generate(12, (m) => DateFormat('MMMMM').format(DateTime(now.year, m + 1))),
        highlight: now.month - 1,
        disabled: {for (var m = now.month; m < 12; m++) m},
        valueLabel: (v) => v.round().toString(),
        semantics: 'Items completed per month in ${now.year}',
      ),
      if (stats.categorySeconds.isNotEmpty) ...[
        const SectionGap(),
        _categoryCard(stats.categorySeconds, stats.focusSeconds),
      ],
    ];
  }

  // ─── All time ─────────────────────────────────────────────────────────────

  List<Widget> _buildAllTime(TodoProvider todoProv) {
    final stats = _PeriodStats.of(todoProv.sessions, todoProv.todos, (_) => true);
    final perDay = <String, int>{};
    for (final s in todoProv.sessions) {
      perDay[s.date] = (perDay[s.date] ?? 0) + s.durationSeconds;
    }
    MapEntry<String, int>? bestDay;
    for (final e in perDay.entries) {
      if (bestDay == null || e.value > bestDay.value) bestDay = e;
    }
    final bestDate = bestDay == null ? null : DateTime.tryParse(bestDay.key);

    if (todoProv.sessions.isEmpty && todoProv.todos.isEmpty) {
      return const [
        EmptyState(
          icon: Icons.insights_outlined,
          title: 'No history yet',
          subtitle: 'Track time on tasks and complete them to build your reports.',
        ),
      ];
    }

    return [
      _summaryCard(label: 'All time', stats: stats, caption: '${stats.activeDays.length} days with focus time'),
      const SectionGap(),
      StatRow(children: [
        StatCard(
          label: 'Best day',
          value: bestDay == null ? '—' : _formatDuration(bestDay.value),
          caption: bestDate == null ? 'No sessions yet' : DateFormat('MMM d, yyyy').format(bestDate),
          icon: Icons.emoji_events_outlined,
          tone: StatusTone.success,
        ),
        StatCard(
          label: 'Avg session',
          value: stats.sessionCount == 0 ? '—' : _formatDuration(stats.focusSeconds ~/ stats.sessionCount),
          caption: '${stats.sessionCount} sessions',
          icon: Icons.av_timer_rounded,
          tone: StatusTone.info,
        ),
      ]),
      if (stats.categorySeconds.isNotEmpty) ...[
        const SectionGap(),
        _categoryCard(stats.categorySeconds, stats.focusSeconds),
      ],
    ];
  }

  // ─── Building blocks ──────────────────────────────────────────────────────

  Widget _summaryCard({required String label, required _PeriodStats stats, String? caption}) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.labelMedium?.copyWith(color: context.colors.textSecondary)),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_formatDuration(stats.focusSeconds), style: context.text.displaySmall),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text('focused', style: context.text.bodyMedium?.copyWith(color: context.colors.textSecondary)),
            ],
          ),
          if (caption != null) Text(caption, style: context.text.bodySmall),
          const SizedBox(height: AppSpacing.md),
          MetricStrip(metrics: [
            Metric(value: '${stats.tasksCompleted}', label: 'tasks done', icon: Icons.task_alt_rounded),
            Metric(value: '${stats.goalsCompleted}', label: 'goals done', icon: Icons.flag_outlined),
            Metric(value: '${stats.sessionCount}', label: 'sessions', icon: Icons.timer_outlined),
          ]),
        ],
      ),
    );
  }

  Widget _chartCard({
    required String title,
    required List<double> values,
    required List<String> labels,
    int? highlight,
    Set<int> disabled = const {},
    String Function(double)? valueLabel,
    required String semantics,
  }) {
    final empty = values.every((v) => v <= 0);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.md),
          if (empty)
            const EmptyState(
              compact: true,
              icon: Icons.bar_chart_rounded,
              title: 'No activity in this period',
              subtitle: 'Start a timer on a task to see it here.',
            )
          else
            BarChart(
              values: values,
              labels: labels,
              highlightIndex: highlight,
              disabledIndices: disabled,
              valueLabel: valueLabel ?? _hours,
              height: 170,
              semanticsLabel: semantics,
            ),
        ],
      ),
    );
  }

  /// [horizon]: 0 = today vs yesterday, 1 = last 7 days vs prior 7, 2 = this month vs last.
  Widget _comparisonCard(TodoProvider todoProv, int horizon) {
    final comp = todoProv.getImprovementComparison();
    late final String title, curLabel, prevLabel, curText, prevText;
    late final double curValue, prevValue;
    late final int pct, curDone, prevDone;
    switch (horizon) {
      case 0:
        title = 'Compared with yesterday';
        curLabel = 'Today';
        prevLabel = 'Yesterday';
        curValue = (comp['todayMinutes'] as int).toDouble();
        prevValue = (comp['yesterdayMinutes'] as int).toDouble();
        curText = '${comp['todayMinutes']}m';
        prevText = '${comp['yesterdayMinutes']}m';
        pct = comp['dayTimeChangePct'] as int;
        curDone = comp['todayCompleted'] as int;
        prevDone = comp['yesterdayCompleted'] as int;
      case 1:
        title = 'Compared with the 7 days before';
        curLabel = 'Last 7 days';
        prevLabel = 'Previous 7';
        curValue = double.tryParse(comp['currentWeekHours'] as String) ?? 0;
        prevValue = double.tryParse(comp['priorWeekHours'] as String) ?? 0;
        curText = '${comp['currentWeekHours']}h';
        prevText = '${comp['priorWeekHours']}h';
        pct = comp['weekTimeChangePct'] as int;
        curDone = comp['currentWeekCompleted'] as int;
        prevDone = comp['priorWeekCompleted'] as int;
      default:
        title = 'Compared with last month';
        curLabel = 'This month';
        prevLabel = 'Last month';
        curValue = double.tryParse(comp['thisMonthHours'] as String) ?? 0;
        prevValue = double.tryParse(comp['prevMonthHours'] as String) ?? 0;
        curText = '${comp['thisMonthHours']}h';
        prevText = '${comp['prevMonthHours']}h';
        pct = comp['monthTimeChangePct'] as int;
        curDone = comp['thisMonthCompleted'] as int;
        prevDone = comp['prevMonthCompleted'] as int;
    }
    final up = pct > 0;
    final flat = pct == 0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: context.text.titleSmall)),
              StatusBadge(
                label: flat ? 'No change' : '${up ? '+' : '−'}${pct.abs()}% focus',
                tone: flat ? StatusTone.neutral : (up ? StatusTone.success : StatusTone.warning),
                icon: flat ? Icons.remove_rounded : (up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ComparisonBars(
            currentLabel: curLabel,
            currentValue: curValue,
            currentText: curText,
            previousLabel: prevLabel,
            previousValue: prevValue,
            previousText: prevText,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Completed: $curDone ${curLabel.toLowerCase()} · $prevDone ${prevLabel.toLowerCase()}', style: context.text.bodySmall),
        ],
      ),
    );
  }

  Widget _categoryCard(Map<String, int> categoryTime, int totalSeconds) {
    final entries = categoryTime.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Time by category', style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.md),
          for (final e in entries) ...[
            Row(
              children: [
                Icon(categoryIcon(e.key), size: AppSizes.iconSm, color: context.colors.textSecondary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text(e.key, style: context.text.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(
                  '${_formatDuration(e.value)} · ${totalSeconds > 0 ? (e.value * 100 / totalSeconds).round() : 0}%',
                  style: context.text.labelMedium?.copyWith(color: context.colors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            LinearMeter(value: totalSeconds > 0 ? e.value / totalSeconds : 0),
            if (e.key != entries.last.key) const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }

  Widget _taskList(List<Todo> tasks, {required bool isDone}) {
    final children = <Widget>[];
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      if (i > 0) children.add(const Divider(indent: 56));
      children.add(ListTile(
        leading: Icon(
          isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          color: isDone ? context.colors.success : context.colors.textSecondary,
          semanticLabel: isDone ? 'Completed' : 'Open',
        ),
        title: Text(
          task.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(decoration: isDone ? TextDecoration.lineThrough : null),
        ),
        subtitle: Text([
          task.isGoal ? 'Goal' : 'Task',
          if (task.category.isNotEmpty) task.category,
        ].join(' · ')),
        trailing: task.timeSpentSeconds > 0
            ? StatusBadge(label: _formatDuration(task.timeSpentSeconds), icon: Icons.timer_outlined, outlined: true)
            : null,
      ));
    }
    return AppCard(padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs), child: Column(children: children));
  }
}
