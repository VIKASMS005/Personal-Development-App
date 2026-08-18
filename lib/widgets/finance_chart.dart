import 'package:flutter/material.dart';
import '../models/finance_transaction.dart';

class FinanceChart extends StatelessWidget {
  final List<FinanceTransaction> transactions;
  final Color? lineColor;
  final Color? fillColor;

  const FinanceChart({
    super.key,
    this.transactions = const [],
    this.lineColor,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = lineColor ?? theme.colorScheme.primary;
    final fill = fillColor ?? theme.colorScheme.primary.withValues(alpha: 0.15);

    if (transactions.isEmpty) {
      return Center(
        child: Text(
          'No data yet',
          style: TextStyle(
            fontSize: 12,
            color: lineColor?.withValues(alpha: 0.7) ??
                theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      );
    }

    final data = transactions.reversed.toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: CustomPaint(
        size: Size.infinite,
        painter: _SparklinePainter(
          data.map((t) => t.amount).toList(),
          lineColor: line,
          fillColor: fill,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;
  final Color fillColor;

  _SparklinePainter(
    this.values, {
    required this.lineColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paintLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = lineColor;

    final paintArea = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor;

    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final span = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);
    final stepX = values.length > 1 ? size.width / (values.length - 1) : 0.0;

    final points = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = i * stepX;
      final normalized = (values[i] - minVal) / span;
      final y = size.height - (normalized * size.height);
      points.add(Offset(x, y));
    }

    if (points.length > 1) {
      final areaPath = Path()
        ..moveTo(points.first.dx, size.height);
      for (final p in points) {
        areaPath.lineTo(p.dx, p.dy);
      }
      areaPath
        ..lineTo(points.last.dx, size.height)
        ..close();
      canvas.drawPath(areaPath, paintArea);

      final linePath = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        linePath.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(linePath, paintLine);
    }

    final dotPaint = Paint()..color = lineColor;
    for (final p in points) {
      canvas.drawCircle(p, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values ||
      old.lineColor != lineColor ||
      old.fillColor != fillColor;
}
