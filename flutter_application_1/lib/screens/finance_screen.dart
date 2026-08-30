import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_providers.dart';
import '../models/finance_transaction.dart';
import '../utils/app_colors.dart';
import '../widgets/empty_state.dart';
import '../widgets/animated_card.dart';
import 'forms/finance_form.dart';

enum FinancePeriod { daily, weekly, monthly, yearly, all }

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  FinancePeriod _selectedPeriod = FinancePeriod.daily;
  DateTime _selectedDate = DateTime.now();

  List<FinanceTransaction> _filterTransactions(List<FinanceTransaction> all) {
    switch (_selectedPeriod) {
      case FinancePeriod.daily:
        return all.where((t) =>
            t.date.year == _selectedDate.year &&
            t.date.month == _selectedDate.month &&
            t.date.day == _selectedDate.day).toList();

      case FinancePeriod.weekly:
        final startOfWeek = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
        final start = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
        final end = start.add(const Duration(days: 7));
        return all.where((t) =>
            t.date.isAfter(start.subtract(const Duration(seconds: 1))) &&
            t.date.isBefore(end)).toList();

      case FinancePeriod.monthly:
        return all.where((t) =>
            t.date.year == _selectedDate.year &&
            t.date.month == _selectedDate.month).toList();

      case FinancePeriod.yearly:
        return all.where((t) => t.date.year == _selectedDate.year).toList();

      case FinancePeriod.all:
        return all;
    }
  }

  void _previousPeriod() {
    setState(() {
      switch (_selectedPeriod) {
        case FinancePeriod.daily:
          _selectedDate = _selectedDate.subtract(const Duration(days: 1));
          break;
        case FinancePeriod.weekly:
          _selectedDate = _selectedDate.subtract(const Duration(days: 7));
          break;
        case FinancePeriod.monthly:
          _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
          break;
        case FinancePeriod.yearly:
          _selectedDate = DateTime(_selectedDate.year - 1, 1, 1);
          break;
        case FinancePeriod.all:
          break;
      }
    });
  }

  void _nextPeriod() {
    setState(() {
      switch (_selectedPeriod) {
        case FinancePeriod.daily:
          _selectedDate = _selectedDate.add(const Duration(days: 1));
          break;
        case FinancePeriod.weekly:
          _selectedDate = _selectedDate.add(const Duration(days: 7));
          break;
        case FinancePeriod.monthly:
          _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
          break;
        case FinancePeriod.yearly:
          _selectedDate = DateTime(_selectedDate.year + 1, 1, 1);
          break;
        case FinancePeriod.all:
          break;
      }
    });
  }

  Future<void> _pickCustomDate() async {
    if (_selectedPeriod == FinancePeriod.all) return;

    if (_selectedPeriod == FinancePeriod.yearly) {
      // Pick year dialog
      final selected = await showDialog<int>(
        context: context,
        builder: (ctx) {
          final currentYear = DateTime.now().year;
          return AlertDialog(
            title: const Text('Select Year'),
            content: SizedBox(
              width: 300,
              height: 300,
              child: ListView.builder(
                itemCount: 15,
                itemBuilder: (_, i) {
                  final year = currentYear - 5 + i;
                  final isSel = year == _selectedDate.year;
                  return ListTile(
                    title: Text('$year', style: TextStyle(fontWeight: isSel ? FontWeight.w800 : FontWeight.normal)),
                    trailing: isSel ? const Icon(Icons.check, color: AppColors.primary) : null,
                    onTap: () => Navigator.pop(ctx, year),
                  );
                },
              ),
            ),
          );
        },
      );
      if (selected != null) {
        setState(() => _selectedDate = DateTime(selected, 1, 1));
      }
      return;
    }

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

  String _periodHeaderLabel() {
    switch (_selectedPeriod) {
      case FinancePeriod.daily:
        final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
        if (isToday) return 'Today (${DateFormat('MMM dd, yyyy').format(_selectedDate)})';
        return DateFormat('EEEE, MMM dd, yyyy').format(_selectedDate);

      case FinancePeriod.weekly:
        final startOfWeek = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 6));
        return '${DateFormat('MMM dd').format(startOfWeek)} - ${DateFormat('MMM dd, yyyy').format(endOfWeek)}';

      case FinancePeriod.monthly:
        return DateFormat('MMMM yyyy').format(_selectedDate);

      case FinancePeriod.yearly:
        return 'Year ${_selectedDate.year}';

      case FinancePeriod.all:
        return 'All-Time History';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final finance = context.watch<FinanceProvider>();
    final allTxs = finance.transactions;
    final filteredTxs = _filterTransactions(allTxs);

    double income = 0;
    double expense = 0;
    for (final tx in filteredTxs) {
      if (tx.amount >= 0) {
        income += tx.amount;
      } else {
        expense += tx.amount.abs();
      }
    }
    final netBalance = income - expense;

    // Category breakdown
    final Map<String, double> categoryExpenses = {};
    for (final tx in filteredTxs.where((t) => t.amount < 0)) {
      categoryExpenses[tx.category] = (categoryExpenses[tx.category] ?? 0) + tx.amount.abs();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance & Expenses'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.finance,
        foregroundColor: Colors.white,
        tooltip: 'Add Transaction',
        child: const Icon(Icons.add_rounded),
        onPressed: () async {
          final tx = await FinanceForm.show(context);
          if (tx != null && auth.uid != null) {
            tx.uid = auth.uid!;
            await finance.addTransaction(tx);
          }
        },
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: CustomScrollView(
            slivers: [
              // 1. Period Selector Filter Tabs (Horizontal Scroll - Zero Overflow)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip(FinancePeriod.daily, '📅 Daily'),
                        const SizedBox(width: 8),
                        _filterChip(FinancePeriod.weekly, '📊 Weekly'),
                        const SizedBox(width: 8),
                        _filterChip(FinancePeriod.monthly, '🗓️ Monthly'),
                        const SizedBox(width: 8),
                        _filterChip(FinancePeriod.yearly, '📆 Yearly'),
                        const SizedBox(width: 8),
                        _filterChip(FinancePeriod.all, '♾️ All-Time'),
                      ],
                    ),
                  ),
                ),
              ),

              // 2. Interactive Date Navigation Bar (Only for Daily / Weekly / Monthly / Yearly)
              if (_selectedPeriod != FinancePeriod.all)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded),
                            tooltip: 'Previous',
                            onPressed: _previousPeriod,
                          ),
                          InkWell(
                            onTap: _pickCustomDate,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_month_rounded, size: 16, color: AppColors.finance),
                                  const SizedBox(width: 6),
                                  Text(
                                    _periodHeaderLabel(),
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.arrow_drop_down_rounded, size: 18),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded),
                            tooltip: 'Next',
                            onPressed: _nextPeriod,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 3. Financial Summary Card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Summary (${_selectedPeriod == FinancePeriod.all ? 'All Time' : _periodHeaderLabel()})',
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.finance.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${filteredTxs.length} records',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.finance,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '₹${netBalance.toStringAsFixed(2)}',
                            style: theme.textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: netBalance >= 0 ? AppColors.primary : AppColors.error,
                            ),
                          ),
                          Text(
                            netBalance >= 0 ? 'Net Savings' : 'Deficit / Over Budget',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              // Income Tile
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.arrow_upward_rounded, size: 14, color: AppColors.success),
                                          SizedBox(width: 4),
                                          Text(
                                            'Income',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.success,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '+₹${income.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.success,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Expense Tile
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.arrow_downward_rounded, size: 14, color: AppColors.error),
                                          SizedBox(width: 4),
                                          Text(
                                            'Expenses',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.error,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '-₹${expense.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Category breakdown if any expenses exist
                          if (categoryExpenses.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 6),
                            Text(
                              'Expense Breakdown',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: categoryExpenses.entries.map((e) {
                                final pct = expense > 0 ? (e.value / expense * 100).toStringAsFixed(0) : '0';
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: theme.dividerColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        e.key,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '₹${e.value.toStringAsFixed(0)} ($pct%)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 4. Transactions Section Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Transactions',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${filteredTxs.length} items',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),

              // 5. Transactions List
              if (filteredTxs.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: EmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: 'No transactions found',
                      subtitle: 'Tap + below to add income or expense records',
                      iconColor: AppColors.finance,
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final tx = filteredTxs[i];
                      final isExpense = tx.amount < 0;
                      final dateStr = DateFormat('MMM dd, yyyy').format(tx.date);

                      return AnimatedListItem(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: AppCard(
                            onTap: () async {
                              final edited = await FinanceForm.show(context, initial: tx);
                              if (edited != null) {
                                await finance.updateTransaction(edited);
                              }
                            },
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: (isExpense ? AppColors.error : AppColors.success)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isExpense
                                        ? Icons.arrow_downward_rounded
                                        : Icons.arrow_upward_rounded,
                                    color: isExpense ? AppColors.error : AppColors.success,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tx.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: theme.dividerColor.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              tx.category,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              dateStr,
                                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${isExpense ? '-' : '+'}₹${tx.amount.abs().toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: isExpense ? AppColors.error : AppColors.success,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: AppColors.error.withValues(alpha: 0.7),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.only(left: 4),
                                  constraints: const BoxConstraints(),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Delete Transaction'),
                                        content: const Text('Are you sure you want to delete this record?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      await finance.deleteTransaction(tx.id);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: filteredTxs.length,
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 90)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(FinancePeriod period, String label) {
    final isSelected = _selectedPeriod == period;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: AppColors.finance,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12,
      ),
      onSelected: (val) {
        if (val) {
          setState(() => _selectedPeriod = period);
        }
      },
    );
  }
}
