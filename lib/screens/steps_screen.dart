import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_providers.dart';
import '../models/step_record.dart';
import '../widgets/ds/ds.dart';

final _num = NumberFormat('#,###');

String _compact(double v) {
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k';
  return v.round().toString();
}

DateTime? _parseDate(String s) {
  final parts = s.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]), m = int.tryParse(parts[1]), d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

class StepsScreen extends StatefulWidget {
  const StepsScreen({super.key});

  @override
  State<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends State<StepsScreen> {
  int _selectedPeriod = 0; // 0=Day, 1=Week, 2=Month, 3=Year, 4=All-Time

  DateTime _normalizeDate(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  late DateTime _selectedDate;
  late DateTime _selectedWeekDate;
  late int _selectedMonth;
  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    final today = _normalizeDate(DateTime.now());
    _selectedDate = today;
    _selectedWeekDate = today;
    _selectedMonth = today.month;
    _selectedYear = today.year;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.uid != null) {
        // FIX M3: Use refreshStepData (lightweight) instead of loadStepData (full tracker
        // re-init that creates duplicate polling timers on every screen open).
        context.read<StepProvider>().refreshStepData(auth.uid!);
      }
    });
  }

  void _showSetGoalDialog(BuildContext context, StepProvider stepProv, String uid) {
    final controller = TextEditingController(text: '${stepProv.dailyGoal}');
    String? error;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Daily step goal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose a daily target that keeps you moving.', style: ctx.text.bodyMedium?.copyWith(color: ctx.colors.textSecondary)),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Target', suffixText: 'steps', errorText: error),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [4000, 6000, 8000, 10000, 12000].map((g) {
                  return ActionChip(
                    label: Text(_num.format(g)),
                    onPressed: () => setDialogState(() {
                      controller.text = '$g';
                      error = null;
                    }),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final val = int.tryParse(controller.text.trim());
                if (val != null && val > 0) {
                  await stepProv.updateDailyGoal(uid, val);
                  if (ctx.mounted) Navigator.pop(ctx);
                } else {
                  setDialogState(() => error = 'Enter a number above 0');
                }
              },
              child: const Text('Save goal'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final today = _normalizeDate(DateTime.now());
    final currentAnchor = _selectedPeriod == 1 ? _selectedWeekDate : _selectedDate;
    final initial = _normalizeDate(currentAnchor).isAfter(today) ? today : _normalizeDate(currentAnchor);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: today,
    );
    if (picked != null) {
      final norm = _normalizeDate(picked);
      setState(() {
        final safeDate = norm.isAfter(today) ? today : norm;
        _selectedDate = safeDate;
        _selectedWeekDate = safeDate;
        _selectedMonth = safeDate.month;
        _selectedYear = safeDate.year;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final stepProv = context.watch<StepProvider>();

    // Safety guard: Clamp selected date to today (guards against overnight rollover or stale state)
    final today = _normalizeDate(DateTime.now());
    if (_normalizeDate(_selectedDate).isAfter(today)) {
      _selectedDate = today;
      _selectedMonth = today.month;
      _selectedYear = today.year;
    }
    if (_normalizeDate(_selectedWeekDate).isAfter(today)) {
      _selectedWeekDate = today;
    }
    if (_selectedYear > today.year) {
      _selectedYear = today.year;
      _selectedMonth = today.month;
    } else if (_selectedYear == today.year && _selectedMonth > today.month) {
      _selectedMonth = today.month;
    }

    Future<void> onRefresh() async {
      try {
        final uid = auth.uid ?? 'local_user';
        final isToday = _normalizeDate(_selectedDate) == _normalizeDate(DateTime.now());

        if (_selectedPeriod == 0 && isToday) {
          // On today: force hardware sensor flush, baseline difference recalculation, and SQLite update
          await stepProv.refreshStepData(uid);
        } else {
          // Historical date, week, month, year, or all-time: reload SQLite database records
          // Note: _selectedDate, _selectedMonth, _selectedYear are strictly preserved!
          await stepProv.loadStepData(uid);
        }
      } catch (e) {
        debugPrint('[StepsScreen] Refresh error: $e');
      }
    }

    final List<Widget> content = switch (_selectedPeriod) {
      0 => _buildSpecificDayView(stepProv),
      1 => _buildWeeklyView(stepProv),
      2 => _buildSpecificMonthView(stepProv),
      3 => _buildSpecificYearView(stepProv),
      _ => _buildAllTimeView(stepProv),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Steps'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.flag_outlined, size: AppSizes.iconMd),
            label: const Text('Goal'),
            onPressed: () {
              if (auth.uid != null) {
                _showSetGoalDialog(context, stepProv, auth.uid!);
              }
            },
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: PageListView(
        clearFab: false,
        onRefresh: onRefresh,
        children: [
          AppSegmented<int>(
            segments: const {0: 'Day', 1: 'Week', 2: 'Month', 3: 'Year', 4: 'All'},
            selected: _selectedPeriod,
            onChanged: (v) => setState(() => _selectedPeriod = v),
          ),
          if (!stepProv.isAvailable) ...[
            const SizedBox(height: AppSpacing.sm),
            InlineBanner(
              tone: StatusTone.warning,
              icon: Icons.info_outline_rounded,
              message: !stepProv.hasHardwareSensor
                  ? 'This device has no step sensor, so steps can\'t be counted.'
                  : 'Allow Physical activity permission so steps are counted in the background.',
            ),
          ],
          if (_selectedPeriod < 4) ...[
            const SizedBox(height: AppSpacing.sm),
            _buildDateSelectorBar(),
          ],
          const SizedBox(height: AppSpacing.md),
          AnimatedSwitcher(
            duration: AppMotion.medium,
            child: Column(
              key: ValueKey(_selectedPeriod),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelectorBar() {
    final today = _normalizeDate(DateTime.now());
    final selectedDay = _normalizeDate(_selectedDate);

    final monday = DateTime(
      _selectedWeekDate.year,
      _selectedWeekDate.month,
      _selectedWeekDate.day - (_selectedWeekDate.weekday - 1),
    );
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    final isCurrentWeek = !today.isBefore(monday) && !today.isAfter(sunday);

    bool canGoNext = false;
    if (_selectedPeriod == 0) {
      canGoNext = selectedDay.isBefore(today);
    } else if (_selectedPeriod == 1) {
      canGoNext = !isCurrentWeek && sunday.isBefore(today);
    } else if (_selectedPeriod == 2) {
      canGoNext = (_selectedYear < today.year) ||
          (_selectedYear == today.year && _selectedMonth < today.month);
    } else if (_selectedPeriod == 3) {
      canGoNext = _selectedYear < today.year;
    }

    String label = '';
    if (_selectedPeriod == 0) {
      final isToday = selectedDay == today;
      label = isToday ? 'Today, ${DateFormat('MMM d').format(_selectedDate)}' : DateFormat('EEE, MMM d, yyyy').format(_selectedDate);
    } else if (_selectedPeriod == 1) {
      label = isCurrentWeek
          ? 'This week · ${DateFormat('MMM d').format(monday)} – ${DateFormat('MMM d').format(sunday)}'
          : '${DateFormat('MMM d').format(monday)} – ${DateFormat('MMM d, yyyy').format(sunday)}';
    } else if (_selectedPeriod == 2) {
      label = DateFormat('MMMM yyyy').format(DateTime(_selectedYear, _selectedMonth));
    } else if (_selectedPeriod == 3) {
      label = '$_selectedYear';
    }

    return DateNavigator(
      label: label,
      onTapLabel: _selectedPeriod <= 1 ? _pickDate : null,
      onPrevious: () {
        setState(() {
          if (_selectedPeriod == 0) {
            _selectedDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day - 1);
            _selectedMonth = _selectedDate.month;
            _selectedYear = _selectedDate.year;
          } else if (_selectedPeriod == 1) {
            _selectedWeekDate = _selectedWeekDate.subtract(const Duration(days: 7));
          } else if (_selectedPeriod == 2) {
            if (_selectedMonth == 1) {
              _selectedMonth = 12;
              _selectedYear--;
            } else {
              _selectedMonth--;
            }
          } else if (_selectedPeriod == 3) {
            _selectedYear--;
          }
        });
      },
      onNext: canGoNext
          ? () {
              setState(() {
                if (_selectedPeriod == 0) {
                  final nextDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day + 1);
                  if (!_normalizeDate(nextDay).isAfter(today)) {
                    _selectedDate = nextDay;
                    _selectedMonth = _selectedDate.month;
                    _selectedYear = _selectedDate.year;
                  }
                } else if (_selectedPeriod == 1) {
                  final nextWeek = _selectedWeekDate.add(const Duration(days: 7));
                  if (!_normalizeDate(nextWeek).isAfter(today)) {
                    _selectedWeekDate = nextWeek;
                  } else {
                    _selectedWeekDate = today;
                  }
                } else if (_selectedPeriod == 2) {
                  if (_selectedYear < today.year || (_selectedYear == today.year && _selectedMonth < today.month)) {
                    if (_selectedMonth == 12) {
                      _selectedMonth = 1;
                      _selectedYear++;
                    } else {
                      _selectedMonth++;
                    }
                  }
                } else if (_selectedPeriod == 3) {
                  if (_selectedYear < today.year) {
                    _selectedYear++;
                  }
                }
              });
            }
          : null,
    );
  }

  // ─── Shared week chart ─────────────────────────────────────────────────────

  Widget _weekChartCard(StepProvider stepProv, DateTime anchor, {required String title}) {
    final today = _normalizeDate(DateTime.now());
    final monday = DateTime(anchor.year, anchor.month, anchor.day - (anchor.weekday - 1));
    final weekRecords = stepProv.getWeekRecords(anchor);
    const dayNames = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    int? highlight;
    final disabled = <int>{};
    for (var i = 0; i < 7; i++) {
      final d = DateTime(monday.year, monday.month, monday.day + i);
      if (d == today) highlight = i;
      if (d.isAfter(today)) disabled.add(i);
    }
    final goal = stepProv.dailyGoal.toDouble();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: context.text.titleSmall)),
              Text('Goal ${_num.format(stepProv.dailyGoal)}', style: context.text.labelSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          BarChart(
            values: weekRecords.map((r) => r.stepCount.toDouble()).toList(),
            labels: dayNames,
            highlightIndex: highlight,
            goal: goal > 0 ? goal : null,
            disabledIndices: disabled,
            valueLabel: _compact,
            height: 170,
            semanticsLabel: 'Steps per day for $title',
          ),
          const SizedBox(height: AppSpacing.sm),
          ChartLegend(items: [
            (context.colors.chartPrimary, 'Today'),
            (context.colors.chartPrimary.withValues(alpha: 0.5), 'Goal met'),
            (context.colors.chartMuted, 'Below goal'),
          ]),
        ],
      ),
    );
  }

  Widget _dayTile(StepRecord r, {String? title, bool isToday = false, bool isFuture = false}) {
    final d = _parseDate(r.date);
    final dateLabel = title ?? (d != null ? DateFormat('EEE, MMM d').format(d) : r.date);
    return ListTile(
      leading: IconBadge(
        icon: isFuture
            ? Icons.schedule_rounded
            : r.isGoalReached
                ? Icons.check_rounded
                : Icons.directions_walk_rounded,
        tone: isFuture ? StatusTone.neutral : (r.isGoalReached ? StatusTone.success : StatusTone.neutral),
        size: 36,
      ),
      title: Row(
        children: [
          Flexible(child: Text(dateLabel, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (isToday) ...[
            const SizedBox(width: AppSpacing.xs),
            const StatusBadge(label: 'Today', tone: StatusTone.primary),
          ],
        ],
      ),
      subtitle: Text(
        isFuture
            ? 'Upcoming'
            : '${r.distanceKm.toStringAsFixed(2)} km · ${r.calories.toStringAsFixed(0)} kcal${r.isGoalReached ? ' · Goal met' : ''}',
      ),
      trailing: Text(
        isFuture ? '—' : _num.format(r.stepCount),
        style: context.text.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }

  Widget _listCard(List<Widget> tiles) {
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) children.add(const Divider(indent: 68));
      children.add(tiles[i]);
    }
    return AppCard(padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs), child: Column(children: children));
  }

  // ─── 1. Specific Day View ──────────────────────────────────────────────────

  List<Widget> _buildSpecificDayView(StepProvider stepProv) {
    final today = _normalizeDate(DateTime.now());
    final isToday = _normalizeDate(_selectedDate) == today;
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final history = stepProv.historyRecords;
    final record = isToday && stepProv.todayRecord != null
        ? stepProv.todayRecord!
        : history.firstWhere(
            (r) => r.date == dateStr,
            orElse: () => StepRecord(date: dateStr, stepCount: 0, goal: stepProv.dailyGoal),
          );

    final steps = record.stepCount;
    final goal = record.goal;
    final progress = goal > 0 ? (steps / goal).clamp(0.0, 1.0) : 0.0;
    final remaining = (goal - steps).clamp(0, goal);

    // Recent days (UI-only view of existing history): unique dates, newest first.
    final seen = <String>{dateStr};
    final recent = <StepRecord>[];
    for (final r in [...history]..sort((a, b) => b.date.compareTo(a.date))) {
      if (seen.add(r.date) && r.date.compareTo(dateStr) < 0) recent.add(r);
      if (recent.length == 5) break;
    }

    return [
      AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            ProgressRing(
              value: progress,
              size: 200,
              strokeWidth: 14,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_walk_rounded, color: context.scheme.primary, size: AppSizes.iconLg),
                  const SizedBox(height: AppSpacing.xxs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_num.format(steps), style: context.text.displaySmall),
                  ),
                  Text('of ${_num.format(goal)} steps', style: context.text.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            StatusBadge(
              label: record.isGoalReached ? 'Goal reached' : '${(progress * 100).toInt()}% · ${_num.format(remaining)} to go',
              tone: record.isGoalReached ? StatusTone.success : StatusTone.primary,
              icon: record.isGoalReached ? Icons.check_rounded : Icons.flag_outlined,
            ),
            const SizedBox(height: AppSpacing.lg),
            MetricStrip(metrics: [
              Metric(value: record.distanceKm.toStringAsFixed(2), label: 'km', icon: Icons.place_outlined),
              Metric(value: record.calories.toStringAsFixed(0), label: 'kcal', icon: Icons.local_fire_department_outlined),
              Metric(value: '${record.activeMinutes}', label: 'active min', icon: Icons.timer_outlined),
            ]),
          ],
        ),
      ),
      const SectionGap(),
      _weekChartCard(stepProv, _selectedDate, title: isToday ? 'This week' : 'That week'),
      const SectionGap(),
      const SectionHeader(title: 'History'),
      if (recent.isEmpty)
        const EmptyState(
          compact: true,
          icon: Icons.history_rounded,
          title: 'No earlier days yet',
          subtitle: 'Your daily totals will appear here.',
        )
      else
        _listCard(recent.map((r) => _dayTile(r)).toList()),
    ];
  }

  // ─── 2. Weekly View (Monday to Sunday) ─────────────────────────────────────

  List<Widget> _buildWeeklyView(StepProvider stepProv) {
    final today = _normalizeDate(DateTime.now());
    final monday = DateTime(
      _selectedWeekDate.year,
      _selectedWeekDate.month,
      _selectedWeekDate.day - (_selectedWeekDate.weekday - 1),
    );
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    final isCurrentWeek = !today.isBefore(monday) && !today.isAfter(sunday);

    final weekRecords = stepProv.getWeekRecords(_selectedWeekDate);
    final summary = stepProv.getWeekSummary(_selectedWeekDate);

    String dayValue(StepRecord? r, String fallback) {
      if (r == null || r.stepCount <= 0) return fallback;
      final d = _parseDate(r.date);
      return d != null ? DateFormat('EEEE').format(d) : r.date;
    }

    return [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(isCurrentWeek ? 'This week' : 'Week total', style: context.text.labelMedium?.copyWith(color: context.colors.textSecondary))),
                StatusBadge(
                  label: '${summary.goalsReached} of 7 goal days',
                  tone: summary.goalsReached > 0 ? StatusTone.success : StatusTone.neutral,
                  icon: Icons.flag_outlined,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(_num.format(summary.totalSteps), style: context.text.displaySmall))),
                const SizedBox(width: AppSpacing.xs),
                Text('steps', style: context.text.bodyMedium?.copyWith(color: context.colors.textSecondary)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            MetricStrip(metrics: [
              Metric(value: _num.format(summary.dailyAverage), label: 'daily avg', icon: Icons.speed_rounded),
              Metric(value: summary.totalDistanceKm.toStringAsFixed(1), label: 'km', icon: Icons.place_outlined),
              Metric(value: summary.totalCalories.toStringAsFixed(0), label: 'kcal', icon: Icons.local_fire_department_outlined),
            ]),
          ],
        ),
      ),
      const SectionGap(),
      _weekChartCard(stepProv, _selectedWeekDate, title: 'Daily steps'),
      const SectionGap(),
      StatRow(children: [
        StatCard(
          label: 'Best day',
          value: dayValue(summary.highestDay, 'None yet'),
          caption: summary.highestDay != null && summary.highestDay!.stepCount > 0
              ? '${_num.format(summary.highestDay!.stepCount)} steps'
              : null,
          icon: Icons.emoji_events_outlined,
          tone: StatusTone.success,
        ),
        StatCard(
          label: 'Lowest day',
          value: dayValue(summary.lowestDay, summary.daysElapsed > 0 ? '0 steps' : 'None yet'),
          caption: summary.lowestDay != null && summary.lowestDay!.stepCount > 0
              ? '${_num.format(summary.lowestDay!.stepCount)} steps'
              : null,
          icon: Icons.trending_down_rounded,
          tone: StatusTone.neutral,
        ),
      ]),
      const SectionGap(),
      const SectionHeader(title: 'Day by day'),
      _listCard(List.generate(7, (idx) {
        final dayDate = DateTime(monday.year, monday.month, monday.day + idx);
        return _dayTile(
          weekRecords[idx],
          title: DateFormat('EEE, MMM d').format(dayDate),
          isToday: _normalizeDate(dayDate) == today,
          isFuture: _normalizeDate(dayDate).isAfter(today),
        );
      })),
    ];
  }

  // ─── 3. Specific Month View ────────────────────────────────────────────────

  List<Widget> _buildSpecificMonthView(StepProvider stepProv) {
    final history = stepProv.historyRecords;
    final prefix = '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';

    // Canonical aggregation by calendar date: guaranteed exactly 1 entry per date.
    // FIX: Use MAX step count when de-duplicating (not SUM) — historyRecords can contain
    // both a legacy in-memory record and the DB record, both representing the same daily total.
    final Map<String, StepRecord> dailyMap = {};
    for (final r in history) {
      if (!r.date.startsWith(prefix)) continue;
      if (dailyMap.containsKey(r.date)) {
        final existing = dailyMap[r.date]!;
        // Take the record with higher step count — both are daily totals, not increments
        if (r.stepCount > existing.stepCount) {
          dailyMap[r.date] = r;
        }
      } else {
        dailyMap[r.date] = r;
      }
    }

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (stepProv.todayRecord != null && todayStr.startsWith(prefix)) {
      dailyMap[todayStr] = stepProv.todayRecord!;
    }

    final monthRecords = dailyMap.values.toList()..sort((a, b) => b.date.compareTo(a.date));

    final totalSteps = monthRecords.fold(0, (sum, r) => sum + r.stepCount);
    final daysInMonth = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    final avgSteps = daysInMonth > 0 ? (totalSteps / daysInMonth).round() : 0;
    final goalsReached = monthRecords.where((r) => r.isGoalReached).length;
    final totalKm = monthRecords.fold(0.0, (sum, r) => sum + r.distanceKm);

    // Per-day values for the month chart.
    final perDay = List<double>.generate(daysInMonth, (i) {
      final key = '$prefix-${(i + 1).toString().padLeft(2, '0')}';
      return (dailyMap[key]?.stepCount ?? 0).toDouble();
    });
    final today = _normalizeDate(DateTime.now());
    final isThisMonth = today.year == _selectedYear && today.month == _selectedMonth;
    final disabled = <int>{
      for (var i = 0; i < daysInMonth; i++)
        if (DateTime(_selectedYear, _selectedMonth, i + 1).isAfter(today)) i,
    };

    return [
      StatRow(children: [
        StatCard(label: 'Total steps', value: _num.format(totalSteps), icon: Icons.directions_walk_rounded),
        StatCard(label: 'Daily average', value: _num.format(avgSteps), unit: '/day', icon: Icons.speed_rounded, tone: StatusTone.info),
      ]),
      const SizedBox(height: AppSpacing.sm),
      StatRow(children: [
        StatCard(label: 'Goal days', value: '$goalsReached', unit: '/ $daysInMonth', icon: Icons.flag_outlined, tone: StatusTone.success),
        StatCard(label: 'Distance', value: totalKm.toStringAsFixed(1), unit: 'km', icon: Icons.route_outlined, tone: StatusTone.neutral),
      ]),
      const SectionGap(),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Daily steps', style: context.text.titleSmall),
            const SizedBox(height: AppSpacing.md),
            BarChart(
              values: perDay,
              labels: List.generate(daysInMonth, (i) => (i == 0 || (i + 1) % 5 == 0) ? '${i + 1}' : ''),
              highlightIndex: isThisMonth ? today.day - 1 : null,
              goal: stepProv.dailyGoal > 0 ? stepProv.dailyGoal.toDouble() : null,
              disabledIndices: disabled,
              valueLabel: _compact,
              height: 150,
              semanticsLabel: 'Steps per day in ${DateFormat('MMMM').format(DateTime(_selectedYear, _selectedMonth))}',
            ),
          ],
        ),
      ),
      const SectionGap(),
      const SectionHeader(title: 'Daily activity'),
      if (monthRecords.isEmpty)
        const EmptyState(
          compact: true,
          icon: Icons.directions_walk_rounded,
          title: 'No steps recorded',
          subtitle: 'There\'s no step activity for this month.',
        )
      else
        _listCard(monthRecords.map((r) => _dayTile(r, isToday: r.date == todayStr)).toList()),
    ];
  }

  // ─── 4. Year View (Jan–Dec) ────────────────────────────────────────────────

  List<Widget> _buildSpecificYearView(StepProvider stepProv) {
    final history = stepProv.historyRecords;
    final yearPrefix = '$_selectedYear-';
    final yearRecords = history.where((r) => r.date.startsWith(yearPrefix)).toList();

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final List<StepRecord> effectiveYearRecords = [];
    final seenDates = <String>{};
    if (stepProv.todayRecord != null && todayStr.startsWith(yearPrefix)) {
      effectiveYearRecords.add(stepProv.todayRecord!);
      seenDates.add(todayStr);
    }
    for (final r in yearRecords) {
      if (!seenDates.contains(r.date)) {
        effectiveYearRecords.add(r);
        seenDates.add(r.date);
      }
    }

    final List<int> monthlyTotals = List.generate(12, (m) {
      final monthStr = '$_selectedYear-${(m + 1).toString().padLeft(2, '0')}';
      return effectiveYearRecords.where((r) => r.date.startsWith(monthStr)).fold(0, (sum, r) => sum + r.stepCount);
    });

    final totalYearSteps = monthlyTotals.fold(0, (sum, val) => sum + val);

    int bestMonthIdx = 0;
    int bestMonthVal = 0;
    for (int i = 0; i < 12; i++) {
      if (monthlyTotals[i] > bestMonthVal) {
        bestMonthVal = monthlyTotals[i];
        bestMonthIdx = i;
      }
    }
    final bestMonthName = DateFormat('MMMM').format(DateTime(_selectedYear, bestMonthIdx + 1));
    final now = DateTime.now();
    final activeDays = effectiveYearRecords.where((r) => r.stepCount > 0).length;
    final goalDays = effectiveYearRecords.where((r) => r.isGoalReached).length;
    final disabled = <int>{
      if (_selectedYear == now.year)
        for (var m = now.month; m < 12; m++) m,
    };

    return [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total in $_selectedYear', style: context.text.labelMedium?.copyWith(color: context.colors.textSecondary)),
            const SizedBox(height: AppSpacing.xs),
            FittedBox(fit: BoxFit.scaleDown, child: Text(_num.format(totalYearSteps), style: context.text.displaySmall)),
            const SizedBox(height: AppSpacing.xs),
            if (bestMonthVal > 0)
              StatusBadge(
                label: 'Best month: $bestMonthName · ${_compact(bestMonthVal.toDouble())}',
                tone: StatusTone.success,
                icon: Icons.emoji_events_outlined,
              ),
            const SizedBox(height: AppSpacing.md),
            MetricStrip(metrics: [
              Metric(value: '$activeDays', label: 'active days'),
              Metric(value: '$goalDays', label: 'goal days'),
              Metric(value: _num.format(activeDays > 0 ? (totalYearSteps / activeDays).round() : 0), label: 'avg / active day'),
            ]),
          ],
        ),
      ),
      const SectionGap(),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Monthly steps', style: context.text.titleSmall),
            const SizedBox(height: AppSpacing.md),
            BarChart(
              values: monthlyTotals.map((v) => v.toDouble()).toList(),
              labels: List.generate(12, (m) => DateFormat('MMMMM').format(DateTime(_selectedYear, m + 1))),
              highlightIndex: bestMonthVal > 0 ? bestMonthIdx : null,
              disabledIndices: disabled,
              valueLabel: _compact,
              height: 180,
              semanticsLabel: 'Steps per month in $_selectedYear',
            ),
            const SizedBox(height: AppSpacing.sm),
            ChartLegend(items: [
              (context.colors.chartPrimary, 'Best month'),
              (context.colors.chartMuted, 'Other months'),
            ]),
          ],
        ),
      ),
    ];
  }

  // ─── 5. All-Time View ──────────────────────────────────────────────────────

  List<Widget> _buildAllTimeView(StepProvider stepProv) {
    return [
      AppCard(
        emphasized: true,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            IconBadge(icon: Icons.workspace_premium_outlined, size: 48),
            const SizedBox(height: AppSpacing.sm),
            Text('Lifetime steps', style: context.text.labelMedium?.copyWith(color: context.colors.textSecondary)),
            const SizedBox(height: AppSpacing.xxs),
            FittedBox(fit: BoxFit.scaleDown, child: Text(_num.format(stepProv.lifetimeSteps), style: context.text.displaySmall)),
          ],
        ),
      ),
      const SectionGap(),
      StatRow(children: [
        StatCard(
          label: 'Total distance',
          value: stepProv.lifetimeDistanceKm.toStringAsFixed(1),
          unit: 'km',
          icon: Icons.map_outlined,
          tone: StatusTone.info,
        ),
        StatCard(
          label: 'Best single day',
          value: _num.format(stepProv.bestSingleDaySteps),
          unit: 'steps',
          icon: Icons.bolt_rounded,
          tone: StatusTone.success,
        ),
      ]),
    ];
  }
}
