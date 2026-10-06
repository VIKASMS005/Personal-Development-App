import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Label shown above a group of form controls.
class FieldLabel extends StatelessWidget {
  final String text;
  final String? hint;

  const FieldLabel(this.text, {super.key, this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Text(text, style: context.text.labelMedium),
          if (hint != null) ...[
            const SizedBox(width: AppSpacing.xxs),
            Text(hint!, style: context.text.labelSmall),
          ],
        ],
      ),
    );
  }
}

/// Read-only field that opens a picker (date, time, …). Looks like a text
/// field so forms stay visually consistent.
class PickerField extends StatelessWidget {
  final String label;
  final String? value;
  final String placeholder;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.placeholder = 'Select',
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasValue = value != null && value!.isNotEmpty;
    // On narrow fields (two side by side on a small phone) the icon is
    // dropped so the value stays readable.
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 170;
      return Semantics(
        button: true,
        label: '$label: ${hasValue ? value : placeholder}',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdAll,
          child: InputDecorator(
            isEmpty: false,
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: compact ? null : Icon(icon, size: AppSizes.iconMd),
              suffixIcon: hasValue && onClear != null
                  ? IconButton(
                      tooltip: 'Clear $label',
                      icon: const Icon(Icons.close_rounded, size: AppSizes.iconMd),
                      onPressed: onClear,
                    )
                  : null,
            ),
            child: Text(
              hasValue ? value! : placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyLarge?.copyWith(color: hasValue ? colors.textPrimary : colors.textDisabled),
            ),
          ),
        ),
      );
    });
  }
}

/// Wrap of selectable chips for a small set of options (category, priority).
class ChoiceWrap<T> extends StatelessWidget {
  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final IconData Function(T)? iconOf;
  final ValueChanged<T> onSelected;

  const ChoiceWrap({
    super.key,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.iconOf,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: options.map((o) {
        final isSelected = o == selected;
        return ChoiceChip(
          label: Text(labelOf(o)),
          avatar: iconOf == null
              ? null
              : Icon(
                  iconOf!(o),
                  size: AppSizes.iconSm,
                  color: isSelected ? context.scheme.onPrimaryContainer : context.colors.textSecondary,
                ),
          selected: isSelected,
          labelStyle: context.text.labelMedium?.copyWith(
            color: isSelected ? context.scheme.onPrimaryContainer : context.colors.textPrimary,
          ),
          side: BorderSide(color: isSelected ? context.scheme.primary.withValues(alpha: 0.4) : context.colors.border),
          onSelected: (_) => onSelected(o),
        );
      }).toList(),
    );
  }
}
