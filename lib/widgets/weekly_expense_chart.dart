import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/finance_transaction.dart';
import '../utils/app_colors.dart';

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

    // Determine current week's Monday (start) and Sunday (end)
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));

    final dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final List<double> dayExpenses = List.filled(7, 0.0);

    for (final tx in transactions) {
      if (tx.amount < 0) {
        final txDate = DateTime(tx.date.year, tx.date.month, tx.date.day);
        final diffDays = txDate.difference(monday).inDays;
        if (diffDays >= 0 && diffDays < 7) {
          dayExpenses[diffDays] += tx.amount.abs();
        }
      }
    }

    final totalWeeklyExpense = dayExpenses.reduce((a, b) => a + b);
    final maxExpense = dayExpenses.reduce((a, b) => math.max(a, b));
    final currentDayIndex = now.weekday - 1;

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
                          'Mon ${DateFormat('d').format(monday)} – Sun ${DateFormat('d MMM').format(monday.add(const Duration(days: 6)))}',
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
                Text(
                  '₹${totalWeeklyExpense.toStringAsFixed(0)}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: totalWeeklyExpense > 0 ? AppColors.error : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'spent this week',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.dividerColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Avg: ₹${(totalWeeklyExpense / 7).toStringAsFixed(0)}/day',
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
                children: List.generate(7, (i) {
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
                                  gradient: isToday
                                      ? LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            AppColors.finance,
                                            AppColors.finance.withValues(alpha: 0.7),
                                          ],
                                        )
                                      : LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: expense > 0
                                              ? [
                                                  AppColors.error.withValues(alpha: 0.7),
                                                  AppColors.error.withValues(alpha: 0.4),
                                                ]
                                              : [
                                                  theme.dividerColor.withValues(alpha: isDark ? 0.3 : 0.4),
                                                  theme.dividerColor.withValues(alpha: isDark ? 0.15 : 0.2),
                                                ],
                                        ),
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: isToday
                                      ? [
                                          BoxShadow(
                                            color: AppColors.finance.withValues(alpha: 0.3),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
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
