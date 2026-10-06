import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Shown instead of a blank list: icon, one-line title, short explanation and
/// the action that fixes it.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  final bool compact;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.action,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: compact ? AppSpacing.lg : AppSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 48 : 64,
            height: compact ? 48 : 64,
            decoration: BoxDecoration(color: colors.surfaceMuted, shape: BoxShape.circle),
            child: Icon(icon, size: compact ? 24 : 30, color: colors.textSecondary),
          ),
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
          Text(title, style: context.text.titleSmall, textAlign: TextAlign.center),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(subtitle, style: context.text.bodySmall, textAlign: TextAlign.center),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.md),
            action!,
          ],
        ],
      ),
    );
    return Center(child: SingleChildScrollView(child: content));
  }
}

/// Friendly error with a retry button. Never shows raw exception text.
class ErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const ErrorState({
    super.key,
    this.title = 'Something went wrong',
    this.message = 'We couldn\'t load this right now. Please try again.',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_rounded,
      title: title,
      subtitle: message,
      action: onRetry == null
          ? null
          : OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: AppSizes.iconMd),
              label: const Text('Try again'),
            ),
    );
  }
}

/// Inline notice for a non-blocking problem (missing permission, sensor
/// unavailable). Icon + text, tinted by tone.
class InlineBanner extends StatelessWidget {
  final String message;
  final StatusTone tone;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const InlineBanner({
    super.key,
    required this.message,
    this.tone = StatusTone.info,
    this.icon = Icons.info_outline_rounded,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = colors.toneColor(tone, context.scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.toneContainer(tone, context.scheme),
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        children: [
          Icon(icon, size: AppSizes.iconMd, color: fg),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: context.text.bodySmall?.copyWith(color: colors.textPrimary))),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// Placeholder block that gently pulses while content loads.
class SkeletonBox extends StatefulWidget {
  final double height;
  final double? width;
  final BorderRadius borderRadius;

  const SkeletonBox({super.key, required this.height, this.width, this.borderRadius = AppRadius.mdAll});

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Color.lerp(colors.surfaceMuted, colors.surfaceStrong, _c.value),
          borderRadius: widget.borderRadius,
        ),
      ),
    );
  }
}

/// Skeleton version of a list of cards.
class LoadingList extends StatelessWidget {
  final int count;
  final double itemHeight;

  const LoadingList({super.key, this.count = 4, this.itemHeight = 76});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.screen),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (_, __) => SkeletonBox(height: itemHeight, borderRadius: AppRadius.lgAll),
      ),
    );
  }
}
