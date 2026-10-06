import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/task_tracker_provider.dart';
import '../theme/theme_context.dart';

/// Floating mini-tracker bar that stays visible across all app screens
/// while a task timer is actively running.
class GlobalTaskTrackerBar extends StatelessWidget {
  const GlobalTaskTrackerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<TaskTrackerProvider>();

    if (!tracker.isTracking || tracker.activeTodo == null) {
      return const SizedBox.shrink();
    }

    final colors = context.colors;
    final scheme = context.scheme;
    final todo = tracker.activeTodo!;
    final paused = tracker.isPaused;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Material(
        color: Theme.of(context).cardTheme.color ?? scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
          child: Row(
            children: [
              Icon(
                paused ? Icons.pause_circle_rounded : Icons.timer_rounded,
                color: paused ? colors.warning : scheme.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todo.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      paused ? 'Paused' : 'Tracking',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(
                        color: paused ? colors.warning : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                tracker.formattedTime,
                style: context.text.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              IconButton(
                icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                color: scheme.primary,
                onPressed: tracker.togglePauseResume,
                tooltip: paused ? 'Resume' : 'Pause',
              ),
              IconButton(
                icon: const Icon(Icons.stop_rounded),
                color: colors.error,
                tooltip: 'End and save',
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await tracker.finish(context);
                  messenger
                    ..clearSnackBars()
                    ..showSnackBar(const SnackBar(
                      content: Text('Session saved'),
                      duration: Duration(seconds: 2),
                    ));
                },
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms);
  }
}
