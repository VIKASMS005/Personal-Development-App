import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/task_tracker_provider.dart';
import 'ds/ds.dart';

/// Mini tracker bar that stays visible across screens while a task timer runs.
class GlobalTaskTrackerBar extends StatelessWidget {
  const GlobalTaskTrackerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<TaskTrackerProvider>();

    return AnimatedSwitcher(
      duration: AppMotion.medium,
      transitionBuilder: (child, anim) => SizeTransition(sizeFactor: anim, child: FadeTransition(opacity: anim, child: child)),
      child: (!tracker.isTracking || tracker.activeTodo == null)
          ? const SizedBox(width: double.infinity)
          : _Bar(key: const ValueKey('bar'), tracker: tracker),
    );
  }
}

class _Bar extends StatelessWidget {
  final TaskTrackerProvider tracker;
  const _Bar({super.key, required this.tracker});

  @override
  Widget build(BuildContext context) {
    final todo = tracker.activeTodo!;
    final colors = context.colors;
    final scheme = context.scheme;
    const btn = BoxConstraints(minWidth: 44, minHeight: 44);

    return ContentWidth(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.xs, AppSpacing.screen, AppSpacing.xs),
        child: Material(
          color: scheme.primaryContainer,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xxs, AppSpacing.xxs, AppSpacing.xxs),
            child: Row(
              children: [
                Icon(tracker.isPaused ? Icons.pause_circle_outline_rounded : Icons.timer_outlined,
                    color: scheme.onPrimaryContainer, size: AppSizes.iconMd),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        todo.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelLarge?.copyWith(color: scheme.onPrimaryContainer),
                      ),
                      Text(
                        '${tracker.isPaused ? 'Paused' : 'Tracking'} · ${tracker.formattedTime}',
                        maxLines: 1,
                        style: context.text.labelSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  constraints: btn,
                  color: scheme.onPrimaryContainer,
                  icon: Icon(tracker.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                  onPressed: () => tracker.togglePauseResume(),
                  tooltip: tracker.isPaused ? 'Resume' : 'Pause',
                ),
                IconButton(
                  constraints: btn,
                  color: scheme.onPrimaryContainer,
                  icon: const Icon(Icons.check_rounded),
                  tooltip: 'Finish and save',
                  onPressed: () async {
                    await tracker.finish(context);
                    if (context.mounted) {
                      AppSnack.show(context, 'Focus session saved', tone: StatusTone.success, duration: const Duration(seconds: 2));
                    }
                  },
                ),
                IconButton(
                  constraints: btn,
                  color: colors.textSecondary,
                  icon: const Icon(Icons.close_rounded, size: AppSizes.iconMd),
                  tooltip: 'Discard timer',
                  onPressed: () async {
                    final ok = await ConfirmDialog.show(
                      context,
                      title: 'Discard this session?',
                      message: 'The time tracked since you started won\'t be saved.',
                      confirmLabel: 'Discard',
                      destructive: true,
                    );
                    if (ok) tracker.cancel();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
