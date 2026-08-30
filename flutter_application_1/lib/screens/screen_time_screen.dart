import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_providers.dart';
import '../models/screen_time_record.dart';
import '../services/screen_time_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenProv = context.watch<ScreenTimeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Screen Time'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Stats',
            onPressed: () {
              screenProv.recheckAndLoad();
              _loadCurrentTab();
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
              // Permission Banner if Usage Access not enabled
              if (!screenProv.hasPermission)
                _buildPermissionBanner(theme, screenProv),

              // 1. Period Selector (Day / Week / Month / Year)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      _buildPeriodTab(0, 'Daily'),
                      _buildPeriodTab(1, 'Weekly'),
                      _buildPeriodTab(2, 'Monthly'),
                      _buildPeriodTab(3, 'Yearly'),
                    ],
                  ),
                ),
              ),

              // 2. Interactive Navigation Bar for selected period
              _buildDateSelectorBar(theme, isDark),

              // 3. Tab Content
              Expanded(
                child: _selectedPeriod == 0
                    ? _buildDailyView(theme, isDark)
                    : _selectedPeriod == 1
                        ? _buildWeeklyView(theme, isDark, screenProv)
                        : _selectedPeriod == 2
                            ? _buildMonthlyView(theme, isDark)
                            : _buildYearlyView(theme, isDark),
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
        onTap: () {
          if (_selectedPeriod != index) {
            setState(() => _selectedPeriod = index);
            _loadCurrentTab();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelectorBar(ThemeData theme, bool isDark) {
    final now = DateTime.now();
    String label = '';

    if (_selectedPeriod == 0) {
      // Daily
      final isToday = _selectedDate.year == now.year &&
          _selectedDate.month == now.month &&
          _selectedDate.day == now.day;
      label = isToday
          ? 'Today (${DateFormat('MMM d, yyyy').format(_selectedDate)})'
          : DateFormat('EEEE, MMM d, yyyy').format(_selectedDate);
    } else if (_selectedPeriod == 1) {
      // Weekly: Mon - Sun of that week
      final mon = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
      final sun = mon.add(const Duration(days: 6));
      label = '${DateFormat('MMM d').format(mon)} – ${DateFormat('MMM d, yyyy').format(sun)}';
    } else if (_selectedPeriod == 2) {
      // Monthly
      label = DateFormat('MMMM yyyy').format(DateTime(_selectedYear, _selectedMonth));
    } else if (_selectedPeriod == 3) {
      // Yearly
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
            onPressed: () {
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
            },
          ),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF6366F1)),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 24),
            onPressed: () {
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
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionBanner(ThemeData theme, ScreenTimeProvider prov) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade900.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade700.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.phone_android_rounded, color: Colors.orange, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Usage Access Required',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    SizedBox(height: 2),
                    Text(
                      'Grant permission to track all-app screen time',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Steps:\n1. Tap "Grant Access" below\n2. Find "Grow" in the list\n3. Enable "Permit usage access"\n4. Come back and tap "Refresh"',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.settings_rounded, size: 16),
                  label: const Text('Grant Access', style: TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () async {
                    await prov.requestUsagePermission();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade700,
                    side: BorderSide(color: Colors.orange.shade700),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Refresh', style: TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () async {
                    await prov.recheckAndLoad();
                    _loadCurrentTab();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppIcon(AppUsageRecord app, Color color) {
    if (app.iconBase64 != null && app.iconBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(app.iconBase64!);
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(bytes, width: 36, height: 36, fit: BoxFit.cover),
        );
      } catch (_) {}
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          app.appName.isNotEmpty ? app.appName[0].toUpperCase() : 'A',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color),
        ),
      ),
    );
  }

  // 1. DAILY VIEW
  Widget _buildDailyView(ThemeData theme, bool isDark) {
    if (_isLoadingDay) {
      return const Center(child: CircularProgressIndicator());
    }

    final total = _dayTotal;
    final apps = _dayApps;
    final totalSec = total.inSeconds > 0 ? total.inSeconds : 1;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1E1B4B), const Color(0xFF0F172A)]
                  : [const Color(0xFFEEF2FF), const Color(0xFFE0E7FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phone_android_rounded, color: Color(0xFF6366F1), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'TOTAL SCREEN TIME',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _formatDuration(total),
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF1E1B4B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${apps.length} apps active on this day',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Apps Used Today', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  Text('${apps.length} apps', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                ],
              ),
              const SizedBox(height: 14),
              if (apps.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('No app usage recorded for this date.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: apps.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final app = apps[idx];
                    final pct = (app.usage.inSeconds / totalSec).clamp(0.0, 1.0);
                    final color = _categoryColor(app.category);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _buildAppIcon(app, color),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      app.appName,
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      app.category,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: color,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _formatDuration(app.usage),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: pct,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(4),
                            backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                          ),
                        ],
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

  // 2. WEEKLY VIEW
  Widget _buildWeeklyView(ThemeData theme, bool isDark, ScreenTimeProvider prov) {
    if (_isLoadingWeek) {
      return const Center(child: CircularProgressIndicator());
    }

    final weekDays = _weekSummaries;
    final totalWeek = _weekTotal;
    final avgPerDay = weekDays.isNotEmpty ? (totalWeek.inSeconds / 7).round() : 0;

    final allSecs = weekDays.map((s) => s.totalDuration.inSeconds.toDouble()).toList();
    final maxSec = allSecs.isEmpty ? 7200.0 : allSecs.reduce((a, b) => a > b ? a : b);
    final safeMax = maxSec > 7200.0 ? maxSec : 7200.0;

    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total This Week', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(_formatDuration(totalWeek), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('${_formatDuration(Duration(seconds: avgPerDay))}/day avg', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Active Days', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('${weekDays.where((d) => d.totalDuration.inSeconds > 0).length} / 7', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('Logged screen days', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Daily Comparison (Mon – Sun)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 4),
              Text('Compare screen time for everyday of this week', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
              const SizedBox(height: 22),
              SizedBox(
                height: 190,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(7, (i) {
                    final summary = i < weekDays.length ? weekDays[i] : null;
                    final sec = summary?.totalDuration.inSeconds.toDouble() ?? 0.0;
                    final heightFactor = (sec / safeMax).clamp(0.02, 1.0);
                    final dayLabel = dayLabels[i];
                    final hasUsage = sec > 0;

                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            hasUsage ? _formatDuration(Duration(seconds: sec.round())) : '',
                            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF6366F1)),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 24,
                            height: hasUsage ? (140 * heightFactor).clamp(8.0, 140.0) : 4.0,
                            decoration: BoxDecoration(
                              gradient: hasUsage
                                  ? const LinearGradient(
                                      colors: [Color(0xFF818CF8), Color(0xFF6366F1)],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    )
                                  : null,
                              color: hasUsage ? null : theme.colorScheme.onSurface.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            dayLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: hasUsage
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.4),
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
        if (weekDays.isNotEmpty) ...[
          const Text('Top Apps This Week', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 10),
          ..._buildTopAppsList(theme, weekDays),
        ],
      ],
    );
  }

  // 3. MONTHLY VIEW
  Widget _buildMonthlyView(ThemeData theme, bool isDark) {
    if (_isLoadingMonth) {
      return const Center(child: CircularProgressIndicator());
    }

    final weeks = _monthWeeks;
    final totalMonth = _monthTotal;
    final daysInMonth = DateUtils.getDaysInMonth(_selectedYear, _selectedMonth);
    final dailyAvgSec = (totalMonth.inSeconds / daysInMonth).round();

    final allSecs = weeks.map((w) => w.totalDuration.inSeconds.toDouble()).toList();
    final maxSec = allSecs.isEmpty ? 14400.0 : allSecs.reduce((a, b) => a > b ? a : b);
    final safeMax = maxSec > 14400.0 ? maxSec : 14400.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total This Month', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(_formatDuration(totalMonth), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('${_formatDuration(Duration(seconds: dailyAvgSec))}/day avg', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Month Range', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('$daysInMonth Days', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('${weeks.length} calendar weeks', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weekly Comparison (${DateFormat('MMMM yyyy').format(DateTime(_selectedYear, _selectedMonth))})',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text('Compare screen time for every week of this month', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
              const SizedBox(height: 22),
              SizedBox(
                height: 190,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: weeks.map((w) {
                    final sec = w.totalDuration.inSeconds.toDouble();
                    final heightFactor = (sec / safeMax).clamp(0.02, 1.0);
                    final hasUsage = sec > 0;

                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            hasUsage ? _formatDuration(w.totalDuration) : '',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF8B5CF6)),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 28,
                            height: hasUsage ? (140 * heightFactor).clamp(8.0, 140.0) : 4.0,
                            decoration: BoxDecoration(
                              gradient: hasUsage
                                  ? const LinearGradient(
                                      colors: [Color(0xFFA78BFA), Color(0xFF8B5CF6)],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    )
                                  : null,
                              color: hasUsage ? null : theme.colorScheme.onSurface.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            w.date.replaceAll('Week ', 'W'),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: hasUsage
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (weeks.isNotEmpty) ...[
          const Text('Top Apps This Month', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 10),
          ..._buildTopAppsList(theme, weeks),
        ],
      ],
    );
  }

  // 4. YEARLY VIEW
  Widget _buildYearlyView(ThemeData theme, bool isDark) {
    if (_isLoadingYear) {
      return const Center(child: CircularProgressIndicator());
    }

    final months = _yearMonths;
    final totalYear = _yearTotal;
    final activeMonths = months.where((m) => m.totalDuration.inSeconds > 0).length;
    final monthlyAvgSec = activeMonths > 0 ? (totalYear.inSeconds / activeMonths).round() : 0;

    final allSecs = months.map((m) => m.totalDuration.inSeconds.toDouble()).toList();
    final maxSec = allSecs.isEmpty ? 36000.0 : allSecs.reduce((a, b) => a > b ? a : b);
    final safeMax = maxSec > 36000.0 ? maxSec : 36000.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF312E81)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total ($_selectedYear)', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(_formatDuration(totalYear), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('${_formatDuration(Duration(seconds: monthlyAvgSec))}/month avg', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Active Months', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('$activeMonths / 12', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('Months recorded so far', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '12-Month Comparison ($_selectedYear)',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text('Compare screen time for every month of the year', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
              const SizedBox(height: 22),
              SizedBox(
                height: 190,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: months.map((m) {
                    final sec = m.totalDuration.inSeconds.toDouble();
                    final heightFactor = (sec / safeMax).clamp(0.02, 1.0);
                    final hasUsage = sec > 0;

                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            hasUsage ? '${m.totalDuration.inHours}h' : '',
                            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF6366F1)),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 16,
                            height: hasUsage ? (140 * heightFactor).clamp(6.0, 140.0) : 4.0,
                            decoration: BoxDecoration(
                              gradient: hasUsage
                                  ? const LinearGradient(
                                      colors: [Color(0xFF818CF8), Color(0xFF4F46E5)],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    )
                                  : null,
                              color: hasUsage ? null : theme.colorScheme.onSurface.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            m.date,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: hasUsage
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (months.isNotEmpty) ...[
          const Text('Top Apps This Year', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 10),
          ..._buildTopAppsList(theme, months),
        ],
      ],
    );
  }

  List<Widget> _buildTopAppsList(ThemeData theme, List<DailyScreenTimeSummary> summaries) {
    final Map<String, Duration> appTotals = {};
    final Map<String, AppUsageRecord> appRecords = {};

    for (final s in summaries) {
      for (final app in s.appUsages) {
        appTotals[app.packageName] = (appTotals[app.packageName] ?? Duration.zero) + app.usage;
        appRecords[app.packageName] = app;
      }
    }

    final sorted = appTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(10).toList();
    final totalSec = top.fold(0, (s, e) => s + e.value.inSeconds);

    if (top.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No app usage recorded for this timeframe.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            ),
          ),
        ),
      ];
    }

    return top.map((entry) {
      final app = appRecords[entry.key]!;
      final color = _categoryColor(app.category);
      final pct = totalSec > 0 ? (entry.value.inSeconds / totalSec) : 0.0;

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              _buildAppIcon(app, color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.appName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: pct.clamp(0.0, 1.0),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(4),
                      backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(_formatDuration(entry.value), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ],
          ),
        ),
      );
    }).toList();
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'Social':
        return const Color(0xFFEC4899);
      case 'Entertainment':
        return const Color(0xFFF59E0B);
      case 'Gaming':
        return const Color(0xFFEF4444);
      case 'Productivity':
        return const Color(0xFF10B981);
      case 'Browsing':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF6B7280);
    }
  }
}
