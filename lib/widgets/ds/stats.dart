import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/theme.dart';
import 'app_card.dart';

/// A labelled number in a card: "Daily average · 6,240 steps".
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final String? caption;
  final IconData? icon;
  final StatusTone tone;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.caption,
    this.icon,
    this.tone = StatusTone.neutral,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      onTap: onTap,
      semanticLabel: '$label: $value${unit != null ? ' $unit' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppSizes.iconSm, color: colors.toneColor(tone, context.scheme)),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: value, style: context.text.headlineMedium?.copyWith(fontSize: 22)),
                  if (unit != null) TextSpan(text: ' $unit', style: context.text.bodySmall),
                ],
              ),
              maxLines: 1,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
          ],
        ],
      ),
    );
  }
}

/// Two [StatCard]s (or any widgets) side by side with the standard gap.
class StatRow extends StatelessWidget {
  final List<Widget> children;

  const StatRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) items.add(const SizedBox(width: AppSpacing.sm));
      items.add(Expanded(child: children[i]));
    }
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
    );
  }
}

/// One value in a [MetricStrip].
class Metric {
  final String value;
  final String label;
  final IconData? icon;

  const Metric({required this.value, required this.label, this.icon});
}

/// A row of small metrics separated by hairlines, e.g. kcal · km · minutes.
class MetricStrip extends StatelessWidget {
  final List<Metric> metrics;

  const MetricStrip({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final items = <Widget>[];
    for (var i = 0; i < metrics.length; i++) {
      if (i > 0) {
        items.add(Container(width: 1, height: 32, color: colors.divider));
      }
      final m = metrics[i];
      items.add(
        Expanded(
          child: Semantics(
            label: '${m.label}: ${m.value}',
            excludeSemantics: true,
            child: Column(
              children: [
                if (m.icon != null) ...[
                  Icon(m.icon, size: AppSizes.iconSm, color: colors.textSecondary),
                  const SizedBox(height: AppSpacing.xxs),
                ],
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(m.value, style: context.text.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                const SizedBox(height: 2),
                Text(m.label, style: context.text.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      );
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: items);
  }
}

/// Circular progress with content in the middle. Animates value changes.
class ProgressRing extends StatelessWidget {
  final double value;
  final double size;
  final double strokeWidth;
  final Widget? child;
  final Color? color;

  const ProgressRing({
    super.key,
    required this.value,
    this.size = 180,
    this.strokeWidth = 12,
    this.child,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.colors.chartPrimary;
    final track = context.colors.chartTrack;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: AppMotion.slow,
        curve: AppMotion.curve,
        builder: (context, v, _) => CustomPaint(
          painter: _RingPainter(value: v, color: fg, track: track, strokeWidth: strokeWidth),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;
  final double strokeWidth;

  _RingPainter({required this.value, required this.color, required this.track, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final deflated = rect.deflate(strokeWidth / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = track;
    canvas.drawArc(deflated, 0, math.pi * 2, false, base);
    if (value <= 0) return;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(deflated, -math.pi / 2, math.pi * 2 * value, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track || old.strokeWidth != strokeWidth;
}

/// Thin horizontal progress bar with rounded ends.
class LinearMeter extends StatelessWidget {
  final double value;
  final Color? color;
  final double height;

  const LinearMeter({super.key, required this.value, this.color, this.height = 6});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.pillAll,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: AppMotion.slow,
        curve: AppMotion.curve,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          color: color ?? context.colors.chartPrimary,
          backgroundColor: context.colors.chartTrack,
        ),
      ),
    );
  }
}
