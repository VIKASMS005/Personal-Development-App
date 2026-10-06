import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/finance_transaction.dart';
import '../utils/app_colors.dart';
import '../utils/month_weeks.dart';

class WeeklyExpenseChart extends StatelessWidget {
  final List<FinanceTransaction> transactions;
  final VoidCallback? onTapDetails;

  const WeeklyExpenseChart({
    super.key,
    required this.transactions,
    this.onTapDetails,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final now = DateTime.now();

    // Current week; weeks stay inside their month (1–7, 8–14, ...).
    final week = monthWeekOf(now);
    final days = week.days;
    final monday = week.start;

    final weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dayLabels = [for (final d in days) weekdayNames[d.weekday - 1]];
    final List<double> dayExpenses = List.filled(days.length, 0.0);

    for (final tx in transactions) {
      if (tx.amount < 0) {
        final txDate = DateTime(tx.date.year, tx.date.month, tx.date.day);
        final diffDays = txDate.day - monday.day;
        if (week.contains(txDate) && diffDays >= 0 && diffDays < days.length) {
          dayExpenses[diffDays] += tx.amount.abs();
        }
      }
    }

    final totalWeeklyExpense = dayExpenses.reduce((a, b) => a + b);
    final maxExpense = dayExpenses.reduce((a, b) => math.max(a, b));
    final currentDayIndex = now.day - monday.day;
    final elapsedDays = currentDayIndex + 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Title & Total
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.finance.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.bar_chart_rounded, color: AppColors.finance, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Weekly Expenditure',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${DateFormat('MMM d').format(monday)} – ${DateFormat('d MMM').format(week.last)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (onTapDetails != null)
                  TextButton.icon(
                    onPressed: onTapDetails,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Text('Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.finance)),
                    label: const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: AppColors.finance),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Total spent badge & Average
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                    Flexible(
                     child: Text(
                      '₹${totalWeeklyExpense.toStringAsFixed(0)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: totalWeeklyExpense > 0 ? AppColors.error : AppColors.primary,
                      ),
                    ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                     child: Text(
                      'spent this week',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.dividerColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Avg: ₹${(totalWeeklyExpense / elapsedDays).toStringAsFixed(0)}/day',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Bar Chart Area
            SizedBox(
              height: 130,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(days.length, (i) {
                  final expense = dayExpenses[i];
                  final isToday = i == currentDayIndex;
                  final double fillRatio = maxExpense > 0 ? (expense / maxExpense).clamp(0.08, 1.0) : 0.08;

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Expense label above bar
                          if (expense > 0)
                            Text(
                              '₹${expense >= 1000 ? '${(expense / 1000).toStringAsFixed(1)}k' : expense.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: isToday ? AppColors.finance : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            )
                          else
                            const SizedBox(height: 12),
                          const SizedBox(height: 4),

                          // Bar container
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeOutCubic,
                                height: 85 * fillRatio,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: expense > 0
                                        ? const [Color(0xFFF87171), AppColors.error]
                                        : [
                                            theme.dividerColor.withValues(alpha: isDark ? 0.3 : 0.4),
                                            theme.dividerColor.withValues(alpha: isDark ? 0.15 : 0.2),
                                          ],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Day Label
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: isToday
                                ? BoxDecoration(
                                    color: AppColors.finance.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  )
                                : null,
                            child: Text(
                              dayLabels[i],
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                                color: isToday
                                    ? AppColors.finance
                                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
