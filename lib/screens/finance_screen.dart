import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_providers.dart';
import '../models/finance_transaction.dart';
import '../widgets/ds/ds.dart';
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
            title: const Text('Select year'),
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
                    trailing: isSel ? Icon(Icons.check_rounded, color: ctx.scheme.primary) : null,
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
        if (isToday) return 'Today, ${DateFormat('MMM d').format(_selectedDate)}';
        return DateFormat('EEE, MMM d, yyyy').format(_selectedDate);

      case FinancePeriod.weekly:
        final startOfWeek = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 6));
        return '${DateFormat('MMM d').format(startOfWeek)} – ${DateFormat('MMM d, yyyy').format(endOfWeek)}';

      case FinancePeriod.monthly:
        return DateFormat('MMMM yyyy').format(_selectedDate);

      case FinancePeriod.yearly:
        return '${_selectedDate.year}';

      case FinancePeriod.all:
        return 'All time';
    }
  }

  String _money(double v) => '₹${NumberFormat('#,##0').format(v)}';

  Future<void> _add(AuthProvider auth, FinanceProvider finance) async {
    final tx = await FinanceForm.show(context, defaultDate: _selectedDate);
    if (tx != null && auth.uid != null) {
      tx.uid = auth.uid!;
      await finance.addTransaction(tx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final finance = context.watch<FinanceProvider>();
    final allTxs = finance.transactions;
    final filteredTxs = _filterTransactions(allTxs);
    final colors = context.colors;

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
    final sortedCategories = categoryExpenses.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: const Text('Finance')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(auth, finance),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add entry'),
      ),
      body: PageListView(
        children: [
          AppSegmented<FinancePeriod>(
            segments: const {
              FinancePeriod.daily: 'Day',
              FinancePeriod.weekly: 'Week',
              FinancePeriod.monthly: 'Month',
              FinancePeriod.yearly: 'Year',
              FinancePeriod.all: 'All',
            },
            selected: _selectedPeriod,
            onChanged: (p) => setState(() => _selectedPeriod = p),
          ),
          if (_selectedPeriod != FinancePeriod.all) ...[
            const SizedBox(height: AppSpacing.xs),
            DateNavigator(
              label: _periodHeaderLabel(),
              onPrevious: _previousPeriod,
              onNext: _nextPeriod,
              onTapLabel: _pickCustomDate,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        netBalance >= 0 ? 'Net balance' : 'Spent more than earned',
                        style: context.text.labelMedium?.copyWith(color: colors.textSecondary),
                      ),
                    ),
                    StatusBadge(label: '${filteredTxs.length} ${filteredTxs.length == 1 ? 'entry' : 'entries'}', outlined: true),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${netBalance < 0 ? '−' : ''}${_money(netBalance.abs())}',
                    style: context.text.displaySmall?.copyWith(color: netBalance < 0 ? colors.error : colors.textPrimary),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: _FlowTile(label: 'Income', amount: '+${_money(income)}', icon: Icons.south_west_rounded, tone: StatusTone.success)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: _FlowTile(label: 'Expenses', amount: '−${_money(expense)}', icon: Icons.north_east_rounded, tone: StatusTone.error)),
                  ],
                ),
              ],
            ),
          ),
          if (sortedCategories.isNotEmpty) ...[
            const SectionGap(),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Where the money went', style: context.text.titleSmall),
                  const SizedBox(height: AppSpacing.md),
                  for (final e in sortedCategories) ...[
                    Row(
                      children: [
                        Expanded(child: Text(e.key, style: context.text.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        Text(
                          '${_money(e.value)} · ${expense > 0 ? (e.value / expense * 100).toStringAsFixed(0) : '0'}%',
                          style: context.text.labelMedium?.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    LinearMeter(value: expense > 0 ? e.value / expense : 0),
                    if (e.key != sortedCategories.last.key) const SizedBox(height: AppSpacing.md),
                  ],
                ],
              ),
            ),
          ],
          const SectionGap(),
          SectionHeader(title: 'Transactions', subtitle: filteredTxs.isEmpty ? null : 'Tap an entry to edit it.'),
          if (filteredTxs.isEmpty)
            EmptyState(
              compact: true,
              icon: Icons.receipt_long_outlined,
              title: 'No entries in this period',
              subtitle: 'Add income or an expense to start tracking.',
              action: OutlinedButton(onPressed: () => _add(auth, finance), child: const Text('Add entry')),
            )
          else
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Column(
                children: [
                  for (var i = 0; i < filteredTxs.length; i++) ...[
                    if (i > 0) const Divider(indent: 68),
                    _TxTile(
                      tx: filteredTxs[i],
                      amount: '${filteredTxs[i].amount < 0 ? '−' : '+'}${_money(filteredTxs[i].amount.abs())}',
                      onTap: () async {
                        final edited = await FinanceForm.show(context, initial: filteredTxs[i]);
                        if (edited != null) {
                          await finance.updateTransaction(edited);
                        }
                      },
                      onDelete: () async {
                        final tx = filteredTxs[i];
                        final ok = await ConfirmDialog.show(
                          context,
                          title: 'Delete entry?',
                          message: '"${tx.title}" will be removed permanently.',
                          confirmLabel: 'Delete',
                          destructive: true,
                        );
                        if (ok) {
                          await finance.deleteTransaction(tx.id);
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FlowTile extends StatelessWidget {
  final String label;
  final String amount;
  final IconData icon;
  final StatusTone tone;

  const _FlowTile({required this.label, required this.amount, required this.icon, required this.tone});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: colors.surfaceMuted, borderRadius: AppRadius.mdAll),
      child: Row(
        children: [
          IconBadge(icon: icon, tone: tone, size: 32),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.text.labelSmall),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(amount, style: context.text.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TxTile extends StatelessWidget {
  final FinanceTransaction tx;
  final String amount;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _TxTile({required this.tx, required this.amount, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isExpense = tx.amount < 0;
    final colors = context.colors;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.only(left: AppSpacing.md),
      leading: IconBadge(
        icon: isExpense ? Icons.north_east_rounded : Icons.south_west_rounded,
        tone: isExpense ? StatusTone.error : StatusTone.success,
        size: 36,
      ),
      title: Text(tx.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${tx.category} · ${DateFormat('MMM d').format(tx.date)}', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            amount,
            semanticsLabel: '${isExpense ? 'Expense' : 'Income'} $amount',
            style: context.text.titleSmall?.copyWith(
              color: isExpense ? colors.textPrimary : colors.success,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) => v == 'edit' ? onTap() : onDelete(),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: colors.error))),
            ],
          ),
        ],
      ),
    );
  }
}
