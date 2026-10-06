import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Simple vertical bar chart that follows the theme.
///
/// * the highlighted bar (today / current period) uses the primary chart color
/// * bars at or above [goal] use a lighter primary
/// * other bars are neutral
/// * an optional dashed goal line is labelled, so meaning never depends on color
class BarChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final int? highlightIndex;
  final double? goal;
  final Set<int> disabledIndices;
  final String Function(double)? valueLabel;
  final double height;
  final String? semanticsLabel;

  const BarChart({
    super.key,
    required this.values,
    required this.labels,
    this.highlightIndex,
    this.goal,
    this.disabledIndices = const {},
    this.valueLabel,
    this.height = 180,
    this.semanticsLabel,
  }) : assert(values.length == labels.length);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final maxValue = [
      ...values,
      if (goal != null) goal!,
    ].fold<double>(0, (a, b) => a > b ? a : b);
    final scaleMax = maxValue <= 0 ? 1.0 : maxValue * 1.08;
    final dense = values.length > 8;

    return Semantics(
      label: semanticsLabel,
      container: true,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(builder: (context, constraints) {
          const labelBlock = 22.0;
          const valueBlock = 18.0;
          final plotHeight = constraints.maxHeight - labelBlock - valueBlock;
          final goalY = goal == null ? null : plotHeight * (1 - (goal! / scaleMax).clamp(0.0, 1.0)) + valueBlock;

          return Stack(
            children: [
              if (goalY != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: goalY,
                  child: _DashedLine(color: colors.textSecondary.withValues(alpha: 0.5)),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(values.length, (i) {
                  final v = values[i];
                  final disabled = disabledIndices.contains(i);
                  final isHighlight = i == highlightIndex;
                  final metGoal = goal != null && v >= goal! && v > 0;
                  final barColor = disabled
                      ? colors.chartTrack
                      : isHighlight
                          ? colors.chartPrimary
                          : metGoal
                              ? colors.chartPrimary.withValues(alpha: 0.5)
                              : colors.chartMuted;
                  final h = disabled ? 4.0 : (plotHeight * (v / scaleMax)).clamp(v > 0 ? 4.0 : 2.0, plotHeight);
                  return Expanded(
                    child: Semantics(
                      label: '${labels[i]}: ${valueLabel?.call(v) ?? v.round()}',
                      excludeSemantics: true,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SizedBox(
                            height: valueBlock,
                            child: (dense && !isHighlight) || disabled || valueLabel == null
                                ? null
                                : FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      valueLabel!(v),
                                      style: context.text.labelSmall?.copyWith(
                                        color: isHighlight ? colors.textPrimary : colors.textSecondary,
                                        fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                          ),
                          AnimatedContainer(
                            duration: AppMotion.slow,
                            curve: AppMotion.curve,
                            height: h,
                            margin: EdgeInsets.symmetric(horizontal: dense ? 3 : 7),
                            decoration: BoxDecoration(
                              color: barColor,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(2)),
                            ),
                          ),
                          SizedBox(
                            height: labelBlock,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  labels[i],
                                  style: context.text.labelSmall?.copyWith(
                                    color: isHighlight ? colors.textPrimary : colors.textSecondary,
                                    fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  final Color color;
  const _DashedLine({required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(double.infinity, 1), painter: _DashPainter(color));
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0, gap = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset((x + dash).clamp(0, size.width), 0), p);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// Legend entry: swatch + label.
class ChartLegend extends StatelessWidget {
  final List<(Color, String)> items;
  const ChartLegend({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xxs,
      children: items
          .map((e) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: e.$1, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 6),
                  Text(e.$2, style: context.text.labelSmall),
                ],
              ))
          .toList(),
    );
  }
}

/// Current vs previous period as two labelled horizontal bars and a change badge.
class ComparisonBars extends StatelessWidget {
  final String currentLabel;
  final double currentValue;
  final String currentText;
  final String previousLabel;
  final double previousValue;
  final String previousText;

  const ComparisonBars({
    super.key,
    required this.currentLabel,
    required this.currentValue,
    required this.currentText,
    required this.previousLabel,
    required this.previousValue,
    required this.previousText,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final maxV = currentValue > previousValue ? currentValue : previousValue;
    double frac(double v) => maxV <= 0 ? 0 : v / maxV;

    Widget row(String label, String text, double f, Color c, bool bold) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: context.text.labelSmall)),
                Text(text, style: (bold ? context.text.labelMedium : context.text.labelSmall)),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            ClipRRect(
              borderRadius: AppRadius.pillAll,
              child: LinearProgressIndicator(value: f, minHeight: 8, color: c, backgroundColor: colors.chartTrack),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        row(currentLabel, currentText, frac(currentValue), colors.chartPrimary, true),
        row(previousLabel, previousText, frac(previousValue), colors.chartMuted, false),
      ],
    );
  }
}
