import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/app_providers.dart';
import '../models/todo.dart';
import '../models/task_session.dart';
import '../utils/app_colors.dart';

class TaskReportScreen extends StatefulWidget {
  const TaskReportScreen({super.key});

  @override
  State<TaskReportScreen> createState() => _TaskReportScreenState();
}

class _TaskReportScreenState extends State<TaskReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) {
      return '${h}h ${m}m';
    }
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todoProv = context.watch<TodoProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Tracker & Reports'),
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [
            Tab(icon: Icon(Icons.assessment_rounded, size: 20), text: 'Daily Report'),
            Tab(icon: Icon(Icons.trending_up_rounded, size: 20), text: 'Improvement & Trends'),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDailyReportTab(theme, todoProv),
              _buildImprovementTab(theme, todoProv),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 1. DAILY REPORT TAB ====================
  Widget _buildDailyReportTab(ThemeData theme, TodoProvider todoProv) {
    final report = todoProv.getDailyReport(_selectedDate);
    final totalSeconds = report['totalSeconds'] as int;
    final completedTasks = report['completedTasks'] as List<Todo>;
    final pendingTasks = report['pendingTasks'] as List<Todo>;
    final categoryTime = report['categoryTime'] as Map<String, int>;
    final completionRate = report['completionRate'] as int;
    final daySessions = report['daySessions'] as List<TaskSession>;

    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      children: [
        // 1. Date Selector Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: theme.cardTheme.color ?? theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Previous Day',
                onPressed: _previousDay,
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _pickDate,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.calendar_month_rounded, size: 16, color: AppColors.tasks),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            isToday
                                ? 'Today • ${DateFormat('MMM d').format(_selectedDate)}'
                                : DateFormat('EEE, MMM d').format(_selectedDate),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Next Day',
                onPressed: _nextDay,
              ),
            ],
          ),
        ).animate().fadeIn(duration: 300.ms),
        const SizedBox(height: 16),

        // 2. Summary Metric Cards Grid
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                theme: theme,
                title: 'Total Tracked',
                value: _formatDuration(totalSeconds),
                subtitle: '${daySessions.length} sessions logged',
                icon: Icons.timer_rounded,
                color: AppColors.tasks,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                theme: theme,
                title: 'Completion Rate',
                value: '$completionRate%',
                subtitle: '${completedTasks.length} done / ${pendingTasks.length} pending',
                icon: Icons.check_circle_rounded,
                color: completionRate >= 70 ? AppColors.success : AppColors.warning,
              ),
            ),
          ],
        ).animate().fadeIn(delay: 100.ms),
        const SizedBox(height: 16),

        // 3. Category Breakdown Card
        if (categoryTime.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.cardTheme.color ?? theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.pie_chart_rounded, color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Time by Category',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...categoryTime.entries.map((e) {
                  final pct = totalSeconds > 0 ? (e.value / totalSeconds) : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            Text(_formatDuration(e.value),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 6,
                            backgroundColor: theme.dividerColor.withValues(alpha: 0.15),
                            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.tasks),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ).animate().fadeIn(delay: 150.ms),
          const SizedBox(height: 16),
        ],

        // 4. Tasks Completed (Done)
        _buildSectionHeader(theme, 'Tasks Completed (${completedTasks.length})', Icons.task_alt_rounded, AppColors.success),
        const SizedBox(height: 8),
        if (completedTasks.isEmpty)
          _buildEmptyText('No completed tasks recorded for this date.')
        else
          ...completedTasks.map((t) => _buildTaskItem(theme, t, isDone: true)),
        const SizedBox(height: 18),

        // 5. Tasks Not Done (Pending)
        _buildSectionHeader(theme, 'Tasks Not Done / Pending (${pendingTasks.length})', Icons.pending_actions_rounded, AppColors.warning),
        const SizedBox(height: 8),
        if (pendingTasks.isEmpty)
          _buildEmptyText('All tasks are completed! Great job! 🎉')
        else
          ...pendingTasks.map((t) => _buildTaskItem(theme, t, isDone: false)),
        const SizedBox(height: 24),
      ],
    );
  }

  // ==================== 2. IMPROVEMENT COMPARISON TAB ====================
  Widget _buildImprovementTab(ThemeData theme, TodoProvider todoProv) {
    final comp = todoProv.getImprovementComparison();

    final todayMin = comp['todayMinutes'] as int;
    final yesterdayMin = comp['yesterdayMinutes'] as int;
    final todayDone = comp['todayCompleted'] as int;
    final yesterdayDone = comp['yesterdayCompleted'] as int;
    final dayChangePct = comp['dayTimeChangePct'] as int;

    final curWeekHours = comp['currentWeekHours'] as String;
    final priorWeekHours = comp['priorWeekHours'] as String;
    final curWeekDailyAvg = comp['currentWeekDailyAvgMinutes'] as int;
    final curWeekDone = comp['currentWeekCompleted'] as int;
    final priorWeekDone = comp['priorWeekCompleted'] as int;
    final weekChangePct = comp['weekTimeChangePct'] as int;

    final thisMonthHours = comp['thisMonthHours'] as String;
    final prevMonthHours = comp['prevMonthHours'] as String;
    final thisMonthDone = comp['thisMonthCompleted'] as int;
    final prevMonthDone = comp['prevMonthCompleted'] as int;
    final monthChangePct = comp['monthTimeChangePct'] as int;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      children: [
        // 1. Day-to-Day Comparison Card
        _buildComparisonCard(
          theme: theme,
          horizon: 'Day-to-Day Improvement',
          period1Label: 'Today',
          period1Value: '${todayMin}m tracked',
          period1Extra: '$todayDone tasks completed',
          period2Label: 'Yesterday',
          period2Value: '${yesterdayMin}m tracked',
          period2Extra: '$yesterdayDone tasks completed',
          pctChange: dayChangePct,
          icon: Icons.today_rounded,
          accentColor: AppColors.tasks,
        ).animate().fadeIn(delay: 50.ms),
        const SizedBox(height: 16),

        // 2. Week-to-Week Comparison Card
        _buildComparisonCard(
          theme: theme,
          horizon: 'Week-to-Week Improvement',
          period1Label: 'This Week',
          period1Value: '${curWeekHours}h total',
          period1Extra: 'Avg ${curWeekDailyAvg}m/day • $curWeekDone tasks',
          period2Label: 'Last Week',
          period2Value: '${priorWeekHours}h total',
          period2Extra: '$priorWeekDone tasks completed',
          pctChange: weekChangePct,
          icon: Icons.view_week_rounded,
          accentColor: AppColors.primary,
        ).animate().fadeIn(delay: 150.ms),
        const SizedBox(height: 16),

        // 3. Month-to-Month Comparison Card
        _buildComparisonCard(
          theme: theme,
          horizon: 'Month-to-Month Improvement',
          period1Label: 'This Month',
          period1Value: '${thisMonthHours}h tracked',
          period1Extra: '$thisMonthDone tasks completed',
          period2Label: 'Last Month',
          period2Value: '${prevMonthHours}h tracked',
          period2Extra: '$prevMonthDone tasks completed',
          pctChange: monthChangePct,
          icon: Icons.calendar_view_month_rounded,
          accentColor: AppColors.secondary,
        ).animate().fadeIn(delay: 250.ms),
        const SizedBox(height: 24),
      ],
    );
  }

  // ==================== HELPER WIDGETS ====================

  Widget _buildMetricCard({
    required ThemeData theme,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonCard({
    required ThemeData theme,
    required String horizon,
    required String period1Label,
    required String period1Value,
    required String period1Extra,
    required String period2Label,
    required String period2Value,
    required String period2Extra,
    required int pctChange,
    required IconData icon,
    required Color accentColor,
  }) {
    final isPositive = pctChange >= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: accentColor, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    horizon,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isPositive ? AppColors.success : AppColors.error).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      size: 14,
                      color: isPositive ? AppColors.success : AppColors.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${pctChange.abs()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: isPositive ? AppColors.success : AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              // Current Period
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(period1Label, style: TextStyle(color: accentColor, fontWeight: FontWeight.w700, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(period1Value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(period1Extra, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Prior Period
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(period2Label,
                          style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(period2Value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(period2Extra, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _buildEmptyText(String msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        msg,
        style: TextStyle(fontSize: 13, color: Colors.grey.withValues(alpha: 0.8), fontStyle: FontStyle.italic),
      ),
    );
  }

  Widget _buildTaskItem(ThemeData theme, Todo task, {required bool isDone}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(
            isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: isDone ? AppColors.success : AppColors.warning,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (task.category.isNotEmpty)
                  Text(
                    task.category,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
          if (task.timeSpentSeconds > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.tasks.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_outlined, size: 12, color: AppColors.tasks),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(task.timeSpentSeconds),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.tasks,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
