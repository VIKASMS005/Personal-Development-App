import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/finance_transaction.dart';
import '../utils/app_colors.dart';

final _money = NumberFormat('#,##0');

const _sliceColors = [
  Color(0xFFEF4444),
  Color(0xFFF59E0B),
  Color(0xFF3B82F6),
  Color(0xFF10B981),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFF06B6D4),
  Color(0xFFF97316),
  Color(0xFF84CC16),
  Color(0xFF64748B),
  Color(0xFF0F766E),
  Color(0xFFA16207),
];

/// One spending category: its total and its expenses, largest first.
class CategorySpend {
  final String name;
  final double total;
  final List<FinanceTransaction> expenses;
  const CategorySpend(this.name, this.total, this.expenses);
}

/// Expense categories sorted by total spend, largest first.
List<CategorySpend> categorySpends(List<FinanceTransaction> txs) {
  final byCat = <String, List<FinanceTransaction>>{};
  for (final tx in txs.where((t) => t.amount < 0)) {
    byCat.putIfAbsent(tx.category, () => []).add(tx);
  }
  final list = byCat.entries.map((e) {
    final items = e.value..sort((a, b) => a.amount.compareTo(b.amount)); // most negative first
    final total = items.fold<double>(0, (s, t) => s + t.amount.abs());
    return CategorySpend(e.key, total, items);
  }).toList()
    ..sort((a, b) => b.total.compareTo(a.total));
  return list;
}

/// Color of the category at [index] in [categorySpends] order. Categories past
/// the palette share the last color, which the pie labels "Other".
Color categoryColor(int index) => _sliceColors[math.min(index, _sliceColors.length - 1)];

/// Pie chart of expenses by category, with a compact legend.
class ExpensePieChart extends StatelessWidget {
  final List<FinanceTransaction> transactions;
  const ExpensePieChart({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cats = categorySpends(transactions);
    if (cats.isEmpty) return const SizedBox.shrink();

    // Fold the tail into "Other" so every slice has its own color.
    final slices = <MapEntry<String, double>>[];
    for (var i = 0; i < cats.length; i++) {
      if (i < _sliceColors.length - 1 || cats.length == _sliceColors.length) {
        slices.add(MapEntry(cats[i].name, cats[i].total));
      } else {
        final rest = cats.skip(i).fold<double>(0, (s, c) => s + c.total);
        slices.add(MapEntry('Other', rest));
        break;
      }
    }
    final total = slices.fold<double>(0, (s, e) => s + e.value);

    return Column(
      children: [
        SizedBox(
          width: 160,
          height: 160,
          child: CustomPaint(
            painter: _PiePainter(
              values: slices.map((e) => e.value).toList(),
              gapColor: theme.cardColor,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Spent', style: theme.textTheme.bodySmall),
                  Text('₹${_money.format(total)}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < slices.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(color: categoryColor(i), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${slices[i].key} ${(slices[i].value / total * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Categories in descending order of spend. Each one expands to show its
/// [topCount] largest expenses.
class CategoryExpenseList extends StatelessWidget {
  final List<FinanceTransaction> transactions;
  final int topCount;
  const CategoryExpenseList({super.key, required this.transactions, this.topCount = 10});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cats = categorySpends(transactions);
    final total = cats.fold<double>(0, (s, c) => s + c.total);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Column(
      children: [
        for (var i = 0; i < cats.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  key: PageStorageKey('cat-${cats[i].name}'),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  leading: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: categoryColor(i), shape: BoxShape.circle),
                  ),
                  title: Text(
                    cats[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${cats[i].expenses.length} expenses · ${(cats[i].total / total * 100).toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 11.5, color: muted),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('₹${_money.format(cats[i].total)}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.error)),
                      const SizedBox(width: 4),
                      Icon(Icons.expand_more_rounded, color: muted),
                    ],
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Top ${math.min(topCount, cats[i].expenses.length)} expenses',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: muted),
                        ),
                      ),
                    ),
                    for (final tx in cats[i].expenses.take(topCount))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tx.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  Text(DateFormat('MMM d, yyyy').format(tx.date),
                                      style: TextStyle(fontSize: 11, color: muted)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('₹${_money.format(tx.amount.abs())}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PiePainter extends CustomPainter {
  final List<double> values;
  final Color gapColor;

  _PiePainter({required this.values, required this.gapColor});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (s, v) => s + v);
    if (total <= 0) return;
    final rect = Offset.zero & size;
    final stroke = size.shortestSide * 0.2;
    final arcRect = rect.deflate(stroke / 2);
    final c = rect.center;
    final r1 = arcRect.width / 2 - stroke / 2;
    final r2 = arcRect.width / 2 + stroke / 2;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * math.pi;
      canvas.drawArc(
        arcRect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = categoryColor(i),
      );
      if (values.length > 1) {
        final dir = Offset(math.cos(start), math.sin(start));
        canvas.drawLine(c + dir * r1, c + dir * r2, Paint()
          ..color = gapColor
          ..strokeWidth = 2);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) => old.values != values || old.gapColor != gapColor;
}
