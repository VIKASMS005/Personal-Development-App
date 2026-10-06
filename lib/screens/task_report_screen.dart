import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/task_session.dart';
import '../providers/app_providers.dart';
import '../services/task_analytics.dart';
import '../theme/theme_context.dart';
import '../widgets/date_stepper.dart';

/// Task Analytics: how today, this week, this month and this year compare
/// with the period before. Tasks only; goals are not analysed here.
class TaskReportScreen extends StatefulWidget {
  const TaskReportScreen({super.key});

  @override
  State<TaskReportScreen> createState() => _TaskReportScreenState();
}

class _TaskReportScreenState extends State<TaskReportScreen> {
  AnalyticsPeriod _period = AnalyticsPeriod.daily;
  DateTime _anchor = clampToToday(DateTime.now());

  void _setAnchor(DateTime d) => setState(() => _anchor = clampToToday(d));

  @override
  Widget build(BuildContext context) {
    final todoProv = context.watch<TodoProvider>();
    final report = todoProv.analytics().report(_period, _anchor);
    final next = nextAnchor(_period, _anchor);

    return Scaffold(
      appBar: AppBar(title: const Text('Task Analytics')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<AnalyticsPeriod>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: AnalyticsPeriod.daily, label: Text('Daily')),
                    ButtonSegment(value: AnalyticsPeriod.weekly, label: Text('Weekly')),
                    ButtonSegment(value: AnalyticsPeriod.monthly, label: Text('Monthly')),
                    ButtonSegment(value: AnalyticsPeriod.yearly, label: Text('Yearly')),
                  ],
                  selected: {_period},
                  onSelectionChanged: (s) => setState(() {
                    _period = s.first;
                    _anchor = clampToToday(DateTime.now());
                  }),
                ),
              ),
              const SizedBox(height: 4),
              DateStepper(
                label: _periodLabel(report.range),
                onPrevious: () => _setAnchor(previousAnchor(_period, _anchor)),
                onNext: next == null ? null : () => _setAnchor(next),
                onTapLabel: () async {
                  final picked = await pickPastDate(context, _anchor);
                  if (picked != null) _setAnchor(picked);
                },
              ),
              const SizedBox(height: 8),
              if (report.current.total == 0 &&
                  report.current.focusSeconds == 0 &&
                  report.previous.total == 0 &&
                  report.previous.focusSeconds == 0)
                _EmptyPeriod(period: _period)
              else ...[
                _SummaryCard(report: report, previousLabel: _previousLabel()),
                const SizedBox(height: 12),
                _ChartCard(report: report),
                const SizedBox(height: 12),
                _ComparisonCard(report: report, previousLabel: _previousLabel()),
                if (_period == AnalyticsPeriod.daily) ...[
                  const SizedBox(height: 12),
                  _SessionsCard(sessions: todoProv.sessionsOn(_anchor)),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool get _isCurrentPeriod => rangeFor(_period, DateTime.now()).contains(_anchor);

  String _periodLabel(DateRange range) {
    switch (_period) {
      case AnalyticsPeriod.daily:
        return _isCurrentPeriod
            ? 'Today, ${DateFormat('MMM d').format(_anchor)}'
            : DateFormat('EEE, MMM d, y').format(_anchor);
      case AnalyticsPeriod.weekly:
        final last = range.end.subtract(const Duration(days: 1));
        final sameMonth = range.start.month == last.month;
        final span = sameMonth
            ? '${DateFormat('MMM d').format(range.start)}–${last.day}'
            : '${DateFormat('MMM d').format(range.start)} – ${DateFormat('MMM d').format(last)}';
        return _isCurrentPeriod ? 'This week, $span' : span;
      case AnalyticsPeriod.monthly:
        return DateFormat('MMMM y').format(range.start);
      case AnalyticsPeriod.yearly:
        return '${range.start.year}';
    }
  }

  String _previousLabel() {
    final current = _isCurrentPeriod;
    switch (_period) {
      case AnalyticsPeriod.daily:
        return current ? 'yesterday' : 'the day before';
      case AnalyticsPeriod.weekly:
        return current ? 'last week' : 'the week before';
      case AnalyticsPeriod.monthly:
        return current ? 'last month' : 'the month before';
      case AnalyticsPeriod.yearly:
        return current ? 'last year' : 'the year before';
    }
  }
}

String formatFocus(int seconds) {
  if (seconds > 0 && seconds < 60) return '<1m';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  return '${m}m';
}

/// Short duration for chart labels: "42m", "1.5h", "36h".
String _shortFocus(int seconds) {
  if (seconds < 3600) return formatFocus(seconds);
  final h = seconds / 3600;
  return h >= 10 ? '${h.round()}h' : '${h.toStringAsFixed(1)}h';
}

/// Main insight sentence, e.g. "You focused 25m more than yesterday."
String insightFor(PeriodReport r, String previousLabel) {
  final cur = r.current.focusSeconds;
  final prev = r.previous.focusSeconds;
  if (cur == 0 && prev == 0) return 'No focus time recorded yet.';
  if (prev == 0) return 'No focus time $previousLabel to compare with.';
  final diff = r.focusChange;
  if (diff.abs() < 60) return 'About the same focus time as $previousLabel.';
  final pct = r.focusChangePercent!;
  return diff > 0
      ? 'You focused ${formatFocus(diff)} more than $previousLabel (+$pct%).'
      : 'You focused ${formatFocus(-diff)} less than $previousLabel ($pct%).';
}

class _SummaryCard extends StatelessWidget {
  final PeriodReport report;
  final String previousLabel;
  const _SummaryCard({required this.report, required this.previousLabel});

  @override
  Widget build(BuildContext context) {
    final c = report.current;
    final colors = context.colors;
    final diff = report.focusChange;
    final up = diff >= 60;
    final down = diff <= -60;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Focus time', style: context.text.labelMedium?.copyWith(color: colors.textSecondary)),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatFocus(c.focusSeconds),
                      style: context.text.displaySmall?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                if (up || down) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: up ? colors.successContainer : colors.errorContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                            size: 14, color: up ? colors.success : colors.error),
                        const SizedBox(width: 2),
                        Text(formatFocus(diff.abs()),
                            style: context.text.labelMedium
                                ?.copyWith(color: up ? colors.success : colors.error, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              insightFor(report, previousLabel),
              style: context.text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: colors.divider),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                children: [
                  _Stat(label: 'Completed', value: c.completed, dot: colors.chartPrimary),
                  VerticalDivider(width: 1, color: colors.divider),
                  _Stat(label: 'Missed', value: c.missed, dot: colors.error),
                  VerticalDivider(width: 1, color: colors.divider),
                  _Stat(label: 'Pending', value: c.pending, dot: colors.chartMuted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final Color dot;
  const _Stat({required this.label, required this.value, required this.dot});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Expanded(
      child: Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: Column(
          children: [
            Text(
              '$value',
              style: context.text.headlineSmall?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelMedium?.copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final PeriodReport report;
  const _ChartCard({required this.report});

  String get _title {
    switch (report.period) {
      case AnalyticsPeriod.daily:
        return 'Focus time, last 7 days';
      case AnalyticsPeriod.weekly:
        return 'Focus time by day';
      case AnalyticsPeriod.monthly:
        return 'Focus time by week';
      case AnalyticsPeriod.yearly:
        return 'Focus time by month';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title, style: context.text.titleSmall?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            _BarChart(buckets: report.chart),
            if (report.period != AnalyticsPeriod.daily) ...[
              const SizedBox(height: 12),
              Text(
                'Average ${formatFocus(report.dailyAverageFocus)} per day',
                style: context.text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One bar of focus time per bucket; the current day/week/month is
/// highlighted, future buckets are left empty.
class _BarChart extends StatelessWidget {
  final List<ChartBucket> buckets;
  const _BarChart({required this.buckets});

  static const _barArea = 110.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final maxValue = buckets.fold<int>(1, (m, b) => b.counts.focusSeconds > m ? b.counts.focusSeconds : m);

    return Semantics(
      label: buckets
          .where((b) => !b.isFuture)
          .map((b) => '${b.label}: ${formatFocus(b.counts.focusSeconds)}')
          .join('; '),
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final b in buckets)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: buckets.length > 8 ? 2 : 4),
                child: Column(
                  children: [
                    SizedBox(
                      height: 14,
                      child: b.isFuture || b.counts.focusSeconds == 0
                          ? null
                          : FittedBox(
                              child: Text(_shortFocus(b.counts.focusSeconds),
                                  style: context.text.labelSmall?.copyWith(color: colors.textSecondary)),
                            ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      height: _barArea,
                      decoration: BoxDecoration(
                        color: colors.chartTrack,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.bottomCenter,
                      clipBehavior: Clip.antiAlias,
                      child: b.isFuture || b.counts.focusSeconds == 0
                          ? null
                          : Container(
                              height: _barArea * b.counts.focusSeconds / maxValue,
                              color: b.isCurrent ? colors.chartPrimary : colors.chartPrimary.withValues(alpha: 0.55),
                            ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        b.label,
                        maxLines: 1,
                        style: context.text.labelSmall?.copyWith(
                          color: b.isFuture
                              ? colors.textDisabled
                              : b.isCurrent
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                          fontWeight: b.isCurrent ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  final PeriodReport report;
  final String previousLabel;
  const _ComparisonCard({required this.report, required this.previousLabel});

  String _change(int seconds) {
    if (seconds.abs() < 60) return 'Same';
    return '${seconds > 0 ? '+' : '-'}${formatFocus(seconds.abs())}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cur = report.current;
    final prev = report.previous;
    final daily = report.period == AnalyticsPeriod.daily;

    final rows = <Widget>[
      _CompareRow(
        label: 'Focus time',
        previous: formatFocus(prev.focusSeconds),
        current: formatFocus(cur.focusSeconds),
        change: report.focusChange,
        changeText: _change(report.focusChange),
      ),
      if (!daily)
        _CompareRow(
          label: 'Daily average',
          previous: formatFocus(report.previousDailyAverageFocus),
          current: formatFocus(report.dailyAverageFocus),
          change: report.dailyAverageFocus - report.previousDailyAverageFocus,
          changeText: _change(report.dailyAverageFocus - report.previousDailyAverageFocus),
        ),
      _CompareRow(
        label: 'Sessions',
        previous: '${prev.sessionCount}',
        current: '${cur.sessionCount}',
        change: cur.sessionCount - prev.sessionCount,
        changeText: cur.sessionCount == prev.sessionCount
            ? 'Same'
            : '${cur.sessionCount > prev.sessionCount ? '+' : ''}${cur.sessionCount - prev.sessionCount}',
      ),
      _CompareRow(
        label: 'Longest session',
        previous: formatFocus(prev.longestSessionSeconds),
        current: formatFocus(cur.longestSessionSeconds),
        change: cur.longestSessionSeconds - prev.longestSessionSeconds,
        changeText: _change(cur.longestSessionSeconds - prev.longestSessionSeconds),
      ),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Time compared with $previousLabel',
                style: context.text.titleSmall?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700)),
            if (report.comparedDays != null) ...[
              const SizedBox(height: 2),
              Text(
                'First ${report.comparedDays} ${report.comparedDays == 1 ? 'day' : 'days'} of each period, so far',
                style: context.text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
            const SizedBox(height: 4),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: colors.divider),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Timer sessions saved for the selected day, with their real start and end.
class _SessionsCard extends StatelessWidget {
  final List<TaskSession> sessions;
  const _SessionsCard({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = sessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);
    final time = DateFormat.jm();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Timer sessions',
                      style: context.text.titleSmall?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700)),
                ),
                if (sessions.isNotEmpty)
                  Text('Total ${formatFocus(total)}',
                      style: context.text.labelMedium?.copyWith(color: colors.textSecondary, fontWeight: FontWeight.w700)),
              ],
            ),
            if (sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('No timer sessions on this day.',
                    style: context.text.bodyMedium?.copyWith(color: colors.textSecondary)),
              )
            else
              for (var i = 0; i < sessions.length; i++) ...[
                if (i > 0) Divider(height: 1, color: colors.divider),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(sessions[i].taskTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.bodyMedium
                                    ?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              '${time.format(sessions[i].startTime)} – ${time.format(sessions[i].endTime)}',
                              style: context.text.bodySmall?.copyWith(color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(formatFocus(sessions[i].durationSeconds),
                          style: context.text.bodyMedium?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  final String label;
  final String previous;
  final String current;

  /// Positive = better than before, negative = worse.
  final int change;
  final String? changeText;

  const _CompareRow({
    required this.label,
    required this.previous,
    required this.current,
    required this.change,
    required this.changeText,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tone = change > 0 ? colors.success : (change < 0 ? colors.error : colors.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodyMedium?.copyWith(color: colors.textSecondary)),
          ),
          Text(previous, style: context.text.bodyMedium?.copyWith(color: colors.textSecondary)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward_rounded, size: 14, color: colors.textDisabled),
          ),
          Text(current,
              style: context.text.bodyMedium?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700)),
          if (changeText != null)
            Container(
              width: 64,
              alignment: Alignment.centerRight,
              child: Text(
                changeText!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelMedium?.copyWith(color: tone, fontWeight: FontWeight.w700),
              ),
            )
          else
            const SizedBox(width: 64),
        ],
      ),
    );
  }
}

class _EmptyPeriod extends StatelessWidget {
  final AnalyticsPeriod period;
  const _EmptyPeriod({required this.period});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final what = {
      AnalyticsPeriod.daily: 'this day',
      AnalyticsPeriod.weekly: 'this week',
      AnalyticsPeriod.monthly: 'this month',
      AnalyticsPeriod.yearly: 'this year',
    }[period]!;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            Icon(Icons.insights_rounded, size: 40, color: colors.textDisabled),
            const SizedBox(height: 12),
            Text('No activity for $what',
                textAlign: TextAlign.center,
                style: context.text.titleSmall?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Timer sessions and tasks will show up here.',
                textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: colors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
