import 'package:flutter/material.dart';
import '../../theme/semantics.dart';
import '../../theme/theme.dart';

/// Small pill with a label (and optional icon) in a semantic tone.
/// Always carries text, so status is never shown by color alone.
class StatusBadge extends StatelessWidget {
  final String label;
  final StatusTone tone;
  final IconData? icon;
  final bool outlined;

  const StatusBadge({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = colors.toneColor(tone, context.scheme);
    final bg = outlined ? Colors.transparent : colors.toneContainer(tone, context.scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.pillAll,
        border: outlined ? Border.all(color: colors.border) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Priority shown as icon + label + tone.
class PriorityBadge extends StatelessWidget {
  final int priority;
  final bool compact;

  const PriorityBadge({super.key, required this.priority, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final p = PriorityStyle.of(priority);
    return Semantics(
      label: 'Priority: ${p.label}',
      excludeSemantics: true,
      child: StatusBadge(label: compact ? p.shortLabel : p.label, tone: p.tone, icon: p.icon),
    );
  }
}

/// An icon inside a soft rounded square. Used as the leading visual of
/// cards and list rows.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final StatusTone tone;
  final double size;

  const IconBadge({super.key, required this.icon, this.tone = StatusTone.primary, this.size = AppSizes.iconBadge});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = tone == StatusTone.primary ? context.scheme.onPrimaryContainer : colors.toneColor(tone, context.scheme);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.toneContainer(tone, context.scheme),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.5, color: fg),
    );
  }
}
