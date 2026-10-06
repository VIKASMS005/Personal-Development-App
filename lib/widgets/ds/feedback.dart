import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Consistent snackbars. Replaces ad-hoc colored SnackBars across screens.
class AppSnack {
  AppSnack._();

  static void show(
    BuildContext context,
    String message, {
    StatusTone tone = StatusTone.neutral,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 2),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    // Icons sit on the inverse surface, so they use its foreground color;
    // the icon shape carries the meaning.
    final iconColor = context.scheme.onInverseSurface;
    final IconData? icon = switch (tone) {
      StatusTone.success => Icons.check_circle_rounded,
      StatusTone.error => Icons.error_outline_rounded,
      StatusTone.warning => Icons.warning_amber_rounded,
      _ => null,
    };
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: duration,
          content: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppSizes.iconMd, color: iconColor),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(child: Text(message)),
            ],
          ),
          action: actionLabel != null && onAction != null
              ? SnackBarAction(label: actionLabel, onPressed: onAction)
              : null,
        ),
      );
  }
}

/// Confirmation dialog. Destructive confirmations get an error-colored button.
class ConfirmDialog {
  ConfirmDialog._();

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = ctx.colors;
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actionsPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(foregroundColor: colors.textSecondary),
              child: Text(cancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: destructive
                  ? FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: ctx.scheme.onError)
                  : null,
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result == true;
  }
}
