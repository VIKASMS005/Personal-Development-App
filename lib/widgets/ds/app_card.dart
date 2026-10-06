import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// The one card style used everywhere: surface color, hairline border,
/// no shadow, [AppRadius.lg] corners.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Tinted background, for the single highlighted card on a screen.
  final bool emphasized;

  /// Overrides the border, e.g. an error border on a missed item.
  final Color? borderColor;
  final String? semanticLabel;

  const AppCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.cardPadding,
    this.onTap,
    this.onLongPress,
    this.emphasized = false,
    this.borderColor,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final colors = context.colors;
    final bg = emphasized ? scheme.primaryContainer.withValues(alpha: context.isDark ? 0.55 : 0.6) : scheme.surface;
    final border = borderColor ?? (emphasized ? scheme.primary.withValues(alpha: 0.18) : colors.border);

    Widget content = Padding(padding: padding, child: child);
    if (onTap != null || onLongPress != null) {
      content = InkWell(onTap: onTap, onLongPress: onLongPress, child: content);
    }

    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      container: true,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }
}
