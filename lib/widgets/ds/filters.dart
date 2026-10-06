import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// One option in a [FilterBar].
class FilterOption {
  final String label;
  final int? count;
  final IconData? icon;

  const FilterOption(this.label, {this.count, this.icon});
}

/// Horizontally scrolling single-select chips with optional counts:
/// "Scheduled 4 · Completed 12 · Missed 1 · All 17".
class FilterBar extends StatelessWidget {
  final List<FilterOption> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsetsGeometry padding;

  const FilterBar({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    this.padding = AppSpacing.screenPadding,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final colors = context.colors;
    return SizedBox(
      height: AppSizes.minTouchTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, i) {
          final o = options[i];
          final selected = i == selectedIndex;
          final fg = selected ? scheme.onPrimaryContainer : colors.textSecondary;
          return Center(
            child: ChoiceChip(
              selected: selected,
              onSelected: (_) => onSelected(i),
              side: BorderSide(color: selected ? scheme.primary.withValues(alpha: 0.35) : colors.border),
              avatar: o.icon == null ? null : Icon(o.icon, size: AppSizes.iconSm, color: fg),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(o.label, style: context.text.labelMedium?.copyWith(color: selected ? scheme.onPrimaryContainer : colors.textPrimary)),
                  if (o.count != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${o.count}',
                      style: context.text.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Two-to-five option switcher (Tasks / Goals, Day / Week / Month …).
class AppSegmented<T> extends StatelessWidget {
  final Map<T, String> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final Map<T, IconData>? icons;

  const AppSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.icons,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
        showSelectedIcon: false,
        segments: segments.entries
            .map((e) => ButtonSegment<T>(
                  value: e.key,
                  icon: icons?[e.key] == null ? null : Icon(icons![e.key], size: AppSizes.iconSm),
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(e.value, maxLines: 1)),
                ))
            .toList(),
        selected: {selected},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

/// "‹  Today, Oct 6  ›" period navigator used by Steps and Reports.
class DateNavigator extends StatelessWidget {
  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onTapLabel;

  const DateNavigator({super.key, required this.label, this.onPrevious, this.onNext, this.onTapLabel});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: onPrevious,
        ),
        Expanded(
          child: InkWell(
            borderRadius: AppRadius.mdAll,
            onTap: onTapLabel,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall,
                    ),
                  ),
                  if (onTapLabel != null) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    Icon(Icons.expand_more_rounded, size: AppSizes.iconMd, color: context.colors.textSecondary),
                  ],
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next',
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: onNext,
        ),
      ],
    );
  }
}
