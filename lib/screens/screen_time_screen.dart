import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_providers.dart';
import '../models/screen_time_record.dart';
import '../services/screen_time_service.dart';
import '../widgets/ds/ds.dart';

class ScreenTimeScreen extends StatefulWidget {
  const ScreenTimeScreen({super.key});

  @override
  State<ScreenTimeScreen> createState() => _ScreenTimeScreenState();
}

class _ScreenTimeScreenState extends State<ScreenTimeScreen> {
  int _selectedPeriod = 0; // 0=Day, 1=Week, 2=Month, 3=Year

  DateTime _selectedDate = DateTime.now();
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  // Specific day state
  bool _isLoadingDay = false;
  List<AppUsageRecord> _dayApps = [];
  Duration _dayTotal = Duration.zero;

  // Weekly comparison state
  bool _isLoadingWeek = false;
  List<DailyScreenTimeSummary> _weekSummaries = [];
  Duration _weekTotal = Duration.zero;

  // Monthly comparison state
  bool _isLoadingMonth = false;
  List<DailyScreenTimeSummary> _monthWeeks = [];
  Duration _monthTotal = Duration.zero;

  // Yearly comparison state
  bool _isLoadingYear = false;
  List<DailyScreenTimeSummary> _yearMonths = [];
  Duration _yearTotal = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ScreenTimeProvider>().loadScreenTime();
      _loadCurrentTab();
    });
  }

  void _loadCurrentTab() {
    if (_selectedPeriod == 0) {
      _loadDayData(_selectedDate);
    } else if (_selectedPeriod == 1) {
      _loadWeekData(_selectedDate);
    } else if (_selectedPeriod == 2) {
      _loadMonthData(_selectedYear, _selectedMonth);
    } else if (_selectedPeriod == 3) {
      _loadYearData(_selectedYear);
    }
  }

  Future<void> _loadDayData(DateTime date) async {
    setState(() => _isLoadingDay = true);
    final isToday = date.year == DateTime.now().year &&
        date.month == DateTime.now().month &&
        date.day == DateTime.now().day;
    final start = DateTime(date.year, date.month, date.day);
    final end = isToday ? DateTime.now() : DateTime(date.year, date.month, date.day, 23, 59, 59);

    final summary = await ScreenTimeService.instance.getSummaryForRange(
      startDate: start,
      endDate: end,
      dateLabel: DateFormat('yyyy-MM-dd').format(date),
    );

    if (mounted) {
      setState(() {
        _dayApps = summary.appUsages;
        _dayTotal = summary.totalDuration;
        _isLoadingDay = false;
      });
    }
  }

  Future<void> _loadWeekData(DateTime date) async {
    setState(() => _isLoadingWeek = true);
    final prov = context.read<ScreenTimeProvider>();
    final summaries = await prov.getWeekDays(date);

    Duration total = Duration.zero;
    for (final s in summaries) {
      total += s.totalDuration;
    }

    if (mounted) {
      setState(() {
        _weekSummaries = summaries;
        _weekTotal = total;
        _isLoadingWeek = false;
      });
    }
  }

  Future<void> _loadMonthData(int year, int month) async {
    setState(() => _isLoadingMonth = true);
    final prov = context.read<ScreenTimeProvider>();
    final weeks = await prov.getMonthWeeks(year, month);

    Duration total = Duration.zero;
    for (final w in weeks) {
      total += w.totalDuration;
    }

    if (mounted) {
      setState(() {
        _monthWeeks = weeks;
        _monthTotal = total;
        _isLoadingMonth = false;
      });
    }
  }

  Future<void> _loadYearData(int year) async {
    setState(() => _isLoadingYear = true);
    final prov = context.read<ScreenTimeProvider>();
    final months = await prov.getYearMonths(year);

    Duration total = Duration.zero;
    for (final m in months) {
      total += m.totalDuration;
    }

    if (mounted) {
      setState(() {
        _yearMonths = months;
        _yearTotal = total;
        _isLoadingYear = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedMonth = picked.month;
        _selectedYear = picked.year;
      });
      _loadCurrentTab();
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '0m';
  }

  String _hoursLabel(double seconds) {
    if (seconds <= 0) return '0';
    final h = seconds / 3600;
    if (h >= 1) return '${h.toStringAsFixed(h >= 10 ? 0 : 1)}h';
    return '${(seconds / 60).round()}m';
  }

  void _previous() {
    setState(() {
      if (_selectedPeriod == 0) {
        _selectedDate = _selectedDate.subtract(const Duration(days: 1));
        _selectedMonth = _selectedDate.month;
        _selectedYear = _selectedDate.year;
      } else if (_selectedPeriod == 1) {
        _selectedDate = _selectedDate.subtract(const Duration(days: 7));
        _selectedMonth = _selectedDate.month;
        _selectedYear = _selectedDate.year;
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
    _loadCurrentTab();
  }

  void _next() {
    final now = DateTime.now();
    setState(() {
      if (_selectedPeriod == 0) {
        if (_selectedDate.isBefore(now.subtract(const Duration(days: 1)))) {
          _selectedDate = _selectedDate.add(const Duration(days: 1));
          _selectedMonth = _selectedDate.month;
          _selectedYear = _selectedDate.year;
        } else {
          _selectedDate = now;
        }
      } else if (_selectedPeriod == 1) {
        final nextWeek = _selectedDate.add(const Duration(days: 7));
        if (!nextWeek.isAfter(now)) {
          _selectedDate = nextWeek;
          _selectedMonth = _selectedDate.month;
          _selectedYear = _selectedDate.year;
        }
      } else if (_selectedPeriod == 2) {
        if (_selectedYear < now.year || (_selectedYear == now.year && _selectedMonth < now.month)) {
          if (_selectedMonth == 12) {
            _selectedMonth = 1;
            _selectedYear++;
          } else {
            _selectedMonth++;
          }
        }
      } else if (_selectedPeriod == 3) {
        if (_selectedYear < now.year) {
          _selectedYear++;
        }
      }
    });
    _loadCurrentTab();
  }

  bool get _canGoNext {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 0:
        return !DateUtils.isSameDay(_selectedDate, now);
      case 1:
        return !_selectedDate.add(const Duration(days: 7)).isAfter(now);
      case 2:
        return _selectedYear < now.year || (_selectedYear == now.year && _selectedMonth < now.month);
      default:
        return _selectedYear < now.year;
    }
  }

  String _periodLabel() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 0:
        return DateUtils.isSameDay(_selectedDate, now)
            ? 'Today, ${DateFormat('MMM d').format(_selectedDate)}'
            : DateFormat('EEE, MMM d, yyyy').format(_selectedDate);
      case 1:
        final mon = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
        final sun = mon.add(const Duration(days: 6));
        return '${DateFormat('MMM d').format(mon)} – ${DateFormat('MMM d, yyyy').format(sun)}';
      case 2:
        return DateFormat('MMMM yyyy').format(DateTime(_selectedYear, _selectedMonth));
      default:
        return '$_selectedYear';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenProv = context.watch<ScreenTimeProvider>();

    final List<Widget> content = switch (_selectedPeriod) {
      0 => _buildDailyView(),
      1 => _buildWeeklyView(),
      2 => _buildMonthlyView(),
      _ => _buildYearlyView(),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Screen time'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () {
              screenProv.recheckAndLoad();
              _loadCurrentTab();
            },
          ),
          const SizedBox(width: AppSpacing.xxs),
        ],
      ),
      body: PageListView(
        clearFab: false,
        children: [
          if (!screenProv.hasPermission) ...[
            _buildPermissionCard(screenProv),
            const SizedBox(height: AppSpacing.md),
          ],
          AppSegmented<int>(
            segments: const {0: 'Day', 1: 'Week', 2: 'Month', 3: 'Year'},
            selected: _selectedPeriod,
            onChanged: (index) {
              if (_selectedPeriod != index) {
                setState(() => _selectedPeriod = index);
                _loadCurrentTab();
              }
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          DateNavigator(
            label: _periodLabel(),
            onPrevious: _previous,
            onNext: _canGoNext ? _next : null,
            onTapLabel: _pickDate,
          ),
          const SizedBox(height: AppSpacing.sm),
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

  Widget _buildPermissionCard(ScreenTimeProvider prov) {
    return AppCard(
      borderColor: context.colors.warning.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.lock_open_outlined, tone: StatusTone.warning, size: 36),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('Allow usage access', style: context.text.titleSmall)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Grow needs usage access to show screen time for your apps.\n'
            '1. Tap Open settings\n2. Find Grow in the list\n3. Turn on Permit usage access\n4. Come back and tap Check again',
            style: context.text.bodySmall?.copyWith(height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    await prov.requestUsagePermission();
                  },
                  child: const FittedBox(child: Text('Open settings')),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await prov.recheckAndLoad();
                    _loadCurrentTab();
                  },
                  child: const FittedBox(child: Text('Check again')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppIcon(AppUsageRecord app) {
    if (app.iconBase64 != null && app.iconBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(app.iconBase64!);
        return ClipRRect(
          borderRadius: AppRadius.smAll,
          child: Image.memory(bytes, width: 36, height: 36, fit: BoxFit.cover),
        );
      } catch (_) {}
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: context.colors.surfaceMuted, borderRadius: AppRadius.smAll),
      alignment: Alignment.center,
      child: Text(
        app.appName.isNotEmpty ? app.appName[0].toUpperCase() : 'A',
        style: context.text.labelLarge?.copyWith(color: context.colors.textSecondary),
      ),
    );
  }

  List<Widget> _loading() => const [LoadingList(count: 3, itemHeight: 96)];

  Widget _hero({required String label, required Duration total, required List<Metric> metrics}) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.labelMedium?.copyWith(color: context.colors.textSecondary)),
          const SizedBox(height: AppSpacing.xxs),
          FittedBox(fit: BoxFit.scaleDown, child: Text(_formatDuration(total), style: context.text.displaySmall)),
          const SizedBox(height: AppSpacing.md),
          MetricStrip(metrics: metrics),
        ],
      ),
    );
  }

  Widget _chart(String title, List<double> values, List<String> labels, {int? highlight}) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.md),
          BarChart(
            values: values,
            labels: labels,
            highlightIndex: highlight,
            valueLabel: _hoursLabel,
            height: 170,
            semanticsLabel: title,
          ),
        ],
      ),
    );
  }

  /// Usage rows for apps, shared by every period.
  Widget _appList(List<(AppUsageRecord, Duration)> items) {
    if (items.isEmpty) {
      return const EmptyState(
        compact: true,
        icon: Icons.phone_android_outlined,
        title: 'No app usage',
        subtitle: 'Nothing was recorded for this period.',
      );
    }
    final total = items.fold<int>(0, (a, e) => a + e.$2.inSeconds);
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final (app, usage) = items[i];
      final pct = total > 0 ? usage.inSeconds / total : 0.0;
      if (i > 0) children.add(const Divider(indent: 68));
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            _buildAppIcon(app),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(app.appName, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: AppSpacing.xs),
                      Text(_formatDuration(usage), style: context.text.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    ],
                  ),
                  Text('${app.category} · ${(pct * 100).round()}%', style: context.text.labelSmall),
                  const SizedBox(height: AppSpacing.xxs + 2),
                  LinearMeter(value: pct, height: 4),
                ],
              ),
            ),
          ],
        ),
      ));
    }
    return AppCard(padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs), child: Column(children: children));
  }

  List<(AppUsageRecord, Duration)> _topApps(List<DailyScreenTimeSummary> summaries) {
    final Map<String, Duration> appTotals = {};
    final Map<String, AppUsageRecord> appRecords = {};
    for (final s in summaries) {
      for (final app in s.appUsages) {
        appTotals[app.packageName] = (appTotals[app.packageName] ?? Duration.zero) + app.usage;
        appRecords[app.packageName] = app;
      }
    }
    final sorted = appTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(10).map((e) => (appRecords[e.key]!, e.value)).toList();
  }

  // 1. DAILY VIEW
  List<Widget> _buildDailyView() {
    if (_isLoadingDay) return _loading();
    final apps = [..._dayApps]..sort((a, b) => b.usage.compareTo(a.usage));
    final categories = <String, Duration>{};
    for (final a in apps) {
      categories[a.category] = (categories[a.category] ?? Duration.zero) + a.usage;
    }
    final topCat = categories.entries.isEmpty
        ? null
        : categories.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return [
      _hero(
        label: 'Total screen time',
        total: _dayTotal,
        metrics: [
          Metric(value: '${apps.length}', label: 'apps used', icon: Icons.apps_rounded),
          Metric(value: apps.isEmpty ? '—' : _formatDuration(apps.first.usage), label: 'top app', icon: Icons.star_outline_rounded),
          Metric(value: topCat?.key ?? '—', label: 'top category', icon: Icons.category_outlined),
        ],
      ),
      const SectionGap(),
      const SectionHeader(title: 'Apps'),
      _appList(apps.map((a) => (a, a.usage)).toList()),
    ];
  }

  // 2. WEEKLY VIEW
  List<Widget> _buildWeeklyView() {
    if (_isLoadingWeek) return _loading();
    final weekDays = _weekSummaries;
    final avgPerDay = weekDays.isNotEmpty ? (_weekTotal.inSeconds / 7).round() : 0;
    final activeDays = weekDays.where((d) => d.totalDuration.inSeconds > 0).length;
    final now = DateTime.now();
    final mon = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
    int? todayIdx;
    for (var i = 0; i < 7; i++) {
      if (DateUtils.isSameDay(mon.add(Duration(days: i)), now)) todayIdx = i;
    }
    return [
      _hero(
        label: 'This week',
        total: _weekTotal,
        metrics: [
          Metric(value: _formatDuration(Duration(seconds: avgPerDay)), label: 'daily avg', icon: Icons.speed_rounded),
          Metric(value: '$activeDays', label: 'active days', icon: Icons.event_available_outlined),
        ],
      ),
      const SectionGap(),
      _chart(
        'Screen time per day',
        List.generate(7, (i) => i < weekDays.length ? weekDays[i].totalDuration.inSeconds.toDouble() : 0.0),
        const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
        highlight: todayIdx,
      ),
      const SectionGap(),
      const SectionHeader(title: 'Top apps'),
      _appList(_topApps(weekDays)),
    ];
  }

  // 3. MONTHLY VIEW
  List<Widget> _buildMonthlyView() {
    if (_isLoadingMonth) return _loading();
    final weeks = _monthWeeks;
    final daysInMonth = DateUtils.getDaysInMonth(_selectedYear, _selectedMonth);
    final dailyAvgSec = (_monthTotal.inSeconds / daysInMonth).round();
    return [
      _hero(
        label: DateFormat('MMMM yyyy').format(DateTime(_selectedYear, _selectedMonth)),
        total: _monthTotal,
        metrics: [
          Metric(value: _formatDuration(Duration(seconds: dailyAvgSec)), label: 'daily avg', icon: Icons.speed_rounded),
          Metric(value: '$daysInMonth', label: 'days', icon: Icons.calendar_month_outlined),
        ],
      ),
      const SectionGap(),
      _chart(
        'Screen time per week',
        weeks.map((w) => w.totalDuration.inSeconds.toDouble()).toList(),
        weeks.map((w) => w.date.replaceAll('Week ', 'W')).toList(),
      ),
      const SectionGap(),
      const SectionHeader(title: 'Top apps'),
      _appList(_topApps(weeks)),
    ];
  }

  // 4. YEARLY VIEW
  List<Widget> _buildYearlyView() {
    if (_isLoadingYear) return _loading();
    final months = _yearMonths;
    final activeMonths = months.where((m) => m.totalDuration.inSeconds > 0).length;
    final monthlyAvgSec = activeMonths > 0 ? (_yearTotal.inSeconds / activeMonths).round() : 0;
    final now = DateTime.now();
    return [
      _hero(
        label: 'Total in $_selectedYear',
        total: _yearTotal,
        metrics: [
          Metric(value: _formatDuration(Duration(seconds: monthlyAvgSec)), label: 'monthly avg', icon: Icons.speed_rounded),
          Metric(value: '$activeMonths', label: 'active months', icon: Icons.event_available_outlined),
        ],
      ),
      const SectionGap(),
      _chart(
        'Screen time per month',
        months.map((m) => m.totalDuration.inSeconds.toDouble()).toList(),
        months.map((m) => m.date.isNotEmpty ? m.date.substring(0, 1) : '').toList(),
        highlight: _selectedYear == now.year && months.length == 12 ? now.month - 1 : null,
      ),
      const SectionGap(),
      const SectionHeader(title: 'Top apps'),
      _appList(_topApps(months)),
    ];
  }
}
