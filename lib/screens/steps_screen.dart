import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/app_providers.dart';
import '../models/step_record.dart';
import '../utils/app_colors.dart';
import '../utils/month_weeks.dart';

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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.flag_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Set Daily Step Goal'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose your daily target to stay active and healthy.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Target Steps',
                suffixText: 'steps',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [4000, 6000, 8000, 10000, 12000].map((g) {
                return ActionChip(
                  label: Text('$g'),
                  onPressed: () => controller.text = '$g',
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final val = int.tryParse(controller.text.trim());
              if (val != null && val > 0) {
                await stepProv.updateDailyGoal(uid, val);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Save Goal'),
          ),
        ],
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Step Counter & Activity'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Adjust Daily Goal',
            onPressed: () {
              if (auth.uid != null) {
                _showSetGoalDialog(context, stepProv, auth.uid!);
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              // 1. Period Selector (Day / Week / Month / Year / All-Time)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      _buildPeriodTab(0, 'Day'),
                      _buildPeriodTab(1, 'Week'),
                      _buildPeriodTab(2, 'Month'),
                      _buildPeriodTab(3, 'Year'),
                      _buildPeriodTab(4, 'All-Time'),
                    ],
                  ),
                ),
              ),

              if (!stepProv.isAvailable)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          !stepProv.hasHardwareSensor
                              ? 'Hardware step sensor is not available on this device.'
                              : 'Activity Recognition permission needed for background step counting.',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.warning),
                        ),
                      ),
                    ],
                  ),
                ),

              // 2. Interactive Date Navigation Bar (if not All-Time)
              if (_selectedPeriod < 4)
                _buildDateSelectorBar(theme, isDark),

              // 3. Main Analytics Content
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    try {
                      final uid = auth.uid ?? 'local_user';

                      // Re-reads the live count and every stored day. (loadStepData
                      // would restart the tracker and rewrite goals on every pull.)
                      await stepProv.refreshStepData(uid);
                    } catch (e) {
                      debugPrint('[StepsScreen] Refresh error: $e');
                    }
                  },
                  child: _selectedPeriod == 0
                      ? _buildSpecificDayView(theme, isDark, stepProv)
                      : _selectedPeriod == 1
                          ? _buildWeeklyView(theme, isDark, stepProv)
                          : _selectedPeriod == 2
                              ? _buildSpecificMonthView(theme, isDark, stepProv)
                              : _selectedPeriod == 3
                                  ? _buildSpecificYearView(theme, isDark, stepProv)
                                  : _buildAllTimeView(theme, isDark, stepProv),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodTab(int index, String label) {
    final isSelected = _selectedPeriod == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedPeriod = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 13,
              color: isSelected ? Colors.white : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelectorBar(ThemeData theme, bool isDark) {
    final today = _normalizeDate(DateTime.now());
    final selectedDay = _normalizeDate(_selectedDate);

    // Weeks stay inside their month (1–7, 8–14, ...); see month_weeks.dart.
    final week = monthWeekOf(_selectedWeekDate);
    final monday = week.start;
    final sunday = week.last;
    final isCurrentWeek = week.contains(today);

    bool canGoNext = false;
    if (_selectedPeriod == 0) {
      canGoNext = selectedDay.isBefore(today);
    } else if (_selectedPeriod == 1) {
      canGoNext = nextMonthWeek(week, today) != null;
    } else if (_selectedPeriod == 2) {
      canGoNext = (_selectedYear < today.year) ||
          (_selectedYear == today.year && _selectedMonth < today.month);
    } else if (_selectedPeriod == 3) {
      canGoNext = _selectedYear < today.year;
    }

    String label = '';
    if (_selectedPeriod == 0) {
      final isToday = selectedDay == today;
      label = isToday
          ? 'Today (${DateFormat('MMM d, yyyy').format(_selectedDate)})'
          : DateFormat('EEEE, MMM d, yyyy').format(_selectedDate);
    } else if (_selectedPeriod == 1) {
      label = isCurrentWeek
          ? 'This Week (${DateFormat('MMM d').format(monday)} – ${DateFormat('MMM d').format(sunday)})'
          : 'Week of ${DateFormat('MMM d').format(monday)} – ${DateFormat('MMM d, yyyy').format(sunday)}';
    } else if (_selectedPeriod == 2) {
      label = DateFormat('MMMM yyyy').format(DateTime(_selectedYear, _selectedMonth));
    } else if (_selectedPeriod == 3) {
      label = 'Year $_selectedYear';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 24),
            tooltip: 'Previous',
            onPressed: () {
              setState(() {
                if (_selectedPeriod == 0) {
                  _selectedDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day - 1);
                  _selectedMonth = _selectedDate.month;
                  _selectedYear = _selectedDate.year;
                } else if (_selectedPeriod == 1) {
                  _selectedWeekDate = previousMonthWeek(monthWeekOf(_selectedWeekDate)).start;
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
          ),
          Flexible(
            child: InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 24),
            tooltip: canGoNext ? 'Next' : null,
            onPressed: canGoNext
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
                        final nextWeek = nextMonthWeek(monthWeekOf(_selectedWeekDate), today);
                        _selectedWeekDate = nextWeek == null
                            ? today
                            : (nextWeek.contains(today) ? today : nextWeek.start);
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
          ),
        ],
      ),
    );
  }

  // ─── 1. Specific Day View ──────────────────────────────────────────────────

  Widget _buildSpecificDayView(ThemeData theme, bool isDark, StepProvider stepProv) {
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
    // A past day with nothing stored is "no data", not a walked 0.
    final hasData = isToday || stepProv.hasRecordFor(dateStr);
    final cal = record.calories;
    final km = record.distanceKm;
    final mins = record.activeMinutes;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        // Circular Progress Hero Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF0F2E1E), const Color(0xFF071910)]
                  : [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              SizedBox(
                width: 190,
                height: 190,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 170,
                      height: 170,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 14,
                        strokeCap: StrokeCap.round,
                        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.directions_walk_rounded, color: AppColors.primary, size: 28),
                        const SizedBox(height: 4),
                        Text(
                          hasData ? NumberFormat('#,###').format(steps) : 'No data',
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1),
                        ),
                        Text(
                          '/ ${NumberFormat('#,###').format(goal)} steps',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            hasData ? '${(progress * 100).toInt()}% Goal Reached' : 'Nothing recorded this day',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: _MetricItem(
                    icon: Icons.local_fire_department_rounded,
                    color: Colors.orange,
                    value: hasData ? cal.toStringAsFixed(1) : '—',
                    unit: 'kcal',
                    label: 'Est. burned',
                    ),
                  ),
                  Container(height: 36, width: 1, color: Colors.black12),
                  Expanded(
                    child: _MetricItem(
                    icon: Icons.place_rounded,
                    color: AppColors.secondary,
                    value: hasData ? km.toStringAsFixed(2) : '—',
                    unit: 'km',
                    label: 'Est. distance',
                    ),
                  ),
                  Container(height: 36, width: 1, color: Colors.black12),
                  Expanded(
                    child: _MetricItem(
                    icon: Icons.timer_outlined,
                    color: Colors.purple,
                    value: hasData ? '$mins' : '—',
                    unit: 'mins',
                    label: 'Est. active',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ).animate().fadeIn(duration: 300.ms),
      ],
    );
  }

  // ─── 2. Weekly View (7-Day Bar Chart: Monday to Sunday) ─────────────────────

  Widget _buildWeeklyView(ThemeData theme, bool isDark, StepProvider stepProv) {
    final now = DateTime.now();
    final today = _normalizeDate(now);
    final week = monthWeekOf(_selectedWeekDate);
    final monday = week.start;
    final sunday = week.last;
    final isCurrentWeek = week.contains(today);

    final weekRecords = stepProv.getWeekRecords(_selectedWeekDate);
    final summary = stepProv.getWeekSummary(_selectedWeekDate);
    final goal = stepProv.dailyGoal;

    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    // Maximum steps for scaling bars
    final maxStepsInWeek = weekRecords.map((r) => r.stepCount).fold(0, (a, b) => a > b ? a : b);
    final chartMax = max(goal, maxStepsInWeek);
    final effectiveChartMax = chartMax > 0 ? chartMax : 6000;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        // 1. Weekly Performance Summary Hero Card
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF0F2E28), const Color(0xFF071915)]
                  : [const Color(0xFFE0F2F1), const Color(0xFFB2DFDB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                   child: Text(
                    isCurrentWeek ? "THIS WEEK'S TOTAL" : 'WEEK TOTAL',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.teal.shade900,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${summary.goalsReached} / ${weekRecords.length} Goals',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    NumberFormat('#,###').format(summary.totalSteps),
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'steps',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: _MetricItem(
                    icon: Icons.speed_rounded,
                    color: AppColors.secondary,
                    value: NumberFormat('#,###').format(summary.dailyAverage),
                    unit: 'steps/d',
                    label: 'Daily Avg',
                    ),
                  ),
                  Container(height: 36, width: 1, color: Colors.black12),
                  Expanded(
                    child: _MetricItem(
                    icon: Icons.place_rounded,
                    color: Colors.teal,
                    value: summary.totalDistanceKm.toStringAsFixed(1),
                    unit: 'km',
                    label: 'Distance',
                    ),
                  ),
                  Container(height: 36, width: 1, color: Colors.black12),
                  Expanded(
                    child: _MetricItem(
                    icon: Icons.local_fire_department_rounded,
                    color: Colors.orange,
                    value: summary.totalCalories.toStringAsFixed(0),
                    unit: 'kcal',
                    label: 'Calories',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ).animate().fadeIn(duration: 300.ms),

        const SizedBox(height: 18),

        // 2. 7-Day Bar Chart Container (Monday to Sunday)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Flexible(
                    child: Text(
                      'Daily Activity This Week',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Goal: ${NumberFormat('#,###').format(goal)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // The 7 Bars
              SizedBox(
                height: 200,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(weekRecords.length, (i) {
                    final dayDate = DateTime(monday.year, monday.month, monday.day + i);
                    final isDayToday = _normalizeDate(dayDate) == today;
                    final isFuture = _normalizeDate(dayDate).isAfter(today);
                    final record = weekRecords[i];
                    final steps = record.stepCount;
                    // A day with no stored count shows "—" and no bar, not a made-up 0.
                    final hasData = stepProv.hasRecordFor(record.date);
                    final isGoalMet = hasData && record.isGoalReached;
                    final barFactor = isFuture || !hasData || steps == 0
                        ? 0.0
                        : (steps / effectiveChartMax).clamp(0.04, 1.0);

                    final dayLabel = dayNames[dayDate.weekday - 1];
                    final dateNum = '${dayDate.day}';

                    String stepLabel = '—';
                    if (!isFuture && hasData) {
                      if (steps >= 1000) {
                        stepLabel = '${(steps / 1000).toStringAsFixed(1)}k';
                      } else {
                        stepLabel = '$steps';
                      }
                    }

                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Step Count Label above Bar
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              stepLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isDayToday ? FontWeight.w900 : FontWeight.w700,
                                color: isDayToday
                                    ? AppColors.primary
                                    : isGoalMet
                                        ? const Color(0xFF10B981)
                                        : theme.colorScheme.onSurface.withValues(alpha: isFuture ? 0.3 : 0.6),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Vertical Bar Stack
                          Expanded(
                            child: LayoutBuilder(
                              builder: (ctx, constraints) {
                                final maxHeight = constraints.maxHeight;
                                final barHeight = isFuture ? 6.0 : (maxHeight * barFactor);

                                return Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    // Background track
                                    Container(
                                      width: 22,
                                      height: maxHeight,
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white.withValues(alpha: 0.04)
                                            : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                    ),
                                    // Active Bar
                                    Container(
                                      width: 22,
                                      height: barHeight,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: isFuture
                                              ? [Colors.transparent, Colors.transparent]
                                              : [AppColors.primaryLight, AppColors.primary],
                                        ),
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: isGoalMet && barHeight >= 22
                                          ? const Align(
                                              alignment: Alignment.topCenter,
                                              child: Padding(
                                                padding: EdgeInsets.only(top: 2),
                                                child: Icon(
                                                  Icons.check_rounded,
                                                  size: 14,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            )
                                          : null,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Day Label & Date Number
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: isDayToday
                                ? BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  )
                                : null,
                            child: Column(
                              children: [
                                Text(
                                  dayLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isDayToday ? FontWeight.w900 : FontWeight.w700,
                                    color: isDayToday
                                        ? AppColors.primary
                                        : theme.colorScheme.onSurface.withValues(alpha: isFuture ? 0.35 : 0.8),
                                  ),
                                ),
                                Text(
                                  dateNum,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: isDayToday
                                        ? AppColors.primary
                                        : theme.colorScheme.onSurface.withValues(alpha: isFuture ? 0.25 : 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // 3. Weekly Highlights Cards (Highest / Lowest Day)
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Highest Day',
                value: summary.highestDay != null && summary.highestDay!.stepCount > 0
                    ? (() {
                        final parts = summary.highestDay!.date.split('-');
                        final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
                        return '${DateFormat('EEEE').format(d)}\n${NumberFormat('#,###').format(summary.highestDay!.stepCount)} steps';
                      })()
                    : 'None yet',
                icon: Icons.emoji_events_rounded,
                color: Colors.amber.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: 'Lowest Day',
                value: summary.lowestDay != null && summary.lowestDay!.stepCount > 0
                    ? (() {
                        final parts = summary.lowestDay!.date.split('-');
                        final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
                        return '${DateFormat('EEEE').format(d)}\n${NumberFormat('#,###').format(summary.lowestDay!.stepCount)} steps';
                      })()
                    : (summary.daysElapsed > 0 ? '0 steps' : 'None yet'),
                icon: Icons.trending_down_rounded,
                color: Colors.blueGrey,
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        // 4. Daily Breakdown List (Monday to Sunday)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Week Breakdown (${DateFormat('MMM d').format(monday)} – ${DateFormat('MMM d, yyyy').format(sunday)})',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 14),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: weekRecords.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, idx) {
                  final dayDate = DateTime(monday.year, monday.month, monday.day + idx);
                  final isDayToday = _normalizeDate(dayDate) == today;
                  final isFuture = _normalizeDate(dayDate).isAfter(today);
                  final r = weekRecords[idx];

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: isFuture
                          ? Colors.grey.withValues(alpha: 0.05)
                          : r.isGoalReached
                              ? AppColors.primary.withValues(alpha: 0.15)
                              : Colors.grey.withValues(alpha: 0.1),
                      child: Icon(
                        isFuture
                            ? Icons.schedule_rounded
                            : r.isGoalReached
                                ? Icons.check_circle_rounded
                                : Icons.directions_walk_rounded,
                        color: isFuture
                            ? Colors.grey.shade400
                            : r.isGoalReached
                                ? AppColors.primary
                                : Colors.grey,
                        size: 20,
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(
                          DateFormat('EEEE, MMM d').format(dayDate),
                          style: TextStyle(
                            fontWeight: isDayToday ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 14,
                            color: isDayToday ? AppColors.primary : null,
                          ),
                        ),
                        if (isDayToday) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'TODAY',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      isFuture
                          ? 'Upcoming'
                          : !stepProv.hasRecordFor(r.date)
                              ? 'No step data recorded'
                              : '${r.distanceKm.toStringAsFixed(2)} km · ${r.calories.toStringAsFixed(0)} kcal',
                      style: TextStyle(
                        fontSize: 12,
                        color: isFuture ? theme.colorScheme.onSurface.withValues(alpha: 0.4) : null,
                      ),
                    ),
                    trailing: Text(
                      isFuture || !stepProv.hasRecordFor(r.date) ? '—' : '${NumberFormat('#,###').format(r.stepCount)} steps',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: isFuture
                            ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                            : r.isGoalReached
                                ? AppColors.primary
                                : null,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── 3. Specific Month View ────────────────────────────────────────────────

  Widget _buildSpecificMonthView(ThemeData theme, bool isDark, StepProvider stepProv) {
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

    final monthRecords = dailyMap.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final totalSteps = monthRecords.fold(0, (sum, r) => sum + r.stepCount);
    // Average over the days that have happened: the current month is not
    // divided by days that are still to come.
    final now = DateTime.now();
    final isCurrentMonth = _selectedYear == now.year && _selectedMonth == now.month;
    final daysInMonth = isCurrentMonth
        ? now.day
        : DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    final avgSteps = daysInMonth > 0 ? (totalSteps / daysInMonth).round() : 0;
    final goalsReached = monthRecords.where((r) => r.isGoalReached).length;
    final totalKm = monthRecords.fold(0.0, (sum, r) => sum + r.distanceKm);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Total Monthly Steps',
                value: NumberFormat('#,###').format(totalSteps),
                icon: Icons.calendar_month_rounded,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: 'Daily Average',
                value: '${NumberFormat('#,###').format(avgSteps)}/day',
                icon: Icons.speed_rounded,
                color: AppColors.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Goal Hit Days',
                value: '$goalsReached / $daysInMonth days',
                icon: Icons.emoji_events_rounded,
                color: Colors.amber.shade700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: 'Total Distance',
                value: '${totalKm.toStringAsFixed(1)} km',
                icon: Icons.route_rounded,
                color: Colors.teal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Daily Activity List in Month
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Daily Activity — ${DateFormat('MMMM yyyy').format(DateTime(_selectedYear, _selectedMonth))}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 14),
              if (monthRecords.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text('No step activity recorded in this month.', style: TextStyle(fontStyle: FontStyle.italic)),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: monthRecords.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final r = monthRecords[idx];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: r.isGoalReached
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.1),
                        child: Icon(
                          r.isGoalReached ? Icons.check_circle_rounded : Icons.directions_walk_rounded,
                          color: r.isGoalReached ? AppColors.primary : Colors.grey,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        '${NumberFormat('#,###').format(r.stepCount)} steps',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      subtitle: Text('${r.distanceKm.toStringAsFixed(2)} km · ${r.calories.toStringAsFixed(0)} kcal'),
                      trailing: Text(
                        (() {
                          try {
                            final parts = r.date.split('-');
                            if (parts.length == 3) {
                              final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
                              return DateFormat('MMM d, yyyy').format(d);
                            }
                          } catch (_) {}
                          return r.date;
                        })(),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── 3. In-Depth Specific Year View (Jan-Dec 12 Month Breakdown) ────────────

  Widget _buildSpecificYearView(ThemeData theme, bool isDark, StepProvider stepProv) {
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

    // 12 months data
    final List<int> monthlyTotals = List.generate(12, (m) {
      final monthStr = '$_selectedYear-${(m + 1).toString().padLeft(2, '0')}';
      return effectiveYearRecords
          .where((r) => r.date.startsWith(monthStr))
          .fold(0, (sum, r) => sum + r.stepCount);
    });

    final totalYearSteps = monthlyTotals.fold(0, (sum, val) => sum + val);
    final maxMonthSteps = monthlyTotals.fold(1, (max, v) => v > max ? v : max);

    int bestMonthIdx = 0;
    int bestMonthVal = 0;
    for (int i = 0; i < 12; i++) {
      if (monthlyTotals[i] > bestMonthVal) {
        bestMonthVal = monthlyTotals[i];
        bestMonthIdx = i;
      }
    }
    final bestMonthName = DateFormat('MMMM').format(DateTime(_selectedYear, bestMonthIdx + 1));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        // Year Summary Card
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF115E59)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F766E).withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                'ANNUAL TOTAL ($_selectedYear)',
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2),
              ),
              const SizedBox(height: 6),
              Text(
                NumberFormat('#,###').format(totalYearSteps),
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                bestMonthVal > 0
                    ? '🏆 Highest Active Month: $bestMonthName (${NumberFormat('#,###').format(bestMonthVal)} steps)'
                    : 'No step data recorded in $_selectedYear',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.amberAccent),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 12-Month Jan-Dec Bar Chart
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '12-Month Activity Trend ($_selectedYear)',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 180,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(12, (m) {
                    final monthName = DateFormat('MMM').format(DateTime(_selectedYear, m + 1));
                    final val = monthlyTotals[m];
                    final factor = val == 0 ? 0.0 : (val / maxMonthSteps).clamp(0.04, 1.0);
                    final isBest = m == bestMonthIdx && val > 0;

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          val > 999 ? '${(val / 1000).toStringAsFixed(0)}k' : '$val',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: isBest ? AppColors.primary : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 18,
                          height: 125 * factor,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: const [AppColors.primaryLight, AppColors.primary],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          monthName,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── 4. All-Time View ──────────────────────────────────────────────────────

  Widget _buildAllTimeView(ThemeData theme, bool isDark, StepProvider stepProv) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 36),
              const SizedBox(height: 8),
              const Text(
                'LIFETIME ACTIVITY',
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5),
              ),
              const SizedBox(height: 6),
              Text(
                NumberFormat('#,###').format(stepProv.lifetimeSteps),
                style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900),
              ),
              const Text('Total Steps Walked', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Total Kilometers',
                value: '${stepProv.lifetimeDistanceKm.toStringAsFixed(1)} km',
                icon: Icons.map_rounded,
                color: Colors.teal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: 'Single Day Record',
                value: NumberFormat('#,###').format(stepProv.bestSingleDaySteps),
                icon: Icons.bolt_rounded,
                color: Colors.deepOrange,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String unit;
  final String label;

  const _MetricItem({
    required this.icon,
    required this.color,
    required this.value,
    required this.unit,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(width: 2),
              Text(unit, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ],
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
